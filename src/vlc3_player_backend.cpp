#include "vlc3_player_backend.hpp"

#include <QFileInfo>
#include <QHash>
#include <QUrl>
#include <utility>

#include <vlc_configuration.h>

namespace {

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

const char *const kPlaylistVars[] = {"volume", "mute", "fullscreen", "rate", "loop", "repeat", "random"};
const char *const kPlaylistChangeVars[] = {"playlist-item-append", "playlist-item-deleted", "item-change"};

template <typename Fn>
void post(QObject *context, Fn &&fn)
{
    QMetaObject::invokeMethod(context, std::forward<Fn>(fn), Qt::QueuedConnection);
}

class Vlc3PlayerBackend final : public PlayerBackend
{
public:
    Vlc3PlayerBackend(intf_thread_t *intf, playlist_t *playlist) : m_intf(intf), m_playlist(playlist)
    {
        var_AddCallback(m_playlist, "input-current", onInputCurrent, this);
        for (const char *name : kPlaylistVars)
            var_AddCallback(m_playlist, name, onPlaylistVar, this);
        for (const char *name : kPlaylistChangeVars)
            var_AddCallback(m_playlist, name, onPlaylistChange, this);
    }

    ~Vlc3PlayerBackend() override
    {
        for (const char *name : kPlaylistChangeVars)
            var_DelCallback(m_playlist, name, onPlaylistChange, this);
        for (const char *name : kPlaylistVars)
            var_DelCallback(m_playlist, name, onPlaylistVar, this);
        var_DelCallback(m_playlist, "input-current", onInputCurrent, this);
        clearCurrentInput();
    }

    void togglePause() override { playlist_TogglePause(m_playlist); }
    void play() override { playlist_Play(m_playlist); }
    void pause() override { playlist_Pause(m_playlist); }
    void stop() override { playlist_Stop(m_playlist); }
    void next() override { playlist_Next(m_playlist); }
    void previous() override { playlist_Prev(m_playlist); }
    void setRate(double rate) override { var_SetFloat(m_playlist, "rate", float(rate)); }
    void setVolume(double volume) override { playlist_VolumeSet(m_playlist, float(volume)); }
    void setMuted(bool muted) override { playlist_MuteSet(m_playlist, muted); }
    void toggleMute() override { playlist_MuteToggle(m_playlist); }

    void openUrls(const QList<QUrl> &urls, bool playNow) override
    {
        bool first = true;
        for (const QUrl &url : urls) {
            const QByteArray mrl = url.toString(QUrl::FullyEncoded).toUtf8();
            playlist_Add(m_playlist, mrl.constData(), playNow && first);
            first = false;
        }
    }

    void playItem(int id) override
    {
        playlist_Lock(m_playlist);
        playlist_item_t *item = playlist_ItemGetById(m_playlist, id);
        if (item)
            playlist_ViewPlay(m_playlist, nullptr, item);
        playlist_Unlock(m_playlist);
    }

    void removeItem(int id) override
    {
        playlist_Lock(m_playlist);
        playlist_item_t *item = playlist_ItemGetById(m_playlist, id);
        if (item)
            playlist_NodeDelete(m_playlist, item);
        playlist_Unlock(m_playlist);
    }

    void clearQueue() override { playlist_Clear(m_playlist, pl_Unlocked); }

    QueueSnapshot queueSnapshot() const override
    {
        QueueSnapshot snapshot;
        playlist_Lock(m_playlist);
        collectLeaves(m_playlist->p_playing, snapshot.entries);
        playlist_item_t *current = playlist_CurrentPlayingItem(m_playlist);
        snapshot.currentId = current ? current->i_id : -1;
        playlist_Unlock(m_playlist);
        return snapshot;
    }

    int currentQueueItemId() const override
    {
        playlist_Lock(m_playlist);
        playlist_item_t *current = playlist_CurrentPlayingItem(m_playlist);
        const int currentId = current ? current->i_id : -1;
        playlist_Unlock(m_playlist);
        return currentId;
    }

