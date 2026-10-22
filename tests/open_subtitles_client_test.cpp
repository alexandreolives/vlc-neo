#include "../src/open_subtitles_client.hpp"

#include <QCoreApplication>
#include <QEventLoop>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSettings>
#include <QTcpServer>
#include <QTcpSocket>
#include <QTemporaryFile>
#include <QTimer>

#include <cstdio>

namespace {

bool expect(bool condition, const char *name)
{
    if (condition)
        return true;
    std::fprintf(stderr, "failed: %s\n", name);
    return false;
}

QByteArray searchResponse()
{
    const QJsonObject file{{QStringLiteral("file_id"), 987654}};
    const QJsonObject attributes{
        {QStringLiteral("feature_details"), QJsonObject{{QStringLiteral("movie_name"), QStringLiteral("Interstellar")}}},
        {QStringLiteral("release"), QStringLiteral("Interstellar.2014.1080p")},
        {QStringLiteral("language"), QStringLiteral("en")},
        {QStringLiteral("hearing_impaired"), true},
        {QStringLiteral("download_count"), 1234},
        {QStringLiteral("ratings"), 9.2},
        {QStringLiteral("moviehash_match"), true},
        {QStringLiteral("url"), QStringLiteral("https://www.opensubtitles.com/en/subtitles/987654")},
        {QStringLiteral("files"), QJsonArray{file}}
    };
    const QJsonObject entry{{QStringLiteral("attributes"), attributes}};
    return QJsonDocument(QJsonObject{{QStringLiteral("data"), QJsonArray{entry}}})
        .toJson(QJsonDocument::Compact);
}

} // namespace

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    QCoreApplication::setOrganizationName(QStringLiteral("vlc-neo"));
    QCoreApplication::setApplicationName(QStringLiteral("neo"));
    QSettings().remove(QStringLiteral("openSubtitles/apiKey"));

    QTcpServer server;
    if (!server.listen(QHostAddress::LocalHost, 0)) {
        std::fprintf(stderr, "failed: local OpenSubtitles fixture could not listen\n");
        return 1;
    }

    QByteArray requestBytes;
    QObject::connect(&server, &QTcpServer::newConnection, &app, [&] {
        while (server.hasPendingConnections()) {
            QTcpSocket *socket = server.nextPendingConnection();
            QObject::connect(socket, &QTcpSocket::readyRead, socket, [socket, &requestBytes] {
                requestBytes += socket->readAll();
                if (!requestBytes.contains("\r\n\r\n"))
                    return;
                const QByteArray body = searchResponse();
                const QByteArray response = "HTTP/1.1 200 OK\r\n"
                    "Content-Type: application/json\r\n"
                    "Connection: close\r\n"
                    "Content-Length: " + QByteArray::number(body.size()) + "\r\n\r\n" + body;
                socket->write(response);
                socket->disconnectFromHost();
            });
        }
    });

    const QUrl apiBaseUrl(QStringLiteral("http://127.0.0.1:%1/api/v1/").arg(server.serverPort()));
    OpenSubtitlesClient client(nullptr, apiBaseUrl);
    client.setApiKey(QStringLiteral("local-test-key"));

    QTemporaryFile mediaFile;
    if (!mediaFile.open()) {
        std::fprintf(stderr, "failed: local moviehash fixture could not be created\n");
        return 1;
    }
    QByteArray mediaBytes;
    mediaBytes.reserve(128 * 1024);
    for (int i = 0; i < 512; ++i) {
        for (int byte = 0; byte < 256; ++byte)
            mediaBytes.append(char(byte));
    }
    if (mediaFile.write(mediaBytes) != mediaBytes.size() || !mediaFile.flush()) {
        std::fprintf(stderr, "failed: local moviehash fixture could not be written\n");
        return 1;
    }

    QEventLoop waitForSearch;
    QTimer timeout;
    timeout.setSingleShot(true);
    QObject::connect(&timeout, &QTimer::timeout, &waitForSearch, &QEventLoop::quit);
    QObject::connect(&client, &OpenSubtitlesClient::resultsChanged, &waitForSearch, [&] {
        if (!client.searching() && (!client.results().isEmpty() || !client.error().isEmpty()))
            waitForSearch.quit();
    });
    timeout.start(5000);
    client.search(QStringLiteral("InterStellar"), QStringLiteral("en"),
                  QUrl::fromLocalFile(mediaFile.fileName()));
    if (client.searching())
        waitForSearch.exec();

    bool ok = true;
    ok &= expect(requestBytes.startsWith("GET /api/v1/subtitles?"), "requests the subtitles search endpoint");
    ok &= expect(requestBytes.contains("languages=en") && requestBytes.contains("query=interstellar"),
                 "sends normalized title and language query parameters");
    ok &= expect(requestBytes.contains("moviehash=a0601fdf9f610000"),
                 "computes and sends the OpenSubtitles moviehash for a local media file");
    ok &= expect(requestBytes.toLower().contains("api-key: local-test-key"), "sends the configured API key");
    ok &= expect(!client.searching() && client.error().isEmpty(), "finishes search without an error");
    ok &= expect(client.results().size() == 1, "parses one subtitle result");
    if (client.results().size() == 1) {
        const QVariantMap result = client.results().first().toMap();
        ok &= expect(result.value(QStringLiteral("title")).toString() == QStringLiteral("Interstellar"),
                     "maps the movie title");
        ok &= expect(result.value(QStringLiteral("release")).toString() == QStringLiteral("Interstellar.2014.1080p"),
                     "maps the release label");
        ok &= expect(result.value(QStringLiteral("languageCode")).toString() == QStringLiteral("en"),
                     "maps the language code");
        ok &= expect(result.value(QStringLiteral("hearingImpaired")).toBool(), "maps the SDH flag");
        ok &= expect(result.value(QStringLiteral("downloadCount")).toInt() == 1234, "maps the download count");
        ok &= expect(qAbs(result.value(QStringLiteral("rating")).toDouble() - 9.2) < 0.001,
                     "maps the rating");
        ok &= expect(result.value(QStringLiteral("movieHashMatch")).toBool(), "maps the exact-file marker");
        ok &= expect(result.value(QStringLiteral("fileId")).toInt() == 987654, "maps the subtitle file id");
    }
    client.clearApiKey();
    return ok ? 0 : 1;
}
