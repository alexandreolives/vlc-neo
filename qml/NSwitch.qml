import QtQuick
import Neo 1.0

// Rectangular ON/OFF switch from the Figma settings screens.
Rectangle {
    id: root
    property bool checked: false
    signal toggled(bool checked)
    implicitWidth: 52
    implicitHeight: 22
    radius: 3
    color: Theme.field
    border.color: Theme.border

    Rectangle {
        width: 22; height: 16; radius: 2
        anchors.verticalCenter: parent.verticalCenter
        x: root.checked ? parent.width - width - 3 : 3
        color: root.checked ? Theme.accent : Theme.raised
        Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
    }
    NText {
        text: root.checked ? "ON" : "OFF"
        font.pixelSize: 9
        dim: true
        anchors.verticalCenter: parent.verticalCenter
        x: root.checked ? 6 : parent.width - width - 6
    }
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled(!root.checked)
    }
}
