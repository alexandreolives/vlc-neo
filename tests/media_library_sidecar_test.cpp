#include "../src/media_library.hpp"

#include <QCoreApplication>
#include <QDateTime>
#include <QDir>
#include <QEventLoop>
#include <QElapsedTimer>
#include <QFile>
#include <QFileDevice>
#include <QFileInfo>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <QThread>
#include <QUrl>

#include <sqlite3.h>
#include <cstdio>

namespace {

bool expect(bool condition, const char *name)
{
    if (condition)
        return true;
    std::fprintf(stderr, "failed: %s\n", name);
    return false;
}

bool waitForScan(MediaLibrary &library, QCoreApplication &application)
{
    QElapsedTimer timeout;
    timeout.start();
    while (library.scanning() && timeout.elapsed() < 5000) {
        application.processEvents(QEventLoop::AllEvents, 25);
        QThread::msleep(5);
    }
    application.processEvents(QEventLoop::AllEvents, 25);
    return !library.scanning();
}

bool waitForScanAndModel(MediaLibrary &library, MediaLibraryModel &model,
                         QCoreApplication &application)
{
    if (!waitForScan(library, application))
        return false;

    QElapsedTimer timeout;
    timeout.start();
    while (model.loading() && timeout.elapsed() < 5000) {
        application.processEvents(QEventLoop::AllEvents, 25);
        QThread::msleep(5);
    }
    application.processEvents(QEventLoop::AllEvents, 25);
    return !model.loading();
}

bool writeFile(const QString &path, const QByteArray &contents)
{
    QFile file(path);
    return file.open(QIODevice::WriteOnly | QIODevice::Truncate)
        && file.write(contents) == contents.size() && file.flush();
}

} // namespace

int main(int argc, char **argv)
{
    QTemporaryDir temporary;
    if (!temporary.isValid())
        return 2;
    qputenv("XDG_DATA_HOME", QDir(temporary.path()).filePath(QStringLiteral("data")).toLocal8Bit());
    QCoreApplication::setOrganizationName(QStringLiteral("vlc-neo"));
    QCoreApplication::setApplicationName(QStringLiteral("neo"));
    QCoreApplication application(argc, argv);

    // Seed the pre-migration schema to verify that existing libraries upgrade.
    const QString appData = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    QDir().mkpath(appData);
    const QByteArray databasePath = QFile::encodeName(QDir(appData).filePath(QStringLiteral("library.sqlite")));
    sqlite3 *database = nullptr;
    if (sqlite3_open(databasePath.constData(), &database) != SQLITE_OK)
        return 2;
    const char *oldSchema =
        "CREATE TABLE roots(path TEXT PRIMARY KEY);"
        "CREATE TABLE media(path TEXT PRIMARY KEY,root TEXT NOT NULL,title TEXT NOT NULL,"
        "artist TEXT NOT NULL,album TEXT NOT NULL,genre TEXT NOT NULL,kind TEXT NOT NULL,"
        "duration INTEGER NOT NULL,size INTEGER NOT NULL,modified INTEGER NOT NULL,artwork TEXT NOT NULL);";
    char *sqlError = nullptr;
    const int schemaResult = sqlite3_exec(database, oldSchema, nullptr, nullptr, &sqlError);
    if (sqlError)
        sqlite3_free(sqlError);
    sqlite3_close(database);
    if (schemaResult != SQLITE_OK)
        return 2;

    const QString music = QDir(temporary.path()).filePath(QStringLiteral("music"));
    QDir().mkpath(music);
    const QString track = QDir(music).filePath(QStringLiteral("unchanged.ogg"));
    const QString cover = QDir(music).filePath(QStringLiteral("cover.png"));
    QFile audioFixture(QStringLiteral(NEO_TEST_AUDIO_FIXTURE));
    if (!audioFixture.open(QIODevice::ReadOnly)
        || !writeFile(track, audioFixture.readAll()))
        return 2;
    const QByteArray firstCover = QByteArray::fromHex("89504e470d0a1a0a") + QByteArray(32, 'A');
    const QByteArray secondCover = QByteArray::fromHex("89504e470d0a1a0a") + QByteArray(32, 'B');
    if (!writeFile(cover, firstCover))
        return 2;

    bool ok = true;
    QString originalArtwork;
    QString updatedArtwork;
    {
        MediaLibrary library;
        auto *model = qobject_cast<MediaLibraryModel *>(library.model());
        ok &= expect(model != nullptr, "media model is available");
        ok &= expect(library.addFolder(QUrl::fromLocalFile(music)), "add temporary music folder");
        ok &= expect(model && waitForScanAndModel(library, *model, application),
                     "initial sidecar scan and model load complete");
        if (model && model->itemCount() == 1)
            originalArtwork = model->itemAt(0).value(QStringLiteral("artwork")).toString();
        ok &= expect(!originalArtwork.isEmpty() && QFileInfo::exists(originalArtwork),
                     "initial sidecar cover is cached");

        const QDateTime originalTimestamp = QFileInfo(cover).lastModified();
        ok &= expect(writeFile(cover, secondCover), "rewrite the sidecar cover");
        QFile coverFile(cover);
        ok &= expect(coverFile.open(QIODevice::ReadOnly)
                         && coverFile.setFileTime(originalTimestamp, QFileDevice::FileModificationTime),
                     "restore the original sidecar timestamp");
        coverFile.close();

        library.refresh();
        ok &= expect(model && waitForScanAndModel(library, *model, application),
                     "updated sidecar scan and model load complete");
        if (model && model->itemCount() == 1)
            updatedArtwork = model->itemAt(0).value(QStringLiteral("artwork")).toString();
        ok &= expect(!updatedArtwork.isEmpty() && updatedArtwork != originalArtwork,
                     "same-size same-mtime content change refreshes cached artwork");

        QFile::remove(cover);
        library.refresh();
        ok &= expect(model && waitForScanAndModel(library, *model, application),
                     "removed sidecar scan and model load complete");
        const QString removedArtwork = model && model->itemCount() == 1
            ? model->itemAt(0).value(QStringLiteral("artwork")).toString() : QStringLiteral("unexpected");
        ok &= expect(removedArtwork.isEmpty(), "removed sidecar clears the indexed artwork");
        ok &= expect(!QFileInfo::exists(originalArtwork) && !QFileInfo::exists(updatedArtwork),
                     "unreferenced cover cache files are deleted");
    }

    return ok ? 0 : 1;
}
