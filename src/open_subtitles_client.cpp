#include "open_subtitles_client.hpp"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileDevice>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QSaveFile>
#include <QSettings>
#include <QStandardPaths>
#include <QUrl>
#include <QUrlQuery>
#include <QtConcurrent/QtConcurrentRun>
#include <QtEndian>

#include <utility>

namespace {
const QString kApiKeySetting = QStringLiteral("openSubtitles/apiKey");
constexpr qint64 kMovieHashChunkSize = 64 * 1024;

QString movieHash(const QString &path)
{
    QFile file(path);
    const qint64 size = file.size();
    if (size < 2 * kMovieHashChunkSize || !file.open(QIODevice::ReadOnly))
        return {};

    quint64 hash = quint64(size);
    const qint64 offsets[] = { 0, size - kMovieHashChunkSize };
    for (const qint64 offset : offsets) {
        if (!file.seek(offset))
            return {};
        const QByteArray chunk = file.read(kMovieHashChunkSize);
        if (chunk.size() != kMovieHashChunkSize)
            return {};
        for (qsizetype index = 0; index < chunk.size(); index += qsizetype(sizeof(quint64)))
            hash += qFromLittleEndian<quint64>(reinterpret_cast<const uchar *>(chunk.constData() + index));
    }
    return QStringLiteral("%1").arg(hash, 16, 16, QLatin1Char('0'));
}
}

OpenSubtitlesClient::OpenSubtitlesClient(QObject *parent)
    : OpenSubtitlesClient(parent, QUrl(QStringLiteral("https://api.opensubtitles.com/api/v1")))
{
}

OpenSubtitlesClient::OpenSubtitlesClient(QObject *parent, const QUrl &apiBaseUrl)
    : QObject(parent)
    , m_apiBaseUrl(apiBaseUrl)
    , m_network(this)
    , m_hashWatcher(this)
{
    connect(&m_hashWatcher, &QFutureWatcher<QString>::finished, this, [this] {
        requestSearch(m_pendingQuery, m_pendingLanguage, m_pendingKey,
                      m_hashWatcher.result(), m_searchId);
    });
}

bool OpenSubtitlesClient::apiKeyConfigured() const
{
    return !QSettings().value(kApiKeySetting).toString().trimmed().isEmpty();
}

void OpenSubtitlesClient::setApiKey(const QString &key)
{
    const bool wasConfigured = apiKeyConfigured();
    const QString normalized = key.trimmed();
    QSettings settings;
    if (normalized.isEmpty())
        settings.remove(kApiKeySetting);
    else
        settings.setValue(kApiKeySetting, normalized);
    settings.sync();
    QFile::setPermissions(settings.fileName(), QFileDevice::ReadOwner | QFileDevice::WriteOwner);
    if (wasConfigured != apiKeyConfigured())
        emit apiKeyConfiguredChanged();
}

void OpenSubtitlesClient::clearApiKey()
{
    setApiKey({});
}

void OpenSubtitlesClient::setSearching(bool searching)
{
    if (m_searching == searching)
        return;
    m_searching = searching;
    emit searchingChanged();
}

void OpenSubtitlesClient::setDownloading(bool downloading)
{
    if (m_downloading == downloading)
        return;
    m_downloading = downloading;
    emit downloadingChanged();
}

void OpenSubtitlesClient::setError(QString error)
{
    if (m_error == error)
        return;
    m_error = std::move(error);
    emit errorChanged();
}

void OpenSubtitlesClient::search(const QString &query, const QString &language, const QUrl &mediaUrl)
{
    if (m_searching)
        return;
    const QString key = QSettings().value(kApiKeySetting).toString().trimmed();
    const QString normalizedQuery = query.trimmed();
    const quint64 requestId = ++m_searchId;
    m_results.clear();
    emit resultsChanged();
    setError({});

    if (key.isEmpty()) {
        setSearching(false);
        setError(QStringLiteral("Add your OpenSubtitles API key in Subtitle Settings to search."));
        return;
    }
    if (normalizedQuery.isEmpty()) {
        setSearching(false);
        setError(QStringLiteral("Enter a movie or episode title."));
        return;
    }

    setSearching(true);
    if (mediaUrl.isLocalFile() && QFileInfo::exists(mediaUrl.toLocalFile())) {
        const QString localPath = mediaUrl.toLocalFile();
        m_pendingQuery = normalizedQuery;
        m_pendingLanguage = language;
        m_pendingKey = key;
        m_hashWatcher.setFuture(QtConcurrent::run([localPath] { return movieHash(localPath); }));
        return;
    }
    requestSearch(normalizedQuery, language, key, {}, requestId);
}

