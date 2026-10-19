#include "player.hpp"
#include "subtitle_matcher.hpp"

#include <QCryptographicHash>
#include <QDir>
#include <QFileInfo>
#include <QPointer>

#include <vlc_configuration.h>

namespace {

constexpr int kRecentMax = 15;
constexpr qint64 kUsPerMs = 1000;

QString takeString(char *raw)
{
    QString out = raw ? QString::fromUtf8(raw) : QString();
    free(raw);
    return out;
}

QByteArray esVarName(const QString &category)
{
    if (category == QLatin1String("spu"))
        return "spu-es";
    if (category == QLatin1String("audio"))
        return "audio-es";
    return "video-es";
}

template <typename Fn>
void post(QObject *ctx, Fn &&fn)
{
    QMetaObject::invokeMethod(ctx, std::forward<Fn>(fn), Qt::QueuedConnection);
}

const char *const kPlaylistVars[] = {"volume", "mute", "fullscreen", "rate", "loop", "repeat", "random"};
const char *const kPlaylistChangeVars[] = {"playlist-item-append", "playlist-item-deleted", "item-change"};

} // namespace

// -------------------------------------------------------------------- Player

Player::Player(intf_thread_t *intf, QObject *parent)
    : QObject(parent), m_intf(intf), m_pl(pl_Get(intf)),
      m_settings(QStringLiteral("vlc-neo"), QStringLiteral("neo"))
{
    m_queueTimer.setSingleShot(true);
    m_queueTimer.setInterval(120);
    connect(&m_queueTimer, &QTimer::timeout, this, &Player::rebuildQueue);

    m_sleepTimer.setInterval(1000);
    connect(&m_sleepTimer, &QTimer::timeout, this, [this] {
        if (--m_sleepRemaining <= 0) {
            m_sleepTimer.stop();
            m_sleepRemaining = 0;
            playlist_Pause(m_pl);
            emit notify(tr("Sleep timer finished"));
        }
        emit sleepChanged();
    });

    var_AddCallback(m_pl, "input-current", onInputCurrent, this);
    for (const char *name : kPlaylistVars)
        var_AddCallback(m_pl, name, onPlaylistVar, this);
    for (const char *name : kPlaylistChangeVars)
        var_AddCallback(m_pl, name, onPlaylistChange, this);

    attachInput();
    refreshVolume();
    refreshModes();
    rebuildQueue();
}

Player::~Player()
{
    for (const char *name : kPlaylistChangeVars)
        var_DelCallback(m_pl, name, onPlaylistChange, this);
    for (const char *name : kPlaylistVars)
        var_DelCallback(m_pl, name, onPlaylistVar, this);
    var_DelCallback(m_pl, "input-current", onInputCurrent, this);
    detachInput();
}

// ------------------------------------------------------------ VLC callbacks

int Player::onInputCurrent(vlc_object_t *, const char *, vlc_value_t, vlc_value_t, void *data)
{
    auto *self = static_cast<Player *>(data);
    post(self, [self] { self->attachInput(); });
    return VLC_SUCCESS;
}

int Player::onInputEvent(vlc_object_t *, const char *, vlc_value_t, vlc_value_t newval, void *data)
{
    auto *self = static_cast<Player *>(data);
    switch (newval.i_int) {
    case INPUT_EVENT_POSITION:
    case INPUT_EVENT_LENGTH:
        if (!self->m_timePosted.exchange(true))
            post(self, [self] { self->refreshTime(); });
        break;
    case INPUT_EVENT_STATE:
    case INPUT_EVENT_RECORD:
    case INPUT_EVENT_RATE:
        post(self, [self] { self->refreshState(); });
        break;
    case INPUT_EVENT_ES:
    case INPUT_EVENT_VOUT:
        post(self, [self] { self->refreshTracks(); });
        break;
    case INPUT_EVENT_ITEM_META:
    case INPUT_EVENT_TITLE:
        post(self, [self] { self->refreshMeta(); });
        break;
    case INPUT_EVENT_AUDIO_DELAY:
    case INPUT_EVENT_SUBTITLE_DELAY:
        post(self, [self] { self->refreshDelays(); });
        break;
    case INPUT_EVENT_AOUT:
        post(self, [self] { self->refreshVolume(); });
        break;
    case INPUT_EVENT_DEAD:
        post(self, [self] { self->attachInput(); });
        break;
    default:
        break;
    }
    return VLC_SUCCESS;
}

