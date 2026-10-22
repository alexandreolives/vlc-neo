#include "player.hpp"

#include <QCoreApplication>
#include <QDir>
#include <QHash>
#include <QTemporaryDir>

#include <algorithm>
#include <cstdio>
#include <limits>

namespace {

class FakeBackend final : public PlayerBackend
{
public:
    void record(const char *name) const { calls.append(QString::fromLatin1(name)); }
    bool called(const char *name) const { return calls.contains(QString::fromLatin1(name)); }

    void togglePause() override { record("togglePause"); ++togglePauseCalls; }
    void play() override { record("play"); ++playCalls; }
    void pause() override { record("pause"); ++pauseCalls; }
    void stop() override { record("stop"); }
    void next() override { record("next"); }
    void previous() override { record("previous"); }
    void setRate(double value) override { record("setRate"); rate = value; }
    void setVolume(double value) override { record("setVolume"); volume = value; }
    void setMuted(bool value) override { record("setMuted"); muted = value; }
    void toggleMute() override { record("toggleMute"); muted = !muted; }
    void openUrls(const QList<QUrl> &urls, bool playNow) override
    {
        record("openUrls");
        lastOpenedUrls = urls;
        lastPlayNow = playNow;
    }
    void playItem(int) override { record("playItem"); }
    void removeItem(int) override { record("removeItem"); }
    void clearQueue() override { record("clearQueue"); }
    QueueSnapshot queueSnapshot() const override { return {}; }
    int currentQueueItemId() const override { return -1; }
    bool exportQueue(const QString &) override { record("exportQueue"); return true; }
    BackendPlaylistState playlistState() const override
    {
        BackendPlaylistState result;
        result.rate = rate;
        result.volume = volume;
        result.muted = muted;
        return result;
    }
    bool syncCurrentInput() override { record("syncCurrentInput"); return false; }
    BackendInputState inputState() const override { return input; }
    bool hasInput() const override { return input.hasInput; }
    void seek(double value) override { record("seek"); position = value; }
    void seekBy(int) override { record("seekBy"); }
    void frameStep() override { record("frameStep"); }
    void jumpTo(qint64 value) override { record("jumpTo"); lastJumpMs = value; }
    void toggleRecord() override { record("toggleRecord"); }
    QList<BackendTrack> tracks(const QString &) const override { record("tracks"); return {}; }
    void selectTrack(const QString &, int) override { record("selectTrack"); }
    bool addSubtitleFile(const QUrl &, bool) override { record("addSubtitleFile"); return true; }
    QList<BackendAudioDevice> audioDevices() const override { record("audioDevices"); return {}; }
    void setAudioDevice(const QString &) override { record("setAudioDevice"); }
    void setAudioDelay(int) override { record("setAudioDelay"); }
    void setSubtitleDelay(int) override { record("setSubtitleDelay"); }
    QList<BackendChapter> chapters() const override { record("chapters"); return {}; }
    void selectChapter(int) override { record("selectChapter"); }
    void setSubtitleScale(int value) override { record("setSubtitleScale"); subtitleScaleValue = value; }
    int subtitleScale() const override { return subtitleScaleValue; }
    void setSubtitleMargin(int value) override { record("setSubtitleMargin"); subtitleMarginValue = value; }
    int subtitleMargin() const override { return subtitleMarginValue; }
    void setAspectRatio(const QString &value) override { record("setAspectRatio"); aspectRatioValue = value; }
    QString aspectRatio() const override { return aspectRatioValue; }
    bool setVideoFilterChain(const QString &value) override { videoFilterChain = value; return true; }
    bool setVideoAdjustment(const QString &option, double value) override { videoAdjustments.insert(option, value); return true; }
    void setTransform(const QString &) override { record("setTransform"); }
    void setDeinterlace(bool) override { record("setDeinterlace"); }
    void setEqualizerEnabled(const QString &, bool) override { record("setEqualizerEnabled"); }
    bool snapshot() override { record("snapshot"); return snapshotResult; }
    void setLoop(bool) override { record("setLoop"); }
    void setRepeatOne(bool) override { record("setRepeatOne"); }
    void setRandom(bool) override { record("setRandom"); }
    void setFullscreen(bool) override { record("setFullscreen"); }
    QVariant config(const QString &name) const override { record("config"); return configValues.value(name); }
    QString configType(const QString &) const override { record("configType"); return {}; }
    QString configDescription(const QString &) const override { record("configDescription"); return {}; }
    void setConfig(const QString &, const QVariant &) override { record("setConfig"); }
    QVariantList addons() const override { return addonEntries; }
    bool addonsLoading() const override { return loadingAddons; }
    void loadAddons() override { record("loadAddons"); ++loadAddonsCalls; }
    void findAddons(const QString &source) override { record("findAddons"); addonSearchSource = source; }
    bool installAddon(const QString &) override { record("installAddon"); return true; }
    bool removeAddon(const QString &) override { record("removeAddon"); return true; }
    void sendHotkey(int) override { record("sendHotkey"); }
    bool forwardKey(int, int, const QString &) override { record("forwardKey"); return forwardKeyResult; }
    bool forwardWheel(int, int, int) override { record("forwardWheel"); return forwardWheelResult; }

