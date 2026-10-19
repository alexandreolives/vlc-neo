#include "player_state_store.hpp"

#include "subtitle_matcher.hpp"

#include <QCryptographicHash>

#include <algorithm>

namespace {

constexpr int kRecentMax = 15;
constexpr qint64 kResumeMinMs = 10000;
constexpr qint64 kResumeMaxTailMs = 20000;

QString hashKey(const QString &prefix, const QString &value)
{
    const QByteArray hash = QCryptographicHash::hash(value.toUtf8(), QCryptographicHash::Md5).toHex();
    return prefix + QString::fromLatin1(hash);
}

} // namespace

PlayerStateStore::PlayerStateStore()
    : m_settings(QStringLiteral("vlc-neo"), QStringLiteral("neo"))
{
}

QStringList PlayerStateStore::recentMedia() const
{
    return m_settings.value(QStringLiteral("recent")).toStringList();
}

void PlayerStateStore::rememberRecentMedia(const QString &mrl)
{
    QStringList list = recentMedia();
    list.removeAll(mrl);
    list.prepend(mrl);
    while (list.size() > kRecentMax)
        list.removeLast();
    m_settings.setValue(QStringLiteral("recent"), list);
}

void PlayerStateStore::clearRecentMedia()
{
    m_settings.remove(QStringLiteral("recent"));
}

QString PlayerStateStore::equalizerPreset() const
{
    return m_settings.value(QStringLiteral("equalizer"), QStringLiteral("off")).toString();
}

void PlayerStateStore::setEqualizerPreset(const QString &preset)
{
    m_settings.setValue(QStringLiteral("equalizer"), preset);
}

QString PlayerStateStore::mediaKey(const QString &group, const QUrl &media) const
{
    if (media.isEmpty())
        return {};
    return hashKey(group + QLatin1Char('/'), media.toString());
}

void PlayerStateStore::saveResumePoint(const QUrl &media, qint64 timeMs, qint64 lengthMs)
{
    const QString key = mediaKey(QStringLiteral("resume"), media);
    if (key.isEmpty() || lengthMs <= 0)
        return;

    const qint64 tail = qMin(kResumeMaxTailMs, lengthMs / 10);
    if (timeMs < kResumeMinMs || timeMs > lengthMs - tail)
        m_settings.remove(key);
    else
        m_settings.setValue(key, timeMs);
}

qint64 PlayerStateStore::resumePoint(const QUrl &media) const
{
    const QString key = mediaKey(QStringLiteral("resume"), media);
    return key.isEmpty() ? 0 : m_settings.value(key, 0).toLongLong();
}

QList<qint64> PlayerStateStore::bookmarks(const QUrl &media) const
{
    QList<qint64> marks;
    const QString key = mediaKey(QStringLiteral("bookmarks"), media);
    if (key.isEmpty())
        return marks;
    for (const QVariant &value : m_settings.value(key).toList())
        marks.append(value.toLongLong());
    std::sort(marks.begin(), marks.end());
    return marks;
}

void PlayerStateStore::addBookmark(const QUrl &media, qint64 timeMs)
{
    const QString key = mediaKey(QStringLiteral("bookmarks"), media);
    if (key.isEmpty())
        return;
    QVariantList list = m_settings.value(key).toList();
    list.append(timeMs);
    m_settings.setValue(key, list);
}

void PlayerStateStore::removeBookmark(const QUrl &media, qint64 timeMs)
{
    const QString key = mediaKey(QStringLiteral("bookmarks"), media);
    if (key.isEmpty())
        return;
    QVariantList list = m_settings.value(key).toList();
    for (int i = list.size() - 1; i >= 0; --i) {
        if (list.at(i).toLongLong() == timeMs)
            list.removeAt(i);
    }
    m_settings.setValue(key, list);
}

QString PlayerStateStore::presetKey(const QString &folder) const
{
    return folder.isEmpty() ? QString() : hashKey(QStringLiteral("presets/"), folder);
}

void PlayerStateStore::saveFolderPreset(const QString &folder, const FolderPlaybackPreset &preset)
{
    const QString key = presetKey(folder);
    if (key.isEmpty())
        return;
    m_settings.beginGroup(key);
    m_settings.setValue(QStringLiteral("folder"), folder);
    m_settings.setValue(QStringLiteral("spuDelay"), preset.subtitleDelayMs);
    m_settings.setValue(QStringLiteral("audioDelay"), preset.audioDelayMs);
    m_settings.setValue(QStringLiteral("subScale"), preset.subtitleScale);
    m_settings.setValue(QStringLiteral("spuTrack"), preset.subtitleTrack);
    m_settings.setValue(QStringLiteral("audioTrack"), preset.audioTrack);
    m_settings.endGroup();
}

bool PlayerStateStore::hasFolderPreset(const QString &folder) const
{
    const QString key = presetKey(folder);
    return !key.isEmpty() && m_settings.contains(key + QStringLiteral("/folder"));
}

FolderPlaybackPreset PlayerStateStore::folderPreset(const QString &folder) const
{
    FolderPlaybackPreset preset;
    const QString key = presetKey(folder);
    if (key.isEmpty())
        return preset;
    preset.subtitleDelayMs = m_settings.value(key + QStringLiteral("/spuDelay"), 0).toInt();
    preset.audioDelayMs = m_settings.value(key + QStringLiteral("/audioDelay"), 0).toInt();
    preset.subtitleScale = m_settings.value(key + QStringLiteral("/subScale"), 100).toInt();
    preset.subtitleTrack = m_settings.value(key + QStringLiteral("/spuTrack")).toString();
    preset.audioTrack = m_settings.value(key + QStringLiteral("/audioTrack")).toString();
    return preset;
}

void PlayerStateStore::forgetFolderPreset(const QString &folder)
{
    const QString key = presetKey(folder);
    if (!key.isEmpty())
        m_settings.remove(key);
}

QString PlayerStateStore::linkedSubtitleFolder(const QString &mediaFolder) const
{
    if (mediaFolder.isEmpty())
        return {};
    return m_settings.value(SubtitleMatcher::folderSettingsKey(mediaFolder)).toString();
}

void PlayerStateStore::linkSubtitleFolder(const QString &mediaFolder, const QString &subtitleFolder)
{
    if (!mediaFolder.isEmpty())
        m_settings.setValue(SubtitleMatcher::folderSettingsKey(mediaFolder), subtitleFolder);
}

void PlayerStateStore::unlinkSubtitleFolder(const QString &mediaFolder)
{
    if (!mediaFolder.isEmpty())
        m_settings.remove(SubtitleMatcher::folderSettingsKey(mediaFolder));
}
