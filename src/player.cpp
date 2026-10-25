#include "player.hpp"
#include "subtitle_matcher.hpp"

#include <QFutureWatcher>
#include <QCryptographicHash>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QRegularExpression>
#include <QSaveFile>
#include <QStandardPaths>
#include <QSet>
#include <QStringList>
#include <QtConcurrent/QtConcurrentRun>

#include <cmath>
#include <algorithm>
#include <utility>

namespace {
const QStringList &profileOptionNames()
{
    static const QStringList names = {
        QStringLiteral("audio-language"), QStringLiteral("sub-language"),
        QStringLiteral("file-caching"), QStringLiteral("disc-caching"),
        QStringLiteral("network-caching"), QStringLiteral("live-caching"),
        QStringLiteral("avcodec-hw"), QStringLiteral("deinterlace"),
        QStringLiteral("deinterlace-mode"), QStringLiteral("video-filter"),
        QStringLiteral("audio-filter"), QStringLiteral("play-and-pause"),
        QStringLiteral("play-and-exit"), QStringLiteral("freetype-font"),
        QStringLiteral("freetype-color"), QStringLiteral("freetype-opacity"),
        QStringLiteral("freetype-bold"), QStringLiteral("freetype-outline-thickness"),
        QStringLiteral("freetype-shadow-opacity"), QStringLiteral("freetype-rel-fontsize")
    };
    return names;
}

QList<QUrl> parseNetworkUrls(const QString &lines)
{
    QList<QUrl> urls;
    for (const QString &line : lines.split(QLatin1Char('\n'))) {
        const QString value = line.trimmed();
        if (value.isEmpty() || value.startsWith(QLatin1Char('#')))
            continue;
        const QUrl url = QUrl::fromUserInput(value);
        if (!url.isValid() || url.scheme().isEmpty() || url.isLocalFile())
            return {};
        urls.append(url);
    }
    return urls;
}
} // namespace

// -------------------------------------------------------------------- Player

Player::Player(std::unique_ptr<PlayerBackend> backend, QObject *parent)
    : QObject(parent), m_backend(std::move(backend))
{
    Q_ASSERT(m_backend);
    m_queueTimer.setSingleShot(true);
    m_queueTimer.setInterval(120);
    connect(&m_queueTimer, &QTimer::timeout, this, &Player::rebuildQueue);

    m_subtitleDebounce.setSingleShot(true);
    m_subtitleDebounce.setInterval(120);
    connect(&m_subtitleDebounce, &QTimer::timeout, this, &Player::loadSubtitleTimeline);

    m_sleepTimer.setInterval(1000);
    connect(&m_sleepTimer, &QTimer::timeout, this, [this] {
        if (--m_sleepRemaining <= 0) {
            m_sleepTimer.stop();
            m_sleepRemaining = 0;
            m_backend->pause();
            emit notify(tr("Sleep timer finished"));
        }
        emit sleepChanged();
    });

    connect(m_backend.get(), &PlayerBackend::inputChanged, this, &Player::onBackendInputChanged);
    connect(m_backend.get(), &PlayerBackend::inputEvent, this, &Player::onBackendInputEvent);
    connect(m_backend.get(), &PlayerBackend::fullscreenChanged, this, &Player::fullscreenRequested);
    connect(m_backend.get(), &PlayerBackend::volumeStateChanged, this, &Player::refreshVolume);
    connect(m_backend.get(), &PlayerBackend::rateStateChanged, this, &Player::refreshState);
    connect(m_backend.get(), &PlayerBackend::playbackModesChanged, this, &Player::refreshModes);
    connect(m_backend.get(), &PlayerBackend::queueChanged, this, [this] {
        if (!m_queueTimer.isActive())
            m_queueTimer.start();
    });
    connect(m_backend.get(), &PlayerBackend::addonsChanged, this, &Player::addonsChanged);
    connect(m_backend.get(), &PlayerBackend::addonsLoadingChanged, this, &Player::addonsLoadingChanged);
    connect(m_backend.get(), &PlayerBackend::rendererDevicesChanged, this, &Player::rendererDevicesChanged);

    // VLC 3 marks these options obsolete on POSIX and does not write them to
    // vlcrc. Restore Neo's saved values before any media can start playback.
    if (m_stateStore.hasHttpProxySettings()) {
        m_backend->setConfig(QStringLiteral("http-proxy"), m_stateStore.httpProxy());
        m_backend->setConfig(QStringLiteral("http-proxy-pwd"), m_stateStore.httpProxyPassword());
    }
    // VLC treats core verbosity as a command-line option and omits it from
    // vlcrc. Keep Neo's visible verbosity preference in its own settings.
    if (m_stateStore.hasCoreVerbosity())
        m_backend->setConfig(QStringLiteral("verbose"), m_stateStore.coreVerbosity());

    if (!m_backend->syncCurrentInput())
        refreshCurrentInput();
    refreshVolume();
    refreshModes();
    rebuildQueue();
    const QString equalizer = m_stateStore.equalizerPreset();
    m_backend->setEqualizerEnabled(equalizer, !equalizer.isEmpty() && equalizer != QLatin1String("off"));
}

Player::~Player()
{
    saveResumePoint();
}

