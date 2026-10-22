#pragma once

#include <QObject>
#include <QFutureWatcher>
#include <QNetworkAccessManager>
#include <QUrl>
#include <QVariantList>

class OpenSubtitlesClient final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool apiKeyConfigured READ apiKeyConfigured NOTIFY apiKeyConfiguredChanged)
    Q_PROPERTY(bool searching READ searching NOTIFY searchingChanged)
    Q_PROPERTY(bool downloading READ downloading NOTIFY downloadingChanged)
    Q_PROPERTY(QVariantList results READ results NOTIFY resultsChanged)
    Q_PROPERTY(QString error READ error NOTIFY errorChanged)

public:
    explicit OpenSubtitlesClient(QObject *parent = nullptr);
    // Allows deterministic local API fixtures; the default uses OpenSubtitles over HTTPS.
    OpenSubtitlesClient(QObject *parent, const QUrl &apiBaseUrl);

    bool apiKeyConfigured() const;
    bool searching() const { return m_searching; }
    bool downloading() const { return m_downloading; }
    QVariantList results() const { return m_results; }
    QString error() const { return m_error; }

    Q_INVOKABLE void setApiKey(const QString &key);
    Q_INVOKABLE void clearApiKey();
    Q_INVOKABLE void search(const QString &query, const QString &language, const QUrl &mediaUrl = {});
    Q_INVOKABLE void download(int fileId);

signals:
    void apiKeyConfiguredChanged();
    void searchingChanged();
    void downloadingChanged();
    void resultsChanged();
    void errorChanged();
    void subtitleReady(const QUrl &fileUrl);

private:
    void setSearching(bool searching);
    void setDownloading(bool downloading);
    void setError(QString error);
    void requestSearch(const QString &query, const QString &language, const QString &key,
                       const QString &movieHash, quint64 requestId);

    QUrl m_apiBaseUrl;
    QNetworkAccessManager m_network;
    QFutureWatcher<QString> m_hashWatcher;
    QVariantList m_results;
    QString m_error;
    QString m_pendingQuery;
    QString m_pendingLanguage;
    QString m_pendingKey;
    quint64 m_searchId = 0;
    quint64 m_downloadId = 0;
    bool m_searching = false;
    bool m_downloading = false;
};