void OpenSubtitlesClient::requestSearch(const QString &normalizedQuery, const QString &language,
                                       const QString &key, const QString &movieHashValue,
                                       quint64 requestId)
{
    if (requestId != m_searchId)
        return;
    QUrl url = m_apiBaseUrl;
    url.setPath(url.path().chopped(url.path().endsWith(QLatin1Char('/')) ? 1 : 0)
                 + QStringLiteral("/subtitles"));
    QUrlQuery parameters;
    if (!language.isEmpty() && language != QLatin1String("all"))
        parameters.addQueryItem(QStringLiteral("languages"), language.toLower());
    if (!movieHashValue.isEmpty())
        parameters.addQueryItem(QStringLiteral("moviehash"), movieHashValue);
    parameters.addQueryItem(QStringLiteral("query"), normalizedQuery.toCaseFolded());
    url.setQuery(parameters);

    QNetworkRequest request(url);
    request.setHeader(QNetworkRequest::UserAgentHeader,
                      QStringLiteral("VLC Neo v%1").arg(QCoreApplication::applicationVersion()));
    request.setRawHeader("Api-Key", key.toUtf8());
    request.setRawHeader("Accept", "application/json");
    request.setTransferTimeout(20000);

    QNetworkReply *reply = m_network.get(request);
    connect(reply, &QNetworkReply::finished, this, [this, reply, requestId] {
        const QByteArray body = reply->readAll();
        const auto status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const auto networkError = reply->error();
        const QString networkMessage = reply->errorString();
        reply->deleteLater();
        if (requestId != m_searchId)
            return;
        setSearching(false);

        if (networkError != QNetworkReply::NoError) {
            if (status == 401 || status == 403)
                setError(QStringLiteral("OpenSubtitles rejected the API key. Check it in Subtitle Settings."));
            else if (status == 429)
                setError(QStringLiteral("OpenSubtitles search limit reached. Try again later."));
            else
                setError(QStringLiteral("OpenSubtitles request failed: %1").arg(networkMessage));
            return;
        }

        QJsonParseError parseError;
        const QJsonDocument document = QJsonDocument::fromJson(body, &parseError);
        if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
            setError(QStringLiteral("OpenSubtitles returned an invalid response."));
            return;
        }
        const QJsonArray data = document.object().value(QStringLiteral("data")).toArray();
        QVariantList found;
        for (const QJsonValue &entry : data) {
            const QJsonObject attributes = entry.toObject().value(QStringLiteral("attributes")).toObject();
            const QJsonObject feature = attributes.value(QStringLiteral("feature_details")).toObject();
            const QJsonArray files = attributes.value(QStringLiteral("files")).toArray();
            if (files.isEmpty())
                continue;
            QVariantMap result;
            result.insert(QStringLiteral("title"), feature.value(QStringLiteral("movie_name")).toString());
            result.insert(QStringLiteral("release"), attributes.value(QStringLiteral("release")).toString());
            result.insert(QStringLiteral("language"), attributes.value(QStringLiteral("language")).toString());
            result.insert(QStringLiteral("languageCode"), attributes.value(QStringLiteral("language")).toString());
            result.insert(QStringLiteral("hearingImpaired"), attributes.value(QStringLiteral("hearing_impaired")).toBool());
            result.insert(QStringLiteral("downloadCount"), attributes.value(QStringLiteral("download_count")).toInt());
            result.insert(QStringLiteral("rating"), attributes.value(QStringLiteral("ratings")).toDouble());
            result.insert(QStringLiteral("movieHashMatch"), attributes.value(QStringLiteral("moviehash_match")).toBool());
            result.insert(QStringLiteral("pageUrl"), attributes.value(QStringLiteral("url")).toString());
            result.insert(QStringLiteral("fileId"), files.first().toObject().value(QStringLiteral("file_id")).toInt());
            found.append(result);
        }
        m_results = found;
        emit resultsChanged();
        if (found.isEmpty())
            setError(QStringLiteral("No subtitles found for this title and language."));
    });
}