int Player::onPlaylistVar(vlc_object_t *, const char *name, vlc_value_t, vlc_value_t newval, void *data)
{
    auto *self = static_cast<Player *>(data);
    const QByteArray var(name);
    if (var == "fullscreen") {
        const bool fs = newval.b_bool;
        post(self, [self, fs] { emit self->fullscreenRequested(fs); });
    } else if (var == "volume" || var == "mute") {
        post(self, [self] { self->refreshVolume(); });
    } else if (var == "rate") {
        post(self, [self] { self->refreshState(); });
    } else {
        post(self, [self] { self->refreshModes(); });
    }
    return VLC_SUCCESS;
}

int Player::onPlaylistChange(vlc_object_t *, const char *, vlc_value_t, vlc_value_t, void *data)
{
    auto *self = static_cast<Player *>(data);
    post(self, [self] {
        if (!self->m_queueTimer.isActive())
            self->m_queueTimer.start();
    });
    return VLC_SUCCESS;
}

// ------------------------------------------------------------ input binding

void Player::attachInput()
{
    input_thread_t *input = playlist_CurrentInput(m_pl);
    if (input && input == m_input) {
        vlc_object_release(input);
    } else {
        detachInput();
        m_input = input;
        if (m_input) {
            var_AddCallback(m_input, "intf-event", onInputEvent, this);
            m_presetPending = true;
            m_subsLinkedApplied = false;
            m_linkedSubtitleFile.clear();
            m_lastSavedResume = 0;
        }
        m_presetActive = false;
        emit presetChanged();
    }

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

    playlist_Lock(m_pl);
    playlist_item_t *current = playlist_CurrentPlayingItem(m_pl);
    const int currentId = current ? current->i_id : -1;
    playlist_Unlock(m_pl);
    m_queue.setCurrentId(currentId);
}

void Player::detachInput()
{
    if (!m_input)
        return;
    saveResumePoint();
    var_DelCallback(m_input, "intf-event", onInputEvent, this);
    vlc_object_release(m_input);
    m_input = nullptr;
}

