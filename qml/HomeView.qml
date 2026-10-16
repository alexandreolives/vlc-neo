import QtQuick
import QtQuick.Layouts
import Neo 1.0

// Shown when nothing is playing: continue where you left off instead of a blank cone.
Item {
    id: root
    signal openFile()
    signal openFolder()
    signal openNetwork()
    property var recents: []
    onVisibleChanged: if (visible) recents = player.recentMedia().slice(0, 8)
    Component.onCompleted: recents = player.recentMedia().slice(0, 8)

    ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(parent.width - 48, 560)
        spacing: 14

        Icon { name: "cone"; size: 72; Layout.alignment: Qt.AlignHCenter }
        NText {
            text: "Drop media here, or open something to play"
            font.pixelSize: Theme.fontTitle
            Layout.alignment: Qt.AlignHCenter
        }
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 8
            NButton { text: "Open File"; icon: "file-video"; primary: true; onClicked: root.openFile() }
            NButton { text: "Open Folder"; icon: "folder-open"; onClicked: root.openFolder() }
            NButton { text: "Network Stream"; icon: "link"; onClicked: root.openNetwork() }
        }
        NText {
            visible: root.recents.length > 0
            text: "Continue"
            dim: true
            font.pixelSize: 12
            Layout.topMargin: 12
        }
        Repeater {
            model: root.recents
            delegate: Rectangle {
                required property string modelData
                Layout.fillWidth: true
                implicitHeight: 38
                radius: Theme.radiusSmall
                color: recentMouse.containsMouse ? Theme.hover : Theme.bar
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 10
                    Icon { name: "history"; size: 15 }
                    NText { text: decodeURIComponent(modelData.split("/").pop()); Layout.fillWidth: true }
                    Icon { name: "play"; size: 13; color: Theme.accent }
                }
                MouseArea {
                    id: recentMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: player.openLocation(modelData, true)
                }
            }
        }
    }
}