void Player::onBackendInputChanged()
{
    saveResumePoint();
    const QString equalizer = m_stateStore.equalizerPreset();
    m_backend->setEqualizerEnabled(equalizer, !equalizer.isEmpty() && equalizer != QLatin1String("off"));
    m_presetPending = true;
    m_subsLinkedApplied = false;
    m_linkedSubtitleFile.clear();
    m_manualSubtitlePath.clear();
    m_linkedSubtitleTrackId = -1;
    m_manualSubtitleTrackId = -1;
    refreshSubtitleTimeline();
    m_lastSavedResume = 0;
    m_presetActive = false;
    emit presetChanged();
    refreshCurrentInput();
}

void Player::onBackendInputEvent(BackendInputEvent event)
{
    switch (event) {
    case BackendInputEvent::Position:
        if (!m_timePosted.exchange(true))
            QMetaObject::invokeMethod(this, [this] { refreshTime(); }, Qt::QueuedConnection);
        break;
    case BackendInputEvent::State:
        refreshState();
        break;
    case BackendInputEvent::Tracks:
        refreshTracks();
        break;
    case BackendInputEvent::Metadata:
        refreshMeta();
        break;
    case BackendInputEvent::Delays:
        refreshDelays();
        break;
    case BackendInputEvent::Volume:
        refreshVolume();
        break;
    case BackendInputEvent::Dead:
        if (!m_backend->syncCurrentInput())
            refreshCurrentInput();
        break;
    }
}

// ---------------------------------------------------------- input state sync

void Player::refreshCurrentInput()
{
    const QUrl previousUrl = m_mediaUrl;
    refreshMeta();
    refreshState();
    refreshTime();
    refreshTracks();
    refreshDelays();
    if (m_mediaUrl != previousUrl) {
        emit bookmarksChanged();
        emit chaptersChanged();
        const qint64 point = resumePoint();
        if (point > 0 && m_stateStore.resumeEnabled())
            emit resumeAvailable(point);
    }

    m_queue.setCurrentId(m_backend->currentQueueItemId());
}

void Player::refreshTime()
{
    m_timePosted = false;
    const BackendInputState state = m_backend->inputState();
    if (state.hasInput) {
        m_position = state.position;
        m_timeMs = state.timeMs;
        m_lengthMs = state.lengthMs;
        if (qAbs(m_timeMs - m_lastSavedResume) > 5000)
            saveResumePoint();
        if (state.seekable != m_seekable) {
            m_seekable = state.seekable;
            emit mediaChanged();
        }
    } else {
        m_position = 0.0;
        m_timeMs = m_lengthMs = 0;
    }
    emit timeChanged();
}

void Player::refreshState()
{
    const BackendInputState input = m_backend->inputState();
    const int state = input.state;
    const bool recording = input.recording;
    const double rate = input.hasInput ? input.rate : m_backend->playlistState().rate;
    if (state != m_state) {
        m_state = state;
        emit stateChanged();
        if (state == 2 && m_presetPending)
            QTimer::singleShot(300, this, &Player::applyPendingPreset);
    }
    if (recording != m_recording) {
        m_recording = recording;
        emit recordingChanged();
    }
    if (rate > 0 && !qFuzzyCompare(rate, m_rate)) {
        m_rate = rate;
        emit rateChanged();
    }
}

void Player::refreshMeta()
{
    const BackendInputState state = m_backend->inputState();
    const QString title = state.title;
    const QString artist = state.artist;
    const QString artwork = state.artworkUrl;
    const QUrl url = state.mediaUrl;
    const QString folderPath = url.isLocalFile() ? QFileInfo(url.toLocalFile()).absolutePath() : QString();
    const bool newMedia = url != m_mediaUrl;
    m_title = title;
    m_artist = artist;
    m_artworkUrl = artwork;
    m_mediaUrl = url;
    m_folderPath = folderPath;
    m_folderName = folderPath.isEmpty() ? QString() : QDir(folderPath).dirName();
    if (newMedia && !url.isEmpty() && m_backend->config(QStringLiteral("qt-recentplay")).toBool()) {
        const QString filter = m_backend->config(QStringLiteral("qt-recentplay-filter")).toString();
        bool filtered = false;
        for (const QString &term : filter.split(QLatin1Char('|'), Qt::SkipEmptyParts)) {
            if (url.toString().contains(term.trimmed(), Qt::CaseInsensitive)) {
                filtered = true;
                break;
            }
        }
        if (!filtered)
            rememberRecent(url.toString());
    }
    emit mediaChanged();
}

void Player::refreshTracks()
{
    m_hasVideo = m_backend->inputState().hasVideo;
    emit tracksChanged();
    emit chaptersChanged();
    applyLinkedSubtitles();
    applyPendingPreset();
    refreshSubtitleTimeline();
}

void Player::refreshDelays()
{
    const BackendInputState state = m_backend->inputState();
    const int audio = state.audioDelayMs;
    const int spu = state.subtitleDelayMs;
    if (audio != m_audioDelayMs || spu != m_subtitleDelayMs) {
        m_audioDelayMs = audio;
        m_subtitleDelayMs = spu;
        emit delaysChanged();
    }
}

void Player::refreshVolume()
{
    const BackendPlaylistState state = m_backend->playlistState();
    m_volume = state.volume;
    m_muted = state.muted;
    emit volumeChanged();
}

void Player::refreshModes()
{
    const BackendPlaylistState state = m_backend->playlistState();
    m_loop = state.loop;
    m_repeatOne = state.repeatOne;
    m_random = state.random;
    emit playbackModeChanged();
}

void Player::rebuildQueue()
{
    const QueueSnapshot snapshot = m_backend->queueSnapshot();
    m_queue.reset(snapshot.entries, snapshot.currentId);
}

