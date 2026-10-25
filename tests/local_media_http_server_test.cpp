#include "local_media_http_server.hpp"

#include <QCoreApplication>
#include <QEventLoop>
#include <QFile>
#include <QNetworkAccessManager>
#include <QNetworkProxy>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QTemporaryDir>
#include <QTimer>
#include <iostream>

namespace {
struct Response {
    int status = 0;
    QByteArray body;
    QList<QPair<QByteArray, QByteArray>> headers;
    QByteArray header(const QByteArray &name) const
    {
        for (const auto &entry : headers)
            if (entry.first.compare(name, Qt::CaseInsensitive) == 0)
                return entry.second;
        return {};
    }
};

Response request(QNetworkAccessManager &network, const QUrl &url,
                 const QByteArray &method = QByteArrayLiteral("GET"),
                 const QByteArray &range = {})
{
    QNetworkRequest request(url);
    if (!range.isEmpty())
        request.setRawHeader("Range", range);
    QNetworkReply *reply = network.sendCustomRequest(request, method);
    QEventLoop loop;
    QTimer timeout;
    timeout.setSingleShot(true);
    QObject::connect(reply, &QNetworkReply::finished, &loop, &QEventLoop::quit);
    QObject::connect(&timeout, &QTimer::timeout, &loop, &QEventLoop::quit);
    timeout.start(3000);
    loop.exec();

    Response response;
    response.status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    response.body = reply->readAll();
    for (const QByteArray &name : reply->rawHeaderList())
        response.headers.append({name, reply->rawHeader(name)});
    reply->deleteLater();
    return response;
}

void check(bool condition, const char *description, int &failures)
{
    if (condition)
        std::cout << "PASS " << description << '\n';
    else {
        std::cerr << "FAIL " << description << '\n';
        ++failures;
    }
}
}

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    int failures = 0;
    QTemporaryDir temp;
    check(temp.isValid(), "temporary media directory created", failures);
    const QString mediaPath = temp.filePath(QStringLiteral("sample video.mp4"));
    QFile media(mediaPath);
    check(media.open(QIODevice::WriteOnly), "fixture media file opened", failures);
    media.write("0123456789", 10);
    media.close();

    LocalMediaHttpServer server;
    QUrl publishedUrl;
    QString error;
    const QHostAddress loopbackRoute = LocalMediaHttpServer::routeAddressFor(
        QUrl(QStringLiteral("http://127.0.0.1:1900/description.xml")), &error);
    check(loopbackRoute == QHostAddress::LocalHost,
          "UDP route lookup selects the interface used to reach the renderer", failures);
    check(!server.start(QUrl::fromLocalFile(mediaPath), QHostAddress::AnyIPv4, &publishedUrl, &error),
          "relay refuses a wildcard bind that would expose every interface", failures);
    check(server.start(QUrl::fromLocalFile(mediaPath), QHostAddress::LocalHost, &publishedUrl, &error),
          "relay starts for a readable local file", failures);
    check(server.isActive() && publishedUrl.scheme() == QLatin1String("http")
          && publishedUrl.host() == QLatin1String("127.0.0.1") && publishedUrl.port() > 0,
          "relay publishes a reachable ephemeral HTTP URL", failures);
    check(publishedUrl.path(QUrl::FullyEncoded).contains(QStringLiteral("sample%20video.mp4"))
          && !publishedUrl.toString().contains(mediaPath),
          "published URL uses an opaque token without exposing the source path", failures);
    check(server.contentType() == QLatin1String("video/mp4") && server.contentLength() == 10,
          "relay reports the file MIME type and byte length", failures);

    QNetworkAccessManager network;
    network.setProxy(QNetworkProxy::NoProxy);
    const Response full = request(network, publishedUrl);
    check(full.status == 200 && full.body == QByteArrayLiteral("0123456789")
          && full.header("Accept-Ranges") == QByteArrayLiteral("bytes"),
          "GET streams the complete media and advertises byte ranges", failures);

    const Response bounded = request(network, publishedUrl, "GET", "bytes=3-6");
    check(bounded.status == 206 && bounded.body == QByteArrayLiteral("3456")
          && bounded.header("Content-Range") == QByteArrayLiteral("bytes 3-6/10"),
          "bounded byte range returns 206 and the requested bytes", failures);

    const Response openEnded = request(network, publishedUrl, "GET", "bytes=7-");
    check(openEnded.status == 206 && openEnded.body == QByteArrayLiteral("789"),
          "open-ended byte range returns the file suffix", failures);

    const Response suffix = request(network, publishedUrl, "GET", "bytes=-3");
    check(suffix.status == 206 && suffix.body == QByteArrayLiteral("789"),
          "suffix byte range returns the requested tail", failures);

    const Response head = request(network, publishedUrl, "HEAD");
    check(head.status == 200 && head.body.isEmpty() && head.header("Content-Length") == QByteArrayLiteral("10"),
          "HEAD returns media headers without a body", failures);

    const Response invalid = request(network, publishedUrl, "GET", "bytes=20-");
    check(invalid.status == 416 && invalid.header("Content-Range") == QByteArrayLiteral("bytes */10"),
          "unsatisfiable range returns 416 with the file size", failures);

    QUrl wrongPath = publishedUrl;
    wrongPath.setPath(QStringLiteral("/not-the-token/file.mp4"));
    check(request(network, wrongPath).status == 404,
          "unknown paths cannot access the served media", failures);
    check(request(network, publishedUrl, "POST").status == 405,
          "methods other than GET and HEAD are rejected", failures);
    check(request(network, publishedUrl, "GET", "bytes=0-2,5-7").status == 416,
          "multi-range requests are rejected", failures);

    server.stop();
    check(!server.isActive(), "disconnect stops the temporary relay", failures);

    const QString largeMediaPath = temp.filePath(QStringLiteral("bounded-transfer.mp4"));
    const QByteArray largePayload(512 * 1024, 'v');
    QFile largeMedia(largeMediaPath);
    check(largeMedia.open(QIODevice::WriteOnly) && largeMedia.write(largePayload) == largePayload.size(),
          "bounded-transfer fixture written", failures);
    largeMedia.close();
    QUrl largeUrl;
    check(server.start(QUrl::fromLocalFile(largeMediaPath), QHostAddress::LocalHost, &largeUrl, &error),
          "relay restarts for the next local file", failures);
    const Response large = request(network, largeUrl);
    check(large.status == 200 && large.body == largePayload,
          "streaming remains correct when a response exceeds the socket buffer window", failures);
    server.stop();
    return failures == 0 ? 0 : 1;
}