    BackendPlaylistState playlistState() const override
    {
        BackendPlaylistState state;
        float volume = playlist_VolumeGet(m_playlist);
        if (volume < 0.f)
            volume = var_GetFloat(m_playlist, "volume");
        state.rate = var_GetFloat(m_playlist, "rate");
        state.volume = volume;
        state.muted = playlist_MuteGet(m_playlist) > 0;
        state.loop = var_GetBool(m_playlist, "loop");
        state.repeatOne = var_GetBool(m_playlist, "repeat");
        state.random = var_GetBool(m_playlist, "random");
        return state;
    }

    ~Vlc3PlayerBackend() override { clearCurrentInput(); }

    bool syncCurrentInput() override
    {
        input_thread_t *input = playlist_CurrentInput(m_playlist);
        if (input == m_input) {
            if (input)
                vlc_object_release(input);
            return false;
        }
        clearCurrentInput();
        m_input = input;
        if (m_input)
            var_AddCallback(m_input, "intf-event", onInputEvent, this);
        emit inputChanged();
        return true;
    }

    void clearCurrentInput()
    {
        if (!m_input)
            return;
        var_DelCallback(m_input, "intf-event", onInputEvent, this);
        vlc_object_release(m_input);
        m_input = nullptr;
    }

    static int onInputCurrent(vlc_object_t *, const char *, vlc_value_t, vlc_value_t, void *data)
    {
        auto *self = static_cast<Vlc3PlayerBackend *>(data);
        post(self, [self] { self->syncCurrentInput(); });
        return VLC_SUCCESS;
    }

    static int onInputEvent(vlc_object_t *, const char *, vlc_value_t, vlc_value_t newval, void *data)
    {
        auto *self = static_cast<Vlc3PlayerBackend *>(data);
        BackendInputEvent event;
        switch (newval.i_int) {
        case INPUT_EVENT_POSITION:
        case INPUT_EVENT_LENGTH: event = BackendInputEvent::Position; break;
        case INPUT_EVENT_STATE:
        case INPUT_EVENT_RECORD:
        case INPUT_EVENT_RATE: event = BackendInputEvent::State; break;
        case INPUT_EVENT_ES:
        case INPUT_EVENT_VOUT: event = BackendInputEvent::Tracks; break;
        case INPUT_EVENT_ITEM_META:
        case INPUT_EVENT_TITLE: event = BackendInputEvent::Metadata; break;
        case INPUT_EVENT_AUDIO_DELAY:
        case INPUT_EVENT_SUBTITLE_DELAY: event = BackendInputEvent::Delays; break;
        case INPUT_EVENT_AOUT: event = BackendInputEvent::Volume; break;
        case INPUT_EVENT_DEAD: event = BackendInputEvent::Dead; break;
        default: return VLC_SUCCESS;
        }
        post(self, [self, event] { emit self->inputEvent(event); });
        return VLC_SUCCESS;
    }

    static int onPlaylistVar(vlc_object_t *, const char *name, vlc_value_t, vlc_value_t newval, void *data)
    {
        auto *self = static_cast<Vlc3PlayerBackend *>(data);
        const QByteArray variable(name);
        if (variable == "fullscreen") {
            const bool fullscreen = newval.b_bool;
            post(self, [self, fullscreen] { emit self->fullscreenChanged(fullscreen); });
        } else if (variable == "volume" || variable == "mute") {
            post(self, [self] { emit self->volumeStateChanged(); });
        } else if (variable == "rate") {
            post(self, [self] { emit self->rateStateChanged(); });
        } else {
            post(self, [self] { emit self->playbackModesChanged(); });
        }
        return VLC_SUCCESS;
    }

    static int onPlaylistChange(vlc_object_t *, const char *, vlc_value_t, vlc_value_t, void *data)
    {
        auto *self = static_cast<Vlc3PlayerBackend *>(data);
        post(self, [self] { emit self->queueChanged(); });
        return VLC_SUCCESS;
    }