void Player::refreshTime()
{
    m_timePosted = false;
    if (m_input) {
        m_position = var_GetFloat(m_input, "position");
        m_timeMs = var_GetInteger(m_input, "time") / kUsPerMs;
        m_lengthMs = var_GetInteger(m_input, "length") / kUsPerMs;
        if (qAbs(m_timeMs - m_lastSavedResume) > 5000)
            saveResumePoint();
        const bool seekable = var_GetBool(m_input, "can-seek");
        if (seekable != m_seekable) {
            m_seekable = seekable;
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
    int state = 0;
    bool recording = false;
    double rate = var_GetFloat(m_pl, "rate");
    if (m_input) {
        switch (var_GetInteger(m_input, "state")) {
        case INIT_S:
        case OPENING_S: state = 1; break;
        case PLAYING_S: state = 2; break;
        case PAUSE_S: state = 3; break;
        default: state = 0; break;
        }
        recording = var_GetBool(m_input, "record");
        rate = var_GetFloat(m_input, "rate");
    }
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
    QString title, artist, artwork, folderPath;
    QUrl url;
    if (m_input) {
        input_item_t *item = input_GetItem(m_input);
        title = takeString(input_item_GetTitleFbName(item));
        artist = takeString(input_item_GetArtist(item));
        artwork = takeString(input_item_GetArtworkURL(item));
        url = QUrl(takeString(input_item_GetURI(item)));
        if (url.isLocalFile())
            folderPath = QFileInfo(url.toLocalFile()).absolutePath();
    }
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
    bool hasVideo = false;
    if (m_input) {
        vout_thread_t *vout = input_GetVout(m_input);
        if (vout) {
            hasVideo = true;
            vlc_object_release(vout);
        }
    }
    m_hasVideo = hasVideo;
    emit tracksChanged();
    emit chaptersChanged();
    applyLinkedSubtitles();
    applyPendingPreset();
}

void Player::refreshDelays()
{
    int audio = 0, spu = 0;
    if (m_input) {
        audio = int(var_GetInteger(m_input, "audio-delay") / kUsPerMs);
        spu = int(var_GetInteger(m_input, "spu-delay") / kUsPerMs);
    }
    if (audio != m_audioDelayMs || spu != m_subtitleDelayMs) {
        m_audioDelayMs = audio;
        m_subtitleDelayMs = spu;
        emit delaysChanged();
    }
}

void Player::refreshVolume()
{
    float vol = playlist_VolumeGet(m_pl);
    if (vol < 0.f)
        vol = var_GetFloat(m_pl, "volume");
    m_volume = vol;
    m_muted = playlist_MuteGet(m_pl) > 0;
    emit volumeChanged();
}

void Player::refreshModes()
{
    m_loop = var_GetBool(m_pl, "loop");
    m_repeatOne = var_GetBool(m_pl, "repeat");
    m_random = var_GetBool(m_pl, "random");
    emit playbackModeChanged();
}

static void collectLeaves(playlist_item_t *node, QList<QueueModel::Entry> &out)
{
    for (int i = 0; i < node->i_children; ++i) {
        playlist_item_t *child = node->pp_children[i];
        if (child->i_children >= 0) {
            collectLeaves(child, out);
            continue;
        }
        input_item_t *in = child->p_input;
        QueueModel::Entry e;
        e.id = child->i_id;
        e.title = takeString(input_item_GetTitleFbName(in));
        const vlc_tick_t d = input_item_GetDuration(in);
        e.durationMs = d > 0 ? d / kUsPerMs : 0;
        e.uri = takeString(input_item_GetURI(in));
        out.append(e);
    }
}

void Player::rebuildQueue()
{
    QList<QueueModel::Entry> entries;
    playlist_Lock(m_pl);
    collectLeaves(m_pl->p_playing, entries);
    playlist_item_t *current = playlist_CurrentPlayingItem(m_pl);
    const int currentId = current ? current->i_id : -1;
    playlist_Unlock(m_pl);
    m_queue.reset(std::move(entries), currentId);
}

// ---------------------------------------------------------------- transport

void Player::togglePause()
{
    if (!m_input) {
        playlist_Play(m_pl);
        return;
    }
    playlist_TogglePause(m_pl);
}

void Player::play() { playlist_Play(m_pl); }
void Player::stop() { playlist_Stop(m_pl); }
void Player::next() { playlist_Next(m_pl); }
void Player::previous() { playlist_Prev(m_pl); }

void Player::seek(double position)
{
    if (m_input)
        var_SetFloat(m_input, "position", float(qBound(0.0, position, 1.0)));
}

void Player::seekBy(int ms)
{
    if (m_input)
        var_SetInteger(m_input, "time-offset", vlc_tick_t(ms) * kUsPerMs);
}

void Player::setRate(double rate)
{
    var_SetFloat(m_pl, "rate", float(qBound(0.25, rate, 4.0)));
}

void Player::setVolume(double volume)
{
    playlist_VolumeSet(m_pl, float(qBound(0.0, volume, 1.25)));
    if (m_muted && volume > 0.0)
        playlist_MuteSet(m_pl, false);
}

void Player::toggleMute() { playlist_MuteToggle(m_pl); }

void Player::frameStep()
{
    if (m_input)
        var_TriggerCallback(m_input, "frame-next");
}

// -------------------------------------------------------------------- media

void Player::openUrls(const QList<QUrl> &urls, bool playNow)
{
    bool first = true;
    for (const QUrl &url : urls) {
        const QByteArray mrl = url.toString(QUrl::FullyEncoded).toUtf8();
        playlist_Add(m_pl, mrl.constData(), playNow && first);
        first = false;
    }
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
    playlist_Lock(m_pl);
    playlist_item_t *item = playlist_ItemGetById(m_pl, id);
    if (item)
        playlist_ViewPlay(m_pl, nullptr, item);
    playlist_Unlock(m_pl);
}

void Player::removeItem(int id)
{
    playlist_Lock(m_pl);
    playlist_item_t *item = playlist_ItemGetById(m_pl, id);
    if (item)
        playlist_NodeDelete(m_pl, item);
    playlist_Unlock(m_pl);
}

void Player::clearQueue() { playlist_Clear(m_pl, pl_Unlocked); }

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
    if (!m_input)
        return out;
    const QByteArray name = esVarName(category);
    vlc_value_t val, text;
    if (var_Change(m_input, name.constData(), VLC_VAR_GETCHOICES, &val, &text) != VLC_SUCCESS)
        return out;
    const int64_t current = var_GetInteger(m_input, name.constData());
    for (int i = 0; i < val.p_list->i_count; ++i) {
        const int64_t id = val.p_list->p_values[i].i_int;
        const char *label = text.p_list->p_values[i].psz_string;
        QVariantMap track;
        track.insert(QStringLiteral("id"), qint64(id));
        track.insert(QStringLiteral("name"), label ? QString::fromUtf8(label) : QString::number(id));
        track.insert(QStringLiteral("selected"), id == current);
        out.append(track);
    }
    var_FreeList(&val, &text);
    return out;
}

void Player::selectTrack(const QString &category, int id)
{
    if (m_input)
        var_SetInteger(m_input, esVarName(category).constData(), id);
}

bool Player::addSubtitleFile(const QUrl &url)
{
    if (!m_input)
        return false;
    const QByteArray mrl = url.toString(QUrl::FullyEncoded).toUtf8();
    const bool ok = input_AddSlave(m_input, SLAVE_TYPE_SPU, mrl.constData(), true, true, true) == VLC_SUCCESS;
    emit notify(ok ? tr("Subtitle added") : tr("Could not load subtitle"));
    return ok;
}

QVariantList Player::audioDevices() const
{
    QVariantList out;
    audio_output_t *aout = playlist_GetAout(m_pl);
    if (!aout)
        return out;
    char **ids = nullptr, **names = nullptr;
    const int count = aout_DevicesList(aout, &ids, &names);
    const QString current = takeString(aout_DeviceGet(aout));
    for (int i = 0; i < count; ++i) {
        QVariantMap dev;
        const QString id = QString::fromUtf8(ids[i]);
        dev.insert(QStringLiteral("id"), id);
        dev.insert(QStringLiteral("name"), QString::fromUtf8(names[i]));
        dev.insert(QStringLiteral("selected"), id == current);
        out.append(dev);
        free(ids[i]);
        free(names[i]);
    }
    free(ids);
    free(names);
    vlc_object_release(aout);
    return out;
}

void Player::setAudioDevice(const QString &id)
{
    audio_output_t *aout = playlist_GetAout(m_pl);
    if (!aout)
        return;
    aout_DeviceSet(aout, id.toUtf8().constData());
    vlc_object_release(aout);
}

// --------------------------------------------------------------- live tuning

vout_thread_t *Player::currentVout() const
{
    return m_input ? input_GetVout(m_input) : nullptr;
}

void Player::setAudioDelay(int ms)
{
    if (m_input)
        var_SetInteger(m_input, "audio-delay", vlc_tick_t(ms) * kUsPerMs);
}

void Player::setSubtitleDelay(int ms)
{
    if (m_input)
        var_SetInteger(m_input, "spu-delay", vlc_tick_t(ms) * kUsPerMs);
}

void Player::setSubtitleScale(int percent)
{
    // freetype re-reads "sub-text-scale" by inheritance on every render (VLC 3),
    // so a playlist-level variable applies live to the current and next videos.
    percent = qBound(10, percent, 500);
    if (var_Type(m_pl, "sub-text-scale") == 0)
        var_Create(m_pl, "sub-text-scale", VLC_VAR_INTEGER | VLC_VAR_DOINHERIT);
    var_SetInteger(m_pl, "sub-text-scale", percent);
}

int Player::subtitleScale() const
{
    const int value = int(var_InheritInteger(m_pl, "sub-text-scale"));
    return value > 0 ? value : 100;
}

void Player::setSubtitleMargin(int px)
{
    var_Create(m_pl, "sub-margin", VLC_VAR_INTEGER | VLC_VAR_DOINHERIT);
    var_SetInteger(m_pl, "sub-margin", px);
    if (vout_thread_t *vout = currentVout()) {
        var_SetInteger(vout, "sub-margin", px);
        vlc_object_release(vout);
    }
}

int Player::subtitleMargin() const
{
    int value = 0;
    if (vout_thread_t *vout = currentVout()) {
        value = int(var_GetInteger(vout, "sub-margin"));
        vlc_object_release(vout);
    }
    return value;
}

void Player::setAspectRatio(const QString &ratio)
{
    if (vout_thread_t *vout = currentVout()) {
        var_SetString(vout, "aspect-ratio", ratio.toUtf8().constData());
        vlc_object_release(vout);
    }
}

QString Player::aspectRatio() const
{
    QString value;
    if (vout_thread_t *vout = currentVout()) {
        value = takeString(var_GetString(vout, "aspect-ratio"));
        vlc_object_release(vout);
    }
    return value;
}

void Player::setTransform(const QString &type)
{
    vout_thread_t *vout = currentVout();
    if (!vout)
        return;
    var_Create(vout, "transform-type", VLC_VAR_STRING);
    var_SetString(vout, "transform-type", type.toUtf8().constData());
    var_SetString(vout, "video-filter", type.isEmpty() ? "" : "transform");
    vlc_object_release(vout);
}

void Player::setDeinterlace(bool on)
{
    if (vout_thread_t *vout = currentVout()) {
        var_SetString(vout, "deinterlace-mode", "yadif");
        var_SetInteger(vout, "deinterlace", on ? 1 : 0);
        vlc_object_release(vout);
    }
}

void Player::setEqualizerPreset(const QString &preset)
{
    m_settings.setValue(QStringLiteral("equalizer"), preset);
    if (preset.isEmpty() || preset == QLatin1String("off")) {
        playlist_EnableAudioFilter(m_pl, "equalizer", false);
        return;
    }
    const QByteArray name = preset.toUtf8();
    var_Create(m_pl, "equalizer-preset", VLC_VAR_STRING | VLC_VAR_DOINHERIT);
    var_SetString(m_pl, "equalizer-preset", name.constData());
    if (audio_output_t *aout = playlist_GetAout(m_pl)) {
        var_Create(aout, "equalizer-preset", VLC_VAR_STRING | VLC_VAR_DOINHERIT);
        var_SetString(aout, "equalizer-preset", name.constData());
        vlc_object_release(aout);
    }
    playlist_EnableAudioFilter(m_pl, "equalizer", true);
}

QString Player::equalizerPreset() const
{
    return m_settings.value(QStringLiteral("equalizer"), QStringLiteral("off")).toString();
}

void Player::setLoop(bool on) { var_SetBool(m_pl, "loop", on); }
void Player::setRepeatOne(bool on) { var_SetBool(m_pl, "repeat", on); }
void Player::setRandom(bool on) { var_SetBool(m_pl, "random", on); }

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
    if (vout_thread_t *vout = currentVout()) {
        var_TriggerCallback(vout, "video-snapshot");
        vlc_object_release(vout);
        emit notify(tr("Snapshot saved"));
    }
}

