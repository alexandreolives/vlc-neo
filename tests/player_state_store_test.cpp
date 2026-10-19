#include "player_state_store.hpp"

#include <QCoreApplication>
#include <QSettings>

#include <cstdio>

namespace {

bool expect(bool condition, const char *message)
{
    if (condition)
        return true;
    std::fprintf(stderr, "FAIL: %s\n", message);
    return false;
}

} // namespace

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    QCoreApplication::setOrganizationName(QStringLiteral("vlc-neo"));
    QCoreApplication::setApplicationName(QStringLiteral("neo"));
    QSettings::setDefaultFormat(QSettings::IniFormat);
    QSettings settings(QStringLiteral("vlc-neo"), QStringLiteral("neo"));
    settings.clear();
    settings.sync();

    PlayerStateStore store;
    bool ok = true;
    const QUrl media = QUrl::fromLocalFile(QStringLiteral("/tmp/episode-01.mkv"));
    const QString folder = QStringLiteral("/tmp/season");

    store.clearRecentMedia();
    for (int i = 0; i < 17; ++i)
        store.rememberRecentMedia(QStringLiteral("file-%1").arg(i));
    store.rememberRecentMedia(QStringLiteral("file-10"));
    const QStringList recent = store.recentMedia();
    ok &= expect(recent.size() == 15, "recent media is capped at 15");
    ok &= expect(recent.first() == QStringLiteral("file-10"), "remembering moves an item to the front");
    ok &= expect(!recent.contains(QStringLiteral("file-0")), "oldest recent media is discarded");

    store.saveResumePoint(media, 9000, 120000);
    ok &= expect(store.resumePoint(media) == 0, "resume point near the start is ignored");
    store.saveResumePoint(media, 45000, 120000);
    ok &= expect(store.resumePoint(media) == 45000, "resume point in the middle is saved");
    store.saveResumePoint(media, 119000, 120000);
    ok &= expect(store.resumePoint(media) == 0, "resume point near the end is cleared");

    store.addBookmark(media, 60000);
    store.addBookmark(media, 15000);
    store.addBookmark(media, 60000);
    ok &= expect(store.bookmarks(media) == QList<qint64>({15000, 60000, 60000}), "bookmarks are sorted and duplicates retained");
    store.removeBookmark(media, 60000);
    ok &= expect(store.bookmarks(media) == QList<qint64>({15000}), "removing a bookmark removes every matching timestamp");

    FolderPlaybackPreset preset{120, -80, 135, QStringLiteral("English"), QStringLiteral("Stereo")};
    store.saveFolderPreset(folder, preset);
    ok &= expect(store.hasFolderPreset(folder), "folder preset is detected");
    const FolderPlaybackPreset loaded = store.folderPreset(folder);
    ok &= expect(loaded.subtitleDelayMs == 120 && loaded.audioDelayMs == -80 && loaded.subtitleScale == 135,
                 "folder preset timing values round-trip");
    ok &= expect(loaded.subtitleTrack == QStringLiteral("English") && loaded.audioTrack == QStringLiteral("Stereo"),
                 "folder preset track names round-trip");
    store.forgetFolderPreset(folder);
    ok &= expect(!store.hasFolderPreset(folder), "folder preset can be forgotten");

    store.setEqualizerPreset(QStringLiteral("rock"));
    ok &= expect(store.equalizerPreset() == QStringLiteral("rock"), "equalizer preset round-trips");
    const QString subtitleFolder = QStringLiteral("/tmp/subtitles");
    store.linkSubtitleFolder(folder, subtitleFolder);
    ok &= expect(store.linkedSubtitleFolder(folder) == subtitleFolder, "subtitle folder link round-trips");
    store.unlinkSubtitleFolder(folder);
    ok &= expect(store.linkedSubtitleFolder(folder).isEmpty(), "subtitle folder link can be removed");

    return ok ? 0 : 1;
}
