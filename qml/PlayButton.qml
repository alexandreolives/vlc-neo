import QtQuick
import Neo 1.0

// Orange pill play/pause button, slightly bigger than the other controls.
Rectangle {
    id: root
    signal clicked()
    property bool compact: false
    implicitWidth: compact ? 42 : 54
    implicitHeight: compact ? 26 : 28
    radius: 6
    color: mouse.pressed ? Qt.darker(Theme.accent, 1.15) : (mouse.containsMouse ? Qt.lighter(Theme.accent, 1.1) : Theme.accent)
    Icon {
        anchors.centerIn: parent
        name: player.playing ? "pause" : "play"
        size: root.compact ? 18 : 24
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