// ---------------------------------------------------------------- transport

void Player::togglePause()
{
    if (!m_backend->hasInput()) {
        m_backend->play();
        return;
    }
    m_backend->togglePause();
}

void Player::play() { m_backend->play(); }
void Player::stop() { m_backend->stop(); }
void Player::next() { m_backend->next(); }
void Player::previous() { m_backend->previous(); }

void Player::seek(double position)
{
    const double target = qBound(0.0, position, 1.0);
    m_backend->seek(target);
    if (!m_seekable || m_lengthMs <= 0)
        return;
    m_position = target;
    m_timeMs = qRound64(target * m_lengthMs);
    emit timeChanged();
}

void Player::seekBy(int ms)
{
    m_backend->seekBy(ms);
    if (!m_seekable || m_lengthMs <= 0)
        return;
    m_timeMs = qBound<qint64>(0, m_timeMs + ms, m_lengthMs);
    m_position = double(m_timeMs) / double(m_lengthMs);
    emit timeChanged();
}

void Player::setRate(double rate)
{
    m_backend->setRate(qBound(0.25, rate, 4.0));
}

void Player::setVolume(double volume)
{
    m_backend->setVolume(qBound(0.0, volume, 3.0));
    if (m_muted && volume > 0.0)
        m_backend->setMuted(false);
}

void Player::toggleMute() { m_backend->toggleMute(); }

void Player::frameStep()
{
    m_backend->frameStep();
}

// -------------------------------------------------------------------- media

void Player::openUrls(const QList<QUrl> &urls, bool playNow)
{
    static const QSet<QString> playlistExtensions = {
        QStringLiteral("m3u"), QStringLiteral("m3u8"), QStringLiteral("pls"), QStringLiteral("xspf")
    };
    QString playlistName;
    if (playNow && urls.size() == 1) {
        const QUrl &url = urls.constFirst();
        const QFileInfo fileInfo(url.path());
        if (playlistExtensions.contains(fileInfo.suffix().toLower()))
            playlistName = fileInfo.completeBaseName();
    }
    if (playNow && m_requestedPlaylistName != playlistName) {
        m_requestedPlaylistName = playlistName;
        emit mediaChanged();
    }
    m_backend->openUrls(urls, playNow);
}

void Player::openNetworkUrls(const QString &urlLines, bool playNow)
{
    const QList<QUrl> urls = parseNetworkUrls(urlLines);
    if (!urls.isEmpty())
        openUrls(urls, playNow);
}

void Player::openLocation(const QString &mrl, bool playNow)
{
    const QString trimmed = mrl.trimmed();
    if (trimmed.isEmpty())
        return;
    QUrl url = QFileInfo::exists(trimmed) ? QUrl::fromLocalFile(trimmed) : QUrl::fromUserInput(trimmed);
    openUrls({url}, playNow);
}

void Player::playItem(int id)
{
    m_backend->playItem(id);
}

void Player::removeItem(int id)
{
    m_backend->removeItem(id);
}

void Player::clearQueue() { m_backend->clearQueue(); }

void Player::rememberRecent(const QString &mrl)
{
    m_stateStore.rememberRecentMedia(mrl);
    emit recentMediaChanged();
}

QStringList Player::recentMedia() const
{
    return m_stateStore.recentMedia();
}

void Player::clearRecentMedia()
{
    m_stateStore.clearRecentMedia();
    emit recentMediaChanged();
}

void Player::clearPlaybackHistory()
{
    m_stateStore.clearRecentMedia();
    m_stateStore.clearResumePoints();
    emit recentMediaChanged();
}

bool Player::resumeEnabled() const { return m_stateStore.resumeEnabled(); }

void Player::setResumeEnabled(bool enabled) { m_stateStore.setResumeEnabled(enabled); }

// ------------------------------------------------------------------- tracks

QVariantList Player::tracks(const QString &category) const
{
    QVariantList out;
    for (const BackendTrack &track : m_backend->tracks(category)) {
        QVariantMap row;
        row.insert(QStringLiteral("id"), track.id);
        row.insert(QStringLiteral("name"), track.name);
        row.insert(QStringLiteral("selected"), track.selected);
        out.append(row);
    }
    return out;
}

void Player::selectTrack(const QString &category, int id)
{
    m_backend->selectTrack(category, id);
    if (category == QLatin1String("spu"))
        refreshSubtitleTimeline();
}

bool Player::addSubtitleFile(const QUrl &url)
{
    const bool ok = m_backend->addSubtitleFile(url, true);
    if (ok) {
        m_manualSubtitlePath = url.isLocalFile() ? url.toLocalFile() : QString();
        m_manualSubtitleTrackId = -1;
        refreshSubtitleTimeline();
    }
    emit notify(ok ? tr("Subtitle added") : tr("Could not load subtitle"));
    return ok;
}