    BackendInputState inputState() const override
    {
        BackendInputState state;
        if (!m_input)
            return state;
        state.hasInput = true;
        switch (var_GetInteger(m_input, "state")) {
        case INIT_S:
        case OPENING_S: state.state = 1; break;
        case PLAYING_S: state.state = 2; break;
        case PAUSE_S: state.state = 3; break;
        default: state.state = 0; break;
        }
        state.position = var_GetFloat(m_input, "position");
        state.timeMs = var_GetInteger(m_input, "time") / 1000;
        state.lengthMs = var_GetInteger(m_input, "length") / 1000;
        state.seekable = var_GetBool(m_input, "can-seek");
        state.recording = var_GetBool(m_input, "record");
        state.rate = var_GetFloat(m_input, "rate");
        state.audioDelayMs = int(var_GetInteger(m_input, "audio-delay") / 1000);
        state.subtitleDelayMs = int(var_GetInteger(m_input, "spu-delay") / 1000);

        input_item_t *item = input_GetItem(m_input);
        if (item) {
            state.title = takeString(input_item_GetTitleFbName(item));
            state.artist = takeString(input_item_GetArtist(item));
            state.artworkUrl = takeString(input_item_GetArtworkURL(item));
            state.mediaUrl = QUrl(takeString(input_item_GetURI(item)));
        }
        vout_thread_t *vout = input_GetVout(m_input);
        state.hasVideo = vout != nullptr;
        if (vout)
            vlc_object_release(vout);
        return state;
    }

    bool hasInput() const override { return m_input != nullptr; }
    void seek(double position) override
    {
        if (m_input)
            var_SetFloat(m_input, "position", float(qBound(0.0, position, 1.0)));
    }
    void seekBy(int ms) override
    {
        if (m_input)
            var_SetInteger(m_input, "time-offset", vlc_tick_t(ms) * 1000);
    }
    void frameStep() override
    {
        if (m_input)
            var_TriggerCallback(m_input, "frame-next");
    }
    void jumpTo(qint64 ms) override
    {
        if (m_input)
            var_SetInteger(m_input, "time", vlc_tick_t(ms) * 1000);
    }
    void toggleRecord() override
    {
        if (m_input)
            var_ToggleBool(m_input, "record");
    }

