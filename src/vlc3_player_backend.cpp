#include "vlc3_player_backend.hpp"
#include "vlc_addon_uuid.hpp"
#include "local_media_http_server.hpp"

#include <QFileInfo>
#include <QDebug>
#include <QHash>
#include <QSharedPointer>
#include <QStringList>
#include <QMutex>
#include <QMutexLocker>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QHostAddress>
#include <QMimeDatabase>
#include <QXmlStreamReader>
#include <QXmlStreamWriter>
#include <QUdpSocket>
#include <QMap>
#include <QHash>
#include <QTimer>
#include <QUrl>
#include <QUrlQuery>
#include <QSet>
#include <algorithm>
#include <cstdlib>
#include <functional>
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

struct DlnaRenderer {
    QString id;
    QString udn;
    QString name;
    QUrl avTransport;
    QUrl renderingControl;
};

struct DialDevice {
    QString id;
    QString name;
};

QHash<QString, QString> soapFields(const QByteArray &xml)
{
    QHash<QString, QString> fields;
    QXmlStreamReader reader(xml);
    while (!reader.atEnd()) {
        reader.readNext();
        if (!reader.isStartElement())
            continue;
        const QString name = reader.name().toString();
        if (name == QLatin1String("CurrentTransportState")
            || name == QLatin1String("CurrentTransportStatus")
            || name == QLatin1String("RelTime") || name == QLatin1String("AbsTime")
            || name == QLatin1String("TrackDuration") || name == QLatin1String("TrackURI")
            || name == QLatin1String("CurrentTrackURI") || name == QLatin1String("CurrentURI"))
            fields.insert(name, reader.readElementText());
    }
    return fields;
}

bool soapResponseSucceeded(const QByteArray &xml)
{
    if (xml.trimmed().isEmpty())
        return false;
    QXmlStreamReader reader(xml);
    bool hasEnvelope = false;
    bool hasFault = false;
    while (!reader.atEnd()) {
        reader.readNext();
        if (!reader.isStartElement())
            continue;
        const QString name = reader.name().toString();
        hasEnvelope |= name == QLatin1String("Envelope");
        hasFault |= name == QLatin1String("Fault")
            || name == QLatin1String("UPnPError")
            || name == QLatin1String("errorCode");
    }
    return !reader.hasError() && hasEnvelope && !hasFault;
}