QVariantList Player::subtitleFilesForMedia(const QUrl &folder) const
{
    QVariantList out;
    if (!m_mediaUrl.isLocalFile() || !folder.isLocalFile()
        || !QFileInfo(folder.toLocalFile()).isDir())
        return out;

    const QString mediaPath = m_mediaUrl.toLocalFile();
    const QString wantedKey = SubtitleMatcher::episodeKey(mediaPath);
    const QString mediaBase = QFileInfo(mediaPath).completeBaseName();
    const QStringList filters = {QStringLiteral("*.srt"), QStringLiteral("*.ass"),
                                 QStringLiteral("*.ssa"), QStringLiteral("*.sub"),
                                 QStringLiteral("*.vtt"), QStringLiteral("*.smi")};
    const QStringList files = QDir(folder.toLocalFile()).entryList(filters, QDir::Files, QDir::Name);
    for (const QString &name : files) {
        const QString key = SubtitleMatcher::episodeKey(name);
        const bool episodeMatch = !wantedKey.isEmpty() && key == wantedKey;
        const bool prefixMatch = QFileInfo(name).completeBaseName().startsWith(mediaBase, Qt::CaseInsensitive);
        if (!episodeMatch && !prefixMatch)
            continue;
        const QString path = QDir(folder.toLocalFile()).filePath(name);
        out.append(QVariantMap{
            {QStringLiteral("name"), name},
            {QStringLiteral("url"), QUrl::fromLocalFile(path)},
            {QStringLiteral("path"), path},
            {QStringLiteral("selected"), path == m_manualSubtitlePath}
        });
    }
    return out;
}

QVariantList Player::audioDevices() const
{
    QVariantList out;
    for (const BackendAudioDevice &device : m_backend->audioDevices()) {
        QVariantMap dev;
        dev.insert(QStringLiteral("id"), device.id);
        dev.insert(QStringLiteral("name"), device.name);
        dev.insert(QStringLiteral("selected"), device.selected);
        out.append(dev);
    }
    return out;
}

void Player::setAudioDevice(const QString &id) { m_backend->setAudioDevice(id); }

// --------------------------------------------------------------- live tuning

void Player::setAudioDelay(int ms)
{
    m_backend->setAudioDelay(ms);
}

void Player::setSubtitleDelay(int ms)
{
    m_backend->setSubtitleDelay(ms);
}

void Player::setSubtitleScale(int percent)
{
    m_backend->setSubtitleScale(qBound(10, percent, 500));
}

int Player::subtitleScale() const { return m_backend->subtitleScale(); }

void Player::setSubtitleMargin(int px) { m_backend->setSubtitleMargin(px); }

int Player::subtitleMargin() const { return m_backend->subtitleMargin(); }

void Player::setAspectRatio(const QString &ratio) { m_backend->setAspectRatio(ratio); }

QString Player::aspectRatio() const { return m_backend->aspectRatio(); }

bool Player::setVideoFilterChain(const QString &filters) { return m_backend->setVideoFilterChain(filters); }

bool Player::setVideoAdjustment(const QString &option, double value)
{
    return std::isfinite(value) && m_backend->setVideoAdjustment(option, value);
}

void Player::setTransform(const QString &type) { m_backend->setTransform(type); }

void Player::setDeinterlace(bool on) { m_backend->setDeinterlace(on); }

void Player::setEqualizerPreset(const QString &preset)
{
    m_stateStore.setEqualizerPreset(preset);
    m_backend->setEqualizerEnabled(preset, !preset.isEmpty() && preset != QLatin1String("off"));
}

QString Player::equalizerPreset() const
{
    return m_stateStore.equalizerPreset();
}

void Player::setLoop(bool on) { m_backend->setLoop(on); }
void Player::setRepeatOne(bool on) { m_backend->setRepeatOne(on); }
void Player::setRandom(bool on) { m_backend->setRandom(on); }

void Player::setSleepTimer(int minutes)
{
    m_sleepRemaining = qMax(0, minutes) * 60;
    if (m_sleepRemaining > 0)
        m_sleepTimer.start();
    else
        m_sleepTimer.stop();
    emit sleepChanged();
}

// -------------------------------------------------------------------- tools

void Player::snapshot()
{
    if (m_backend->snapshot())
        emit notify(tr("Snapshot saved"));
}

void Player::toggleRecord()
{
    m_backend->toggleRecord();
}

void Player::setFullscreenState(bool fs)
{
    m_backend->setFullscreen(fs);
}

// ------------------------------------------------------------------ presets

static QString selectedTrackName(const QVariantList &tracks)
{
    for (const QVariant &t : tracks) {
        const QVariantMap m = t.toMap();
        if (m.value(QStringLiteral("selected")).toBool())
            return m.value(QStringLiteral("name")).toString();
    }
    return {};
}

void Player::savePresetForFolder()
{
    if (m_folderPath.isEmpty()) {
        emit notify(tr("Presets work with local folders only"));
        return;
    }
    refreshDelays(); // read live values, events may still be queued
    m_stateStore.saveFolderPreset(m_folderPath, FolderPlaybackPreset{
        m_subtitleDelayMs, m_audioDelayMs, subtitleScale(),
        selectedTrackName(tracks(QStringLiteral("spu"))),
        selectedTrackName(tracks(QStringLiteral("audio")))});
    m_presetActive = true;
    emit presetChanged();
    emit notify(tr("Preset saved for \"%1\"").arg(m_folderName));
}

void Player::forgetPresetForFolder()
{
    if (m_folderPath.isEmpty())
        return;
    m_stateStore.forgetFolderPreset(m_folderPath);
    m_presetActive = false;
    emit presetChanged();
    emit notify(tr("Preset removed"));
}