    QList<BackendTrack> tracks(const QString &category) const override
    {
        QList<BackendTrack> out;
        if (!m_input)
            return out;
        const QByteArray name = esVarName(category);
        vlc_value_t val, text;
        if (var_Change(m_input, name.constData(), VLC_VAR_GETCHOICES, &val, &text) != VLC_SUCCESS)
            return out;
        const int64_t current = var_GetInteger(m_input, name.constData());
        for (int i = 0; i < val.p_list->i_count; ++i) {
            BackendTrack track;
            track.id = val.p_list->p_values[i].i_int;
            const char *label = text.p_list->p_values[i].psz_string;
            track.name = label ? QString::fromUtf8(label) : QString::number(track.id);
            track.selected = track.id == current;
            out.append(track);
        }
        var_FreeList(&val, &text);
        return out;
    }
    void selectTrack(const QString &category, int id) override
    {
        if (m_input)
            var_SetInteger(m_input, esVarName(category).constData(), id);
    }
    bool addSubtitleFile(const QUrl &url, bool selectImmediately) override
    {
        if (!m_input)
            return false;
        const QByteArray mrl = url.toString(QUrl::FullyEncoded).toUtf8();
        return input_AddSlave(m_input, SLAVE_TYPE_SPU, mrl.constData(), true, selectImmediately, true) == VLC_SUCCESS;
    }
    QList<BackendAudioDevice> audioDevices() const override
    {
        QList<BackendAudioDevice> out;
        audio_output_t *aout = playlist_GetAout(m_playlist);
        if (!aout)
            return out;
        char **ids = nullptr, **names = nullptr;
        const int count = aout_DevicesList(aout, &ids, &names);
        const QString current = takeString(aout_DeviceGet(aout));
        for (int i = 0; i < count; ++i) {
            BackendAudioDevice device;
            device.id = QString::fromUtf8(ids[i]);
            device.name = QString::fromUtf8(names[i]);
            device.selected = device.id == current;
            out.append(device);
            free(ids[i]);
            free(names[i]);
        }
        free(ids);
        free(names);
        vlc_object_release(aout);
        return out;
    }
    void setAudioDevice(const QString &id) override
    {
        if (audio_output_t *aout = playlist_GetAout(m_playlist)) {
            aout_DeviceSet(aout, id.toUtf8().constData());
            vlc_object_release(aout);
        }
    }
    void setAudioDelay(int ms) override
    {
        if (m_input)
            var_SetInteger(m_input, "audio-delay", vlc_tick_t(ms) * 1000);
    }
    void setSubtitleDelay(int ms) override
    {
        if (m_input)
            var_SetInteger(m_input, "spu-delay", vlc_tick_t(ms) * 1000);
    }
    QList<BackendChapter> chapters() const override
    {
        QList<BackendChapter> out;
        if (!m_input)
            return out;
        vlc_value_t val, text;
        if (var_Change(m_input, "chapter", VLC_VAR_GETCHOICES, &val, &text) != VLC_SUCCESS)
            return out;
        const int64_t current = var_GetInteger(m_input, "chapter");
        for (int i = 0; i < val.p_list->i_count; ++i) {
            BackendChapter chapter;
            chapter.index = int(val.p_list->p_values[i].i_int);
            const char *label = text.p_list->p_values[i].psz_string;
            chapter.name = label ? QString::fromUtf8(label) : QStringLiteral("Chapter %1").arg(i + 1);
            chapter.selected = val.p_list->p_values[i].i_int == current;
            out.append(chapter);
        }
        var_FreeList(&val, &text);
        return out;
    }
    void selectChapter(int index) override
    {
        if (m_input)
            var_SetInteger(m_input, "chapter", index);
    }
    void setSubtitleScale(int percent) override
    {
        percent = qBound(10, percent, 500);
        if (var_Type(m_playlist, "sub-text-scale") == 0)
            var_Create(m_playlist, "sub-text-scale", VLC_VAR_INTEGER | VLC_VAR_DOINHERIT);
        var_SetInteger(m_playlist, "sub-text-scale", percent);
    }
    int subtitleScale() const override
    {
        const int value = int(var_InheritInteger(m_playlist, "sub-text-scale"));
        return value > 0 ? value : 100;
    }
    void setSubtitleMargin(int px) override
    {
        var_Create(m_playlist, "sub-margin", VLC_VAR_INTEGER | VLC_VAR_DOINHERIT);
        var_SetInteger(m_playlist, "sub-margin", px);
        if (vout_thread_t *vout = currentVout()) {
            var_SetInteger(vout, "sub-margin", px);
            vlc_object_release(vout);
        }
    }
    int subtitleMargin() const override
    {
        int value = 0;
        if (vout_thread_t *vout = currentVout()) {
            value = int(var_GetInteger(vout, "sub-margin"));
            vlc_object_release(vout);
        }
        return value;
    }
    void setAspectRatio(const QString &ratio) override
    {
        if (vout_thread_t *vout = currentVout()) {
            var_SetString(vout, "aspect-ratio", ratio.toUtf8().constData());
            vlc_object_release(vout);
        }
    }
    QString aspectRatio() const override
    {
        if (vout_thread_t *vout = currentVout()) {
            const QString value = takeString(var_GetString(vout, "aspect-ratio"));
            vlc_object_release(vout);
            return value;
        }
        return {};
    }
    void setTransform(const QString &type) override
    {
        vout_thread_t *vout = currentVout();
        if (!vout)
            return;
        var_Create(vout, "transform-type", VLC_VAR_STRING);
        var_SetString(vout, "transform-type", type.toUtf8().constData());
        var_SetString(vout, "video-filter", type.isEmpty() ? "" : "transform");
        vlc_object_release(vout);
    }
    void setDeinterlace(bool enabled) override
    {
        if (vout_thread_t *vout = currentVout()) {
            var_SetString(vout, "deinterlace-mode", "yadif");
            var_SetInteger(vout, "deinterlace", enabled ? 1 : 0);
            vlc_object_release(vout);
        }
    }
    void setEqualizerEnabled(const QString &preset, bool enabled) override
    {
        if (!enabled) {
            playlist_EnableAudioFilter(m_playlist, "equalizer", false);
            return;
        }
        const QByteArray name = preset.toUtf8();
        var_Create(m_playlist, "equalizer-preset", VLC_VAR_STRING | VLC_VAR_DOINHERIT);
        var_SetString(m_playlist, "equalizer-preset", name.constData());
        if (audio_output_t *aout = playlist_GetAout(m_playlist)) {
            var_Create(aout, "equalizer-preset", VLC_VAR_STRING | VLC_VAR_DOINHERIT);
            var_SetString(aout, "equalizer-preset", name.constData());
            vlc_object_release(aout);
        }
        playlist_EnableAudioFilter(m_playlist, "equalizer", true);
    }
    bool snapshot() override
    {
        if (vout_thread_t *vout = currentVout()) {
            var_TriggerCallback(vout, "video-snapshot");
            vlc_object_release(vout);
            return true;
        }
        return false;
    }

