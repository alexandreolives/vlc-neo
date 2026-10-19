#include "player.hpp"
#include "subtitle_matcher.hpp"

#include <QCryptographicHash>
#include <QDir>
#include <QFileInfo>

#include <utility>

namespace {

constexpr int kRecentMax = 15;

} // namespace

// -------------------------------------------------------------------- Player

Player::Player(std::unique_ptr<PlayerBackend> backend, QObject *parent)
    : QObject(parent), m_backend(std::move(backend)),
      m_settings(QStringLiteral("vlc-neo"), QStringLiteral("neo"))
{
    Q_ASSERT(m_backend);
    m_queueTimer.setSingleShot(true);
    m_queueTimer.setInterval(120);
    connect(&m_queueTimer, &QTimer::timeout, this, &Player::rebuildQueue);

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

    if (!m_backend->syncCurrentInput())
        refreshCurrentInput();
    refreshVolume();
    refreshModes();
    rebuildQueue();
}

Player::~Player()
{
    saveResumePoint();
}

void Player::onBackendInputChanged()
{
    saveResumePoint();
    m_presetPending = true;
    m_subsLinkedApplied = false;
    m_linkedSubtitleFile.clear();
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
        if (point > 0)
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
    if (newMedia && !url.isEmpty())
        rememberRecent(url.toString());
    emit mediaChanged();
}

void Player::refreshTracks()
{
    m_hasVideo = m_backend->inputState().hasVideo;
    emit tracksChanged();
    emit chaptersChanged();
    applyLinkedSubtitles();
    applyPendingPreset();
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
    m_backend->seek(qBound(0.0, position, 1.0));
}

void Player::seekBy(int ms)
{
    m_backend->seekBy(ms);
}

void Player::setRate(double rate)
{
    m_backend->setRate(qBound(0.25, rate, 4.0));
}

void Player::setVolume(double volume)
{
    m_backend->setVolume(qBound(0.0, volume, 1.25));
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
    m_backend->openUrls(urls, playNow);
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
    QStringList list = m_settings.value(QStringLiteral("recent")).toStringList();
    list.removeAll(mrl);
    list.prepend(mrl);
    while (list.size() > kRecentMax)
        list.removeLast();
    m_settings.setValue(QStringLiteral("recent"), list);
}

QStringList Player::recentMedia() const
{
    return m_settings.value(QStringLiteral("recent")).toStringList();
}

void Player::clearRecentMedia() { m_settings.remove(QStringLiteral("recent")); }

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
}

