#include "media_library.hpp"

#include <QCryptographicHash>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QHash>
#include <QSaveFile>
#include <QSet>
#include <QStandardPaths>
#include <QtConcurrent/QtConcurrentRun>

#include <sqlite3.h>

#include <string>
#include <utility>

#include <taglib/attachedpictureframe.h>
#include <taglib/fileref.h>
#include <taglib/flacfile.h>
#include <taglib/flacpicture.h>
#include <taglib/id3v2tag.h>
#include <taglib/mp4coverart.h>
#include <taglib/mp4file.h>
#include <taglib/mp4item.h>
#include <taglib/mp4tag.h>
#include <taglib/mpegfile.h>
#include <taglib/oggflacfile.h>
#include <taglib/vorbisfile.h>
#include <taglib/xiphcomment.h>

namespace {

class SqlStatement
{
public:
    SqlStatement(sqlite3 *db, const char *sql) { sqlite3_prepare_v2(db, sql, -1, &statement, nullptr); }
    ~SqlStatement() { sqlite3_finalize(statement); }
    sqlite3_stmt *statement = nullptr;
};

bool execute(sqlite3 *db, const char *sql, QString *error = nullptr)
{
    char *message = nullptr;
    const int result = sqlite3_exec(db, sql, nullptr, nullptr, &message);
    if (result == SQLITE_OK)
        return true;
    if (error)
        *error = QString::fromUtf8(message ? message : sqlite3_errmsg(db));
    sqlite3_free(message);
    return false;
}

void sqliteCaseFold(sqlite3_context *context, int argumentCount, sqlite3_value **arguments)
{
    if (argumentCount != 1 || sqlite3_value_type(arguments[0]) == SQLITE_NULL) {
        sqlite3_result_null(context);
        return;
    }
    const auto *input = sqlite3_value_text(arguments[0]);
    const QString folded = QString::fromUtf8(reinterpret_cast<const char *>(input)).toCaseFolded();
    const QByteArray output = folded.toUtf8();
    sqlite3_result_text(context, output.constData(), output.size(), SQLITE_TRANSIENT);
}

bool openDatabase(const QString &path, sqlite3 **db, QString *error = nullptr)
{
    const QByteArray filename = QFile::encodeName(path);
    if (sqlite3_open_v2(filename.constData(), db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX, nullptr) != SQLITE_OK) {
        if (error && *db)
            *error = QString::fromUtf8(sqlite3_errmsg(*db));
        if (*db)
            sqlite3_close_v2(*db);
        *db = nullptr;
        return false;
    }
    sqlite3_busy_timeout(*db, 30000);
    sqlite3_create_function_v2(*db, "casefold", 1, SQLITE_UTF8 | SQLITE_DETERMINISTIC, nullptr, sqliteCaseFold, nullptr, nullptr, nullptr);
    return true;
}

QByteArray bytes(const TagLib::ByteVector &value)
{
    return QByteArray(value.data(), int(value.size()));
}

QString tagString(const TagLib::String &value)
{
    const std::string utf8 = value.to8Bit(true);
    return QString::fromUtf8(utf8.data(), int(utf8.size())).trimmed();
}

struct Tags {
    QString title, artist, album, genre, artworkMime;
    QByteArray artwork;
    qint64 duration = 0;
};

Tags readTags(const QString &path)
{
    Tags tags;
    const QByteArray encodedPath = QFile::encodeName(path);
    TagLib::FileRef ref(encodedPath.constData(), true, TagLib::AudioProperties::Fast);
    if (ref.isNull())
        return tags;
    if (const TagLib::Tag *tag = ref.tag()) {
        tags.title = tagString(tag->title());
        tags.artist = tagString(tag->artist());
        tags.album = tagString(tag->album());
        tags.genre = tagString(tag->genre());
    }
    if (const TagLib::AudioProperties *properties = ref.audioProperties())
        tags.duration = qMax(0, properties->lengthInSeconds());

    if (auto *mpeg = dynamic_cast<TagLib::MPEG::File *>(ref.file())) {
        if (TagLib::ID3v2::Tag *id3 = mpeg->ID3v2Tag()) {
            const auto frames = id3->frameListMap().value("APIC");
            for (TagLib::ID3v2::Frame *frame : frames) {
                if (auto *picture = dynamic_cast<TagLib::ID3v2::AttachedPictureFrame *>(frame)) {
                    tags.artwork = bytes(picture->picture());
                    tags.artworkMime = tagString(picture->mimeType());
                    if (!tags.artwork.isEmpty())
                        break;
                }
            }
        }
    } else if (auto *flac = dynamic_cast<TagLib::FLAC::File *>(ref.file())) {
        for (TagLib::FLAC::Picture *picture : flac->pictureList()) {
            tags.artwork = bytes(picture->data());
            tags.artworkMime = tagString(picture->mimeType());
            if (!tags.artwork.isEmpty())
                break;
        }
    } else if (auto *mp4 = dynamic_cast<TagLib::MP4::File *>(ref.file())) {
        if (TagLib::MP4::Tag *tag = mp4->tag()) {
            const auto items = tag->itemMap();
            if (items.contains("covr")) {
                const auto covers = items.value("covr").toCoverArtList();
                if (!covers.isEmpty()) {
                    const TagLib::MP4::CoverArt &cover = covers.front();
                    tags.artwork = bytes(cover.data());
                    switch (cover.format()) {
                    case TagLib::MP4::CoverArt::PNG: tags.artworkMime = QStringLiteral("image/png"); break;
                    case TagLib::MP4::CoverArt::GIF: tags.artworkMime = QStringLiteral("image/gif"); break;
                    case TagLib::MP4::CoverArt::BMP: tags.artworkMime = QStringLiteral("image/bmp"); break;
                    default: tags.artworkMime = QStringLiteral("image/jpeg"); break;
                    }
                }
            }
        }
    } else if (auto *vorbis = dynamic_cast<TagLib::Ogg::Vorbis::File *>(ref.file())) {
        if (TagLib::Ogg::XiphComment *tag = vorbis->tag()) {
            for (TagLib::FLAC::Picture *picture : tag->pictureList()) {
                tags.artwork = bytes(picture->data());
                tags.artworkMime = tagString(picture->mimeType());
                if (!tags.artwork.isEmpty())
                    break;
            }
        }
    } else if (auto *oggFlac = dynamic_cast<TagLib::Ogg::FLAC::File *>(ref.file())) {
        if (TagLib::Ogg::XiphComment *tag = oggFlac->tag()) {
            for (TagLib::FLAC::Picture *picture : tag->pictureList()) {
                tags.artwork = bytes(picture->data());
                tags.artworkMime = tagString(picture->mimeType());
                if (!tags.artwork.isEmpty())
                    break;
            }
        }
    }
    return tags;
}

QString artworkExtension(const QByteArray &data, const QString &mime)
{
    if (mime == QLatin1String("image/png") || data.startsWith(QByteArray::fromHex("89504e470d0a1a0a"))) return QStringLiteral("png");
    if (mime == QLatin1String("image/webp") || (data.startsWith("RIFF") && data.mid(8, 4) == "WEBP")) return QStringLiteral("webp");
    if (mime == QLatin1String("image/gif") || data.startsWith("GIF8")) return QStringLiteral("gif");
    if (mime == QLatin1String("image/bmp") || data.startsWith("BM")) return QStringLiteral("bmp");
    if (mime == QLatin1String("image/jpeg") || data.startsWith(QByteArray::fromHex("ffd8ff"))) return QStringLiteral("jpg");
    return {};
}

QString storeArtwork(const Tags &tags, const QString &directory)
{
    if (tags.artwork.isEmpty() || tags.artwork.size() > 12 * 1024 * 1024)
        return {};
    const QString extension = artworkExtension(tags.artwork, tags.artworkMime);
    if (extension.isEmpty())
        return {};
    const QByteArray digest = QCryptographicHash::hash(tags.artwork, QCryptographicHash::Sha256).toHex();
    const QString path = QDir(directory).filePath(QString::fromLatin1(digest) + QLatin1Char('.') + extension);
    if (!QFileInfo::exists(path)) {
        QSaveFile file(path);
        if (!file.open(QIODevice::WriteOnly) || file.write(tags.artwork) != tags.artwork.size() || !file.commit())
            return {};
    }
    return path;
}

QString sidecarArtwork(const QString &mediaPath)
{
    const QFileInfo media(mediaPath);
    const QStringList names { QStringLiteral("cover"), QStringLiteral("folder"), QStringLiteral("front") };
    const QStringList extensions { QStringLiteral("jpg"), QStringLiteral("jpeg"), QStringLiteral("png"), QStringLiteral("webp") };
    QDir directory(media.absolutePath());
    for (const QString &name : names)
        for (const QString &extension : extensions) {
            const QString candidate = directory.filePath(name + QLatin1Char('.') + extension);
            if (QFileInfo(candidate).isFile())
                return candidate;
        }
    return {};
}

QString sidecarSignature(const QString &mediaPath, QHash<QString, QString> &cache)
{
    const QString sidecar = sidecarArtwork(mediaPath);
    if (sidecar.isEmpty())
        return {};
    if (cache.contains(sidecar))
        return cache.value(sidecar);

    const QFileInfo info(sidecar);
    QString signature = sidecar + QLatin1Char('\n') + QString::number(info.size())
        + QLatin1Char('\n') + QString::number(info.lastModified().toMSecsSinceEpoch());
    if (info.isReadable() && info.size() <= 12 * 1024 * 1024) {
        QFile file(sidecar);
        if (file.open(QIODevice::ReadOnly)) {
            const QByteArray contents = file.read(12 * 1024 * 1024 + 1);
            if (contents.size() <= 12 * 1024 * 1024)
                signature = QCryptographicHash::hash(contents, QCryptographicHash::Sha256).toHex();
        }
    }
    cache.insert(sidecar, signature);
    return signature;
}

QStringList extensionsForKind(bool audio)
{
    return audio
        ? QStringList { "mp3", "flac", "ogg", "opus", "m4a", "aac", "wav", "wma", "alac", "ape", "mpc", "wv" }
        : QStringList { "mkv", "mp4", "avi", "mov", "webm", "m4v", "wmv", "flv", "ts", "m2ts", "mpg", "mpeg", "3gp", "ogv", "iso" };
}

bool bindText(sqlite3_stmt *statement, int index, const QString &value)
{
    if (!statement)
        return false;
    const QByteArray text = value.toUtf8();
    return sqlite3_bind_text(statement, index, text.constData(), text.size(), SQLITE_TRANSIENT) == SQLITE_OK;
}

QString columnText(sqlite3_stmt *statement, int column);

LibraryScanResult scanFolder(const QString &databasePath, const QString &root, const QString &artworkDirectory)
{
    LibraryScanResult result;
    if (!QFileInfo(root).isReadable()) {
        result.error = QStringLiteral("folder is not readable");
        return result;
    }
    QDirIterator directories(root, QDir::Dirs | QDir::NoDotAndDotDot, QDirIterator::Subdirectories);
    while (directories.hasNext()) {
        const QString path = directories.next();
        if (!QFileInfo(path).isReadable()) {
            result.error = QStringLiteral("a subfolder is not readable: ") + path;
            return result;
        }
    }
    sqlite3 *db = nullptr;
    if (!openDatabase(databasePath, &db, &result.error))
        return result;
    auto finish = [&] { sqlite3_close_v2(db); };
    if (!execute(db, "PRAGMA journal_mode=WAL; CREATE TEMP TABLE IF NOT EXISTS seen_paths(path TEXT PRIMARY KEY); DELETE FROM seen_paths; BEGIN IMMEDIATE;", &result.error)) {
        finish();
        return result;
    }

    SqlStatement find(db, "SELECT size, modified, sidecar_signature FROM media WHERE path=?1");
    SqlStatement seen(db, "INSERT OR IGNORE INTO seen_paths(path) VALUES(?1)");
    SqlStatement insert(db, "INSERT INTO media(path,root,title,artist,album,genre,kind,duration,size,modified,artwork,sidecar_signature) VALUES(?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12) ON CONFLICT(path) DO UPDATE SET root=excluded.root,title=excluded.title,artist=excluded.artist,album=excluded.album,genre=excluded.genre,kind=excluded.kind,duration=excluded.duration,size=excluded.size,modified=excluded.modified,artwork=excluded.artwork,sidecar_signature=excluded.sidecar_signature");
    if (!find.statement || !seen.statement || !insert.statement) {
        result.error = QString::fromUtf8(sqlite3_errmsg(db));
        execute(db, "ROLLBACK;");
        finish();
        return result;
    }

    const QStringList audioExtensions = extensionsForKind(true);
    const QStringList videoExtensions = extensionsForKind(false);
    QHash<QString, QString> sidecarSignatures;
    QDirIterator it(root, QDir::Files | QDir::NoDotAndDotDot, QDirIterator::Subdirectories);
    while (it.hasNext()) {
        const QString path = it.next();
        const QFileInfo info = it.fileInfo();
        const QString suffix = info.suffix().toLower();
        const bool audio = audioExtensions.contains(suffix);
        if (!audio && !videoExtensions.contains(suffix))
            continue;
        if (!info.isReadable()) {
            result.error = QStringLiteral("media file is not readable: ") + path;
            break;
        }
        const qint64 size = info.size();
        const qint64 modified = info.lastModified().toMSecsSinceEpoch();
        const QString artworkSignature = audio ? sidecarSignature(path, sidecarSignatures) : QString();
        sqlite3_reset(seen.statement);
        sqlite3_clear_bindings(seen.statement);
        bindText(seen.statement, 1, path);
        if (sqlite3_step(seen.statement) != SQLITE_DONE) {
            result.error = QString::fromUtf8(sqlite3_errmsg(db));
            break;
        }
        sqlite3_reset(find.statement);
        sqlite3_clear_bindings(find.statement);
        bindText(find.statement, 1, path);
        const int found = sqlite3_step(find.statement);
        if (found == SQLITE_ROW && sqlite3_column_int64(find.statement, 0) == size
            && sqlite3_column_int64(find.statement, 1) == modified
            && columnText(find.statement, 2) == artworkSignature) {
            ++result.indexed;
            continue;
        }

        Tags tags;
        if (audio)
            tags = readTags(path);
        if (tags.title.isEmpty())
            tags.title = info.completeBaseName();
        QString artwork = storeArtwork(tags, artworkDirectory);
        if (artwork.isEmpty() && audio) {
            const QString sidecar = sidecarArtwork(path);
            if (!sidecar.isEmpty()) {
                QFile file(sidecar);
                if (file.open(QIODevice::ReadOnly)) {
                    Tags sidecarTags;
                    sidecarTags.artwork = file.read(12 * 1024 * 1024 + 1);
                    sidecarTags.artworkMime = QFileInfo(sidecar).suffix().toLower() == QLatin1String("png") ? QStringLiteral("image/png") : QStringLiteral("image/jpeg");
                    artwork = storeArtwork(sidecarTags, artworkDirectory);
                }
            }
        }
        sqlite3_reset(insert.statement);
        sqlite3_clear_bindings(insert.statement);
        bindText(insert.statement, 1, path);
        bindText(insert.statement, 2, root);
        bindText(insert.statement, 3, tags.title);
        bindText(insert.statement, 4, tags.artist);
        bindText(insert.statement, 5, tags.album);
        bindText(insert.statement, 6, tags.genre);
        bindText(insert.statement, 7, audio ? QStringLiteral("audio") : QStringLiteral("video"));
        sqlite3_bind_int64(insert.statement, 8, tags.duration);
        sqlite3_bind_int64(insert.statement, 9, size);
        sqlite3_bind_int64(insert.statement, 10, modified);
        bindText(insert.statement, 11, artwork);
        bindText(insert.statement, 12, artworkSignature);
        if (sqlite3_step(insert.statement) != SQLITE_DONE) {
            result.error = QString::fromUtf8(sqlite3_errmsg(db));
            break;
        }
        ++result.indexed;
    }

    if (!result.error.isEmpty()) {
        execute(db, "ROLLBACK;");
        finish();
        return result;
    }
    SqlStatement removeStale(db, "DELETE FROM media WHERE root=?1 AND path NOT IN (SELECT path FROM seen_paths)");
    if (!removeStale.statement) {
        result.error = QString::fromUtf8(sqlite3_errmsg(db));
        execute(db, "ROLLBACK;");
        finish();
        return result;
    }
    bindText(removeStale.statement, 1, root);
    if (sqlite3_step(removeStale.statement) != SQLITE_DONE || !execute(db, "COMMIT;", &result.error)) {
        execute(db, "ROLLBACK;");
        finish();
        return result;
    }
    result.ok = true;
    finish();
    return result;
}

QString columnText(sqlite3_stmt *statement, int column)
{
    const auto *value = sqlite3_column_text(statement, column);
    return value ? QString::fromUtf8(reinterpret_cast<const char *>(value)) : QString();
}

} // namespace

