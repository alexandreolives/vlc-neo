import QtQuick
import Neo 1.0

// Orange pill play/pause button, slightly bigger than the other controls.
Rectangle {
    id: root
    signal clicked()
    implicitWidth: 38
    implicitHeight: 24
    radius: 4
    color: mouse.pressed ? Qt.darker(Theme.accent, 1.15) : (mouse.containsMouse ? Qt.lighter(Theme.accent, 1.1) : Theme.accent)
    Icon {
        anchors.centerIn: parent
        name: player.playing ? "pause" : "play"
        size: 13
        color: "#141414"
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
