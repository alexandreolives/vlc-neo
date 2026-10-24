import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Neo 1.0

Modal {
    id: root
    objectName: "network-stream-dialog"
    title: root.sourceCategory === "podcast" ? "Open Podcast Feed"
           : root.sourceCategory === "radio" ? "Open Radio Stream" : "Open Network Stream"
    width: Math.min(1048, win.width - 32)
    height: Math.min(632, win.height - 32)
    bodyMargin: 22
    titlePixelSize: 14
    titleWeight: Font.Normal
    titleColor: Theme.textDim
    titleLeftMargin: 20
    footerSideMargin: 20
    footerBottomMargin: 22
    property var networkUrls: []
    property bool urlsValid: false
    property string sourceCategory: ""
    property alias sourceText: urlList.text
    property alias playlistTitle: playlistName.text

    function openForCategory(category) {
        sourceCategory = category || ""
        open()
    }

    function parseUrls() {
        const lines = urlList.text.split(/\r?\n/)
        const parsed = []
        let valid = true
        for (let i = 0; i < lines.length; ++i) {
            const entry = lines[i].trim()
            if (!entry.length || entry.startsWith("#")) continue
            // Network streams are URLs, not local paths. Keep this check
            // deliberately conservative so malformed lines are not persisted.
            if (!/^[a-z][a-z0-9+.-]*:\/\/\S+$/i.test(entry)) {
                valid = false
                continue
            }
            parsed.push(entry)
        }
        networkUrls = parsed
        urlsValid = valid && parsed.length > 0
    }

    onOpened: {
        urlList.clear()
        playlistName.clear()
        parseUrls()
        urlList.forceActiveFocus()
    }

    ColumnLayout {
        width: root.width - 44
        spacing: 20
        y: 14

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 14
            NText {
                text: root.sourceCategory === "podcast" ? "Podcast Feed URL"
                      : root.sourceCategory === "radio" ? "Radio Stream URL" : "Network URL"
                font.pixelSize: 16
                font.weight: Font.Normal
            }
            NText {
                text: root.sourceCategory === "podcast" ? "Enter one or more podcast feed links to load."
                      : root.sourceCategory === "radio" ? "Enter one or more radio stream links to load."
                      : "You can enter multiple links to load."
                dim: true
                font.pixelSize: 14
            }
            TextArea {
                id: urlList
                objectName: "network-urls"
                Layout.fillWidth: true
                Layout.preferredHeight: 190
                Layout.topMargin: 8
                color: Theme.text
                placeholderTextColor: Theme.textFaint
                selectionColor: Theme.accent
                font.pixelSize: Theme.fontBody
                wrapMode: TextEdit.WrapAnywhere
                placeholderText: root.sourceCategory === "podcast" ? "e.g., https://www.example.com/podcast.rss"
                                : root.sourceCategory === "radio" ? "e.g., https://www.example.com/radio-stream"
                                : "e.g., https://www.example.com/stream.avi"
                background: Rectangle {
                    radius: Theme.radiusSmall
                    color: Theme.field
                    border.color: urlList.activeFocus ? Theme.accent : Theme.border
                }
                leftPadding: 10
                rightPadding: 10
                topPadding: 10
                bottomPadding: 10
                onTextChanged: root.parseUrls()
                Keys.onPressed: (event) => {
                    if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_Return) {
                        if (playlistName.text.trim().length && root.urlsValid) root.saveNamedPlaylist()
                        event.accepted = true
                    }
                }
            }
            NText {
                visible: urlList.text.trim().length > 0 && !root.urlsValid
                text: "Enter one valid network URL per line. Lines starting with # are ignored."
                color: "#E45B5B"
                font.pixelSize: 11
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.topMargin: 3
            spacing: 16
            RowLayout {
                spacing: 4
                NText { text: "Playlist Name"; font.pixelSize: 16; font.weight: Font.Normal }
                NText { text: "(optional)"; dim: true; font.pixelSize: 14 }
            }
            NText { text: "The playlist will be saved and displayed with this title."; dim: true; font.pixelSize: 14 }
            NField {
                id: playlistName
                objectName: "network-playlist-name"
                Layout.fillWidth: true
                Layout.topMargin: 8
                placeholderText: "e.g., Favorite TV Channels"
                onAccepted: if (root.urlsValid && text.trim().length) root.saveNamedPlaylist()
            }
        }
    }

    footer: [
        NButton { text: "Cancel"; Layout.preferredWidth: 100; onClicked: root.close() },
        Item { Layout.fillWidth: true },
        NButton { objectName: "network-add-queue"; visible: root.urlsValid; text: "Add to Queue"; onClicked: root.go(false) },
        NButton { objectName: "network-play"; visible: root.urlsValid; text: "Play"; primary: true; onClicked: root.go(true) },
        NButton { objectName: "network-save-playlist"; text: "Save"; primary: root.urlsValid && playlistName.text.trim().length > 0; Layout.preferredWidth: 100; enabledState: root.urlsValid && playlistName.text.trim().length > 0; onClicked: root.saveNamedPlaylist() }
    ]

    function saveNamedPlaylist() {
        if (!urlsValid || playlistName.text.trim().length === 0) return false
        if (!player.saveNetworkPlaylist(playlistName.text, networkUrls.join("\n"))) return false
        close()
        return true
    }
    function go(playNow) {
        if (!urlsValid) return
        player.openNetworkUrls(networkUrls.join("\n"), playNow)
        close()
    }
}
