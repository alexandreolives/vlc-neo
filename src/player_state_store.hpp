// Persistent per-media and per-folder state, separate from the QML facade.
#pragma once

#include <QList>
#include <QSettings>
#include <QStringList>
#include <QUrl>

struct FolderPlaybackPreset {
    int subtitleDelayMs = 0;
    int audioDelayMs = 0;
    int subtitleScale = 100;
    QString subtitleTrack;
    QString audioTrack;
};

class PlayerStateStore
{
public:
    PlayerStateStore();

    QStringList recentMedia() const;
    void rememberRecentMedia(const QString &mrl);
    void clearRecentMedia();

    QString equalizerPreset() const;
    void setEqualizerPreset(const QString &preset);

    void saveResumePoint(const QUrl &media, qint64 timeMs, qint64 lengthMs);
    qint64 resumePoint(const QUrl &media) const;
    QList<qint64> bookmarks(const QUrl &media) const;
    void addBookmark(const QUrl &media, qint64 timeMs);
    void removeBookmark(const QUrl &media, qint64 timeMs);

    void saveFolderPreset(const QString &folder, const FolderPlaybackPreset &preset);
    bool hasFolderPreset(const QString &folder) const;
    FolderPlaybackPreset folderPreset(const QString &folder) const;
    void forgetFolderPreset(const QString &folder);

    QString linkedSubtitleFolder(const QString &mediaFolder) const;
    void linkSubtitleFolder(const QString &mediaFolder, const QString &subtitleFolder);
    void unlinkSubtitleFolder(const QString &mediaFolder);

private:
    QString mediaKey(const QString &group, const QUrl &media) const;
    QString presetKey(const QString &folder) const;

    QSettings m_settings;
};
