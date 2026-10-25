import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Neo 1.0

Modal {
    id: root
    title: "Stream to a Device"
    subtitle: protocol === "http"
              ? "Serve the current media as an H.264/AAC MPEG-TS stream over HTTP."
              : "Send the current media as an H.264/AAC MPEG-TS stream over " + protocol.toUpperCase() + "."
    width: 540
    closable: !vlcTasks.streaming
    property string protocol: "udp"
    property string host: "127.0.0.1"
    property string port: "1234"
    property string errorText: ""
    readonly property int profileVideoBitrateKbps: {
        player.configRevision
        return Number(player.config("sout-transcode-vb"))
    }
    readonly property int profileAudioBitrateKbps: {
        player.configRevision
        return Number(player.config("sout-transcode-ab"))
    }
    readonly property int videoBitrateKbps: profileVideoBitrateKbps >= 250
                                             && profileVideoBitrateKbps <= 20000
                                           ? profileVideoBitrateKbps : 2000
    readonly property int audioBitrateKbps: profileAudioBitrateKbps >= 64
                                             && profileAudioBitrateKbps <= 512
                                           ? profileAudioBitrateKbps : 192

    onOpened: errorText = ""
    function chooseProtocol(value) {
        protocol = value
        host = value === "http" ? "0.0.0.0" : "127.0.0.1"
    }

    ColumnLayout {
        width: root.width - 36
        spacing: 12
        SettingRow {
            label: "Source"
            NText { Layout.fillWidth: true; text: player.hasMedia ? player.title : "Open a media file first"; dim: !player.hasMedia; elide: Text.ElideMiddle }
        }
        SettingRow {
            label: "Protocol"
            NCombo {
                objectName: "stream-protocol"
                width: 180
                model: [{ label: "UDP (MPEG-TS)", value: "udp" },
                        { label: "RTP (MPEG-TS)", value: "rtp" },
                        { label: "HTTP (MPEG-TS)", value: "http" }]
                current: root.protocol
                onPicked: (value) => root.chooseProtocol(value)
            }
        }
        SectionTitle { text: protocol === "http" ? "HTTP server" : "Receiver" }
        RowLayout {
            Layout.fillWidth: true
            NField {
                objectName: "stream-host"
                Layout.fillWidth: true
                text: root.host
                placeholderText: protocol === "http" ? "Bind address (0.0.0.0)" : "Device IP or hostname"
                onTextEdited: root.host = text
            }
            NField {
                objectName: "stream-port"
                Layout.preferredWidth: 92
                text: root.port
                placeholderText: "1234"
                inputMethodHints: Qt.ImhDigitsOnly
                onTextEdited: root.port = text
            }
        }
        NText {
            Layout.fillWidth: true
            text: protocol === "http"
                  ? "On the receiver, open http://<this computer's IP>:" + root.port
                    + "/stream.ts. The bind address 0.0.0.0 listens on all network interfaces."
                  : "On the receiver, open " + protocol + "://@:" + root.port
                    + ". The stream ends when playback finishes or you stop it."
            dim: true
            wrapMode: Text.Wrap
        }
        NText {
            Layout.fillWidth: true
            text: "Transcode quality: " + root.videoBitrateKbps + " kb/s video · "
                  + root.audioBitrateKbps + " kb/s audio"
            dim: true
        }
        NText {
            visible: root.errorText.length > 0 || (vlcTasks.streaming && vlcTasks.status.length > 0)
            Layout.fillWidth: true
            text: root.errorText.length ? root.errorText : vlcTasks.status
            color: vlcTasks.status.startsWith("Starting") ? Theme.accent : Theme.textDim
            wrapMode: Text.Wrap
        }
        BusyIndicator { visible: vlcTasks.streaming; running: visible; Layout.alignment: Qt.AlignHCenter }
    }

    footer: [
        Item { Layout.fillWidth: true },
        NButton { text: vlcTasks.streaming ? "Stop stream" : "Close"; flat: true; onClicked: vlcTasks.streaming ? vlcTasks.stop() : root.close() },
        NButton {
            objectName: "stream-start"
            text: vlcTasks.streaming ? "Streaming…" : "Start stream"
            primary: true
            enabledState: !vlcTasks.busy && player.hasMedia
            onClicked: {
                root.errorText = ""
                const targetPort = Number.parseInt(root.port, 10)
                const includeSubtitles = player.config("sout-spu") !== false
                const subtitleFile = includeSubtitles ? player.activeSubtitleFile : ""
                const subtitleTrackId = includeSubtitles ? player.activeSubtitleTrackId : -1
                if (!vlcTasks.streamTo(player.mediaUrl, root.protocol, root.host, targetPort,
                                       root.videoBitrateKbps, root.audioBitrateKbps,
                                       includeSubtitles, subtitleFile, subtitleTrackId))
                    root.errorText = vlcTasks.status
            }
        }
    ]
}
