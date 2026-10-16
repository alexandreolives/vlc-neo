import QtQuick
import QtQuick.Layouts
import Neo 1.0

Modal {
    id: root
    title: "Open Network Stream"
    subtitle: "A video URL, a live stream, or an online playlist (.m3u). Playlists become a queue automatically."
    width: 560
    onOpened: { url.text = ""; url.forceActiveFocus() }

    ColumnLayout {
        width: root.width - 36
        spacing: 10
        NField {
            id: url
            Layout.fillWidth: true
            placeholderText: "https://… , rtsp://… , udp://@…"
            onAccepted: root.go(true)
        }
        NText { text: "Example: https://iptv-org.github.io/iptv/index.m3u — public TV channels"; dim: true; font.pixelSize: 11 }
        NButton {
            text: "Paste from clipboard"; icon: "clipboard"; flat: true
            onClicked: url.text = platform.clipboardText()
        }
    }
    footer: [
        Item { Layout.fillWidth: true },
        NButton { text: "Add to Queue"; onClicked: root.go(false) },
        NButton { text: "Play"; primary: true; onClicked: root.go(true) }
    ]
    function go(playNow) {
        if (url.text.trim().length === 0) return
        player.openLocation(url.text, playNow)
        close()
    }
}
