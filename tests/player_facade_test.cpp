#include "player.hpp"

#include <QCoreApplication>

#include <cstdio>

namespace {

class FakeBackend final : public PlayerBackend
{
public:
    void togglePause() override { ++togglePauseCalls; }
    void play() override { ++playCalls; }
    void pause() override { ++pauseCalls; }
    void stop() override {}
    void next() override {}
    void previous() override {}
    void setRate(double value) override { rate = value; }
    void setVolume(double value) override { volume = value; }
    void setMuted(bool value) override { muted = value; }
    void toggleMute() override { muted = !muted; }
    void openUrls(const QList<QUrl> &, bool) override {}
    void playItem(int) override {}
    void removeItem(int) override {}
    void clearQueue() override {}
    QueueSnapshot queueSnapshot() const override { return {}; }
    int currentQueueItemId() const override { return -1; }
    bool exportQueue(const QString &) override { return true; }
    BackendPlaylistState playlistState() const override
    {
        BackendPlaylistState result;
        result.rate = rate;
        result.volume = volume;
        result.muted = muted;
        return result;
    }
    bool syncCurrentInput() override { return false; }
    BackendInputState inputState() const override { return input; }
    bool hasInput() const override { return input.hasInput; }
    void seek(double value) override { position = value; }
    void seekBy(int) override {}
    void frameStep() override {}
    void jumpTo(qint64) override {}
    void toggleRecord() override {}
    QList<BackendTrack> tracks(const QString &) const override { return {}; }
    void selectTrack(const QString &, int) override {}
    bool addSubtitleFile(const QUrl &, bool) override { return true; }
    QList<BackendAudioDevice> audioDevices() const override { return {}; }
    void setAudioDevice(const QString &) override {}
    void setAudioDelay(int) override {}
    void setSubtitleDelay(int) override {}
    QList<BackendChapter> chapters() const override { return {}; }
    void selectChapter(int) override {}
    void setSubtitleScale(int) override {}
    int subtitleScale() const override { return 100; }
    void setSubtitleMargin(int) override {}
    int subtitleMargin() const override { return 0; }
    void setAspectRatio(const QString &) override {}
    QString aspectRatio() const override { return {}; }
    void setTransform(const QString &) override {}
    void setDeinterlace(bool) override {}
    void setEqualizerEnabled(const QString &, bool) override {}
    bool snapshot() override { return false; }
    void setLoop(bool) override {}
    void setRepeatOne(bool) override {}
    void setRandom(bool) override {}
    void setFullscreen(bool) override {}
    QVariant config(const QString &) const override { return {}; }
    void setConfig(const QString &, const QVariant &) override {}
    bool forwardKey(int, int, const QString &) override { return false; }

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
    QCoreApplication app(argc, argv);
    auto backend = std::make_unique<FakeBackend>();
    FakeBackend *fake = backend.get();
    Player player(std::move(backend));

    bool ok = true;
    player.seek(-1.0);
    ok &= expect(fake->position == 0.0, "seek clamps below zero");
    player.seek(2.0);
    ok &= expect(fake->position == 1.0, "seek clamps above one");
    player.setRate(0.1);
    ok &= expect(fake->rate == 0.25, "rate clamps to supported minimum");
    player.setVolume(2.0);
    ok &= expect(fake->volume == 1.25, "volume clamps to supported maximum");
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
    input.title = QStringLiteral("Test media");
    fake->publishInputState(input);
    ok &= expect(player.hasMedia(), "media presence comes from the injected backend");
    ok &= expect(player.state() == 2 && player.playing(), "playback state comes from the injected backend");
    ok &= expect(player.position() == 0.4 && player.time() == 12000 && player.length() == 30000 && player.seekable(),
                 "timeline state comes from the injected backend");
    ok &= expect(player.title() == QStringLiteral("Test media"), "metadata comes from the injected backend");
    return ok ? 0 : 1;
}
