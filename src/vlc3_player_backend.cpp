#include "vlc3_player_backend.hpp"

#include <QFileInfo>
#include <QHash>

#include <vlc_configuration.h>

namespace {

QString takeString(char *raw)
{
    QString out = raw ? QString::fromUtf8(raw) : QString();
    free(raw);
    return out;
}

class Vlc3PlayerBackend final : public PlayerBackend
{
public:
    Vlc3PlayerBackend(intf_thread_t *intf, playlist_t *playlist) : m_intf(intf), m_playlist(playlist) {}

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
};

} // namespace

std::unique_ptr<PlayerBackend> makeVlc3PlayerBackend(intf_thread_t *intf, playlist_t *playlist)
{
    return std::make_unique<Vlc3PlayerBackend>(intf, playlist);
}
