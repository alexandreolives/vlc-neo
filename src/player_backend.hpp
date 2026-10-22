// Playback and playlist operations consumed by the QML-facing Player facade.
#pragma once

#include <QList>
#include <QObject>
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

struct BackendTrack {
    qint64 id = -1;
    QString name;
    bool selected = false;
};

struct BackendAudioDevice {
    QString id;
    QString name;
    bool selected = false;
};

struct BackendChapter {
    int index = -1;
    QString name;
    bool selected = false;
};

enum class BackendInputEvent {
    Position,
    State,
    Tracks,
    Metadata,
    Delays,
    Volume,
    Dead
};

class PlayerBackend : public QObject
{
    Q_OBJECT
public:
    explicit PlayerBackend(QObject *parent = nullptr) : QObject(parent) {}
    ~PlayerBackend() override = default;

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
    virtual QString playlistName() const { return {}; }
    virtual bool syncCurrentInput() = 0;
    virtual BackendInputState inputState() const = 0;
    virtual bool hasInput() const = 0;
    virtual void seek(double position) = 0;
    virtual void seekBy(int ms) = 0;
    virtual void frameStep() = 0;
    virtual void jumpTo(qint64 ms) = 0;
    virtual void toggleRecord() = 0;
    virtual QList<BackendTrack> tracks(const QString &category) const = 0;
    virtual void selectTrack(const QString &category, int id) = 0;
    virtual bool addSubtitleFile(const QUrl &url, bool selectImmediately) = 0;
    virtual QList<BackendAudioDevice> audioDevices() const = 0;
    virtual void setAudioDevice(const QString &id) = 0;
    virtual void setAudioDelay(int ms) = 0;
    virtual void setSubtitleDelay(int ms) = 0;
    virtual QList<BackendChapter> chapters() const = 0;
    virtual void selectChapter(int index) = 0;
    virtual void setSubtitleScale(int percent) = 0;
    virtual int subtitleScale() const = 0;
    virtual void setSubtitleMargin(int px) = 0;
    virtual int subtitleMargin() const = 0;
    virtual void setAspectRatio(const QString &ratio) = 0;
    virtual QString aspectRatio() const = 0;
    virtual bool setVideoFilterChain(const QString &filters) = 0;
    virtual bool setVideoAdjustment(const QString &option, double value) = 0;
    virtual void setTransform(const QString &type) = 0;
    virtual void setDeinterlace(bool enabled) = 0;
    virtual void setEqualizerEnabled(const QString &preset, bool enabled) = 0;
    virtual bool snapshot() = 0;

    virtual void setLoop(bool enabled) = 0;
    virtual void setRepeatOne(bool enabled) = 0;
    virtual void setRandom(bool enabled) = 0;
    virtual void setFullscreen(bool enabled) = 0;

    virtual QVariant config(const QString &name) const = 0;
    virtual QString configType(const QString &name) const = 0;
    virtual QString configDescription(const QString &name) const = 0;
    virtual QVariantMap configRange(const QString &) const { return {}; }
    virtual void setConfig(const QString &name, const QVariant &value) = 0;
    virtual QVariantList addons() const = 0;
    virtual bool addonsLoading() const = 0;
    virtual void loadAddons() = 0;
    virtual void findAddons(const QString &source) = 0;
    virtual bool installAddon(const QString &uuid) = 0;
    virtual bool removeAddon(const QString &uuid) = 0;
    virtual QVariantList rendererDevices() const { return {}; }
    virtual bool rendererDiscoverySupported() const { return false; }
    virtual bool discoverRenderers(bool enabled) { Q_UNUSED(enabled); return false; }
    virtual bool setRenderer(const QString &id) { Q_UNUSED(id); return false; }
    virtual void sendHotkey(int vlcKey) = 0;
    virtual bool forwardKey(int qtKey, int qtModifiers, const QString &text) = 0;
    virtual bool forwardWheel(int deltaX, int deltaY, int qtModifiers) = 0;

signals:
    void inputChanged();
    void inputEvent(BackendInputEvent event);
    void fullscreenChanged(bool fullscreen);
    void volumeStateChanged();
    void rateStateChanged();
    void playbackModesChanged();
    void queueChanged();
    void addonsChanged();
    void addonsLoadingChanged();
    void rendererDevicesChanged();
};