MediaLibraryModel::MediaLibraryModel(QObject *parent) : QAbstractListModel(parent), m_queryTimer(this)
{
    m_queryTimer.setSingleShot(true);
    connect(&m_queryTimer, &QTimer::timeout, this, &MediaLibraryModel::startReload);
    connect(&m_queryWatcher, &QFutureWatcher<QueryResult>::finished, this, [this] {
        QueryResult result = m_queryWatcher.result();
        if (result.revision == m_queryRevision) {
            if (!result.error.isEmpty()) {
                setLoadError(result.error);
                setStale(!m_items.isEmpty());
                emit loadFailed(result.error);
            } else {
                beginResetModel();
                m_items = std::move(result.items);
                endResetModel();
                emit countChanged();
                setStale(false);
                setLoadError({});
            }
            if (m_loading) {
                m_loading = false;
                emit loadingChanged();
            }
        } else {
            startReload();
        }
    });
}

int MediaLibraryModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : m_items.size();
}

QVariant MediaLibraryModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_items.size())
        return {};
    const Item &item = m_items.at(index.row());
    switch (role) {
    case TitleRole: return item.title;
    case ArtistRole: return item.artist;
    case AlbumRole: return item.album;
    case GenreRole: return item.genre;
    case PathRole: return item.path;
    case ArtworkRole: return item.artwork.isEmpty() ? QString() : QUrl::fromLocalFile(item.artwork).toString();
    case DurationRole: return item.duration;
    case CountRole: return item.count;
    case KindRole: return item.kind;
    case GroupRole: return item.group;
    default: return {};
    }
}