void Player::toggleRecord()
{
    if (m_input)
        var_ToggleBool(m_input, "record");
}

void Player::sendHotkey(int vlcKey)
{
    var_SetInteger(m_intf->obj.libvlc, "key-pressed", vlcKey);
}

void Player::setFullscreenState(bool fs)
{
    if (var_GetBool(m_pl, "fullscreen") != fs)
        var_SetBool(m_pl, "fullscreen", fs);
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
    if (!m_presetPending || !m_input || m_state != 2)
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
    if (m_input)
        var_SetInteger(m_input, "time", vlc_tick_t(ms) * kUsPerMs);
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
    if (key.isEmpty() || !m_input)
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
    if (!m_input)
        return out;
    vlc_value_t val, text;
    if (var_Change(m_input, "chapter", VLC_VAR_GETCHOICES, &val, &text) != VLC_SUCCESS)
        return out;
    const int64_t current = var_GetInteger(m_input, "chapter");
    for (int i = 0; i < val.p_list->i_count; ++i) {
        const char *label = text.p_list->p_values[i].psz_string;
        out.append(QVariantMap{
            {QStringLiteral("index"), int(val.p_list->p_values[i].i_int)},
            {QStringLiteral("name"), label ? QString::fromUtf8(label) : tr("Chapter %1").arg(i + 1)},
            {QStringLiteral("selected"), val.p_list->p_values[i].i_int == current}});
    }
    var_FreeList(&val, &text);
    return out;
}

