import QtQuick
import QtQuick.Controls.Basic
import Neo 1.0

Rectangle {
    id: root
    property string icon
    property int iconSize: 18
    property real iconOffsetX: 0
    property real iconOffsetY: 0
    property bool checked: false
    property bool accentWhenChecked: true
    property bool colorAnimationEnabled: true
    property string tip
    readonly property bool hovered: mouse.containsMouse
    property color iconColor: !enabled ? Theme.textFaint
                            : checked && accentWhenChecked ? Theme.accent : (hovered ? Theme.text : Theme.icon)
    signal clicked()
    signal rightClicked()

    implicitWidth: 30
    implicitHeight: 28
    radius: Theme.radiusSmall
    color: mouse.pressed ? Theme.raised : (mouse.containsMouse || activeFocus ? Theme.hover : "transparent")
    border.width: activeFocus ? 1 : 0
    border.color: Theme.accent
    activeFocusOnTab: enabled
    Accessible.name: tip.length ? tip : icon
    Accessible.role: Accessible.Button
    Accessible.focusable: enabled
    Behavior on color {
        enabled: root.colorAnimationEnabled
        ColorAnimation { duration: 90 }
    }

    Keys.onPressed: (event) => {
        if (!enabled || (event.key !== Qt.Key_Space && event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter))
            return
        if (!event.isAutoRepeat)
            root.clicked()
        event.accepted = true
    }

    Icon {
        x: (parent.width - width) / 2 + root.iconOffsetX
        y: (parent.height - height) / 2 + root.iconOffsetY
        name: root.icon
        size: root.iconSize
        color: root.iconColor
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: (e) => e.button === Qt.RightButton ? root.rightClicked() : root.clicked()
    }
    ToolTip.visible: tip.length > 0 && mouse.containsMouse
    ToolTip.delay: 600
    ToolTip.text: tip
}
