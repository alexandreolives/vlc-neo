// QML-facing player facade. VLC callbacks only post updates to the GUI thread.
#pragma once

#include <QObject>
#include <QSettings>
#include <QTimer>
#include <QUrl>
#include <QVariant>

#include <atomic>
#include <memory>

#include "queue_model.hpp"
#include "player_backend.hpp"

struct intf_thread_t;

class Player : public QObject
{
    Q_OBJECT
    Q_PROPERTY(int state READ state NOTIFY stateChanged)
    Q_PROPERTY(bool playing READ playing NOTIFY stateChanged)
    Q_PROPERTY(bool hasMedia READ hasMedia NOTIFY mediaChanged)
    Q_PROPERTY(double position READ position NOTIFY timeChanged)
    Q_PROPERTY(qint64 time READ time NOTIFY timeChanged)
    Q_PROPERTY(qint64 length READ length NOTIFY timeChanged)
    Q_PROPERTY(bool seekable READ seekable NOTIFY mediaChanged)
    Q_PROPERTY(double volume READ volume NOTIFY volumeChanged)
    Q_PROPERTY(bool muted READ muted NOTIFY volumeChanged)
    Q_PROPERTY(double rate READ rate NOTIFY rateChanged)
    Q_PROPERTY(QString title READ title NOTIFY mediaChanged)
    Q_PROPERTY(QString artist READ artist NOTIFY mediaChanged)
    Q_PROPERTY(QString artworkUrl READ artworkUrl NOTIFY mediaChanged)
    Q_PROPERTY(QString folderPath READ folderPath NOTIFY mediaChanged)
    Q_PROPERTY(QString folderName READ folderName NOTIFY mediaChanged)
    Q_PROPERTY(QUrl mediaUrl READ mediaUrl NOTIFY mediaChanged)
    Q_PROPERTY(bool hasVideo READ hasVideo NOTIFY tracksChanged)
    Q_PROPERTY(int audioDelay READ audioDelay NOTIFY delaysChanged)
    Q_PROPERTY(int subtitleDelay READ subtitleDelay NOTIFY delaysChanged)
    Q_PROPERTY(bool recording READ recording NOTIFY recordingChanged)
    Q_PROPERTY(bool loop READ loop NOTIFY playbackModeChanged)
    Q_PROPERTY(bool repeatOne READ repeatOne NOTIFY playbackModeChanged)
    Q_PROPERTY(bool random READ random NOTIFY playbackModeChanged)
    Q_PROPERTY(int sleepRemaining READ sleepRemaining NOTIFY sleepChanged)
    Q_PROPERTY(bool presetActive READ presetActive NOTIFY presetChanged)
    Q_PROPERTY(QObject *queue READ queue CONSTANT)

public:
    explicit Player(intf_thread_t *intf, QObject *parent = nullptr);
    ~Player() override;

    int state() const { return m_state; }
    bool playing() const { return m_state == 2; }
    bool hasMedia() const { return m_backend->hasInput(); }
    double position() const { return m_position; }
    qint64 time() const { return m_timeMs; }
    qint64 length() const { return m_lengthMs; }
    bool seekable() const { return m_seekable; }
    double volume() const { return m_volume; }
    bool muted() const { return m_muted; }
    double rate() const { return m_rate; }
    QString title() const { return m_title; }
    QString artist() const { return m_artist; }
    QString artworkUrl() const { return m_artworkUrl; }
    QString folderPath() const { return m_folderPath; }
    QString folderName() const { return m_folderName; }
    QUrl mediaUrl() const { return m_mediaUrl; }
    bool hasVideo() const { return m_hasVideo; }
    int audioDelay() const { return m_audioDelayMs; }
    int subtitleDelay() const { return m_subtitleDelayMs; }
    bool recording() const { return m_recording; }
    bool loop() const { return m_loop; }
    bool repeatOne() const { return m_repeatOne; }
    bool random() const { return m_random; }
    int sleepRemaining() const { return m_sleepRemaining; }
    bool presetActive() const { return m_presetActive; }
    QObject *queue() { return &m_queue; }

    // Transport
    Q_INVOKABLE void togglePause();
    Q_INVOKABLE void play();
    Q_INVOKABLE void stop();
    Q_INVOKABLE void next();
    Q_INVOKABLE void previous();
    Q_INVOKABLE void seek(double position);
    Q_INVOKABLE void seekBy(int ms);
    Q_INVOKABLE void setRate(double rate);
    Q_INVOKABLE void setVolume(double volume);
    Q_INVOKABLE void toggleMute();
    Q_INVOKABLE void frameStep();

    // Media
    Q_INVOKABLE void openUrls(const QList<QUrl> &urls, bool playNow);
    Q_INVOKABLE void openLocation(const QString &mrl, bool playNow);
    Q_INVOKABLE void playItem(int id);
    Q_INVOKABLE void removeItem(int id);
    Q_INVOKABLE void clearQueue();
    Q_INVOKABLE QStringList recentMedia() const;
    Q_INVOKABLE void clearRecentMedia();