bool Player::addSubtitleFile(const QUrl &url)
{
    const bool ok = m_backend->addSubtitleFile(url, true);
    emit notify(ok ? tr("Subtitle added") : tr("Could not load subtitle"));
    return ok;
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

void Player::setTransform(const QString &type) { m_backend->setTransform(type); }

void Player::setDeinterlace(bool on) { m_backend->setDeinterlace(on); }

void Player::setEqualizerPreset(const QString &preset)
{
    m_settings.setValue(QStringLiteral("equalizer"), preset);
    m_backend->setEqualizerEnabled(preset, !preset.isEmpty() && preset != QLatin1String("off"));
}

QString Player::equalizerPreset() const
{
    return m_settings.value(QStringLiteral("equalizer"), QStringLiteral("off")).toString();
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

QString Player::presetKey() const
{
    if (m_folderPath.isEmpty())
        return {};
    const QByteArray hash = QCryptographicHash::hash(m_folderPath.toUtf8(), QCryptographicHash::Md5).toHex();
    return QStringLiteral("presets/") + QString::fromLatin1(hash);
}

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
    const QString key = presetKey();
    if (key.isEmpty()) {
        emit notify(tr("Presets work with local folders only"));
        return;
    }
    refreshDelays(); // read live values, events may still be queued
    m_settings.beginGroup(key);
    m_settings.setValue(QStringLiteral("folder"), m_folderPath);
    m_settings.setValue(QStringLiteral("spuDelay"), m_subtitleDelayMs);
    m_settings.setValue(QStringLiteral("audioDelay"), m_audioDelayMs);
    m_settings.setValue(QStringLiteral("subScale"), subtitleScale());
    m_settings.setValue(QStringLiteral("spuTrack"), selectedTrackName(tracks(QStringLiteral("spu"))));
    m_settings.setValue(QStringLiteral("audioTrack"), selectedTrackName(tracks(QStringLiteral("audio"))));
    m_settings.endGroup();
    m_presetActive = true;
    emit presetChanged();
    emit notify(tr("Preset saved for \"%1\"").arg(m_folderName));
}

void Player::forgetPresetForFolder()
{
    const QString key = presetKey();
    if (key.isEmpty())
        return;
    m_settings.remove(key);
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

    const QString key = presetKey();
    if (key.isEmpty() || !m_settings.contains(key + QStringLiteral("/folder")))
        return;

    m_settings.beginGroup(key);
    const int spuDelay = m_settings.value(QStringLiteral("spuDelay"), 0).toInt();
    const int audioDelay = m_settings.value(QStringLiteral("audioDelay"), 0).toInt();
    const int subScale = m_settings.value(QStringLiteral("subScale"), 100).toInt();
    const QString spuTrack = m_settings.value(QStringLiteral("spuTrack")).toString();
    const QString audioTrack = m_settings.value(QStringLiteral("audioTrack")).toString();
    m_settings.endGroup();

    setSubtitleDelay(spuDelay);
    setAudioDelay(audioDelay);
    setSubtitleScale(subScale);
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
    pick(QStringLiteral("spu"), spuTrack);
    pick(QStringLiteral("audio"), audioTrack);
    m_presetActive = true;
    emit presetChanged();
    emit notify(tr("Preset applied: %1").arg(m_folderName));
}

// ------------------------------------------------- resume / bookmarks / chapters

QString Player::mediaKey(const QString &group) const
{
    if (m_mediaUrl.isEmpty())
        return {};
    const QByteArray hash = QCryptographicHash::hash(m_mediaUrl.toString().toUtf8(), QCryptographicHash::Md5).toHex();
    return group + QLatin1Char('/') + QString::fromLatin1(hash);
}

void Player::saveResumePoint()
{
    const QString key = mediaKey(QStringLiteral("resume"));
    if (key.isEmpty() || m_lengthMs <= 0)
        return;
    m_lastSavedResume = m_timeMs;
    // Nothing to resume at the very start, or at the end (credits = finished).
    constexpr qint64 kMinMs = 10000;
    constexpr qint64 kMaxTailMs = 20000;
    const qint64 tail = qMin(kMaxTailMs, m_lengthMs / 10);
    if (m_timeMs < kMinMs || m_timeMs > m_lengthMs - tail)
        m_settings.remove(key);
    else
        m_settings.setValue(key, m_timeMs);
}

qint64 Player::resumePoint() const
{
    const QString key = mediaKey(QStringLiteral("resume"));
    return key.isEmpty() ? 0 : m_settings.value(key, 0).toLongLong();
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
    const QString key = mediaKey(QStringLiteral("bookmarks"));
    if (key.isEmpty())
        return out;
    QList<qint64> marks;
    for (const QVariant &v : m_settings.value(key).toList())
        marks.append(v.toLongLong());
    std::sort(marks.begin(), marks.end());
    for (qint64 ms : marks)
        out.append(QVariantMap{{QStringLiteral("time"), ms}, {QStringLiteral("label"), formatTime(ms)}});
    return out;
}

void Player::addBookmark()
{
    const QString key = mediaKey(QStringLiteral("bookmarks"));
    if (key.isEmpty() || !m_backend->hasInput())
        return;
    QVariantList list = m_settings.value(key).toList();
    list.append(m_timeMs);
    m_settings.setValue(key, list);
    emit bookmarksChanged();
    emit notify(tr("Bookmark added at %1").arg(formatTime(m_timeMs)));
}

void Player::removeBookmark(qint64 ms)
{
    const QString key = mediaKey(QStringLiteral("bookmarks"));
    if (key.isEmpty())
        return;
    QVariantList list = m_settings.value(key).toList();
    for (int i = list.size() - 1; i >= 0; --i)
        if (list.at(i).toLongLong() == ms)
            list.removeAt(i);
    m_settings.setValue(key, list);
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

} // namespace

int Player::linkSubtitleFolder(const QUrl &folder)
{
    if (m_folderPath.isEmpty()) {
        emit notify(tr("Open a local file first"));
        return 0;
    }
    const QString dir = folder.toLocalFile();
    m_settings.setValue(SubtitleMatcher::folderSettingsKey(m_folderPath), dir);
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

void Player::unlinkSubtitleFolder()
{
    if (!m_folderPath.isEmpty())
        m_settings.remove(SubtitleMatcher::folderSettingsKey(m_folderPath));
    emit notify(tr("Subtitle folder unlinked"));
}

QString Player::linkedSubtitleFolder() const
{
    return m_folderPath.isEmpty() ? QString() : m_settings.value(SubtitleMatcher::folderSettingsKey(m_folderPath)).toString();
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
    if (m_backend->addSubtitleFile(subtitleUrl, false))
        m_linkedSubtitleFile = best;
}

// -------------------------------------------------------- core config

QVariant Player::config(const QString &name) const
{
    return m_backend->config(name);
}

void Player::setConfig(const QString &name, const QVariant &value)
{
    m_backend->setConfig(name, value);
}

// ------------------------------------------------------------- hotkeys

bool Player::forwardKey(int qtKey, int qtModifiers, const QString &text)
{
    return m_backend->forwardKey(qtKey, qtModifiers, text);
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