void Player::applyPendingPreset()
{
    // Input must be fully started, otherwise it resets delays from vlcrc.
    if (!m_presetPending || !m_backend->hasInput() || m_state != 2)
        return;
    m_presetPending = false;

    if (m_folderPath.isEmpty() || !m_stateStore.hasFolderPreset(m_folderPath))
        return;
    const FolderPlaybackPreset preset = m_stateStore.folderPreset(m_folderPath);

    setSubtitleDelay(preset.subtitleDelayMs);
    setAudioDelay(preset.audioDelayMs);
    setSubtitleScale(preset.subtitleScale);
    auto pick = [this](const QString &category, const QString &name) {
        if (name.isEmpty())
            return;
        for (const QVariant &t : tracks(category)) {
            const QVariantMap m = t.toMap();
            if (m.value(QStringLiteral("name")).toString() == name) {
                selectTrack(category, m.value(QStringLiteral("id")).toInt());
                return;
            }
        }
    };
    pick(QStringLiteral("spu"), preset.subtitleTrack);
    pick(QStringLiteral("audio"), preset.audioTrack);
    m_presetActive = true;
    emit presetChanged();
    emit notify(tr("Preset applied: %1").arg(m_folderName));
}

// ------------------------------------------------- resume / bookmarks / chapters

void Player::saveResumePoint()
{
    if (!m_stateStore.resumeEnabled())
        return;
    if (m_mediaUrl.isEmpty() || m_lengthMs <= 0)
        return;
    m_lastSavedResume = m_timeMs;
    m_stateStore.saveResumePoint(m_mediaUrl, m_timeMs, m_lengthMs);
}

qint64 Player::resumePoint() const
{
    return m_stateStore.resumePoint(m_mediaUrl);
}

qint64 Player::resumePointFor(const QUrl &media) const
{
    return m_stateStore.resumePoint(media);
}

qint64 Player::resumeDurationFor(const QUrl &media) const
{
    return m_stateStore.resumeDuration(media);
}

void Player::resume()
{
    const qint64 point = resumePoint();
    if (point > 0)
        jumpTo(point);
}

void Player::jumpTo(qint64 ms)
{
    m_backend->jumpTo(ms);
}

QVariantList Player::bookmarks() const
{
    QVariantList out;
    for (qint64 ms : m_stateStore.bookmarks(m_mediaUrl))
        out.append(QVariantMap{{QStringLiteral("time"), ms}, {QStringLiteral("label"), formatTime(ms)}});
    return out;
}

void Player::addBookmark()
{
    if (m_mediaUrl.isEmpty() || !m_backend->hasInput())
        return;
    m_stateStore.addBookmark(m_mediaUrl, m_timeMs);
    emit bookmarksChanged();
    emit notify(tr("Bookmark added at %1").arg(formatTime(m_timeMs)));
}

void Player::removeBookmark(qint64 ms)
{
    if (m_mediaUrl.isEmpty())
        return;
    m_stateStore.removeBookmark(m_mediaUrl, ms);
    emit bookmarksChanged();
}

QVariantList Player::chapters() const
{
    QVariantList out;
    for (const BackendChapter &chapter : m_backend->chapters()) {
        out.append(QVariantMap{
            {QStringLiteral("index"), chapter.index},
            {QStringLiteral("name"), chapter.name},
            {QStringLiteral("selected"), chapter.selected}});
    }
    return out;
}

void Player::selectChapter(int index)
{
    m_backend->selectChapter(index);
}

// ------------------------------------------------------ folder subtitles

namespace {

const QStringList kSubtitleFilters = {
    QStringLiteral("*.srt"), QStringLiteral("*.ass"), QStringLiteral("*.ssa"),
    QStringLiteral("*.sub"), QStringLiteral("*.vtt"), QStringLiteral("*.smi")};

QStringList playlistMediaFolders(const QList<MediaQueueEntry> &entries);

QString playlistSubtitleKey(const QList<MediaQueueEntry> &entries)
{
    QStringList folders = playlistMediaFolders(entries);
    std::sort(folders.begin(), folders.end());
    return QString::fromLatin1(QCryptographicHash::hash(folders.join(QLatin1Char('\n')).toUtf8(),
                                                          QCryptographicHash::Sha256).toHex());
}

QStringList playlistMediaFolders(const QList<MediaQueueEntry> &entries)
{
    QStringList folders;
    for (const MediaQueueEntry &entry : entries) {
        const QUrl url(entry.uri);
        if (!url.isLocalFile())
            continue;
        const QString folder = QFileInfo(url.toLocalFile()).absolutePath();
        if (!folders.contains(folder))
            folders.append(folder);
    }
    return folders;
}

} // namespace

int Player::linkSubtitleFolder(const QUrl &folder)
{
    if (!folder.isLocalFile() || !QFileInfo(folder.toLocalFile()).isDir()) {
        emit notify(tr("Choose a local folder containing subtitles"));
        return 0;
    }
    if (m_folderPath.isEmpty()) {
        emit notify(tr("Open a local file first"));
        return 0;
    }
    const QString dir = folder.toLocalFile();
    m_stateStore.linkSubtitleFolder(m_folderPath, dir);
    m_subsLinkedApplied = false;
    applyLinkedSubtitles();

    // Report how many queue items will find a subtitle.
    QSet<QString> subKeys;
    for (const QString &f : QDir(dir).entryList(kSubtitleFilters, QDir::Files))
        subKeys.insert(SubtitleMatcher::episodeKey(f));
    int matched = 0;
    for (const MediaQueueEntry &e : m_queue.entries()) {
        const QUrl u(e.uri);
        if (u.isLocalFile() && QFileInfo(u.toLocalFile()).absolutePath() == m_folderPath
            && subKeys.contains(SubtitleMatcher::episodeKey(u.toLocalFile())))
            ++matched;
    }
    emit notify(tr("Subtitles linked: %1 episode(s) matched").arg(matched));
    return matched;
}