QVariantMap MediaLibraryModel::itemAt(int row) const
{
    if (row < 0 || row >= m_items.size())
        return {};
    const Item &item = m_items.at(row);
    return {
        {QStringLiteral("title"), item.title}, {QStringLiteral("artist"), item.artist},
        {QStringLiteral("album"), item.album}, {QStringLiteral("genre"), item.genre},
        {QStringLiteral("path"), item.path}, {QStringLiteral("artwork"), item.artwork},
        {QStringLiteral("duration"), item.duration}, {QStringLiteral("count"), item.count},
        {QStringLiteral("kind"), item.kind}, {QStringLiteral("isGroup"), item.group}
    };
}

QHash<int, QByteArray> MediaLibraryModel::roleNames() const
{
    return { {TitleRole,"title"}, {ArtistRole,"artist"}, {AlbumRole,"album"}, {GenreRole,"genre"},
             {PathRole,"path"}, {ArtworkRole,"artwork"}, {DurationRole,"duration"}, {CountRole,"count"},
             {KindRole,"kind"}, {GroupRole,"isGroup"} };
}

void MediaLibraryModel::setDatabasePath(QString path) { m_databasePath = std::move(path); }

void MediaLibraryModel::setView(const QString &view)
{
    const QStringList views { "tracks", "albums", "artists", "genres", "videos" };
    const QString normalized = views.contains(view) ? view : QStringLiteral("tracks");
    if (m_view == normalized && m_groupColumn.isEmpty())
        return;
    m_view = normalized;
    m_groupColumn.clear();
    m_groupValue.clear();
    m_groupArtist.clear();
    emit viewChanged();
    reload();
}