    void publishInputState(const BackendInputState &state)
    {
        input = state;
        emit inputChanged();
    }

    void publishVolumeState()
    {
        emit volumeStateChanged();
    }

    int togglePauseCalls = 0;
    int playCalls = 0;
    int pauseCalls = 0;
    double rate = 1.0;
    double volume = 1.0;
    double position = -1.0;
    bool muted = false;
    QString videoFilterChain;
    QHash<QString, double> videoAdjustments;
    QVariantList addonEntries;
    QString addonSearchSource;
    int loadAddonsCalls = 0;
    bool loadingAddons = false;
    bool snapshotResult = true;
    bool forwardKeyResult = true;
    bool forwardWheelResult = true;
    QList<QUrl> lastOpenedUrls;
    bool lastPlayNow = false;
    int subtitleScaleValue = 100;
    int subtitleMarginValue = 0;
    qint64 lastJumpMs = -1;
    QString aspectRatioValue;
    QHash<QString, QVariant> configValues;
    mutable QStringList calls;
    BackendInputState input;
};

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
    QTemporaryDir configDir;
    if (!configDir.isValid())
        return 1;
    qputenv("XDG_CONFIG_HOME", configDir.path().toUtf8());

    QCoreApplication app(argc, argv);
    auto backend = std::make_unique<FakeBackend>();
    FakeBackend *fake = backend.get();
    fake->configValues.insert(QStringLiteral("qt-recentplay"), true);
    Player player(std::move(backend));

