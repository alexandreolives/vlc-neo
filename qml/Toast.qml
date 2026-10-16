import QtQuick
import Neo 1.0

// On-screen message that also shows which key was pressed ("Space · Pause").
Rectangle {
    id: root
    property string key
    property string message
    function show(k, m) {
        key = k; message = m
        opacity = 1
        hideTimer.restart()
    }
    width: row.implicitWidth + 24
    height: 34
    radius: Theme.radius
    color: Qt.rgba(0.07, 0.07, 0.07, 0.92)
    border.color: "#333333"
    opacity: 0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: 160 } }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 8
        Rectangle {
            visible: root.key.length > 0
            width: keyText.implicitWidth + 12
            height: 22
            radius: 3
            color: "#2A2A2A"
            border.color: "#444444"
            anchors.verticalCenter: parent.verticalCenter
            NText { id: keyText; anchors.centerIn: parent; text: root.key; font.pixelSize: 11; color: "#EDEDED" }
        }
        NText { text: root.message; color: "#EDEDED"; anchors.verticalCenter: parent.verticalCenter }
    }
    Timer { id: hideTimer; interval: 1600; onTriggered: root.opacity = 0 }
}