void MediaLibraryModel::setSearch(const QString &search)
{
    if (m_search == search)
        return;
    m_search = search;
    emit searchChanged();
    reload();
}

void MediaLibraryModel::selectGroup(int row)
{
    if (row < 0 || row >= m_items.size() || !m_items.at(row).group)
        return;
    const Item selected = m_items.at(row);
    if (m_view == QLatin1String("albums")) {
        m_groupColumn = QStringLiteral("album");
        m_groupArtist = selected.artist;
    } else if (m_view == QLatin1String("artists")) {
        m_groupColumn = QStringLiteral("artist");
        m_groupArtist.clear();
    } else {
        m_groupColumn = QStringLiteral("genre");
        m_groupArtist.clear();
    }
    m_groupValue = selected.title;
    m_view = QStringLiteral("tracks");
    emit viewChanged();
    reload();
}

void MediaLibraryModel::clearGroup()
{
    if (m_groupColumn.isEmpty())
        return;
    m_groupColumn.clear();
    m_groupValue.clear();
    m_groupArtist.clear();
    emit viewChanged();
    reload();
}

bool MediaLibraryModel::reload()
{
    ++m_queryRevision;
    if (!m_items.isEmpty())
        setStale(true);
    if (!m_loading) {
        m_loading = true;
        emit loadingChanged();
    }
    m_queryTimer.start(0);
    return true;
}

