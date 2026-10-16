import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Neo 1.0

// The queue: what plays next. Drop files or library items here.
Rectangle {
    id: root
    signal addFiles()
    signal savePlaylist()
    color: Theme.panel

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 14
            Layout.rightMargin: 8
            implicitHeight: 46
            NText { text: "Queue"; font.pixelSize: Theme.fontTitle; font.weight: Font.DemiBold }
            NText { text: player.queue.count; dim: true }
            Item { Layout.fillWidth: true }
            IconButton { icon: player.random ? "shuffle" : "shuffle"; checked: player.random; tip: "Shuffle"; onClicked: player.setRandom(!player.random) }
            IconButton { icon: player.repeatOne ? "repeat-1" : "repeat"; checked: player.loop || player.repeatOne; tip: "Repeat"
                onClicked: player.repeatOne ? player.setRepeatOne(false) : (player.loop ? (player.setLoop(false), player.setRepeatOne(true)) : player.setLoop(true)) }
            IconButton { icon: "plus"; tip: "Add files"; onClicked: root.addFiles() }
            IconButton { icon: "list-video"; tip: "Save as playlist"; onClicked: root.savePlaylist() }
            IconButton { icon: "trash-2"; tip: "Clear queue"; onClicked: player.clearQueue() }
        }
        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }

        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: player.queue
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {}
            delegate: Rectangle {
                id: row
                required property int index
                required property int itemId
                required property string title
                required property var duration
                required property bool current
                width: ListView.view.width
                height: 40
                color: current ? Theme.accentSoft : (rowMouse.containsMouse ? Theme.hover : "transparent")
                Rectangle { visible: row.current; width: 3; height: parent.height; color: Theme.accent }
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 6
                    spacing: 10
                    NText {
                        text: row.current && player.playing ? "▶" : (row.index + 1)
                        dim: !row.current
                        color: row.current ? Theme.accent : Theme.textDim
                        font.pixelSize: 11
                        Layout.preferredWidth: 18
                    }
                    NText {
                        text: row.title
                        Layout.fillWidth: true
                        color: row.current ? Theme.accent : Theme.text
                    }
                    NText { text: row.duration > 0 ? player.formatTime(row.duration) : ""; dim: true; font.pixelSize: 11 }
                    IconButton {
                        icon: "x"; iconSize: 14; tip: "Remove"
                        opacity: rowMouse.containsMouse || hovered ? 1 : 0
                        onClicked: player.removeItem(row.itemId)
                    }
                }
                MouseArea {
                    id: rowMouse
                    anchors.fill: parent
                    anchors.rightMargin: 36
                    hoverEnabled: true
                    onDoubleClicked: player.playItem(row.itemId)
                }
            }
            Column {
                anchors.centerIn: parent
                visible: list.count === 0
                spacing: 8
                Icon { name: "list"; size: 32; color: Theme.textFaint; anchors.horizontalCenter: parent.horizontalCenter }
                NText { text: "The queue is empty"; dim: true; anchors.horizontalCenter: parent.horizontalCenter }
                NText { text: "Drop files here or add them from the library"; color: Theme.textFaint; font.pixelSize: 11; anchors.horizontalCenter: parent.horizontalCenter }
            }
        }
    }

    DropArea {
        id: drop
        anchors.fill: parent
        keys: ["text/uri-list"]
        onDropped: (e) => {
            if (e.hasUrls) {
                player.openUrls(e.urls, false)
                e.acceptProposedAction()
            }
        }
        Rectangle {
            anchors.fill: parent
            visible: drop.containsDrag
            color: Theme.accentSoft
            border.color: Theme.accent
            border.width: 2
            NText { anchors.centerIn: parent; text: "Add to queue"; color: Theme.accent; font.weight: Font.DemiBold }
        }
    }
}
