#include "local_media_http_server.hpp"

#include <QDateTime>
#include <QFile>
#include <QFileInfo>
#include <QHostInfo>
#include <QMimeDatabase>
#include <QRegularExpression>
#include <QTcpServer>
#include <QTcpSocket>
#include <QTimer>
#include <QUdpSocket>
#include <QUuid>
#include <algorithm>

namespace {
constexpr qsizetype kMaximumHeaderBytes = 16 * 1024;
constexpr int kMaximumClients = 4;
constexpr qint64 kChunkBytes = 64 * 1024;
constexpr qint64 kMaximumBufferedBytes = 256 * 1024;

QByteArray statusLine(int status, const QByteArray &reason)
{
    return QByteArrayLiteral("HTTP/1.1 ") + QByteArray::number(status) + ' ' + reason + "\r\n";
}
}

struct LocalMediaHttpServer::Client {
    QFile file;
    QByteArray request;
    QTimer *headerTimer = nullptr;
    qint64 offset = 0;
    qint64 end = -1;
    bool parsed = false;
    bool headOnly = false;
};

LocalMediaHttpServer::LocalMediaHttpServer(QObject *parent)
    : QObject(parent), m_server(new QTcpServer(this))
{
    connect(m_server, &QTcpServer::newConnection, this, &LocalMediaHttpServer::acceptConnections);
}

LocalMediaHttpServer::~LocalMediaHttpServer()
{
    stop();
}

bool LocalMediaHttpServer::start(const QUrl &mediaUrl, const QHostAddress &bindAddress,
                                 QUrl *publishedUrl, QString *error)
{
    stop();
    if (!publishedUrl) {
        if (error) *error = QStringLiteral("No output URL was provided");
        return false;
    }
    if (bindAddress.isNull() || bindAddress.isMulticast()
        || bindAddress == QHostAddress::Any || bindAddress == QHostAddress::AnyIPv4
        || bindAddress == QHostAddress::AnyIPv6 || bindAddress.isBroadcast()) {
        if (error) *error = QStringLiteral("A unicast local bind address is required");
        return false;
    }
    if (!mediaUrl.isLocalFile()) {
        if (error) *error = QStringLiteral("Only local files can be served by this relay");
        return false;
    }

    const QFileInfo info(mediaUrl.toLocalFile());
    const QString canonicalPath = info.canonicalFilePath();
    if (canonicalPath.isEmpty() || !info.isFile() || !info.isReadable()) {
        if (error) *error = QStringLiteral("The current media file is not readable");
        return false;
    }

    if (!m_server->listen(bindAddress, 0)) {
        if (error) *error = QStringLiteral("Could not start the local media relay: %1").arg(m_server->errorString());
        return false;
    }

    m_mediaPath = canonicalPath;
    m_contentLength = info.size();
    m_modified = info.lastModified();
    m_contentType = QMimeDatabase().mimeTypeForFile(info).name();
    if (m_contentType.isEmpty() || m_contentType == QLatin1String("application/octet-stream"))
        m_contentType = QStringLiteral("application/octet-stream");
    m_token = QUuid::createUuid().toString(QUuid::WithoutBraces);

    QUrl url;
    url.setScheme(QStringLiteral("http"));
    url.setHost(bindAddress.toString());
    url.setPort(m_server->serverPort());
    url.setPath(QLatin1Char('/') + m_token + QLatin1Char('/') + info.fileName());
    *publishedUrl = url;
    return true;
}

QHostAddress LocalMediaHttpServer::routeAddressFor(const QUrl &remoteEndpoint, QString *error)
{
    QHostAddress remoteAddress(remoteEndpoint.host());
    if (remoteAddress.isNull()) {
        const QHostInfo resolved = QHostInfo::fromName(remoteEndpoint.host());
        for (const QHostAddress &address : resolved.addresses()) {
            if (address.protocol() == QAbstractSocket::IPv4Protocol) {
                remoteAddress = address;
                break;
            }
        }
    }
    if (remoteAddress.isNull() || remoteAddress.protocol() != QAbstractSocket::IPv4Protocol) {
        if (error) *error = QStringLiteral("The renderer does not have a reachable IPv4 address");
        return {};
    }

    QUdpSocket routeProbe;
    routeProbe.connectToHost(remoteAddress, remoteEndpoint.port(80));
    const QHostAddress localAddress = routeProbe.localAddress();
    if (localAddress.isNull()) {
        if (error) *error = QStringLiteral("Could not determine the network address to reach the renderer");
        return {};
    }
    return localAddress;
}