void MediaLibraryModel::setStale(bool stale)
{
    if (m_stale == stale)
        return;
    m_stale = stale;
    emit staleChanged();
}

void MediaLibraryModel::setLoadError(const QString &error)
{
    if (m_loadError == error)
        return;
    m_loadError = error;
    emit loadErrorChanged();
}

void MediaLibraryModel::startReload()
{
    if (m_queryWatcher.isRunning())
        return;
    const quint64 revision = m_queryRevision;
    const QString databasePath = m_databasePath;
    const QString view = m_view;
    const QString search = m_search;
    const QString groupColumn = m_groupColumn;
    const QString groupValue = m_groupValue;
    const QString groupArtist = m_groupArtist;
    m_queryWatcher.setFuture(QtConcurrent::run([databasePath, view, search, groupColumn, groupValue, groupArtist, revision] {
        return queryDatabase(databasePath, view, search, groupColumn, groupValue, groupArtist, revision);
    }));
}

MediaLibraryModel::QueryResult MediaLibraryModel::queryDatabase(const QString &databasePath,
    const QString &viewName, const QString &searchText, const QString &selectedGroupColumn,
    const QString &selectedGroupValue, const QString &selectedGroupArtist, quint64 revision)
{
    QueryResult result;
    result.revision = revision;
    sqlite3 *db = nullptr;
    if (!openDatabase(databasePath, &db, &result.error)) {
        return result;
    }
    QString select;
    QString where;
    QString group;
    bool groupedView = false;
    if (viewName == QLatin1String("albums")) {
        groupedView = true;
        select = "SELECT album,artist,'', '',MIN(path),SUM(duration),MAX(artwork),COUNT(*),'audio' FROM media";
        where = "kind='audio' AND album<>''";
        group = " GROUP BY album,artist";
    } else if (viewName == QLatin1String("artists")) {
        groupedView = true;
        select = "SELECT artist,'','','',MIN(path),SUM(duration),MAX(artwork),COUNT(*),'audio' FROM media";
        where = "kind='audio' AND artist<>''";
        group = " GROUP BY artist";
    } else if (viewName == QLatin1String("genres")) {
        groupedView = true;
        select = "SELECT genre,'','','',MIN(path),SUM(duration),MAX(artwork),COUNT(*),'audio' FROM media";
        where = "kind='audio' AND genre<>''";
        group = " GROUP BY genre";
    } else {
        select = "SELECT title,artist,album,genre,path,duration,artwork,1,kind FROM media";
        where = viewName == QLatin1String("videos") ? "kind='video'" : "kind='audio'";
    }
    if (!selectedGroupColumn.isEmpty()) {
        select = "SELECT title,artist,album,genre,path,duration,artwork,1,kind FROM media";
        where = "kind='audio' AND " + selectedGroupColumn + "=?1";
        group.clear();
        if (selectedGroupColumn == QLatin1String("album"))
            where += " AND artist=?2";
    }
    if (!searchText.trimmed().isEmpty()) {
        where += " AND instr(casefold(title || ' ' || artist || ' ' || album || ' ' || genre || ' ' || path),casefold(?";
        where += selectedGroupColumn == QLatin1String("album") ? "3" : (!selectedGroupColumn.isEmpty() ? "2" : "1");
        where += "))>0";
    }
    QString query = select + " WHERE " + where + group;
    if (viewName == QLatin1String("albums") && selectedGroupColumn.isEmpty()) query += " ORDER BY lower(album),lower(artist)";
    else if (viewName == QLatin1String("artists") && selectedGroupColumn.isEmpty()) query += " ORDER BY lower(artist)";
    else if (viewName == QLatin1String("genres") && selectedGroupColumn.isEmpty()) query += " ORDER BY lower(genre)";
    else query += " ORDER BY CASE WHEN artist='' THEN 1 ELSE 0 END,lower(artist),lower(album),lower(title)";
    SqlStatement statement(db, query.toUtf8().constData());
    if (!statement.statement) {
        result.error = QString::fromUtf8(sqlite3_errmsg(db));
    } else {
        int bindIndex = 1;
        if (!selectedGroupColumn.isEmpty()) {
            bindText(statement.statement, bindIndex++, selectedGroupValue);
            if (selectedGroupColumn == QLatin1String("album"))
                bindText(statement.statement, bindIndex++, selectedGroupArtist);
        }
        if (!searchText.trimmed().isEmpty())
            bindText(statement.statement, bindIndex, searchText.trimmed());
        int code;
        while ((code = sqlite3_step(statement.statement)) == SQLITE_ROW) {
            Item item;
            item.title = columnText(statement.statement, 0);
            item.artist = columnText(statement.statement, 1);
            item.album = columnText(statement.statement, 2);
            item.genre = columnText(statement.statement, 3);
            item.path = columnText(statement.statement, 4);
            item.duration = sqlite3_column_int64(statement.statement, 5);
            item.artwork = columnText(statement.statement, 6);
            item.count = sqlite3_column_int(statement.statement, 7);
            item.kind = columnText(statement.statement, 8);
            item.group = groupedView;
            result.items.push_back(std::move(item));
        }
        if (code != SQLITE_DONE)
            result.error = QString::fromUtf8(sqlite3_errmsg(db));
    }
    sqlite3_close_v2(db);
    return result;
}