    // Tracks: category is "video", "audio" or "spu"
    Q_INVOKABLE QVariantList tracks(const QString &category) const;
    Q_INVOKABLE void selectTrack(const QString &category, int id);
    Q_INVOKABLE bool addSubtitleFile(const QUrl &url);
    Q_INVOKABLE QVariantList audioDevices() const;
    Q_INVOKABLE void setAudioDevice(const QString &id);

    // Live tuning
    Q_INVOKABLE void setAudioDelay(int ms);
    Q_INVOKABLE void setSubtitleDelay(int ms);
    Q_INVOKABLE void setSubtitleScale(int percent);
    Q_INVOKABLE int subtitleScale() const;
    Q_INVOKABLE void setSubtitleMargin(int px);
    Q_INVOKABLE int subtitleMargin() const;
    Q_INVOKABLE void setAspectRatio(const QString &ratio);
    Q_INVOKABLE QString aspectRatio() const;
    Q_INVOKABLE void setTransform(const QString &type);
    Q_INVOKABLE void setDeinterlace(bool on);
    Q_INVOKABLE void setEqualizerPreset(const QString &preset);
    Q_INVOKABLE QString equalizerPreset() const;
    Q_INVOKABLE void setLoop(bool on);
    Q_INVOKABLE void setRepeatOne(bool on);
    Q_INVOKABLE void setRandom(bool on);
    Q_INVOKABLE void setSleepTimer(int minutes);

    // Tools
    Q_INVOKABLE void snapshot();
    Q_INVOKABLE void toggleRecord();
    Q_INVOKABLE void setFullscreenState(bool fs);

    // Per-folder presets ("show presets")
    Q_INVOKABLE void savePresetForFolder();
    Q_INVOKABLE void forgetPresetForFolder();

    // Resume, bookmarks, chapters
    Q_INVOKABLE qint64 resumePoint() const;
    Q_INVOKABLE void resume();
    Q_INVOKABLE void addBookmark();
    Q_INVOKABLE QVariantList bookmarks() const;
    Q_INVOKABLE void removeBookmark(qint64 ms);
    Q_INVOKABLE QVariantList chapters() const;
    Q_INVOKABLE void jumpTo(qint64 ms);
    Q_INVOKABLE void selectChapter(int index);

    // Subtitles for a whole folder: matched to episodes by number.
    Q_INVOKABLE int linkSubtitleFolder(const QUrl &folder);
    Q_INVOKABLE void unlinkSubtitleFolder();
    Q_INVOKABLE QString linkedSubtitleFolder() const;
    // File name of the subtitle attached from the linked folder to the current media.
    Q_INVOKABLE QString linkedSubtitleFile() const { return m_linkedSubtitleFile; }

    // VLC core configuration (persisted in vlcrc)
    Q_INVOKABLE QVariant config(const QString &name) const;
    Q_INVOKABLE void setConfig(const QString &name, const QVariant &value);

    // Hotkeys: forward a Qt key event to VLC's hotkey engine.
    Q_INVOKABLE bool forwardKey(int qtKey, int qtModifiers, const QString &text);
    Q_INVOKABLE bool saveQueueAs(const QUrl &file);

    Q_INVOKABLE QString formatTime(qint64 ms) const;

signals:
    void stateChanged();
    void mediaChanged();
    void timeChanged();
    void volumeChanged();
    void rateChanged();
    void tracksChanged();
    void bookmarksChanged();
    void chaptersChanged();
    void resumeAvailable(qint64 ms);
    void delaysChanged();
    void recordingChanged();
    void playbackModeChanged();
    void sleepChanged();
    void presetChanged();
    void fullscreenRequested(bool fullscreen);
    void notify(const QString &message);

private:
    // VLC callbacks (any thread)
    void refreshCurrentInput();
    void onBackendInputChanged();
    void onBackendInputEvent(BackendInputEvent event);
    void refreshTime();
    void refreshState();
    void refreshMeta();
    void refreshTracks();
    void refreshDelays();
    void refreshVolume();
    void refreshModes();
    void rebuildQueue();
    void applyPendingPreset();
    void applyLinkedSubtitles();
    void saveResumePoint();
    QString mediaKey(const QString &group) const;
    void rememberRecent(const QString &mrl);
    QString presetKey() const;

    std::unique_ptr<PlayerBackend> m_backend;
    QueueModel m_queue;
    QSettings m_settings;
    QTimer m_queueTimer;
    QTimer m_sleepTimer;

    int m_state = 0;
    double m_position = 0.0;
    qint64 m_timeMs = 0;
    qint64 m_lengthMs = 0;
    bool m_seekable = false;
    double m_volume = 1.0;
    bool m_muted = false;
    double m_rate = 1.0;
    QString m_title, m_artist, m_artworkUrl, m_folderPath, m_folderName;
    QUrl m_mediaUrl;
    bool m_hasVideo = false;
    int m_audioDelayMs = 0;
    int m_subtitleDelayMs = 0;
    bool m_recording = false;
    bool m_loop = false, m_repeatOne = false, m_random = false;
    int m_sleepRemaining = 0;
    bool m_presetActive = false;
    bool m_presetPending = false;
    bool m_subsLinkedApplied = false;
    QString m_linkedSubtitleFile;
    qint64 m_lastSavedResume = 0;
    std::atomic<bool> m_timePosted{false};
};