qint64 upnpTimeMs(const QString &value)
{
    const QStringList parts = value.split(QLatin1Char(':'));
    if (parts.size() != 3)
        return 0;
    bool okH = false, okM = false, okS = false;
    const qint64 h = parts[0].toLongLong(&okH);
    const qint64 m = parts[1].toLongLong(&okM);
    const double s = parts[2].toDouble(&okS);
    if (!okH || !okM || !okS || h < 0 || m < 0 || s < 0)
        return 0;
    return (h * 3600 + m * 60) * 1000 + qint64(s * 1000.0);
}

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
        syncHttpProxyEnvironment();
        m_network = new QNetworkAccessManager(this);
        m_localMediaServer = new LocalMediaHttpServer(this);
        m_ssdpSocket = new QUdpSocket(this);
        connect(m_ssdpSocket, &QUdpSocket::readyRead, this, [this] { readSsdpResponses(); });
        m_ssdpTimer = new QTimer(this);
        m_ssdpTimer->setInterval(4000);
        connect(m_ssdpTimer, &QTimer::timeout, this, [this] { sendSsdpSearch(); });
        m_remotePollTimer = new QTimer(this);
        m_remotePollTimer->setInterval(2000);
        connect(m_remotePollTimer, &QTimer::timeout, this, [this] { pollDlnaRenderer(); });
        var_AddCallback(m_playlist, "input-current", onInputCurrent, this);
        for (const char *name : kPlaylistVars)
            var_AddCallback(m_playlist, name, onPlaylistVar, this);
        for (const char *name : kPlaylistChangeVars)
            var_AddCallback(m_playlist, name, onPlaylistChange, this);
    }

    ~Vlc3PlayerBackend() override
    {
        discoverRenderers(false);
        clearRenderers();
        m_localMediaServer->stop();
        if (m_addonsManager) {
            addons_manager_Delete(m_addonsManager);
            m_addonsManager = nullptr;
        }
        for (const char *name : kPlaylistChangeVars)
            var_DelCallback(m_playlist, name, onPlaylistChange, this);
        for (const char *name : kPlaylistVars)
            var_DelCallback(m_playlist, name, onPlaylistVar, this);
        var_DelCallback(m_playlist, "input-current", onInputCurrent, this);
        clearCurrentInput();
    }

    void togglePause() override
    {
        if (!m_activeDlnaId.isEmpty()) {
            const bool isPlaying = m_remoteInputState.state == 2;
            setRemoteTransportState(isPlaying ? QStringLiteral("Pause") : QStringLiteral("Play"),
                                    isPlaying ? 3 : 2);
            return;
        }
        playlist_TogglePause(m_playlist);
    }
    void play() override
    {
        if (!m_activeDlnaId.isEmpty()) {
            setRemoteTransportState(QStringLiteral("Play"), 2);
            return;
        }
        playlist_Play(m_playlist);
    }
    void pause() override
    {
        if (!m_activeDlnaId.isEmpty()) {
            setRemoteTransportState(QStringLiteral("Pause"), 3);
            return;
        }
        playlist_Pause(m_playlist);
    }
    void stop() override
    {
        if (!m_activeDlnaId.isEmpty()) {
            setRemoteTransportState(QStringLiteral("Stop"), 0);
            return;
        }
        playlist_Stop(m_playlist);
    }
    void next() override
    {
        if (!m_activeDlnaId.isEmpty()) {
            sendDlnaAction(m_activeDlnaId, "Next", {{QStringLiteral("InstanceID"), QStringLiteral("0")}});
            return;
        }
        playlist_Next(m_playlist);
    }
    void previous() override
    {
        if (!m_activeDlnaId.isEmpty()) {
            sendDlnaAction(m_activeDlnaId, "Previous", {{QStringLiteral("InstanceID"), QStringLiteral("0")}});
            return;
        }
        playlist_Prev(m_playlist);
    }
    void setRate(double rate) override { var_SetFloat(m_playlist, "rate", float(rate)); }
    void setVolume(double volume) override
    {
        if (!m_activeDlnaId.isEmpty()) {
            m_remoteVolume = qBound(0.0, volume, 1.0);
            const auto renderer = m_dlnaRenderers.constFind(m_activeDlnaId);
            if (renderer != m_dlnaRenderers.cend() && renderer->renderingControl.isValid())
                sendDlnaAction(m_activeDlnaId, "SetVolume",
                    {{QStringLiteral("InstanceID"), QStringLiteral("0")},
                     {QStringLiteral("Channel"), QStringLiteral("Master")},
                     {QStringLiteral("DesiredVolume"), QString::number(qBound(0, qRound(volume * 100.0), 100))}}, true);
            emit volumeStateChanged();
            return;
        }
        playlist_VolumeSet(m_playlist, float(volume));
    }
    void setMuted(bool muted) override
    {
        if (!m_activeDlnaId.isEmpty()) {
            m_remoteMuted = muted;
            const auto renderer = m_dlnaRenderers.constFind(m_activeDlnaId);
            if (renderer != m_dlnaRenderers.cend() && renderer->renderingControl.isValid())
                sendDlnaAction(m_activeDlnaId, "SetMute",
                    {{QStringLiteral("InstanceID"), QStringLiteral("0")},
                     {QStringLiteral("Channel"), QStringLiteral("Master")},
                     {QStringLiteral("DesiredMute"), muted ? QStringLiteral("1") : QStringLiteral("0")}}, true);
            emit volumeStateChanged();
            return;
        }
        playlist_MuteSet(m_playlist, muted);
    }
    void toggleMute() override
    {
        if (!m_activeDlnaId.isEmpty()) {
            setMuted(!m_remoteMuted);
            return;
        }
        playlist_MuteToggle(m_playlist);
    }

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

    QString playlistName() const override
    {
        QString result;
        playlist_Lock(m_playlist);
        playlist_item_t *current = playlist_CurrentPlayingItem(m_playlist);
        for (playlist_item_t *node = current ? current->p_parent : nullptr;
             node && node != m_playlist->p_playing; node = node->p_parent) {
            if (!node->p_input)
                continue;
            const QString uri = takeString(input_item_GetURI(node->p_input));
            const QString suffix = QFileInfo(QUrl(uri).path()).suffix().toLower();
            if (suffix != QLatin1String("m3u") && suffix != QLatin1String("m3u8")
                && suffix != QLatin1String("pls") && suffix != QLatin1String("xspf"))
                continue;
            result = takeString(input_item_GetName(node->p_input)).trimmed();
            if (result.isEmpty())
                result = QFileInfo(QUrl(uri).path()).completeBaseName();
            break;
        }
        playlist_Unlock(m_playlist);
        return result;
    }

    BackendPlaylistState playlistState() const override
    {
        BackendPlaylistState state;
        if (!m_activeDlnaId.isEmpty()) {
            state.volume = m_remoteVolume;
            state.muted = m_remoteMuted;
            return state;
        }
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
        if (!m_activeDlnaId.isEmpty())
            return m_remoteInputState;
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

    bool hasInput() const override { return !m_activeDlnaId.isEmpty() ? m_remoteInputState.hasInput : m_input != nullptr; }
    void seek(double position) override
    {
        if (!m_activeDlnaId.isEmpty()) {
            if (m_remoteInputState.seekable && m_remoteInputState.lengthMs > 0)
                seekDlnaTo(qint64(qBound(0.0, position, 1.0) * m_remoteInputState.lengthMs));
            return;
        }
        if (m_input)
            var_SetFloat(m_input, "position", float(qBound(0.0, position, 1.0)));
    }
    void seekBy(int ms) override
    {
        if (!m_activeDlnaId.isEmpty()) {
            if (!m_remoteInputState.seekable)
                return;
            seekDlnaTo(qMax<qint64>(0, m_remoteInputState.timeMs + ms));
            return;
        }
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
        if (!m_activeDlnaId.isEmpty()) {
            if (!m_remoteInputState.seekable)
                return;
            seekDlnaTo(qMax<qint64>(0, ms));
            return;
        }
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
    bool setVideoFilterChain(const QString &filters) override
    {
        var_Create(m_playlist, "video-filter", VLC_VAR_STRING | VLC_VAR_DOINHERIT);
        var_SetString(m_playlist, "video-filter", filters.toUtf8().constData());
        if (vout_thread_t *vout = currentVout()) {
            const int result = var_SetString(vout, "video-filter", filters.toUtf8().constData());
            vlc_object_release(vout);
            return result == VLC_SUCCESS;
        }
        return false;
    }
    bool setVideoAdjustment(const QString &option, double value) override
    {
        static const char *const supported[] = {"contrast", "brightness", "hue", "saturation", "gamma"};
        bool known = false;
        for (const char *name : supported)
            known |= option == QLatin1String(name);
        if (!known)
            return false;
        const QByteArray key = option.toUtf8();
        var_Create(m_playlist, key.constData(), VLC_VAR_FLOAT | VLC_VAR_DOINHERIT);
        var_SetFloat(m_playlist, key.constData(), float(value));
        if (vout_thread_t *vout = currentVout()) {
            var_Create(vout, key.constData(), VLC_VAR_FLOAT | VLC_VAR_DOINHERIT);
            const int result = var_SetFloat(vout, key.constData(), float(value));
            vlc_object_release(vout);
            return result == VLC_SUCCESS;
        }
        return false;
    }
    void setTransform(const QString &type) override
    {
        vout_thread_t *vout = currentVout();
        if (!vout)
            return;
        var_Create(vout, "transform-type", VLC_VAR_STRING);
        var_SetString(vout, "transform-type", type.toUtf8().constData());
        QStringList filters = takeString(var_GetString(vout, "video-filter")).split(QLatin1Char(','), Qt::SkipEmptyParts);
        filters.removeAll(QStringLiteral("transform"));
        if (!type.isEmpty())
            filters.append(QStringLiteral("transform"));
        const QString filterChain = filters.join(QLatin1Char(','));
        var_SetString(vout, "video-filter", filterChain.toUtf8().constData());
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
        // Seed the 10-band value before enabling the VLC 3 filter; otherwise
        // VLC's initial preset callback leaves its band variable empty.
        static constexpr const char *flatBands = "0 0 0 0 0 0 0 0 0 0";
        var_Create(m_playlist, "equalizer-preset", VLC_VAR_STRING | VLC_VAR_DOINHERIT);
        var_SetString(m_playlist, "equalizer-preset", name.constData());
        var_Create(m_playlist, "equalizer-bands", VLC_VAR_STRING | VLC_VAR_DOINHERIT);
        var_SetString(m_playlist, "equalizer-bands", flatBands);
        if (audio_output_t *aout = playlist_GetAout(m_playlist)) {
            var_Create(aout, "equalizer-preset", VLC_VAR_STRING | VLC_VAR_DOINHERIT);
            var_SetString(aout, "equalizer-preset", name.constData());
            var_Create(aout, "equalizer-bands", VLC_VAR_STRING | VLC_VAR_DOINHERIT);
            var_SetString(aout, "equalizer-bands", flatBands);
            vlc_object_release(aout);
        }
        playlist_EnableAudioFilter(m_playlist, "equalizer", true);
        if (audio_output_t *aout = playlist_GetAout(m_playlist)) {
            // The filter now has its callback; toggle a valid preset so it
            // replaces the seed bands with the selected profile's real curve.
            const char *alternate = preset == QLatin1String("flat") ? "rock" : "flat";
            var_SetString(aout, "equalizer-preset", alternate);
            var_SetString(aout, "equalizer-preset", name.constData());
            vlc_object_release(aout);
        }
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
        if (name == QLatin1String("equalizer-bands")
            || name == QLatin1String("equalizer-preamp")) {
            if (audio_output_t *aout = playlist_GetAout(m_playlist)) {
                QVariant activeValue;
                if (var_Type(aout, key.constData()) != 0) {
                    activeValue = name == QLatin1String("equalizer-bands")
                        ? QVariant(takeString(var_GetString(aout, key.constData())))
                        : QVariant(double(var_GetFloat(aout, key.constData())));
                }
                vlc_object_release(aout);
                if (activeValue.isValid())
                    return activeValue;
            }
        }
        switch (config_GetType(key.constData())) {
        case VLC_VAR_BOOL: return bool(config_GetInt(object, key.constData()));
        case VLC_VAR_INTEGER: return qint64(config_GetInt(object, key.constData()));
        case VLC_VAR_FLOAT: return double(config_GetFloat(object, key.constData()));
        case VLC_VAR_STRING: return takeString(config_GetPsz(object, key.constData()));
        default: return {};
        }
    }

    QString configType(const QString &name) const override
    {
        const QByteArray key = name.toUtf8();
        switch (config_GetType(key.constData())) {
        case VLC_VAR_BOOL: return QStringLiteral("bool");
        case VLC_VAR_INTEGER: return QStringLiteral("integer");
        case VLC_VAR_FLOAT: return QStringLiteral("float");
        case VLC_VAR_STRING: return QStringLiteral("string");
        default: return {};
        }
    }

    QString configDescription(const QString &name) const override
    {
        const QByteArray key = name.toUtf8();
        const module_config_t *config = config_FindConfig(key.constData());
        if (!config)
            return {};
        const char *description = config->psz_longtext ? config->psz_longtext : config->psz_text;
        return description ? QString::fromUtf8(description).trimmed() : QString();
    }

    QVariantMap configRange(const QString &name) const override
    {
        const QByteArray key = name.toUtf8();
        const module_config_t *config = config_FindConfig(key.constData());
        if (!config)
            return {};

        switch (config_GetType(key.constData())) {
        case VLC_VAR_INTEGER:
            if (config->min.i < config->max.i)
                return {{QStringLiteral("minimum"), QVariant::fromValue<qlonglong>(config->min.i)},
                        {QStringLiteral("maximum"), QVariant::fromValue<qlonglong>(config->max.i)}};
            break;
        case VLC_VAR_FLOAT:
            if (config->min.f < config->max.f)
                return {{QStringLiteral("minimum"), double(config->min.f)},
                        {QStringLiteral("maximum"), double(config->max.f)}};
            break;
        default:
            break;
        }
        return {};
    }

    void setConfig(const QString &name, const QVariant &value) override
    {
        const QByteArray key = name.toUtf8();
        vlc_object_t *object = VLC_OBJECT(m_intf);
        if (name == QLatin1String("http-proxy") || name == QLatin1String("http-proxy-pwd")) {
            config_PutPsz(object, key.constData(), value.toString().toUtf8().constData());
            syncHttpProxyEnvironment();
            config_SaveConfigFile(m_intf);
            return;
        }
        const QString previousAudioFilters = name == QLatin1String("audio-filter")
            ? takeString(config_GetPsz(object, key.constData())) : QString();
        const int configType = config_GetType(key.constData());
        switch (configType) {
        case VLC_VAR_BOOL:
        case VLC_VAR_INTEGER: config_PutInt(object, key.constData(), value.toLongLong()); break;
        case VLC_VAR_FLOAT: config_PutFloat(object, key.constData(), value.toFloat()); break;
        case VLC_VAR_STRING: config_PutPsz(object, key.constData(), value.toString().toUtf8().constData()); break;
        default: return;
        }
        if (name == QLatin1String("audio-filter")) {
            const auto filterNames = [](const QString &chain) {
                QStringList names;
                for (const QString &name : chain.split(QLatin1Char(','), Qt::SkipEmptyParts)) {
                    const QString cleaned = name.trimmed();
                    if (!cleaned.isEmpty() && !names.contains(cleaned))
                        names.append(cleaned);
                }
                return names;
            };
            const QStringList previous = filterNames(previousAudioFilters);
            const QStringList next = filterNames(value.toString());
            for (const QString &filter : previous) {
                if (!next.contains(filter))
                    playlist_EnableAudioFilter(m_playlist, filter.toUtf8().constData(), false);
            }
            for (const QString &filter : next) {
                if (!previous.contains(filter))
                    playlist_EnableAudioFilter(m_playlist, filter.toUtf8().constData(), true);
            }
        } else if (name.startsWith(QLatin1String("equalizer-"))
                   || name.startsWith(QLatin1String("spatializer-"))
                   || name.startsWith(QLatin1String("stereowiden-"))) {
            const auto setRuntimeValue = [&](vlc_object_t *target) {
                switch (configType) {
                case VLC_VAR_BOOL:
                    var_Create(target, key.constData(), VLC_VAR_BOOL | VLC_VAR_DOINHERIT);
                    var_SetBool(target, key.constData(), value.toBool());
                    break;
                case VLC_VAR_INTEGER:
                    var_Create(target, key.constData(), VLC_VAR_INTEGER | VLC_VAR_DOINHERIT);
                    var_SetInteger(target, key.constData(), int(value.toLongLong()));
                    break;
                case VLC_VAR_FLOAT:
                    var_Create(target, key.constData(), VLC_VAR_FLOAT | VLC_VAR_DOINHERIT);
                    var_SetFloat(target, key.constData(), value.toFloat());
                    break;
                case VLC_VAR_STRING:
                    var_Create(target, key.constData(), VLC_VAR_STRING | VLC_VAR_DOINHERIT);
                    var_SetString(target, key.constData(), value.toString().toUtf8().constData());
                    break;
                default: break;
                }
            };
            setRuntimeValue(VLC_OBJECT(m_playlist));
            if (audio_output_t *aout = playlist_GetAout(m_playlist)) {
                setRuntimeValue(VLC_OBJECT(aout));
                vlc_object_release(aout);
            }
        }
        // VLC 3 listens for the "visual" variable on the active audio output.
        // Updating the global audio-visual config alone only affects the next
        // audio output, so forward the selection through VLC's own callback.
        if (name == QLatin1String("audio-visual")) {
            if (audio_output_t *aout = playlist_GetAout(m_playlist)) {
                const QString visualization = value.toString();
                const QString mode = visualization == QLatin1String("none")
                    ? QStringLiteral("none")
                    : takeString(config_GetPsz(object, "effect-list"));
                if (!mode.isEmpty() && var_Type(aout, "visual") != 0)
                    var_SetString(aout, "visual", mode.toUtf8().constData());
                vlc_object_release(aout);
            }
        }
        config_SaveConfigFile(m_intf);
    }

    void sendHotkey(int vlcKey) override
    {
        var_SetInteger(m_intf->obj.libvlc, "key-pressed", vlcKey);
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

    bool forwardWheel(int deltaX, int deltaY, int qtModifiers) override
    {
        uint32_t code = deltaY > 0 ? KEY_MOUSEWHEELUP
                       : deltaY < 0 ? KEY_MOUSEWHEELDOWN
                       : deltaX > 0 ? KEY_MOUSEWHEELRIGHT
                       : deltaX < 0 ? KEY_MOUSEWHEELLEFT : 0;
        if (!code)
            return false;
        if (qtModifiers & Qt::ShiftModifier)
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

    QVariantList addons() const override
    {
        QVariantList result;
        QStringList ids = m_addons.keys();
        std::sort(ids.begin(), ids.end(), [this](const QString &a, const QString &b) {
            return m_addons.value(a).value(QStringLiteral("name")).toString().localeAwareCompare(
                       m_addons.value(b).value(QStringLiteral("name")).toString()) < 0;
        });
        result.reserve(ids.size());
        for (const QString &id : ids)
            result.append(m_addons.value(id));
        return result;
    }
    bool addonsLoading() const override { return m_addonsLoading; }
    void loadAddons() override
    {
        if (!m_addonsManager) {
            const addons_manager_owner owner = {
                this, addonFoundCallback, addonsDiscoveryEndedCallback, addonChangedCallback
            };
            m_addonsManager = addons_manager_New(VLC_OBJECT(m_intf), &owner);
        }
        if (!m_addonsManager || m_addonsLoaded)
            return;
        setAddonsLoading(true);
        m_addonsLoaded = addons_manager_LoadCatalog(m_addonsManager) == VLC_SUCCESS;
        setAddonsLoading(false);
    }
    void findAddons(const QString &source) override
    {
        loadAddons();
        if (!m_addonsManager)
            return;
        setAddonsLoading(true);
        const QByteArray uri = source.isEmpty() ? QByteArrayLiteral("repo://") : source.toUtf8();
        addons_manager_Gather(m_addonsManager, uri.constData());
        QTimer::singleShot(30000, this, [this] { setAddonsLoading(false); });
    }
    bool installAddon(const QString &uuid) override
    {
        if (!m_addonsManager)
            loadAddons();
        const auto addon = m_addons.constFind(uuid);
        if (!m_addonsManager || addon == m_addons.cend()
            || !addon->value(QStringLiteral("manageable")).toBool()
            || addon->value(QStringLiteral("installed")).toBool())
            return false;
        addon_uuid_t id{};
        return parseVlcAddonUuid(uuid, id)
            && addons_manager_Install(m_addonsManager, id) == VLC_SUCCESS;
    }
    bool removeAddon(const QString &uuid) override
    {
        if (!m_addonsManager)
            loadAddons();
        const auto addon = m_addons.constFind(uuid);
        if (!m_addonsManager || addon == m_addons.cend()
            || !addon->value(QStringLiteral("manageable")).toBool()
            || !addon->value(QStringLiteral("installed")).toBool())
            return false;
        addon_uuid_t id{};
        return parseVlcAddonUuid(uuid, id)
            && addons_manager_Remove(m_addonsManager, id) == VLC_SUCCESS;
    }

    QVariantList rendererDevices() const override
    {
        QMutexLocker locker(&m_rendererMutex);
        QVariantList devices;
        devices.reserve(m_renderers.size() + m_dlnaRenderers.size() + m_dialDevices.size());
        for (auto it = m_renderers.cbegin(); it != m_renderers.cend(); ++it) {
            devices.append(QVariantMap{
                {QStringLiteral("id"), it.key()},
                {QStringLiteral("name"), QString::fromUtf8(vlc_renderer_item_name(it.value()))},
                {QStringLiteral("protocol"), QStringLiteral("Chromecast")},
                {QStringLiteral("status"), it.key() == m_activeRendererId ? QStringLiteral("Selected") : QString()},
                {QStringLiteral("selected"), it.key() == m_activeRendererId}
            });
        }
        for (auto it = m_dlnaRenderers.cbegin(); it != m_dlnaRenderers.cend(); ++it) {
            devices.append(QVariantMap{
                {QStringLiteral("id"), it.key()},
                {QStringLiteral("name"), it->name},
                {QStringLiteral("protocol"), QStringLiteral("DLNA")},
                {QStringLiteral("status"), it.key() != m_activeDlnaId ? QString()
                    : m_remoteInputState.state == 2 ? QStringLiteral("Playing")
                    : m_remoteInputState.state == 3 ? QStringLiteral("Paused")
                    : m_remoteInputState.state == 0 ? QStringLiteral("Stopped")
                    : QStringLiteral("Connecting")},
                {QStringLiteral("selected"), it.key() == m_activeDlnaId}
            });
        }
        for (auto it = m_dialDevices.cbegin(); it != m_dialDevices.cend(); ++it) {
            devices.append(QVariantMap{
                {QStringLiteral("id"), it.key()},
                {QStringLiteral("name"), it->name},
                {QStringLiteral("protocol"), QStringLiteral("DIAL")},
                {QStringLiteral("status"), QStringLiteral("App launch only · no direct VLC playback")},
                {QStringLiteral("selected"), false},
                {QStringLiteral("available"), false}
            });
        }
        std::sort(devices.begin(), devices.end(), [](const QVariant &a, const QVariant &b) {
            return a.toMap().value(QStringLiteral("name")).toString().localeAwareCompare(
                       b.toMap().value(QStringLiteral("name")).toString()) < 0;
        });
        return devices;
    }
    bool rendererDiscoverySupported() const override
    {
        return true; // VLC renderer discovery plus VLC Neo's SSDP/DLNA discovery.
    }
    bool discoverRenderers(bool enabled) override
    {
        if (!enabled) {
            m_ssdpTimer->stop();
            m_ssdpSocket->close();
            {
                QMutexLocker locker(&m_rendererMutex);
                for (auto it = m_dlnaRenderers.begin(); it != m_dlnaRenderers.end();) {
                    if (it.key() != m_activeDlnaId)
                        it = m_dlnaRenderers.erase(it);
                    else
                        ++it;
                }
                m_dialDevices.clear();
            }
            m_dlnaLocations.clear();
            emit rendererDevicesChanged();
            QList<vlc_renderer_discovery_t *> discoveries;
            discoveries.swap(m_rendererDiscoveries);
            for (vlc_renderer_discovery_t *discovery : discoveries)
                vlc_rd_release(discovery);
            clearInactiveRenderers();
            return true;
        }
        const bool ssdpBound = m_ssdpSocket->state() == QAbstractSocket::BoundState
            || m_ssdpSocket->bind(QHostAddress::AnyIPv4, 0,
                                  QUdpSocket::ShareAddress | QUdpSocket::ReuseAddressHint);
        if (ssdpBound) {
            sendSsdpSearch();
            m_ssdpTimer->start();
        } else {
            qWarning().noquote() << "VLC Neo DLNA: SSDP discovery could not bind its UDP socket; trying VLC renderer discovery only:"
                                 << m_ssdpSocket->errorString();
        }
        if (!m_rendererDiscoveries.isEmpty())
            return true;

        char **names = nullptr;
        char **longNames = nullptr;
        if (vlc_rd_get_names(VLC_OBJECT(m_intf), &names, &longNames) != VLC_SUCCESS)
            return true;
        const vlc_renderer_discovery_owner owner = {this, onRendererAdded, onRendererRemoved};
        for (char **name = names; name && *name; ++name) {
            if (!isLocalRendererDiscoveryModule(*name))
                continue;
            vlc_renderer_discovery_t *discovery = vlc_rd_new(VLC_OBJECT(m_intf), *name, &owner);
            if (discovery)
                m_rendererDiscoveries.append(discovery);
        }
        freeRendererNames(names, longNames);
        return true;
    }
    bool setRenderer(const QString &id) override
    {
        if (id.startsWith(QStringLiteral("dlna:"))) {
            const auto found = m_dlnaRenderers.constFind(id);
            if (found == m_dlnaRenderers.cend()) {
                qWarning().noquote() << "VLC Neo DLNA: selected renderer disappeared" << id;
                return false;
            }
            const QUrl previousSourceUrl = m_activeDlnaSourceUrl.isEmpty()
                ? m_remoteInputState.mediaUrl : m_activeDlnaSourceUrl;
            if (!m_activeDlnaId.isEmpty() && m_activeDlnaId != id) {
                const QString oldId = m_activeDlnaId;
                m_activeDlnaId.clear();
                m_activeDlnaSourceUrl.clear();
                m_activeDlnaTransportUrl.clear();
                m_activeDlnaContentType.clear();
                m_remotePollTimer->stop();
                m_remotePollPending = false;
                m_remoteTransportCommandPending = false;
                m_remoteInputState = {};
                m_localMediaServer->stop();
                sendDlnaAction(oldId, "Stop", {{QStringLiteral("InstanceID"), QStringLiteral("0")} });
                if (m_localPausedByDlna) {
                    m_localPausedByDlna = false;
                    playlist_TogglePause(m_playlist);
                }
                emit rendererDevicesChanged();
                emit inputChanged();
                emit inputEvent(BackendInputEvent::State);
            }
            QUrl mediaUrl;
            BackendInputState localState;
            if (m_input) {
                localState = inputState();
                if (input_item_t *item = input_GetItem(m_input))
                    mediaUrl = QUrl(takeString(input_item_GetURI(item)));
            }
            if ((!mediaUrl.isValid() || mediaUrl.isEmpty()) && !previousSourceUrl.isEmpty())
                mediaUrl = previousSourceUrl;
            if ((!mediaUrl.isValid() || mediaUrl.isEmpty()) && !m_remoteInputState.mediaUrl.isEmpty())
                mediaUrl = m_remoteInputState.mediaUrl;
            if (!mediaUrl.isValid() || mediaUrl.isEmpty()) {
                qWarning().noquote() << "VLC Neo DLNA: no current media URL is available";
                return false;
            }
            const QString previousDlnaId = m_activeDlnaId;
            const bool localShouldResumeAfterDlna = previousDlnaId.isEmpty()
                ? localState.state == 2 : m_localWasPlayingBeforeDlna;

            QUrl transportUrl = mediaUrl;
            QString contentType;
            if (mediaUrl.isLocalFile()) {
                const bool sameMedia = m_activeDlnaId == id && m_activeDlnaSourceUrl == mediaUrl
                    && m_localMediaServer->isActive();
                if (sameMedia) {
                    transportUrl = m_activeDlnaTransportUrl;
                    contentType = m_activeDlnaContentType;
                } else {
                    QString relayError;
                    const QHostAddress localAddress = LocalMediaHttpServer::routeAddressFor(found->avTransport, &relayError);
                    if (!localAddress.isNull() && (localAddress.isLoopback() || localAddress.isLinkLocal()))
                        relayError = QStringLiteral("The route to the renderer uses a non-routable local address");
                    if (localAddress.isNull() || localAddress.isLoopback() || localAddress.isLinkLocal()
                        || !m_localMediaServer->start(mediaUrl, localAddress, &transportUrl, &relayError)) {
                        qWarning().noquote() << "VLC Neo DLNA: cannot serve local media:" << relayError;
                        if (m_activeDlnaId == id)
                            failDlnaConnection(id);
                        return false;
                    }
                    contentType = m_localMediaServer->contentType();
                }
            } else if (mediaUrl.scheme() == QLatin1String("http")
                       || mediaUrl.scheme() == QLatin1String("https")) {
                m_localMediaServer->stop();
                contentType = QMimeDatabase().mimeTypeForFile(mediaUrl.path(), QMimeDatabase::MatchExtension).name();
                if (contentType.isEmpty())
                    contentType = QStringLiteral("application/octet-stream");
            } else {
                qWarning().noquote() << "VLC Neo DLNA: unsupported current media URL" << mediaUrl.toString();
                return false;
            }

            if (!previousDlnaId.isEmpty() && previousDlnaId != id)
                sendDlnaAction(previousDlnaId, "Stop", {{QStringLiteral("InstanceID"), QStringLiteral("0")} });
            bool clearVlcRenderer = false;
            {
                QMutexLocker locker(&m_rendererMutex);
                clearVlcRenderer = !m_activeRendererId.isEmpty();
                m_activeRendererId.clear();
            }
            if (clearVlcRenderer)
                playlist_SetRenderer(m_playlist, nullptr);
            m_localWasPlayingBeforeDlna = localShouldResumeAfterDlna;
            m_activeDlnaId = id;
            m_activeDlnaSourceUrl = mediaUrl;
            m_activeDlnaTransportUrl = transportUrl;
            m_activeDlnaContentType = contentType;
            const bool mediaHasVideo = m_input ? localState.hasVideo
                : m_remoteInputState.hasVideo || contentType.startsWith(QStringLiteral("video/"))
                    || mediaUrl.path().endsWith(QStringLiteral(".m3u8"), Qt::CaseInsensitive);
            m_remoteInputState = localState;
            m_remoteInputState.hasInput = true;
            m_remoteInputState.hasVideo = mediaHasVideo;
            m_remoteInputState.state = 1;
            m_remoteInputState.mediaUrl = mediaUrl;
            const QString mediaTitle = mediaUrl.isLocalFile()
                ? QFileInfo(mediaUrl.toLocalFile()).fileName() : mediaUrl.fileName();
            m_remoteInputState.title = mediaTitle.isEmpty() ? found->name : mediaTitle;
            // A local VLC duration does not prove the renderer can seek this stream.
            m_remoteInputState.seekable = false;
            qInfo().noquote() << "VLC Neo DLNA: selecting" << found->name << mediaUrl.toString(QUrl::FullyEncoded);
            emit rendererDevicesChanged();
            emit inputChanged();

            sendDlnaAction(id, "GetPositionInfo", {{QStringLiteral("InstanceID"), QStringLiteral("0")}}, false,
                [this, id, mediaUrl, transportUrl, contentType](bool ok, const QByteArray &payload) {
                    if (id != m_activeDlnaId)
                        return;
                    const QHash<QString, QString> fields = ok ? soapFields(payload) : QHash<QString, QString>();
                    const QUrl currentUrl(fields.value(QStringLiteral("TrackURI")));
                    if (currentUrl.isValid() && currentUrl.toString(QUrl::FullyEncoded) == transportUrl.toString(QUrl::FullyEncoded)) {
                        m_remoteInputState.timeMs = upnpTimeMs(fields.value(QStringLiteral("RelTime")));
                        const qint64 duration = upnpTimeMs(fields.value(QStringLiteral("TrackDuration")));
                        if (duration > 0)
                            m_remoteInputState.lengthMs = duration;
                        m_remoteInputState.seekable = duration > 0;
                        // The same URI may still be loaded on the TV after it was stopped.
                        // Explicitly issue Play so selecting it always starts visible playback.
                        activateDlnaRenderer(id, false);
                        return;
                    }
                    startDlnaPlayback(id, mediaUrl, transportUrl, contentType);
                });
            return true;
        }
        if (id.isEmpty() && !m_activeDlnaId.isEmpty()) {
            const QString previousId = m_activeDlnaId;
            m_activeDlnaId.clear();
            m_activeDlnaSourceUrl.clear();
            m_activeDlnaTransportUrl.clear();
            m_activeDlnaContentType.clear();
            m_localMediaServer->stop();
            m_remotePollTimer->stop();
            m_remotePollPending = false;
            m_remoteTransportCommandPending = false;
            m_remoteInputState = {};
            sendDlnaAction(previousId, "Stop", {{QStringLiteral("InstanceID"), QStringLiteral("0")} });
            if (m_localPausedByDlna) {
                m_localPausedByDlna = false;
                playlist_TogglePause(m_playlist);
            }
            emit rendererDevicesChanged();
            emit inputChanged();
            emit inputEvent(BackendInputEvent::State);
            return true;
        }
        if (!m_activeDlnaId.isEmpty()) {
            const QString previousId = m_activeDlnaId;
            m_activeDlnaId.clear();
            m_activeDlnaSourceUrl.clear();
            m_activeDlnaTransportUrl.clear();
            m_activeDlnaContentType.clear();
            m_localMediaServer->stop();
            m_remotePollTimer->stop();
            m_remotePollPending = false;
            m_remoteTransportCommandPending = false;
            m_remoteInputState = {};
            sendDlnaAction(previousId, "Stop", {{QStringLiteral("InstanceID"), QStringLiteral("0")} });
            if (m_localPausedByDlna) {
                m_localPausedByDlna = false;
                playlist_TogglePause(m_playlist);
            }
        }
        vlc_renderer_item_t *item = nullptr;
        if (!id.isEmpty()) {
            QMutexLocker locker(&m_rendererMutex);
            const auto found = m_renderers.constFind(id);
            if (found == m_renderers.cend())
                return false;
            item = vlc_renderer_item_hold(found.value());
        }
        const int result = playlist_SetRenderer(m_playlist, item);
        if (item)
            vlc_renderer_item_release(item);
        if (result != VLC_SUCCESS)
            return false;
        {
            QMutexLocker locker(&m_rendererMutex);
            m_activeRendererId = id;
        }
        emit rendererDevicesChanged();
        return true;
    }

    static void addonFoundCallback(addons_manager_t *manager, addon_entry_t *entry)
    {
        auto *self = static_cast<Vlc3PlayerBackend *>(manager->owner.sys);
        const QSharedPointer<addon_entry_t> held(addon_entry_Hold(entry), addon_entry_Release);
        QMetaObject::invokeMethod(self, [self, held] {
            self->acceptAddon(held.data());
        }, Qt::QueuedConnection);
    }
    static void addonChangedCallback(addons_manager_t *manager, addon_entry_t *entry)
    {
        addonFoundCallback(manager, entry);
    }
    static void addonsDiscoveryEndedCallback(addons_manager_t *manager)
    {
        auto *self = static_cast<Vlc3PlayerBackend *>(manager->owner.sys);
        QMetaObject::invokeMethod(self, [self] { self->setAddonsLoading(false); }, Qt::QueuedConnection);
    }

private:
    void sendSsdpSearch()
    {
        if (!m_ssdpSocket || m_ssdpSocket->state() != QAbstractSocket::BoundState)
            return;
        static const QByteArray search =
            "M-SEARCH * HTTP/1.1\r\n"
            "HOST: 239.255.255.250:1900\r\n"
            "MAN: \"ssdp:discover\"\r\n"
            "MX: 2\r\n"
            "ST: ssdp:all\r\n\r\n";
        m_ssdpSocket->writeDatagram(search, QHostAddress(QStringLiteral("239.255.255.250")), 1900);
    }

    void readSsdpResponses()
    {
        while (m_ssdpSocket->hasPendingDatagrams()) {
            QByteArray datagram;
            datagram.resize(qsizetype(m_ssdpSocket->pendingDatagramSize()));
            m_ssdpSocket->readDatagram(datagram.data(), datagram.size());
            const QList<QByteArray> lines = datagram.split('\n');
            for (const QByteArray &line : lines) {
                const QByteArray trimmed = line.trimmed();
                if (trimmed.left(9).compare("LOCATION:", Qt::CaseInsensitive) != 0)
                    continue;
                const QUrl location(QString::fromUtf8(trimmed.mid(9).trimmed()));
                if (!location.isValid() || location.scheme() != QLatin1String("http"))
                    continue;
                const QString key = location.toString(QUrl::FullyEncoded);
                if (m_dlnaLocations.contains(key))
                    continue;
                m_dlnaLocations.insert(key);
                QNetworkReply *reply = m_network->get(QNetworkRequest(location));
                connect(reply, &QNetworkReply::finished, this, [this, reply, location] {
                    const QByteArray payload = reply->readAll();
                    const bool success = reply->error() == QNetworkReply::NoError;
                    reply->deleteLater();
                    if (!success)
                        return;
                    parseDlnaDescription(location, payload);
                });
                break;
            }
        }
    }

    void parseDlnaDescription(const QUrl &location, const QByteArray &description)
    {
        QXmlStreamReader xml(description);
        QString name, udn, baseUrl, serviceType, controlPath;
        QUrl avTransport, renderingControl;
        bool hasDialService = false;
        bool inService = false;
        while (!xml.atEnd()) {
            xml.readNext();
            if (xml.isStartElement()) {
                const QString tag = xml.name().toString();
                if (tag == QLatin1String("service")) {
                    inService = true;
                    serviceType.clear();
                    controlPath.clear();
                } else if (tag == QLatin1String("friendlyName")) {
                    name = xml.readElementText().trimmed();
                } else if (tag == QLatin1String("UDN")) {
                    udn = xml.readElementText().trimmed();
                } else if (tag == QLatin1String("URLBase")) {
                    baseUrl = xml.readElementText().trimmed();
                } else if (inService && tag == QLatin1String("serviceType")) {
                    serviceType = xml.readElementText().trimmed();
                } else if (inService && tag == QLatin1String("controlURL")) {
                    controlPath = xml.readElementText().trimmed();
                }
            } else if (xml.isEndElement() && xml.name() == QLatin1String("service")) {
                const QUrl base = baseUrl.isEmpty() ? location : QUrl(baseUrl);
                const QUrl control = base.resolved(QUrl(controlPath));
                if (serviceType.contains(QStringLiteral(":AVTransport:")))
                    avTransport = control;
                else if (serviceType.contains(QStringLiteral(":RenderingControl:")))
                    renderingControl = control;
                else if (serviceType.contains(QStringLiteral(":dial:1"), Qt::CaseInsensitive))
                    hasDialService = true;
                inService = false;
            }
        }
        if (xml.hasError() || udn.isEmpty())
            return;
        if (name.isEmpty() || name.compare(QStringLiteral("hisens"), Qt::CaseInsensitive) == 0)
            name = QStringLiteral("Hisense TV");
        if (!avTransport.isValid()) {
            if (!hasDialService)
                return;
            const QString id = QStringLiteral("dial:") + udn;
            {
                QMutexLocker locker(&m_rendererMutex);
                m_dialDevices.insert(id, DialDevice{id, name});
            }
            emit rendererDevicesChanged();
            return;
        }
        const QString id = QStringLiteral("dlna:") + udn;
        {
            QMutexLocker locker(&m_rendererMutex);
            m_dialDevices.remove(QStringLiteral("dial:") + udn);
            m_dlnaRenderers.insert(id, DlnaRenderer{id, udn, name, avTransport, renderingControl});
        }
        emit rendererDevicesChanged();
    }

    void sendDlnaAction(const QString &id, const QString &action,
                        const QMap<QString, QString> &arguments, bool renderingControl = false,
                        std::function<void(bool, const QByteArray &)> finished = {})
    {
        const auto renderer = m_dlnaRenderers.constFind(id);
        if (renderer == m_dlnaRenderers.cend()) {
            if (finished)
                finished(false, {});
            return;
        }
        const QUrl endpoint = renderingControl ? renderer->renderingControl : renderer->avTransport;
        if (!endpoint.isValid()) {
            qWarning().noquote() << "VLC Neo DLNA: missing endpoint for" << action << id;
            if (finished)
                finished(false, {});
            return;
        }
        const QString service = renderingControl
            ? QStringLiteral("urn:schemas-upnp-org:service:RenderingControl:1")
            : QStringLiteral("urn:schemas-upnp-org:service:AVTransport:1");
        QByteArray body;
        QXmlStreamWriter writer(&body);
        writer.writeStartDocument();
        writer.writeStartElement(QStringLiteral("s:Envelope"));
        writer.writeNamespace(QStringLiteral("http://schemas.xmlsoap.org/soap/envelope/"), QStringLiteral("s"));
        writer.writeAttribute(QStringLiteral("s:encodingStyle"), QStringLiteral("http://schemas.xmlsoap.org/soap/encoding/"));
        writer.writeStartElement(QStringLiteral("s:Body"));
        writer.writeStartElement(QStringLiteral("u:") + action);
        writer.writeNamespace(service, QStringLiteral("u"));
        for (auto it = arguments.cbegin(); it != arguments.cend(); ++it)
            writer.writeTextElement(it.key(), it.value());
        writer.writeEndElement();
        writer.writeEndElement();
        writer.writeEndElement();
        writer.writeEndDocument();

        QNetworkRequest request(endpoint);
        request.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("text/xml; charset=\"utf-8\""));
        request.setRawHeader("SOAPAction", QStringLiteral("\"%1#%2\"").arg(service, action).toUtf8());
        const bool isStatePoll = action == QLatin1String("GetTransportInfo")
            || action == QLatin1String("GetPositionInfo");
        if (!isStatePoll)
            qInfo().noquote() << "VLC Neo DLNA: sending" << action << endpoint.toString();
        QNetworkReply *reply = m_network->post(request, body);
        connect(reply, &QNetworkReply::finished, this, [reply, action, finished = std::move(finished)]() mutable {
            const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
            const QByteArray payload = reply->readAll();
            const bool isStatePoll = action == QLatin1String("GetTransportInfo")
                || action == QLatin1String("GetPositionInfo");
            // Some TVs close the SOAP connection just after sending a complete
            // 200 response. Qt may report a network error even though the UPnP
            // action succeeded; trust the HTTP status and SOAP body in that case.
            const bool ok = status >= 200 && status < 300 && soapResponseSucceeded(payload);
            if (ok && !isStatePoll)
                qInfo().noquote() << "VLC Neo DLNA: response" << action << status;
            else if (!ok && (!isStatePoll || status < 200 || status >= 300 || payload.isEmpty()
                             || !soapResponseSucceeded(payload)))
                qWarning().noquote() << "VLC Neo DLNA: response failed" << action << status << reply->errorString() << payload.left(700);
            reply->deleteLater();
            if (finished)
                finished(ok, payload);
        });
    }

    void setRemoteTransportState(const QString &action, int state)
    {
        if (m_activeDlnaId.isEmpty())
            return;
        if (m_remoteTransportCommandPending && m_remotePendingState == state)
            return;
        if (m_remoteInputState.state == state && !m_remoteTransportCommandPending)
            return;

        const QString id = m_activeDlnaId;
        const quint64 command = ++m_remoteCommandSerial;
        m_remotePendingState = state;
        m_remoteTransportCommandPending = true;
        m_remoteInputState.state = state;
        emit inputEvent(BackendInputEvent::State);
        emit rendererDevicesChanged();

        QMap<QString, QString> arguments{{QStringLiteral("InstanceID"), QStringLiteral("0")}};
        if (action == QLatin1String("Play"))
            arguments.insert(QStringLiteral("Speed"), QStringLiteral("1"));
        sendDlnaAction(id, action, arguments, false, [this, id, command, state](bool ok, const QByteArray &) {
            if (id != m_activeDlnaId || command != m_remoteCommandSerial)
                return;
            m_remotePendingState = 0;
            m_remoteTransportCommandPending = false;
            if (ok)
                m_remoteInputState.state = state;
            else
                qWarning().noquote() << "VLC Neo DLNA: transport command failed; querying renderer state";
            emit inputEvent(BackendInputEvent::State);
            emit rendererDevicesChanged();
            if (!ok)
                pollDlnaRenderer();
        });
    }

    void activateDlnaRenderer(const QString &id, bool seekToLocalPosition)
    {
        sendDlnaAction(id, "Play",
            {{QStringLiteral("InstanceID"), QStringLiteral("0")}, {QStringLiteral("Speed"), QStringLiteral("1")} }, false,
            [this, id, seekToLocalPosition](bool ok, const QByteArray &) {
                if (!ok || id != m_activeDlnaId) {
                    failDlnaConnection(id);
                    return;
                }
                m_remotePollTimer->start();
                if (m_input && m_localWasPlayingBeforeDlna && !m_localPausedByDlna) {
                    playlist_Pause(m_playlist);
                    m_localPausedByDlna = true;
                }
                m_remoteInputState.state = 2;
                emit rendererDevicesChanged();
                if (seekToLocalPosition && m_remoteInputState.timeMs > 0)
                    QTimer::singleShot(900, this, [this, id] {
                        if (id == m_activeDlnaId)
                            seekDlnaTo(m_remoteInputState.timeMs);
                    });
                // Keep playback position and state in sync with the renderer.
                // The timer issues read-only status requests; transport actions
                // are sent only in response to user input.
                pollDlnaRenderer();
                emit inputEvent(BackendInputEvent::State);
            });
    }

    void startDlnaPlayback(const QString &id, const QUrl &mediaUrl,
                           const QUrl &transportUrl, const QString &contentType)
    {
        const QString protocolInfo = mediaUrl.isLocalFile()
            ? QStringLiteral("http-get:*:%1:DLNA.ORG_OP=01").arg(contentType)
            : QStringLiteral("http-get:*:%1:*").arg(contentType);
        const QString mediaTitle = mediaUrl.isLocalFile()
            ? QFileInfo(mediaUrl.toLocalFile()).fileName() : mediaUrl.fileName();
        const QString sizeAttribute = mediaUrl.isLocalFile()
            ? QStringLiteral(" size=\"%1\"").arg(m_localMediaServer->contentLength()) : QString();
        const QString didl = QStringLiteral(
            "<DIDL-Lite xmlns=\"urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/\" "
            "xmlns:dc=\"http://purl.org/dc/elements/1.1/\" "
            "xmlns:upnp=\"urn:schemas-upnp-org:metadata-1-0/upnp/\">"
            "<item id=\"0\" parentID=\"-1\" restricted=\"1\"><dc:title>%1</dc:title>"
            "<upnp:class>object.item.%5</upnp:class>"
            "<res protocolInfo=\"%2\"%3>%4</res>"
            "</item></DIDL-Lite>").arg(mediaTitle.toHtmlEscaped(), protocolInfo.toHtmlEscaped(), sizeAttribute,
                transportUrl.toString(QUrl::FullyEncoded).toHtmlEscaped(),
                m_remoteInputState.hasVideo ? QStringLiteral("videoItem") : QStringLiteral("audioItem"));
        sendDlnaAction(id, "SetAVTransportURI",
            {{QStringLiteral("InstanceID"), QStringLiteral("0")},
             {QStringLiteral("CurrentURI"), transportUrl.toString(QUrl::FullyEncoded)},
             {QStringLiteral("CurrentURIMetaData"), didl}}, false,
            [this, id](bool ok, const QByteArray &) {
                if (!ok || id != m_activeDlnaId) {
                    failDlnaConnection(id);
                    return;
                }
                activateDlnaRenderer(id, true);
            });
    }

    void failDlnaConnection(const QString &id)
    {
        if (m_activeDlnaId != id)
            return;
        m_activeDlnaId.clear();
        m_activeDlnaSourceUrl.clear();
        m_activeDlnaTransportUrl.clear();
        m_activeDlnaContentType.clear();
        m_localMediaServer->stop();
        m_remotePollTimer->stop();
        m_remotePollPending = false;
        m_remoteTransportCommandPending = false;
        m_remoteInputState = {};
        if (m_localPausedByDlna) {
            m_localPausedByDlna = false;
            playlist_TogglePause(m_playlist);
        }
        emit rendererDevicesChanged();
        emit inputChanged();
        emit inputEvent(BackendInputEvent::State);
    }

    void seekDlnaTo(qint64 targetMs)
    {
        if (m_activeDlnaId.isEmpty() || !m_remoteInputState.seekable)
            return;
        if (m_remoteInputState.lengthMs > 0)
            targetMs = qMin(targetMs, m_remoteInputState.lengthMs);
        const qint64 seconds = qMax<qint64>(0, targetMs / 1000);
        const QString target = QStringLiteral("%1:%2:%3")
            .arg(seconds / 3600, 2, 10, QLatin1Char('0'))
            .arg((seconds / 60) % 60, 2, 10, QLatin1Char('0'))
            .arg(seconds % 60, 2, 10, QLatin1Char('0'));
        sendDlnaAction(m_activeDlnaId, "Seek",
            {{QStringLiteral("InstanceID"), QStringLiteral("0")},
             {QStringLiteral("Unit"), QStringLiteral("REL_TIME")},
             {QStringLiteral("Target"), target}});
    }

    void pollDlnaRenderer()
    {
        if (m_activeDlnaId.isEmpty() || m_remotePollPending || m_remoteTransportCommandPending)
            return;
        const QString id = m_activeDlnaId;
        m_remotePollPending = true;
        sendDlnaAction(id, "GetTransportInfo", {{QStringLiteral("InstanceID"), QStringLiteral("0")}}, false,
            [this, id](bool ok, const QByteArray &payload) {
                if (id != m_activeDlnaId) {
                    m_remotePollPending = false;
                    return;
                }
                if (!ok) {
                    m_remotePollPending = false;
                    return;
                }
                if (m_remoteTransportCommandPending) {
                    m_remotePollPending = false;
                    return;
                }
                const QString state = soapFields(payload).value(QStringLiteral("CurrentTransportState"));
                if (state == QLatin1String("PLAYING"))
                    m_remoteInputState.state = 2;
                else if (state == QLatin1String("PAUSED_PLAYBACK"))
                    m_remoteInputState.state = 3;
                else if (state == QLatin1String("TRANSITIONING"))
                    m_remoteInputState.state = 1;
                else
                    m_remoteInputState.state = 0;
                queryDlnaPosition(id);
            });
    }

    void queryDlnaPosition(const QString &id)
    {
        sendDlnaAction(id, "GetPositionInfo", {{QStringLiteral("InstanceID"), QStringLiteral("0")}}, false,
            [this, id](bool ok, const QByteArray &payload) {
                if (id != m_activeDlnaId) {
                    m_remotePollPending = false;
                    return;
                }
                if (ok) {
                    const QHash<QString, QString> fields = soapFields(payload);
                    m_remoteInputState.timeMs = upnpTimeMs(fields.value(QStringLiteral("RelTime")));
                    const qint64 duration = upnpTimeMs(fields.value(QStringLiteral("TrackDuration")));
                    if (duration > 0)
                        m_remoteInputState.lengthMs = duration;
                    m_remoteInputState.seekable = duration > 0;
                    m_remoteInputState.position = m_remoteInputState.lengthMs > 0
                        ? double(m_remoteInputState.timeMs) / double(m_remoteInputState.lengthMs) : 0.0;
                    const QString trackUri = fields.value(QStringLiteral("TrackURI"));
                    if (!trackUri.isEmpty())
                        m_remoteInputState.mediaUrl = QUrl(trackUri);
                }
                emit inputEvent(BackendInputEvent::Position);
                emit inputEvent(BackendInputEvent::State);
                emit rendererDevicesChanged();
            });
    }

    void restoreEnvironment(const char *name, bool wasSet, const QByteArray &value)
    {
        if (wasSet)
            qputenv(name, value);
        else
            qunsetenv(name);
    }

    void syncHttpProxyEnvironment()
    {
        const QString proxy = takeString(config_GetPsz(VLC_OBJECT(m_intf), "http-proxy")).trimmed();
        if (proxy.isEmpty()) {
            restoreEnvironment("http_proxy", m_hadHttpProxy, m_originalHttpProxy);
            restoreEnvironment("https_proxy", m_hadHttpsProxy, m_originalHttpsProxy);
            return;
        }

        QString address = proxy;
        if (!address.contains(QStringLiteral("://")))
            address.prepend(QStringLiteral("http://"));
        QUrl url(address);
        if (!url.isValid() || url.scheme() != QLatin1String("http") || url.host().isEmpty()) {
            restoreEnvironment("http_proxy", m_hadHttpProxy, m_originalHttpProxy);
            restoreEnvironment("https_proxy", m_hadHttpsProxy, m_originalHttpsProxy);
            return;
        }

        const QString password = takeString(config_GetPsz(VLC_OBJECT(m_intf), "http-proxy-pwd"));
        if (!password.isEmpty())
            url.setPassword(password);
        const QByteArray proxyUrl = url.toString(QUrl::FullyEncoded).toUtf8();
        qputenv("http_proxy", proxyUrl);
        qputenv("https_proxy", proxyUrl);
    }

    static bool isLocalRendererDiscoveryModule(const char *name)
    {
        const QByteArray lower = QByteArray(name).toLower();
        return lower.contains("avahi") || lower.contains("microdns");
    }
    static void freeRendererNames(char **names, char **longNames)
    {
        if (names) {
            for (char **name = names; *name; ++name)
                free(*name);
            free(names);
        }
        if (longNames) {
            for (char **name = longNames; *name; ++name)
                free(*name);
            free(longNames);
        }
    }
    static QString rendererId(vlc_renderer_item_t *item)
    {
        return QString::number(reinterpret_cast<quintptr>(item), 16);
    }
    static void onRendererAdded(vlc_renderer_discovery_t *discovery, vlc_renderer_item_t *item)
    {
        auto *self = static_cast<Vlc3PlayerBackend *>(discovery->owner.sys);
        if (!self || qstrcmp(vlc_renderer_item_type(item), "chromecast") != 0)
            return;
        const QSharedPointer<vlc_renderer_item_t> held(vlc_renderer_item_hold(item), vlc_renderer_item_release);
        QMetaObject::invokeMethod(self, [self, held] { self->registerRenderer(held.data()); }, Qt::QueuedConnection);
    }
    static void onRendererRemoved(vlc_renderer_discovery_t *discovery, vlc_renderer_item_t *item)
    {
        auto *self = static_cast<Vlc3PlayerBackend *>(discovery->owner.sys);
        if (!self || qstrcmp(vlc_renderer_item_type(item), "chromecast") != 0)
            return;
        const QString id = rendererId(item);
        QMetaObject::invokeMethod(self, [self, id, discovery] {
            if (self->m_rendererDiscoveries.contains(discovery))
                self->unregisterRenderer(id);
        }, Qt::QueuedConnection);
    }
    void registerRenderer(vlc_renderer_item_t *item)
    {
        const QString id = rendererId(item);
        {
            QMutexLocker locker(&m_rendererMutex);
            const auto existing = m_renderers.find(id);
            if (existing != m_renderers.end())
                vlc_renderer_item_release(existing.value());
            m_renderers.insert(id, vlc_renderer_item_hold(item));
        }
        emit rendererDevicesChanged();
    }
    void unregisterRenderer(const QString &id)
    {
        {
            QMutexLocker locker(&m_rendererMutex);
            auto item = m_renderers.find(id);
            if (item == m_renderers.end())
                return;
            // Releasing discovery can enqueue removal notifications after the
            // selected renderer has been intentionally retained. Ignore those
            // stale notifications once discovery is no longer active.
            if (m_activeRendererId == id && m_rendererDiscoveries.isEmpty())
                return;
            vlc_renderer_item_release(item.value());
            m_renderers.erase(item);
            if (m_activeRendererId == id) {
                m_activeRendererId.clear();
                playlist_SetRenderer(m_playlist, nullptr);
            }
        }
        emit rendererDevicesChanged();
    }
    void clearRenderers()
    {
        {
            QMutexLocker locker(&m_rendererMutex);
            for (vlc_renderer_item_t *item : std::as_const(m_renderers))
                vlc_renderer_item_release(item);
            m_renderers.clear();
            if (!m_activeRendererId.isEmpty()) {
                m_activeRendererId.clear();
                playlist_SetRenderer(m_playlist, nullptr);
            }
        }
        emit rendererDevicesChanged();
    }
    void clearInactiveRenderers()
    {
        {
            QMutexLocker locker(&m_rendererMutex);
            for (auto it = m_renderers.begin(); it != m_renderers.end();) {
                if (it.key() == m_activeRendererId) {
                    ++it;
                    continue;
                }
                vlc_renderer_item_release(it.value());
                it = m_renderers.erase(it);
            }
        }
        emit rendererDevicesChanged();
    }
    static QString addonTypeName(addon_type_t type)
    {
        switch (type) {
        case ADDON_EXTENSION: return QStringLiteral("Extension");
        case ADDON_PLAYLIST_PARSER: return QStringLiteral("Playlist parser");
        case ADDON_SERVICE_DISCOVERY: return QStringLiteral("Service discovery");
        case ADDON_SKIN2: return QStringLiteral("Skin");
        case ADDON_PLUGIN: return QStringLiteral("Plugin");
        case ADDON_INTERFACE: return QStringLiteral("Interface");
        case ADDON_META: return QStringLiteral("Metadata provider");
        default: return QStringLiteral("Add-on");
        }
    }
    void setAddonsLoading(bool loading)
    {
        if (m_addonsLoading == loading)
            return;
        m_addonsLoading = loading;
        emit addonsLoadingChanged();
    }
    void acceptAddon(addon_entry_t *entry)
    {
        char *rawId = addons_uuid_to_psz(&entry->uuid);
        const QString id = QString::fromUtf8(rawId ? rawId : "");
        free(rawId);
        if (id.isEmpty())
            return;
        QVariantMap addon {
            {QStringLiteral("uuid"), id},
            {QStringLiteral("name"), QString::fromUtf8(entry->psz_name ? entry->psz_name : "")},
            {QStringLiteral("summary"), QString::fromUtf8(entry->psz_summary ? entry->psz_summary : "")},
            {QStringLiteral("description"), QString::fromUtf8(entry->psz_description ? entry->psz_description : "")},
            {QStringLiteral("author"), QString::fromUtf8(entry->psz_author ? entry->psz_author : "")},
            {QStringLiteral("version"), QString::fromUtf8(entry->psz_version ? entry->psz_version : "")},
            {QStringLiteral("type"), addonTypeName(entry->e_type)},
            {QStringLiteral("installing"), entry->e_state == ADDON_INSTALLING},
            {QStringLiteral("installed"), entry->e_state == ADDON_INSTALLED},
            {QStringLiteral("removing"), entry->e_state == ADDON_UNINSTALLING},
            {QStringLiteral("manageable"), bool(entry->e_flags & ADDON_MANAGEABLE)},
            {QStringLiteral("source"), QString::fromUtf8(entry->psz_source_uri ? entry->psz_source_uri : "")}
        };
        m_addons.insert(id, addon);
        emit addonsChanged();
    }
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
    const bool m_hadHttpProxy = qEnvironmentVariableIsSet("http_proxy");
    const QByteArray m_originalHttpProxy = qgetenv("http_proxy");
    const bool m_hadHttpsProxy = qEnvironmentVariableIsSet("https_proxy");
    const QByteArray m_originalHttpsProxy = qgetenv("https_proxy");
    input_thread_t *m_input = nullptr; // owns the reference returned by playlist_CurrentInput
    addons_manager_t *m_addonsManager = nullptr;
    QHash<QString, QVariantMap> m_addons;
    bool m_addonsLoaded = false;
    bool m_addonsLoading = false;
    QList<vlc_renderer_discovery_t *> m_rendererDiscoveries;
    mutable QMutex m_rendererMutex;
    QHash<QString, vlc_renderer_item_t *> m_renderers;
    QHash<QString, DlnaRenderer> m_dlnaRenderers;
    QHash<QString, DialDevice> m_dialDevices;
    QSet<QString> m_dlnaLocations;
    QNetworkAccessManager *m_network = nullptr;
    LocalMediaHttpServer *m_localMediaServer = nullptr;
    QUdpSocket *m_ssdpSocket = nullptr;
    QTimer *m_ssdpTimer = nullptr;
    QTimer *m_remotePollTimer = nullptr;
    QString m_activeRendererId;
    QString m_activeDlnaId;
    QUrl m_activeDlnaSourceUrl;
    QUrl m_activeDlnaTransportUrl;
    QString m_activeDlnaContentType;
    BackendInputState m_remoteInputState;
    bool m_remotePollPending = false;
    quint64 m_remoteCommandSerial = 0;
    int m_remotePendingState = 0;
    bool m_remoteTransportCommandPending = false;
    bool m_localWasPlayingBeforeDlna = false;
    bool m_localPausedByDlna = false;
    double m_remoteVolume = 1.0;
    bool m_remoteMuted = false;
};

} // namespace

std::unique_ptr<PlayerBackend> makeVlc3PlayerBackend(intf_thread_t *intf, playlist_t *playlist)
{
    return std::make_unique<Vlc3PlayerBackend>(intf, playlist);
}