MediaLibrary::MediaLibrary(QObject *parent)
    : QObject(parent),
      m_databasePath(QDir(QStandardPaths::writableLocation(QStandardPaths::AppDataLocation)).filePath(QStringLiteral("library.sqlite"))),
      m_artworkDirectory(QDir(QStandardPaths::writableLocation(QStandardPaths::AppDataLocation)).filePath(QStringLiteral("LibraryArt")))
{
    m_model.setDatabasePath(m_databasePath);
    connect(&m_watcher, &QFutureWatcher<LibraryScanResult>::finished, this, &MediaLibrary::scanFinished);
    QDir().mkpath(QFileInfo(m_databasePath).absolutePath());
    QDir().mkpath(m_artworkDirectory);
    if (!initializeDatabase())
        return;
    reloadRoots();
    m_model.reload();
    m_pendingRoots = m_roots;
    QMetaObject::invokeMethod(this, &MediaLibrary::startNextScan, Qt::QueuedConnection);
}

bool MediaLibrary::initializeDatabase()
{
    sqlite3 *db = nullptr;
    QString error;
    if (!openDatabase(m_databasePath, &db, &error)) {
        emit notify(QStringLiteral("Could not open media library: ") + error);
        return false;
    }
    bool ok = execute(db,
        "PRAGMA journal_mode=WAL;"
        "CREATE TABLE IF NOT EXISTS roots(path TEXT PRIMARY KEY);"
        "CREATE TABLE IF NOT EXISTS media(path TEXT PRIMARY KEY,root TEXT NOT NULL,title TEXT NOT NULL,artist TEXT NOT NULL,album TEXT NOT NULL,genre TEXT NOT NULL,kind TEXT NOT NULL,duration INTEGER NOT NULL,size INTEGER NOT NULL,modified INTEGER NOT NULL,artwork TEXT NOT NULL,sidecar_signature TEXT NOT NULL DEFAULT '');"
        "CREATE INDEX IF NOT EXISTS media_artist_album ON media(artist,album);"
        "CREATE INDEX IF NOT EXISTS media_genre ON media(genre);"
        "CREATE INDEX IF NOT EXISTS media_root ON media(root);", &error);
    if (ok) {
        bool hasSidecarSignature = false;
        SqlStatement columns(db, "PRAGMA table_info(media)");
        if (!columns.statement) {
            ok = false;
            error = QString::fromUtf8(sqlite3_errmsg(db));
        } else {
            while (sqlite3_step(columns.statement) == SQLITE_ROW) {
                if (columnText(columns.statement, 1) == QLatin1String("sidecar_signature")) {
                    hasSidecarSignature = true;
                    break;
                }
            }
            if (!hasSidecarSignature)
                ok = execute(db, "ALTER TABLE media ADD COLUMN sidecar_signature TEXT NOT NULL DEFAULT '';", &error);
        }
    }
    sqlite3_close_v2(db);
    if (!ok)
        emit notify(QStringLiteral("Could not initialize media library: ") + error);
    return ok;
}