QUrl Player::activeSubtitleFile() const
{
    return m_subtitleTimelineSource.isEmpty()
        ? QUrl{}
        : QUrl::fromLocalFile(m_subtitleTimelineSource);
}

int Player::activeSubtitleTrackId() const
{
    const QVariantList subtitleTracks = tracks(QStringLiteral("spu"));
    for (const QVariant &entry : subtitleTracks) {
        const QVariantMap track = entry.toMap();
        const int id = track.value(QStringLiteral("id")).toInt();
        if (id >= 0 && track.value(QStringLiteral("selected")).toBool())
            return id;
    }
    return -1;
}

int Player::linkSubtitleFolderToPlaylist(const QUrl &folder)
{
    if (!folder.isLocalFile() || !QFileInfo(folder.toLocalFile()).isDir()) {
        emit notify(tr("Choose a local folder containing subtitles"));
        return 0;
    }
    const QStringList mediaFolders = playlistMediaFolders(m_queue.entries());
    if (mediaFolders.isEmpty()) {
        emit notify(tr("The playlist has no local video files"));
        return 0;
    }

    QString subtitleFolder = QFileInfo(folder.toLocalFile()).canonicalFilePath();
    if (subtitleFolder.isEmpty())
        subtitleFolder = QDir::cleanPath(folder.toLocalFile());
    const QStringList files = QDir(subtitleFolder).entryList(kSubtitleFilters, QDir::Files, QDir::Name);
    m_stateStore.linkSubtitleFoldersToPlaylist(playlistSubtitleKey(m_queue.entries()), mediaFolders, subtitleFolder);
    m_subsLinkedApplied = false;
    applyLinkedSubtitles();

    int matched = 0;
    for (const MediaQueueEntry &entry : m_queue.entries()) {
        const QUrl media(entry.uri);
        if (media.isLocalFile()
            && !SubtitleMatcher::bestMatch(media.toLocalFile(), files).isEmpty())
            ++matched;
    }
    emit notify(tr("Subtitles linked to playlist: %1 of %2 item(s) matched")
                    .arg(matched).arg(m_queue.entries().size()));
    return matched;
}

void Player::unlinkSubtitleFolder()
{
    if (!m_folderPath.isEmpty())
        m_stateStore.unlinkSubtitleFolder(m_folderPath);
    emit notify(tr("Subtitle folder unlinked"));
}

void Player::unlinkSubtitleFolderFromPlaylist()
{
    m_stateStore.unlinkSubtitleFoldersFromPlaylist(playlistSubtitleKey(m_queue.entries()));
    m_subsLinkedApplied = false;
    m_linkedSubtitleFile.clear();
    emit notify(tr("Playlist subtitle links removed"));
}

QString Player::linkedSubtitleFolder() const
{
    return m_stateStore.linkedSubtitleFolder(m_folderPath);
}

QVariantList Player::subtitleFolderMatches(const QUrl &folder, const QString &target) const
{
    QVariantList matches;
    if (!folder.isLocalFile() || !QFileInfo(folder.toLocalFile()).isDir())
        return matches;
    const QStringList files = QDir(folder.toLocalFile()).entryList(kSubtitleFilters, QDir::Files, QDir::Name);
    for (const MediaQueueEntry &entry : m_queue.entries()) {
        const QUrl media(entry.uri);
        if (!media.isLocalFile())
            continue;
        const QString mediaPath = media.toLocalFile();
        if (target == QLatin1String("folder")
            && QFileInfo(mediaPath).absolutePath() != m_folderPath)
            continue;
        const QString best = SubtitleMatcher::bestMatch(mediaPath, files);
        matches.append(QVariantMap {
            {QStringLiteral("media"), entry.title},
            {QStringLiteral("uri"), entry.uri},
            {QStringLiteral("subtitle"), best},
            {QStringLiteral("matched"), !best.isEmpty()}
        });
    }
    return matches;
}

void Player::applyLinkedSubtitles()
{
    if (m_subsLinkedApplied || !m_backend->hasInput() || !m_mediaUrl.isLocalFile())
        return;
    const QString dir = linkedSubtitleFolder();
    if (dir.isEmpty())
        return;
    m_subsLinkedApplied = true;

    const QString mediaFile = m_mediaUrl.toLocalFile();
    const QStringList files = QDir(dir).entryList(kSubtitleFilters, QDir::Files, QDir::Name);
    const QString best = SubtitleMatcher::bestMatch(mediaFile, files);
    if (best.isEmpty())
        return;
    const QUrl subtitleUrl = QUrl::fromLocalFile(QDir(dir).filePath(best));
    if (m_backend->addSubtitleFile(subtitleUrl, false)) {
        m_linkedSubtitleFile = best;
        m_linkedSubtitleTrackId = -1;
        refreshSubtitleTimeline();
    }
}