void LocalMediaHttpServer::stop()
{
    if (m_server->isListening())
        m_server->close();
    const auto sockets = m_clients.keys();
    for (QTcpSocket *socket : sockets) {
        if (socket)
            socket->abort();
    }
    m_clients.clear();
    m_mediaPath.clear();
    m_contentType.clear();
    m_token.clear();
    m_contentLength = 0;
    m_modified = {};
}

bool LocalMediaHttpServer::isActive() const
{
    return m_server->isListening() && !m_token.isEmpty();
}

QString LocalMediaHttpServer::contentType() const
{
    return m_contentType;
}

qint64 LocalMediaHttpServer::contentLength() const
{
    return m_contentLength;
}

void LocalMediaHttpServer::acceptConnections()
{
    while (m_server->hasPendingConnections()) {
        QTcpSocket *socket = m_server->nextPendingConnection();
        if (!socket)
            continue;
        if (m_clients.size() >= kMaximumClients) {
            connect(socket, &QTcpSocket::disconnected, socket, &QObject::deleteLater);
            sendError(socket, 503, QByteArrayLiteral("Service Unavailable"));
            continue;
        }

        const QSharedPointer<Client> client(new Client);
        client->headerTimer = new QTimer(socket);
        client->headerTimer->setSingleShot(true);
        client->headerTimer->setInterval(5000);
        connect(client->headerTimer, &QTimer::timeout, socket, &QTcpSocket::disconnectFromHost);
        client->headerTimer->start();
        m_clients.insert(socket, client);
        connect(socket, &QTcpSocket::readyRead, this, [this, socket, client] {
            readRequest(socket, client);
        });
        connect(socket, &QTcpSocket::bytesWritten, this, [this, socket, client] {
            pumpResponse(socket, client);
        });
        connect(socket, &QTcpSocket::disconnected, this, [this, socket] {
            m_clients.remove(socket);
            socket->deleteLater();
        });
    }
}