void MediaLibrary::reloadRoots()
{
    sqlite3 *db = nullptr;
    QString error;
    if (!openDatabase(m_databasePath, &db, &error))
        return;
    SqlStatement query(db, "SELECT path FROM roots ORDER BY path");
    QStringList roots;
    if (query.statement) {
        while (sqlite3_step(query.statement) == SQLITE_ROW)
            roots.push_back(columnText(query.statement, 0));
    }
    SqlStatement count(db, "SELECT COUNT(*) FROM media");
    int total = 0;
    if (count.statement && sqlite3_step(count.statement) == SQLITE_ROW)
        total = sqlite3_column_int(count.statement, 0);
    sqlite3_close_v2(db);
    if (m_roots != roots) {
        m_roots = roots;
        emit rootsChanged();
    }
    if (m_indexedCount != total) {
        m_indexedCount = total;
        emit indexedCountChanged();
    }
}

bool MediaLibrary::addFolder(const QUrl &folder)
{
    if (!folder.isLocalFile() || !QFileInfo(folder.toLocalFile()).isDir()) {
        emit notify(QStringLiteral("Choose a local folder to index"));
        return false;
    }
    QString root = QFileInfo(folder.toLocalFile()).canonicalFilePath();
    if (root.isEmpty())
        root = QDir::cleanPath(folder.toLocalFile());
    if (root.isEmpty()) {
        emit notify(QStringLiteral("Could not read that folder"));
        return false;
    }
    for (const QString &indexedRoot : m_roots) {
        const QString indexedPrefix = indexedRoot.endsWith(QLatin1Char('/')) ? indexedRoot : indexedRoot + QLatin1Char('/');
        const QString newPrefix = root.endsWith(QLatin1Char('/')) ? root : root + QLatin1Char('/');
        if (root == indexedRoot || root.startsWith(indexedPrefix) || indexedRoot.startsWith(newPrefix)) {
            emit notify(QStringLiteral("That folder overlaps an existing library folder"));
            return false;
        }
    }
    sqlite3 *db = nullptr;
    QString error;
    if (!openDatabase(m_databasePath, &db, &error)) {
        emit notify(QStringLiteral("Could not save the library folder: ") + error);
        return false;
    }
    SqlStatement insert(db, "INSERT OR IGNORE INTO roots(path) VALUES(?1)");
    bindText(insert.statement, 1, root);
    const bool ok = insert.statement && sqlite3_step(insert.statement) == SQLITE_DONE;
    sqlite3_close_v2(db);
    if (!ok) {
        emit notify(QStringLiteral("Could not save the library folder"));
        return false;
    }
    reloadRoots();
    m_pendingRoots.push_back(root);
    startNextScan();
    return true;
}

