import QtQuick
import QtQuick.Layouts
import Neo 1.0

Modal {
    id: root
    title: "Media Properties"
    subtitle: player.title.length ? player.title : "Current VLC media item"
    width: Math.min(parent ? parent.width - 48 : 600, 600)

    ColumnLayout {
        width: root.width - 36
        spacing: 10

        component DetailRow: RowLayout {
            required property string label
            required property string value
            Layout.fillWidth: true
            spacing: 18
            NText {
                text: parent.label
                dim: true
                Layout.preferredWidth: 96
                Layout.alignment: Qt.AlignTop
            }
            NText {
                text: parent.value.length ? parent.value : "—"
                Layout.fillWidth: true
                wrapMode: Text.WrapAnywhere
                maximumLineCount: 3
            }
        }

        DetailRow { label: "File"; value: player.mediaUrl.toString().split("/").pop() }
        DetailRow { label: "Location"; value: player.mediaUrl.toString() }
        DetailRow { label: "Artist"; value: player.artist }
        DetailRow { label: "Folder"; value: player.folderPath }
        DetailRow { label: "Duration"; value: player.length > 0 ? player.formatTime(player.length) : "" }
        DetailRow { label: "Tracks"; value: player.tracks("video").length + " video · " + player.tracks("audio").length + " audio · " + player.tracks("spu").length + " subtitles" }
    }

    footer: [
        Item { Layout.fillWidth: true },
        NButton { text: "Close"; primary: true; onClicked: root.close() }
    ]
}