void Player::refreshSubtitleTimeline()
{
    QString source;
    const QVariantList subtitleTracks = tracks(QStringLiteral("spu"));
    int selectedId = -1;
    int activeTrackCount = 0;
    for (const QVariant &row : subtitleTracks) {
        const QVariantMap track = row.toMap();
        const int id = track.value(QStringLiteral("id")).toInt();
        if (id < 0)
            continue;
        ++activeTrackCount;
        if (track.value(QStringLiteral("selected")).toBool())
            selectedId = id;
    }
    const bool enabled = selectedId >= 0;

    if (enabled && !m_manualSubtitlePath.isEmpty() && m_manualSubtitleTrackId < 0)
        m_manualSubtitleTrackId = selectedId;
    if (enabled && !m_linkedSubtitleFile.isEmpty() && m_linkedSubtitleTrackId < 0)
        m_linkedSubtitleTrackId = selectedId;

    if (enabled && !m_manualSubtitlePath.isEmpty() && selectedId == m_manualSubtitleTrackId) {
        source = m_manualSubtitlePath;
    } else if (enabled && !m_linkedSubtitleFile.isEmpty() && selectedId == m_linkedSubtitleTrackId) {
        source = QDir(linkedSubtitleFolder()).filePath(m_linkedSubtitleFile);
    } else if (enabled && activeTrackCount == 1 && m_mediaUrl.isLocalFile()) {
        const QStringList filters = {QStringLiteral("*.srt"), QStringLiteral("*.vtt"),
                                     QStringLiteral("*.ass"), QStringLiteral("*.ssa")};
        const QStringList files = QDir(m_folderPath).entryList(filters, QDir::Files, QDir::Name);
        const QString best = SubtitleMatcher::bestMatch(m_mediaUrl.toLocalFile(), files);
        if (!best.isEmpty())
            source = QDir(m_folderPath).filePath(best);
    }

    if (source == m_subtitleTimelineSource)
        return;
    m_subtitleTimelineSource = source;
    ++m_subtitleTimelineRevision;
    m_subtitleDebounce.stop();
    m_subtitleCues.clear();
    emit subtitleTimelineChanged();
    if (!source.isEmpty())
        m_subtitleDebounce.start();
}

void Player::loadSubtitleTimeline()
{
    const QString source = m_subtitleTimelineSource;
    const quint64 revision = m_subtitleTimelineRevision;
    if (source.isEmpty())
        return;
    if (m_subtitleLoadInProgress) {
        m_subtitleLoadPending = true;
        return;
    }

    m_subtitleLoadInProgress = true;
    auto *watcher = new QFutureWatcher<QList<SubtitleCue>>(this);
    connect(watcher, &QFutureWatcher<QList<SubtitleCue>>::finished, this, [this, watcher, source, revision] {
        const QList<SubtitleCue> parsed = watcher->result();
        watcher->deleteLater();
        m_subtitleLoadInProgress = false;
        if (revision == m_subtitleTimelineRevision && source == m_subtitleTimelineSource) {
            QVariantList cues;
            cues.reserve(parsed.size());
            qint64 maxEnd = 0;
            for (const SubtitleCue &cue : parsed) {
                maxEnd = qMax(maxEnd, cue.endMs);
                cues.append(QVariantMap{{QStringLiteral("start"), cue.startMs},
                                        {QStringLiteral("end"), cue.endMs},
                                        {QStringLiteral("maxEnd"), maxEnd},
                                        {QStringLiteral("text"), cue.text}});
            }
            m_subtitleCues = cues;
            emit subtitleTimelineChanged();
        }

        if (m_subtitleLoadPending) {
            m_subtitleLoadPending = false;
            if (!m_subtitleTimelineSource.isEmpty())
                loadSubtitleTimeline();
        }
    });
    watcher->setFuture(QtConcurrent::run([source] { return SubtitleTimeline::parseFile(source); }));
}

// -------------------------------------------------------- core config

QVariant Player::config(const QString &name) const
{
    return m_backend->config(name);
}

QString Player::configType(const QString &name) const
{
    return m_backend->configType(name);
}

QString Player::configDescription(const QString &name) const
{
    return m_backend->configDescription(name);
}

QVariantMap Player::configRange(const QString &name) const
{
    return m_backend->configRange(name);
}

void Player::setConfig(const QString &name, const QVariant &value)
{
    m_backend->setConfig(name, value);
    if (name == QLatin1String("http-proxy"))
        m_stateStore.setHttpProxy(value.toString());
    else if (name == QLatin1String("http-proxy-pwd"))
        m_stateStore.setHttpProxyPassword(value.toString());
    else if (name == QLatin1String("verbose"))
        m_stateStore.setCoreVerbosity(value.toInt());
    ++m_configRevision;
    emit configRevisionChanged();
    emit configChanged(name);
}

QVariantMap Player::profileOptions() const
{
    QVariantMap options;
    for (const QString &name : profileOptionNames()) {
        if (!m_backend->configType(name).isEmpty()) {
            const QVariant value = m_backend->config(name);
            if (value.isValid())
                options.insert(name, value);
        }
    }
    return options;
}

bool Player::applyProfileOptions(const QVariantMap &options)
{
    bool applied = false;
    for (const QString &name : profileOptionNames()) {
        const auto it = options.constFind(name);
        if (it == options.cend() || m_backend->configType(name).isEmpty())
            continue;
        m_backend->setConfig(name, it.value());
        if (name == QLatin1String("video-filter"))
            m_backend->setVideoFilterChain(it.value().toString());
        ++m_configRevision;
        emit configChanged(name);
        applied = true;
    }
    if (applied)
        emit configRevisionChanged();
    return applied;
}