void Player::selectChapter(int index)
{
    if (m_input)
        var_SetInteger(m_input, "chapter", index);
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
    for (const QueueModel::Entry &e : m_queue.entries()) {
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
    if (m_subsLinkedApplied || !m_input || !m_mediaUrl.isLocalFile())
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
    const QByteArray mrl = QUrl::fromLocalFile(QDir(dir).filePath(best)).toString(QUrl::FullyEncoded).toUtf8();
    if (input_AddSlave(m_input, SLAVE_TYPE_SPU, mrl.constData(), true, false, true) == VLC_SUCCESS)
        m_linkedSubtitleFile = best;
}

// -------------------------------------------------------- core config

QVariant Player::config(const QString &name) const
{
    const QByteArray key = name.toUtf8();
    vlc_object_t *obj = VLC_OBJECT(m_intf);
    switch (config_GetType(key.constData())) {
    case VLC_VAR_BOOL: return bool(config_GetInt(obj, key.constData()));
    case VLC_VAR_INTEGER: return qint64(config_GetInt(obj, key.constData()));
    case VLC_VAR_FLOAT: return double(config_GetFloat(obj, key.constData()));
    case VLC_VAR_STRING: return takeString(config_GetPsz(obj, key.constData()));
    default: return {};
    }
}

void Player::setConfig(const QString &name, const QVariant &value)
{
    const QByteArray key = name.toUtf8();
    vlc_object_t *obj = VLC_OBJECT(m_intf);
    switch (config_GetType(key.constData())) {
    case VLC_VAR_BOOL:
    case VLC_VAR_INTEGER: config_PutInt(obj, key.constData(), value.toLongLong()); break;
    case VLC_VAR_FLOAT: config_PutFloat(obj, key.constData(), value.toFloat()); break;
    case VLC_VAR_STRING: config_PutPsz(obj, key.constData(), value.toString().toUtf8().constData()); break;
    default: return;
    }
    config_SaveConfigFile(m_intf);
}

// ------------------------------------------------------------- hotkeys

bool Player::forwardKey(int qtKey, int qtModifiers, const QString &text)
{
    static const QHash<int, uint32_t> special = {
        {Qt::Key_Left, KEY_LEFT}, {Qt::Key_Right, KEY_RIGHT}, {Qt::Key_Up, KEY_UP}, {Qt::Key_Down, KEY_DOWN},
        {Qt::Key_Space, ' '}, {Qt::Key_Escape, KEY_ESC}, {Qt::Key_Return, KEY_ENTER}, {Qt::Key_Enter, KEY_ENTER},
        {Qt::Key_Tab, KEY_TAB}, {Qt::Key_Backspace, KEY_BACKSPACE}, {Qt::Key_Home, KEY_HOME}, {Qt::Key_End, KEY_END},
        {Qt::Key_PageUp, KEY_PAGEUP}, {Qt::Key_PageDown, KEY_PAGEDOWN}, {Qt::Key_Insert, KEY_INSERT},
        {Qt::Key_Delete, KEY_DELETE}, {Qt::Key_Menu, KEY_MENU}, {Qt::Key_Pause, KEY_PAUSE},
        {Qt::Key_F1, KEY_F1}, {Qt::Key_F2, KEY_F2}, {Qt::Key_F3, KEY_F3}, {Qt::Key_F4, KEY_F4},
        {Qt::Key_F5, KEY_F5}, {Qt::Key_F6, KEY_F6}, {Qt::Key_F7, KEY_F7}, {Qt::Key_F8, KEY_F8},
        {Qt::Key_F9, KEY_F9}, {Qt::Key_F10, KEY_F10}, {Qt::Key_F11, KEY_F11}, {Qt::Key_F12, KEY_F12},
        {Qt::Key_VolumeUp, KEY_VOLUME_UP}, {Qt::Key_VolumeDown, KEY_VOLUME_DOWN},
        {Qt::Key_VolumeMute, KEY_VOLUME_MUTE}, {Qt::Key_MediaPlay, KEY_MEDIA_PLAY_PAUSE},
        {Qt::Key_MediaTogglePlayPause, KEY_MEDIA_PLAY_PAUSE}, {Qt::Key_MediaNext, KEY_MEDIA_NEXT_TRACK},
        {Qt::Key_MediaPrevious, KEY_MEDIA_PREV_TRACK}, {Qt::Key_MediaStop, KEY_MEDIA_STOP}};

    uint32_t code = special.value(qtKey, 0);
    if (!code) {
        if (qtKey >= Qt::Key_A && qtKey <= Qt::Key_Z)
            code = uint32_t('a' + (qtKey - Qt::Key_A));
        else if (!text.isEmpty() && text.at(0).isPrint())
            code = text.toLower().toUcs4().value(0);
        else if (qtKey > 0 && qtKey < 0x80)
            code = uint32_t(qtKey);
    }
    if (!code)
        return false;
    if (qtModifiers & Qt::ShiftModifier && qtKey >= Qt::Key_A && qtKey <= Qt::Key_Z)
        code |= KEY_MODIFIER_SHIFT;
    if (qtModifiers & Qt::ControlModifier)
        code |= KEY_MODIFIER_CTRL;
    if (qtModifiers & Qt::AltModifier)
        code |= KEY_MODIFIER_ALT;
    if (qtModifiers & Qt::MetaModifier)
        code |= KEY_MODIFIER_META;
    var_SetInteger(m_intf->obj.libvlc, "key-pressed", code);
    return true;
}

bool Player::saveQueueAs(const QUrl &file)
{
    QString path = file.toLocalFile();
    if (!path.endsWith(QLatin1String(".m3u8"), Qt::CaseInsensitive) && !path.endsWith(QLatin1String(".m3u")))
        path += QStringLiteral(".m3u8");
    const bool ok = playlist_Export(m_pl, path.toUtf8().constData(), true, "export-m3u8") == VLC_SUCCESS;
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
