// Playback and playlist operations consumed by the QML-facing Player facade.
#pragma once

#include <QList>
#include <QUrl>
#include <QVariant>
#include <QString>

#include "media_queue_entry.hpp"

struct QueueSnapshot {
    QList<MediaQueueEntry> entries;
    int currentId = -1;
};

struct BackendPlaylistState {
    double rate = 1.0;
    double volume = 1.0;
    bool muted = false;
    bool loop = false;
    bool repeatOne = false;
    bool random = false;
};

struct BackendInputState {
    int state = 0; // 0 stopped, 1 opening, 2 playing, 3 paused
    bool hasInput = false;
    bool seekable = false;
    bool hasVideo = false;
    bool recording = false;
    double position = 0.0;
    qint64 timeMs = 0;
    qint64 lengthMs = 0;
    double rate = 1.0;
    int audioDelayMs = 0;
    int subtitleDelayMs = 0;
    QString title;
    QString artist;
    QString artworkUrl;
    QUrl mediaUrl;
};

class PlayerBackend
{
public:
    virtual ~PlayerBackend() = default;

    virtual void togglePause() = 0;
    virtual void play() = 0;
    virtual void pause() = 0;
    virtual void stop() = 0;
    virtual void next() = 0;
    virtual void previous() = 0;
    virtual void setRate(double rate) = 0;
    virtual void setVolume(double volume) = 0;
    virtual void setMuted(bool muted) = 0;
    virtual void toggleMute() = 0;

    virtual void openUrls(const QList<QUrl> &urls, bool playNow) = 0;
    virtual void playItem(int id) = 0;
    virtual void removeItem(int id) = 0;
    virtual void clearQueue() = 0;
    virtual QueueSnapshot queueSnapshot() const = 0;
    virtual int currentQueueItemId() const = 0;
    virtual bool exportQueue(const QString &path) = 0;
    virtual BackendPlaylistState playlistState() const = 0;
    virtual void syncCurrentInput() = 0;
    virtual void clearCurrentInput() = 0;
    virtual BackendInputState inputState() const = 0;

    virtual void setLoop(bool enabled) = 0;
    virtual void setRepeatOne(bool enabled) = 0;
    virtual void setRandom(bool enabled) = 0;
    virtual void setFullscreen(bool enabled) = 0;

    virtual QVariant config(const QString &name) const = 0;
    virtual void setConfig(const QString &name, const QVariant &value) = 0;
    virtual bool forwardKey(int qtKey, int qtModifiers, const QString &text) = 0;
};
