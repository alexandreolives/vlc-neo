#include "../src/media_library.hpp"

#include <QCoreApplication>
#include <QElapsedTimer>
#include <QEventLoop>
#include <QFile>
#include <QTemporaryDir>
#include <QThread>

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

bool executeSql(const QString &path, const char *sql)
{
    sqlite3 *database = nullptr;
    const QByteArray encodedPath = QFile::encodeName(path);
    if (sqlite3_open(encodedPath.constData(), &database) != SQLITE_OK) {
        if (database)
            sqlite3_close(database);
        return false;
    }
    char *error = nullptr;
    const bool ok = sqlite3_exec(database, sql, nullptr, nullptr, &error) == SQLITE_OK;
    if (error)
        sqlite3_free(error);
    sqlite3_close(database);
    return ok;
}

bool waitForQuery(MediaLibraryModel &model, QCoreApplication &application)
{
    QElapsedTimer timeout;
    timeout.start();
    while (model.loading() && timeout.elapsed() < 5000) {
        application.processEvents(QEventLoop::AllEvents, 25);
        QThread::msleep(5);
    }
    application.processEvents(QEventLoop::AllEvents, 25);
    return !model.loading();
}

} // namespace

int main(int argc, char **argv)
{
    QCoreApplication application(argc, argv);
    QTemporaryDir temporary;
    if (!temporary.isValid())
        return 2;
    const QString databasePath = temporary.filePath(QStringLiteral("library.sqlite"));
    const char *schemaAndSeed =
        "CREATE TABLE roots(path TEXT PRIMARY KEY);"
        "CREATE TABLE media(path TEXT PRIMARY KEY,root TEXT NOT NULL,title TEXT NOT NULL,"
        "artist TEXT NOT NULL,album TEXT NOT NULL,genre TEXT NOT NULL,kind TEXT NOT NULL,"
        "duration INTEGER NOT NULL,size INTEGER NOT NULL,modified INTEGER NOT NULL,artwork TEXT NOT NULL,"
        "sidecar_signature TEXT NOT NULL DEFAULT '');"
        "INSERT INTO media VALUES('/old.mp3','/music','Old result','Artist','Album','Genre','audio',"
        "180,1,1,'','');";
    if (!executeSql(databasePath, schemaAndSeed))
        return 2;

    MediaLibraryModel model;
    model.setDatabasePath(databasePath);
    QString failureSignal;
    QObject::connect(&model, &MediaLibraryModel::loadFailed, &application,
                     [&failureSignal](const QString &message) { failureSignal = message; });

    bool ok = true;
    model.reload();
    ok &= expect(waitForQuery(model, application), "initial catalog query completes");
    ok &= expect(model.itemCount() == 1 && model.itemAt(0).value(QStringLiteral("title")).toString() == QStringLiteral("Old result"),
                 "initial result is loaded");
    ok &= expect(!model.stale() && model.loadError().isEmpty(), "initial result is current and has no error");

    ok &= expect(executeSql(databasePath, "DROP TABLE media;"), "invalidate the temporary catalog table");
    model.setSearch(QStringLiteral("missing"));
    ok &= expect(model.loading() && model.stale(), "old rows are marked stale while the new query is pending");
    ok &= expect(waitForQuery(model, application), "failed catalog query settles");
    ok &= expect(failureSignal.contains(QStringLiteral("no such table: media")), "failure signal reports the database error");
    ok &= expect(model.loadError().contains(QStringLiteral("no such table: media")), "query error is exposed as a model property");
    ok &= expect(!model.loading() && model.stale(), "failure ends loading but preserves the stale marker");
    ok &= expect(model.itemCount() == 1 && model.itemAt(0).value(QStringLiteral("title")).toString() == QStringLiteral("Old result"),
                 "old rows remain available after failure");

    const char *restoreMedia =
        "CREATE TABLE media(path TEXT PRIMARY KEY,root TEXT NOT NULL,title TEXT NOT NULL,"
        "artist TEXT NOT NULL,album TEXT NOT NULL,genre TEXT NOT NULL,kind TEXT NOT NULL,"
        "duration INTEGER NOT NULL,size INTEGER NOT NULL,modified INTEGER NOT NULL,artwork TEXT NOT NULL,"
        "sidecar_signature TEXT NOT NULL DEFAULT '');"
        "INSERT INTO media VALUES('/old.mp3','/music','Old result','Artist','Album','Genre','audio',"
        "180,1,1,'','');";
    ok &= expect(executeSql(databasePath, restoreMedia), "restore the temporary catalog table");
    model.reload();
    ok &= expect(waitForQuery(model, application), "recovery query completes");
    ok &= expect(model.loadError().isEmpty() && !model.stale(), "successful recovery clears error and stale state");
    return ok ? 0 : 1;
}
