import QtQuick
import Neo 1.0

// Orange pill play/pause button, slightly bigger than the other controls.
Rectangle {
    id: root
    signal clicked()
    property bool compact: false
    property bool onboarding: false
    implicitWidth: onboarding ? 30 : (compact ? 42 : 54)
    implicitHeight: onboarding ? 16 : (compact ? 26 : 28)
    radius: 6
    border.width: activeFocus ? 2 : 0
    border.color: Theme.accentText
    activeFocusOnTab: enabled
    Accessible.name: player.playing ? "Pause" : "Play"
    Accessible.role: Accessible.Button
    Accessible.focusable: enabled
    color: mouse.pressed ? Qt.darker(Theme.accent, 1.15)
                         : (mouse.containsMouse || activeFocus ? Qt.lighter(Theme.accent, 1.1) : Theme.accent)
    Keys.onPressed: (event) => {
        if (!enabled || (event.key !== Qt.Key_Space && event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter))
            return
        if (!event.isAutoRepeat)
            root.clicked()
        event.accepted = true
    }
    Icon {
        anchors.centerIn: parent
        name: player.playing ? "pause" : "play"
        size: root.onboarding ? 14 : (root.compact ? 18 : 24)
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
