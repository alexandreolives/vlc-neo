#pragma once

#include <QObject>
#include <QHostAddress>
#include <QHash>
#include <QSharedPointer>
#include <QDateTime>
#include <QUrl>

class QTcpServer;
class QTcpSocket;

class LocalMediaHttpServer final : public QObject
{
public:
    explicit LocalMediaHttpServer(QObject *parent = nullptr);
    ~LocalMediaHttpServer() override;

    bool start(const QUrl &mediaUrl, const QHostAddress &bindAddress,
               QUrl *publishedUrl, QString *error = nullptr);
    static QHostAddress routeAddressFor(const QUrl &remoteEndpoint, QString *error = nullptr);
    void stop();
    bool isActive() const;
    QString contentType() const;
    qint64 contentLength() const;

private:
    struct Client;
    void acceptConnections();
    void readRequest(QTcpSocket *socket, const QSharedPointer<Client> &client);
    void pumpResponse(QTcpSocket *socket, const QSharedPointer<Client> &client);
    void sendError(QTcpSocket *socket, int status, const QByteArray &reason);

    QTcpServer *m_server = nullptr;
    QHash<QTcpSocket *, QSharedPointer<Client>> m_clients;
    QString m_mediaPath;
    QString m_contentType;
    QString m_token;
    qint64 m_contentLength = 0;
    QDateTime m_modified;
};
