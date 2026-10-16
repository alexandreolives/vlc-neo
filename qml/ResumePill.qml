import QtQuick
import QtQuick.Layouts
import Neo 1.0

// "Continue from 00:12:30?" placed right above the controls so it is noticed.
Rectangle {
    id: root
    property real point: 0
    function offer(ms) {
        point = ms
        opacity = 1
        hideTimer.restart()
    }
    function dismiss() { opacity = 0 }
    width: row.implicitWidth + 16
    height: 40
    radius: Theme.radius
    color: Theme.surface
    border.color: Theme.accent
    opacity: 0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: 180 } }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 8
        Icon { name: "history"; size: 16; color: Theme.accent }
        NText { text: "Continue from " + player.formatTime(root.point) + "?" }
        NButton { text: "Continue"; primary: true; implicitHeight: 26; onClicked: { player.resume(); root.dismiss() } }
        IconButton { icon: "x"; iconSize: 14; onClicked: root.dismiss() }
    }
    // Shrinking line = time left to answer.
    Rectangle {
        id: progress
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.margins: 1
        height: 2
        radius: 1
        color: Theme.accent
        width: (parent.width - 2) * (hideTimer.running ? remaining : 0)
        property real remaining: 1
        NumberAnimation on remaining { id: shrink; from: 1; to: 0; duration: hideTimer.interval; running: hideTimer.running }
    }
    Connections {
        target: player
        enabled: root.visible
        // Resumed by any route (button, hotkey, seek) -> no longer needed.
        function onTimeChanged() { if (Math.abs(player.time - root.point) < 2000) root.dismiss() }
    }
    Timer { id: hideTimer; interval: 9000; onTriggered: root.dismiss(); onRunningChanged: if (running) shrink.restart() }
}