QVariantList Player::addons() const { return m_backend->addons(); }
bool Player::addonsLoading() const { return m_backend->addonsLoading(); }
void Player::loadAddons() { m_backend->loadAddons(); }
void Player::findAddons(const QString &source) { m_backend->findAddons(source); }
bool Player::installAddon(const QString &uuid) { return m_backend->installAddon(uuid); }
bool Player::removeAddon(const QString &uuid) { return m_backend->removeAddon(uuid); }
QVariantList Player::rendererDevices() const { return m_backend->rendererDevices(); }
bool Player::rendererDiscoverySupported() const { return m_backend->rendererDiscoverySupported(); }
bool Player::discoverRenderers(bool enabled) { return m_backend->discoverRenderers(enabled); }
bool Player::setRenderer(const QString &id) { return m_backend->setRenderer(id); }

// ------------------------------------------------------------- hotkeys

bool Player::forwardKey(int qtKey, int qtModifiers, const QString &text)
{
    return m_backend->forwardKey(qtKey, qtModifiers, text);
}

bool Player::forwardWheel(int deltaX, int deltaY, int qtModifiers)
{
    return m_backend->forwardWheel(deltaX, deltaY, qtModifiers);
}

void Player::sendHotkey(int vlcKey)
{
    m_backend->sendHotkey(vlcKey);
}

bool Player::saveQueueAs(const QUrl &file)
{
    QString path = file.toLocalFile();
    if (!path.endsWith(QLatin1String(".m3u8"), Qt::CaseInsensitive) && !path.endsWith(QLatin1String(".m3u")))
        path += QStringLiteral(".m3u8");
    const bool ok = m_backend->exportQueue(path);
    emit notify(ok ? tr("Playlist saved") : tr("Could not save playlist"));
    return ok;
}

bool Player::savePlaylist(const QString &name, const QList<QUrl> &media, const QUrl &cover)
{
    QString safeName = name.trimmed();
    safeName.replace(QRegularExpression(QStringLiteral("[/\\\\\\x00-\\x1f]")), QStringLiteral("_"));
    safeName = safeName.replace(QRegularExpression(QStringLiteral("\\s+")), QStringLiteral(" "));
    if (safeName.isEmpty() || media.isEmpty()) {
        emit notify(tr("Add a name and at least one media file"));
        return false;
    }

    const QString directory = QDir(QStandardPaths::writableLocation(QStandardPaths::AppDataLocation))
                                  .filePath(QStringLiteral("Playlists"));
    if (!QDir().mkpath(directory)) {
        emit notify(tr("Could not create playlist folder"));
        return false;
    }
    const QString playlistPath = QDir(directory).filePath(safeName + QStringLiteral(".m3u8"));
    QSaveFile playlist(playlistPath);
    if (!playlist.open(QIODevice::WriteOnly | QIODevice::Text)) {
        emit notify(tr("Could not save playlist"));
        return false;
    }
    QByteArray contents("#EXTM3U\n");
    for (const QUrl &url : media) {
        if (!url.isValid() || url.isEmpty())
            continue;
        const QString title = QFileInfo(url.isLocalFile() ? url.toLocalFile() : url.toString()).fileName();
        contents += "#EXTINF:-1," + title.toUtf8().replace('\n', ' ').replace('\r', ' ') + '\n';
        contents += url.toString(QUrl::FullyEncoded).toUtf8() + '\n';
    }
    if (contents == QByteArray("#EXTM3U\n") || playlist.write(contents) != contents.size() || !playlist.commit()) {
        playlist.cancelWriting();
        emit notify(tr("Could not save playlist"));
        return false;
    }

    if (cover.isLocalFile()) {
        QFile image(cover.toLocalFile());
        if (image.open(QIODevice::ReadOnly)) {
            const QByteArray imageData = image.read(12 * 1024 * 1024 + 1);
            const QByteArray signature = imageData.left(8);
            QString extension;
            if (signature.startsWith(QByteArray::fromHex("89504e470d0a1a0a"))) extension = QStringLiteral("png");
            else if (signature.startsWith(QByteArray::fromHex("ffd8ff"))) extension = QStringLiteral("jpg");
            else if (signature.startsWith("GIF8")) extension = QStringLiteral("gif");
            else if (imageData.startsWith("RIFF") && imageData.mid(8, 4) == "WEBP") extension = QStringLiteral("webp");
            if (!extension.isEmpty() && imageData.size() <= 12 * 1024 * 1024) {
                const QString coverName = safeName + QStringLiteral(".cover.") + extension;
                QSaveFile coverFile(QDir(directory).filePath(coverName));
                if (coverFile.open(QIODevice::WriteOnly) && coverFile.write(imageData) == imageData.size() && coverFile.commit()) {
                    for (const QString &oldCover : QDir(directory).entryList({safeName + QStringLiteral(".cover.*")}, QDir::Files)) {
                        if (oldCover != coverName)
                            QFile::remove(QDir(directory).filePath(oldCover));
                    }
                }
            }
        }
    }
    emit notify(tr("Playlist saved"));
    return true;
}

bool Player::saveNetworkPlaylist(const QString &name, const QString &urlLines)
{
    const QList<QUrl> urls = parseNetworkUrls(urlLines);
    if (urls.isEmpty()) {
        emit notify(tr("Add at least one valid network URL"));
        return false;
    }
    return savePlaylist(name, urls);
}

QString Player::formatTime(qint64 ms) const
{
    if (ms < 0)
        ms = 0;
    const qint64 total = ms / 1000;
    return QStringLiteral("%1:%2:%3")
        .arg(total / 3600, 2, 10, QLatin1Char('0'))
        .arg((total / 60) % 60, 2, 10, QLatin1Char('0'))
        .arg(total % 60, 2, 10, QLatin1Char('0'));
}