    bool ok = true;
    QueueModel *queueModel = qobject_cast<QueueModel *>(player.queue());
    ok &= expect(queueModel != nullptr, "the original QML queue property exposes its list model");
    if (queueModel) {
        const auto roles = queueModel->roleNames();
        ok &= expect(queueModel->property("count").toInt() == 0
                     && roles.value(QueueModel::IdRole) == QByteArrayLiteral("itemId")
                     && roles.value(QueueModel::TitleRole) == QByteArrayLiteral("title")
                     && roles.value(QueueModel::DurationRole) == QByteArrayLiteral("duration")
                     && roles.value(QueueModel::CurrentRole) == QByteArrayLiteral("current")
                     && roles.value(QueueModel::UriRole) == QByteArrayLiteral("uri"),
                     "the original queue count and five QML roles remain available");
    }
    QueueModel queueProbe;
    int queueCountSignals = 0;
    QObject::connect(&queueProbe, &QueueModel::countChanged, [&] { ++queueCountSignals; });
    queueProbe.reset({MediaQueueEntry{7, QStringLiteral("Queued item"), 1200, QStringLiteral("file:///queued")}}, 7);
    const QModelIndex queuedIndex = queueProbe.index(0, 0);
    ok &= expect(queueProbe.property("count").toInt() == 1 && queueCountSignals == 1
                 && queueProbe.data(queuedIndex, QueueModel::IdRole).toInt() == 7
                 && queueProbe.data(queuedIndex, QueueModel::CurrentRole).toBool(),
                 "queue reset updates the count notification and current-item role");
    player.seek(-1.0);
    ok &= expect(fake->position == 0.0, "seek clamps below zero");
    player.seek(2.0);
    ok &= expect(fake->position == 1.0, "seek clamps above one");
    player.setRate(0.1);
    ok &= expect(fake->rate == 0.25, "rate clamps to supported minimum");
    player.setVolume(4.0);
    ok &= expect(fake->volume == 3.0, "volume clamps to supported maximum");
    player.toggleMute();
    fake->publishVolumeState();
    ok &= expect(fake->muted && player.muted(), "mute command and state are delegated to the backend");
    player.setVolume(0.5);
    ok &= expect(fake->volume == 0.5 && !fake->muted,
                 "setting a positive volume restores audio after mute");
    fake->muted = false;
    fake->publishVolumeState();
    player.toggleMute();
    ok &= expect(fake->muted, "unmute toggle is delegated to the backend");
    const bool filterApplied = player.setVideoFilterChain(QStringLiteral("adjust,transform"));
    const bool brightnessApplied = player.setVideoAdjustment(QStringLiteral("brightness"), 1.25);
    const bool gammaApplied = player.setVideoAdjustment(QStringLiteral("gamma"), 1.4);
    const bool invalidAdjustmentRejected = !player.setVideoAdjustment(QStringLiteral("contrast"), std::numeric_limits<double>::infinity());
    ok &= expect(filterApplied && brightnessApplied && gammaApplied && invalidAdjustmentRejected,
                 "video filter preview reports whether live Vout controls accepted the update");
    ok &= expect(fake->videoFilterChain == QStringLiteral("adjust,transform"),
                 "video filter preview chain is delegated to the backend");
    ok &= expect(fake->videoAdjustments.value(QStringLiteral("brightness")) == 1.25
                 && fake->videoAdjustments.value(QStringLiteral("gamma")) == 1.4
                 && !fake->videoAdjustments.contains(QStringLiteral("contrast")),
                 "finite video adjustment values are delegated to the backend");
    player.play();
    ok &= expect(fake->playCalls == 1, "play is delegated to the backend");
    player.togglePause();
    ok &= expect(fake->playCalls == 2 && fake->togglePauseCalls == 0,
                 "toggle pause starts playback when there is no current input");