    bool exportQueue(const QString &path) override
    {
        return playlist_Export(m_playlist, path.toUtf8().constData(), true, "export-m3u8") == VLC_SUCCESS;
    }

    void setLoop(bool enabled) override { var_SetBool(m_playlist, "loop", enabled); }
    void setRepeatOne(bool enabled) override { var_SetBool(m_playlist, "repeat", enabled); }
    void setRandom(bool enabled) override { var_SetBool(m_playlist, "random", enabled); }
    void setFullscreen(bool enabled) override
    {
        if (var_GetBool(m_playlist, "fullscreen") != enabled)
            var_SetBool(m_playlist, "fullscreen", enabled);
    }

    QVariant config(const QString &name) const override
    {
        const QByteArray key = name.toUtf8();
        vlc_object_t *object = VLC_OBJECT(m_intf);
        switch (config_GetType(key.constData())) {
        case VLC_VAR_BOOL: return bool(config_GetInt(object, key.constData()));
        case VLC_VAR_INTEGER: return qint64(config_GetInt(object, key.constData()));
        case VLC_VAR_FLOAT: return double(config_GetFloat(object, key.constData()));
        case VLC_VAR_STRING: return takeString(config_GetPsz(object, key.constData()));
        default: return {};
        }
    }

    void setConfig(const QString &name, const QVariant &value) override
    {
        const QByteArray key = name.toUtf8();
        vlc_object_t *object = VLC_OBJECT(m_intf);
        switch (config_GetType(key.constData())) {
        case VLC_VAR_BOOL:
        case VLC_VAR_INTEGER: config_PutInt(object, key.constData(), value.toLongLong()); break;
        case VLC_VAR_FLOAT: config_PutFloat(object, key.constData(), value.toFloat()); break;
        case VLC_VAR_STRING: config_PutPsz(object, key.constData(), value.toString().toUtf8().constData()); break;
        default: return;
        }
        config_SaveConfigFile(m_intf);
    }

    bool forwardKey(int qtKey, int qtModifiers, const QString &text) override
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

private:
    vout_thread_t *currentVout() const { return m_input ? input_GetVout(m_input) : nullptr; }

    static void collectLeaves(playlist_item_t *node, QList<MediaQueueEntry> &out)
    {
        for (int i = 0; i < node->i_children; ++i) {
            playlist_item_t *child = node->pp_children[i];
            if (child->i_children >= 0) {
                collectLeaves(child, out);
                continue;
            }
            input_item_t *input = child->p_input;
            MediaQueueEntry entry;
            entry.id = child->i_id;
            entry.title = takeString(input_item_GetTitleFbName(input));
            const vlc_tick_t duration = input_item_GetDuration(input);
            entry.durationMs = duration > 0 ? duration / 1000 : 0;
            entry.uri = takeString(input_item_GetURI(input));
            out.append(entry);
        }
    }

    intf_thread_t *m_intf;
    playlist_t *m_playlist;
    input_thread_t *m_input = nullptr; // owns the reference returned by playlist_CurrentInput
};

} // namespace

std::unique_ptr<PlayerBackend> makeVlc3PlayerBackend(intf_thread_t *intf, playlist_t *playlist)
{
    return std::make_unique<Vlc3PlayerBackend>(intf, playlist);
}