void LocalMediaHttpServer::readRequest(QTcpSocket *socket, const QSharedPointer<Client> &client)
{
    if (!socket || client->parsed)
        return;
    client->request += socket->readAll();
    if (client->request.size() > kMaximumHeaderBytes) {
        sendError(socket, 431, QByteArrayLiteral("Request Header Fields Too Large"));
        return;
    }
    const qsizetype headerEnd = client->request.indexOf(QByteArrayLiteral("\r\n\r\n"));
    if (headerEnd < 0)
        return;

    client->parsed = true;
    client->headerTimer->stop();
    const QList<QByteArray> lines = client->request.left(headerEnd).split('\n');
    if (lines.isEmpty()) {
        sendError(socket, 400, QByteArrayLiteral("Bad Request"));
        return;
    }
    const QList<QByteArray> requestLine = lines.first().trimmed().split(' ');
    if (requestLine.size() != 3 || !requestLine.at(2).startsWith("HTTP/1.")) {
        sendError(socket, 400, QByteArrayLiteral("Bad Request"));
        return;
    }

    const QByteArray method = requestLine.at(0);
    client->headOnly = method == QByteArrayLiteral("HEAD");
    if (method != QByteArrayLiteral("GET") && !client->headOnly) {
        socket->write(statusLine(405, QByteArrayLiteral("Method Not Allowed"))
                      + QByteArrayLiteral("Allow: GET, HEAD\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"));
        socket->disconnectFromHost();
        return;
    }
    QUrl expectedUrl;
    expectedUrl.setPath(QLatin1Char('/') + m_token + QLatin1Char('/') + QFileInfo(m_mediaPath).fileName());
    if (requestLine.at(1) != expectedUrl.path(QUrl::FullyEncoded).toUtf8()) {
        sendError(socket, 404, QByteArrayLiteral("Not Found"));
        return;
    }

    QHash<QByteArray, QByteArray> headers;
    for (qsizetype i = 1; i < lines.size(); ++i) {
        const QByteArray line = lines.at(i).trimmed();
        const qsizetype colon = line.indexOf(':');
        if (colon > 0)
            headers.insert(line.left(colon).trimmed().toLower(), line.mid(colon + 1).trimmed());
    }

    const QFileInfo currentInfo(m_mediaPath);
    if (currentInfo.canonicalFilePath() != m_mediaPath || !currentInfo.isFile()
        || currentInfo.size() != m_contentLength || currentInfo.lastModified() != m_modified) {
        sendError(socket, 410, QByteArrayLiteral("Gone"));
        return;
    }

    qint64 start = 0;
    qint64 end = m_contentLength - 1;
    bool partial = false;
    const QByteArray range = headers.value(QByteArrayLiteral("range"));
    if (!range.isEmpty()) {
        static const QRegularExpression expression(QStringLiteral("^bytes=(\\d*)-(\\d*)$"));
        const auto match = expression.match(QString::fromLatin1(range));
        if (!match.hasMatch() || m_contentLength == 0) {
            socket->write(statusLine(416, QByteArrayLiteral("Range Not Satisfiable"))
                          + QByteArrayLiteral("Accept-Ranges: bytes\r\nContent-Range: bytes */")
                          + QByteArray::number(m_contentLength)
                          + QByteArrayLiteral("\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"));
            socket->disconnectFromHost();
            return;
        }
        bool firstOk = true;
        bool secondOk = true;
        const QString first = match.captured(1);
        const QString second = match.captured(2);
        if (first.isEmpty()) {
            const qint64 suffix = second.toLongLong(&secondOk);
            if (!secondOk || suffix <= 0) {
                socket->write(statusLine(416, QByteArrayLiteral("Range Not Satisfiable"))
                              + QByteArrayLiteral("Content-Range: bytes */") + QByteArray::number(m_contentLength)
                              + QByteArrayLiteral("\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"));
                socket->disconnectFromHost();
                return;
            }
            start = std::max<qint64>(0, m_contentLength - suffix);
        } else {
            start = first.toLongLong(&firstOk);
            if (!second.isEmpty())
                end = second.toLongLong(&secondOk);
        }
        if (!firstOk || !secondOk || start >= m_contentLength || end < start) {
            socket->write(statusLine(416, QByteArrayLiteral("Range Not Satisfiable"))
                          + QByteArrayLiteral("Content-Range: bytes */") + QByteArray::number(m_contentLength)
                          + QByteArrayLiteral("\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"));
            socket->disconnectFromHost();
            return;
        }
        end = std::min(end, m_contentLength - 1);
        partial = true;
    }

    if (method == QByteArrayLiteral("GET"))
        client->file.setFileName(m_mediaPath);
    if (method == QByteArrayLiteral("GET") && !client->file.open(QIODevice::ReadOnly)) {
        sendError(socket, 404, QByteArrayLiteral("Not Found"));
        return;
    }
    if (method == QByteArrayLiteral("GET") && !client->file.seek(start)) {
        sendError(socket, 500, QByteArrayLiteral("Internal Server Error"));
        return;
    }

    client->offset = start;
    client->end = end;
    QByteArray response = statusLine(partial ? 206 : 200,
                                     partial ? QByteArrayLiteral("Partial Content") : QByteArrayLiteral("OK"));
    response += QByteArrayLiteral("Content-Type: ") + m_contentType.toLatin1() + "\r\n";
    response += QByteArrayLiteral("Accept-Ranges: bytes\r\n");
    if (partial)
        response += QByteArrayLiteral("Content-Range: bytes ") + QByteArray::number(start) + '-'
            + QByteArray::number(end) + '/' + QByteArray::number(m_contentLength) + "\r\n";
    response += QByteArrayLiteral("Content-Length: ") + QByteArray::number(end - start + 1) + "\r\n";
    response += QByteArrayLiteral("Connection: close\r\n\r\n");
    socket->write(response);
    if (client->headOnly || end < start) {
        socket->disconnectFromHost();
        return;
    }
    pumpResponse(socket, client);
}

void LocalMediaHttpServer::pumpResponse(QTcpSocket *socket, const QSharedPointer<Client> &client)
{
    if (!socket || !client->parsed || client->headOnly || !client->file.isOpen())
        return;
    while (client->offset <= client->end && socket->bytesToWrite() < kMaximumBufferedBytes) {
        const qint64 remaining = client->end - client->offset + 1;
        const qint64 capacity = kMaximumBufferedBytes - socket->bytesToWrite();
        const QByteArray chunk = client->file.read(std::min({kChunkBytes, capacity, remaining}));
        if (chunk.isEmpty()) {
            socket->abort();
            return;
        }
        const qint64 accepted = socket->write(chunk);
        if (accepted < 0) {
            socket->abort();
            return;
        }
        client->offset += accepted;
        if (accepted != chunk.size()) {
            client->file.seek(client->offset);
            break;
        }
    }
    if (client->offset > client->end && socket->bytesToWrite() == 0)
        socket->disconnectFromHost();
}

void LocalMediaHttpServer::sendError(QTcpSocket *socket, int status, const QByteArray &reason)
{
    if (!socket)
        return;
    socket->write(statusLine(status, reason) + QByteArrayLiteral("Content-Length: 0\r\nConnection: close\r\n\r\n"));
    socket->disconnectFromHost();
}