    BackendInputState input;
    input.hasInput = true;
    input.state = 2;
    input.position = 0.4;
    input.timeMs = 12000;
    input.lengthMs = 30000;
    input.seekable = true;
    input.mediaUrl = QUrl::fromLocalFile(configDir.filePath(QStringLiteral("Season/Episode.S01E01.mkv")));
    input.title = QStringLiteral("Test media");
    fake->publishInputState(input);
    ok &= expect(player.hasMedia(), "media presence comes from the injected backend");
    ok &= expect(player.state() == 2 && player.playing(), "playback state comes from the injected backend");
    ok &= expect(player.position() == 0.4 && player.time() == 12000 && player.length() == 30000 && player.seekable(),
                 "timeline state comes from the injected backend");
    ok &= expect(player.title() == QStringLiteral("Test media"), "metadata comes from the injected backend");
    ok &= expect(player.recentMedia() == QStringList{input.mediaUrl.toString()},
                 "the original recent-media property still records the current VLC input");
    ok &= expect(player.resumePoint() == 12000,
                 "the original resume-point method reads the saved current-media position");
    ok &= expect(player.resumePointFor(input.mediaUrl) == 12000
                 && player.resumeDurationFor(input.mediaUrl) == 30000,
                 "resume queries for a media URL return its saved point and duration");
    player.resume();
    ok &= expect(fake->called("jumpTo") && fake->lastJumpMs == 12000,
                 "the original resume action seeks the injected VLC backend to its saved point");
    player.addBookmark();
    const QVariantList savedBookmarks = player.bookmarks();
    ok &= expect(savedBookmarks.size() == 1
                 && savedBookmarks.first().toMap().value(QStringLiteral("time")).toLongLong() == 12000
                 && savedBookmarks.first().toMap().value(QStringLiteral("label")).toString() == QStringLiteral("00:00:12"),
                 "the original bookmark methods save and format the current playback position");
    player.removeBookmark(12000);
    ok &= expect(player.bookmarks().isEmpty(), "the original bookmark removal method clears the selected timestamp");
    player.clearRecentMedia();
    ok &= expect(player.recentMedia().isEmpty(), "the original recent-media clear method remains available");
    ok &= expect(player.equalizerPreset() == QStringLiteral("off"),
                 "the original equalizer getter reads the stored default preset");
    player.setEqualizerPreset(QStringLiteral("rock"));
    ok &= expect(player.equalizerPreset() == QStringLiteral("rock") && fake->called("setEqualizerEnabled"),
                 "the original equalizer preset method stores and applies the selected preset");
    player.setSleepTimer(1);
    ok &= expect(player.sleepRemaining() == 60, "the original sleep timer method updates the remaining-time property");
    player.setSleepTimer(0);
    ok &= expect(player.sleepRemaining() == 0, "the original sleep timer method cancels when set to zero");

    player.setSubtitleScale(125);
    player.setSubtitleMargin(24);
    ok &= expect(player.subtitleScale() == 125 && player.subtitleMargin() == 24,
                 "the original subtitle scale and margin getters reflect backend values");

    const QString subtitleFolder = configDir.filePath(QStringLiteral("Subtitles"));
    QDir().mkpath(subtitleFolder);
    const QUrl subtitleFolderUrl = QUrl::fromLocalFile(subtitleFolder);
    player.linkSubtitleFolder(subtitleFolderUrl);
    ok &= expect(player.linkedSubtitleFolder() == subtitleFolder,
                 "the original per-folder subtitle link and lookup methods remain connected to persistent state");
    player.unlinkSubtitleFolder();
    ok &= expect(player.linkedSubtitleFolder().isEmpty(), "the original per-folder subtitle unlink method removes its link");
    ok &= expect(player.linkedSubtitleFile().isEmpty(), "the original linked-subtitle filename accessor remains available");

    player.savePresetForFolder();
    ok &= expect(player.presetActive(), "the original folder-preset save method remains active for local media");
    player.forgetPresetForFolder();
    ok &= expect(!player.presetActive(), "the original folder-preset removal method clears its active state");
    ok &= expect(player.formatTime(3723000) == QStringLiteral("01:02:03"),
                 "the original time formatter preserves hour-minute-second output");
    const QUrl networkLocation(QStringLiteral("https://example.test/movie.mkv"));
    player.openLocation(networkLocation.toString(), false);
    ok &= expect(fake->lastOpenedUrls == QList<QUrl>{networkLocation} && !fake->lastPlayNow,
                 "the original location opener still routes network URLs through VLC");
    const QUrl namedPlaylist = QUrl::fromLocalFile(configDir.filePath(QStringLiteral("Curated List.m3u8")));
    player.openUrls({namedPlaylist}, true);
    ok &= expect(player.playlistName() == QStringLiteral("Curated List"),
                 "opening a named playlist exposes its filename as the playlist label");
    player.openUrls({QUrl::fromLocalFile(QStringLiteral("/tmp/queued-track.mkv"))}, false);
    ok &= expect(player.playlistName() == QStringLiteral("Curated List"),
                 "queue additions preserve the active playlist label");
    player.openUrls({QUrl::fromLocalFile(QStringLiteral("/tmp/standalone-track.mkv"))}, true);
    ok &= expect(player.playlistName().isEmpty(),
                 "opening standalone media clears the previous playlist label");