bool MediaLibrary::removeFolder(const QUrl &folder)
{
    if (m_scanning || !folder.isLocalFile())
        return false;
    QString root = QFileInfo(folder.toLocalFile()).canonicalFilePath();
    if (root.isEmpty())
        root = QDir::cleanPath(folder.toLocalFile());
    sqlite3 *db = nullptr;
    QString error;
    if (!openDatabase(m_databasePath, &db, &error))
        return false;
    bool ok = execute(db, "BEGIN IMMEDIATE;", &error);
    if (ok) {
        SqlStatement removeMedia(db, "DELETE FROM media WHERE root=?1");
        ok = removeMedia.statement && bindText(removeMedia.statement, 1, root) && sqlite3_step(removeMedia.statement) == SQLITE_DONE;
    }
    if (ok) {
        SqlStatement removeRoot(db, "DELETE FROM roots WHERE path=?1");
        ok = removeRoot.statement && bindText(removeRoot.statement, 1, root) && sqlite3_step(removeRoot.statement) == SQLITE_DONE;
    }
    if (ok) {
        ok = execute(db, "COMMIT;", &error);
        if (!ok)
            execute(db, "ROLLBACK;");
    } else {
        execute(db, "ROLLBACK;");
    }
    sqlite3_close_v2(db);
    reloadRoots();
    m_model.reload();
    cleanupArtwork();
    return ok;
}

bool MediaLibrary::clearLibrary()
{
    if (m_scanning) {
        emit notify(QStringLiteral("Wait for indexing to finish before clearing the library"));
        return false;
    }
    sqlite3 *db = nullptr;
    QString error;
    if (!openDatabase(m_databasePath, &db, &error))
        return false;
    const bool ok = execute(db, "BEGIN IMMEDIATE; DELETE FROM media; DELETE FROM roots; COMMIT; PRAGMA wal_checkpoint(TRUNCATE); VACUUM;", &error);
    sqlite3_close_v2(db);
    if (!ok) {
        emit notify(QStringLiteral("Could not clear media library: ") + error);
        return false;
    }
    m_pendingRoots.clear();
    reloadRoots();
    m_model.reload();
    QDir(m_artworkDirectory).removeRecursively();
    QDir().mkpath(m_artworkDirectory);
    emit notify(QStringLiteral("Media library cleared"));
    return true;
}

void MediaLibrary::refresh()
{
    if (m_scanning) {
        emit notify(QStringLiteral("Indexing is already running"));
        return;
    }
    m_pendingRoots = m_roots;
    startNextScan();
}

void MediaLibrary::startNextScan()
{
    if (m_scanning || m_pendingRoots.isEmpty())
        return;
    m_activeRoot = m_pendingRoots.takeFirst();
    m_scanning = true;
    emit scanningChanged();
    m_watcher.setFuture(QtConcurrent::run(scanFolder, m_databasePath, m_activeRoot, m_artworkDirectory));
}

void MediaLibrary::scanFinished()
{
    const LibraryScanResult result = m_watcher.result();
    m_scanning = false;
    emit scanningChanged();
    if (!result.ok)
        emit notify(QStringLiteral("Could not index %1: %2").arg(QDir::toNativeSeparators(m_activeRoot), result.error));
    else
        emit notify(QStringLiteral("Indexed %1 media files").arg(result.indexed));
    reloadRoots();
    m_model.reload();
    cleanupArtwork();
    startNextScan();
}

void MediaLibrary::cleanupArtwork()
{
    sqlite3 *db = nullptr;
    if (!openDatabase(m_databasePath, &db))
        return;
    SqlStatement query(db, "SELECT DISTINCT artwork FROM media WHERE artwork<>''");
    if (!query.statement) {
        sqlite3_close_v2(db);
        return;
    }
    QSet<QString> referenced;
    int code;
    while ((code = sqlite3_step(query.statement)) == SQLITE_ROW)
        referenced.insert(columnText(query.statement, 0));
    if (code != SQLITE_DONE) {
        sqlite3_close_v2(db);
        return;
    }
    sqlite3_close_v2(db);
    QDir directory(m_artworkDirectory);
    for (const QString &file : directory.entryList(QDir::Files)) {
        const QString path = directory.filePath(file);
        if (!referenced.contains(path))
            QFile::remove(path);
    }
}
