import QtQuick
import Neo 1.0

// Rectangular ON/OFF switch from the Figma settings screens.
Rectangle {
    id: root
    property bool checked: false
    readonly property bool inheritsSettingRowLabel: true
    property string accessibleName: ""
    signal toggled(bool checked)
    implicitWidth: 62
    implicitHeight: 28
    radius: 4
    color: Theme.field
    border.width: activeFocus ? 1 : 0
    border.color: activeFocus ? Theme.accent : Theme.border
    activeFocusOnTab: enabled
    Accessible.name: accessibleName.length ? accessibleName : (checked ? "On" : "Off")
    Accessible.description: checked ? "On" : "Off"
    Accessible.role: Accessible.CheckBox
    Accessible.focusable: enabled

    Keys.onPressed: (event) => {
        if (!enabled || (event.key !== Qt.Key_Space && event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter))
            return
        if (!event.isAutoRepeat)
            root.toggled(!root.checked)
        event.accepted = true
    }

    Rectangle {
        width: 26; height: 20; radius: 3
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
        onClicked: {
            root.forceActiveFocus()
            root.toggled(!root.checked)
        }
    }
}