    fake->calls.clear();
    player.stop();
    player.next();
    player.previous();
    player.seekBy(5000);
    player.frameStep();
    player.openUrls({QUrl::fromLocalFile(QStringLiteral("/tmp/neo-test.mkv"))}, true);
    player.playItem(7);
    player.removeItem(7);
    player.clearQueue();
    player.saveQueueAs(QUrl::fromLocalFile(QStringLiteral("/tmp/neo-test.m3u8")));
    player.tracks(QStringLiteral("audio"));
    player.selectTrack(QStringLiteral("audio"), 2);
    player.addSubtitleFile(QUrl::fromLocalFile(QStringLiteral("/tmp/neo-test.srt")));
    player.audioDevices();
    player.setAudioDevice(QStringLiteral("device-1"));
    player.setAudioDelay(120);
    player.setSubtitleDelay(-250);
    player.setSubtitleScale(125);
    player.setSubtitleMargin(24);
    player.setAspectRatio(QStringLiteral("16:9"));
    player.aspectRatio();
    player.setTransform(QStringLiteral("90"));
    player.setDeinterlace(true);
    player.setEqualizerPreset(QStringLiteral("rock"));
    player.setLoop(true);
    player.setRepeatOne(true);
    player.setRandom(true);
    player.snapshot();
    player.toggleRecord();
    player.setFullscreenState(true);
    player.setConfig(QStringLiteral("volume"), 80);
    player.config(QStringLiteral("volume"));
    player.configType(QStringLiteral("volume"));
    player.configDescription(QStringLiteral("volume"));
    player.sendHotkey(0x2000000);
    player.forwardKey(Qt::Key_Space, 0, QStringLiteral(" "));
    player.forwardWheel(0, 120, Qt::ControlModifier);
    player.chapters();
    player.selectChapter(1);
    const QStringList expectedBackendCalls = {
        QStringLiteral("stop"), QStringLiteral("next"), QStringLiteral("previous"),
        QStringLiteral("seekBy"), QStringLiteral("frameStep"), QStringLiteral("openUrls"),
        QStringLiteral("playItem"), QStringLiteral("removeItem"), QStringLiteral("clearQueue"),
        QStringLiteral("exportQueue"), QStringLiteral("tracks"), QStringLiteral("selectTrack"),
        QStringLiteral("addSubtitleFile"), QStringLiteral("audioDevices"), QStringLiteral("setAudioDevice"),
        QStringLiteral("setAudioDelay"), QStringLiteral("setSubtitleDelay"),
        QStringLiteral("setSubtitleScale"), QStringLiteral("setSubtitleMargin"),
        QStringLiteral("setAspectRatio"), QStringLiteral("setTransform"), QStringLiteral("setDeinterlace"),
        QStringLiteral("setEqualizerEnabled"), QStringLiteral("setLoop"), QStringLiteral("setRepeatOne"),
        QStringLiteral("setRandom"), QStringLiteral("snapshot"), QStringLiteral("toggleRecord"),
        QStringLiteral("setFullscreen"), QStringLiteral("setConfig"), QStringLiteral("config"),
        QStringLiteral("configType"), QStringLiteral("configDescription"), QStringLiteral("sendHotkey"), QStringLiteral("forwardKey"), QStringLiteral("forwardWheel"), QStringLiteral("chapters"),
        QStringLiteral("selectChapter")};
    const bool allExistingControlsForwarded = std::all_of(
        expectedBackendCalls.cbegin(), expectedBackendCalls.cend(),
        [fake](const QString &name) { return fake->calls.contains(name); });
    ok &= expect(allExistingControlsForwarded,
                 "the existing QML-facing VLC controls still reach their backend after the facade split");
    return ok ? 0 : 1;
}