void OpenSubtitlesClient::download(int fileId)
{
    if (m_downloading)
        return;
    const QString key = QSettings().value(kApiKeySetting).toString().trimmed();
    if (key.isEmpty()) {
        setError(QStringLiteral("Add your OpenSubtitles API key in Subtitle Settings to download."));
        return;
    }
    if (fileId <= 0) {
        setError(QStringLiteral("Select a subtitle result first."));
        return;
    }

    QString directory = QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation);
    if (directory.isEmpty()) {
        setError(QStringLiteral("VLC Neo could not find a local data folder for downloaded subtitles."));
        return;
    }
    directory = QDir(directory).filePath(QStringLiteral("Subtitles/OpenSubtitles"));
    if (!QDir().mkpath(directory)) {
        setError(QStringLiteral("VLC Neo could not create its downloaded subtitles folder."));
        return;
    }
    const QString filePath = QDir(directory).filePath(QStringLiteral("opensubtitles-%1.srt").arg(fileId));
    const QUrl fileUrl = QUrl::fromLocalFile(filePath);
    if (QFile::exists(filePath)) {
        setError({});
        emit subtitleReady(fileUrl);
        return;
    }

    ++m_downloadId;
    setError({});
    setDownloading(true);
    QUrl downloadUrl = m_apiBaseUrl;
    downloadUrl.setPath(downloadUrl.path().chopped(downloadUrl.path().endsWith(QLatin1Char('/')) ? 1 : 0)
                        + QStringLiteral("/download"));
    QNetworkRequest request(downloadUrl);
    request.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
    request.setRawHeader("Api-Key", key.toUtf8());
    request.setRawHeader("Accept", "application/json");
    request.setHeader(QNetworkRequest::UserAgentHeader,
                      QStringLiteral("VLC Neo v%1").arg(QCoreApplication::applicationVersion()));
    request.setTransferTimeout(30000);
    const QByteArray body = QJsonDocument(QJsonObject{
        {QStringLiteral("file_id"), fileId},
        {QStringLiteral("sub_format"), QStringLiteral("srt")}
    }).toJson(QJsonDocument::Compact);
    QNetworkReply *reply = m_network.post(request, body);
    const quint64 requestId = m_downloadId;
    connect(reply, &QNetworkReply::finished, this, [this, reply, fileUrl, requestId] {
        const QByteArray data = reply->readAll();
        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const auto networkError = reply->error();
        const QString networkMessage = reply->errorString();
        reply->deleteLater();
        if (requestId != m_downloadId)
            return;
        if (networkError != QNetworkReply::NoError) {
            setDownloading(false);
            if (status == 401 || status == 403)
                setError(QStringLiteral("OpenSubtitles rejected the API key or download request."));
            else if (status == 429)
                setError(QStringLiteral("OpenSubtitles download limit reached. Try again later."));
            else
                setError(QStringLiteral("OpenSubtitles download request failed: %1").arg(networkMessage));
            return;
        }
        const QJsonDocument response = QJsonDocument::fromJson(data);
        const QUrl downloadUrl(response.object().value(QStringLiteral("link")).toString());
        if (!downloadUrl.isValid() || downloadUrl.scheme() != QLatin1String("https")) {
            setDownloading(false);
            setError(QStringLiteral("OpenSubtitles did not provide a secure download link."));
            return;
        }

        QNetworkRequest fileRequest(downloadUrl);
        fileRequest.setHeader(QNetworkRequest::UserAgentHeader,
                              QStringLiteral("VLC Neo v%1").arg(QCoreApplication::applicationVersion()));
        fileRequest.setTransferTimeout(30000);
        QNetworkReply *fileReply = m_network.get(fileRequest);
        connect(fileReply, &QNetworkReply::finished, this, [this, fileReply, fileUrl, requestId] {
            const QByteArray subtitle = fileReply->readAll();
            const auto error = fileReply->error();
            const QString errorMessage = fileReply->errorString();
            fileReply->deleteLater();
            if (requestId != m_downloadId)
                return;
            setDownloading(false);
            if (error != QNetworkReply::NoError) {
                setError(QStringLiteral("Could not fetch the subtitle file: %1").arg(errorMessage));
                return;
            }
            if (subtitle.isEmpty() || subtitle.size() > 20 * 1024 * 1024
                || subtitle.startsWith("PK\x03\x04")) {
                setError(QStringLiteral("OpenSubtitles returned an empty, oversized or zipped file."));
                return;
            }
            QSaveFile file(fileUrl.toLocalFile());
            if (!file.open(QIODevice::WriteOnly) || file.write(subtitle) != subtitle.size() || !file.commit()) {
                setError(QStringLiteral("Could not save the downloaded subtitle."));
                return;
            }
            setError({});
            emit subtitleReady(fileUrl);
        });
    });
}
