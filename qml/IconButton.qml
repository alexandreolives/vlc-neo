import QtQuick
import QtQuick.Controls.Basic
import Neo 1.0

Rectangle {
    id: root
    property string icon
    property int iconSize: 18
    property bool checked: false
    property bool accentWhenChecked: true
    property string tip
    readonly property bool hovered: mouse.containsMouse
    property color iconColor: checked && accentWhenChecked ? Theme.accent : (hovered ? Theme.text : Theme.icon)
    signal clicked()
    signal rightClicked()

    implicitWidth: 30
    implicitHeight: 28
    radius: Theme.radiusSmall
    color: mouse.pressed ? Theme.raised : (mouse.containsMouse ? Theme.hover : "transparent")
    Behavior on color { ColorAnimation { duration: 90 } }

    Icon {
        anchors.centerIn: parent
        name: root.icon
        size: root.iconSize
        color: root.iconColor
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: (e) => e.button === Qt.RightButton ? root.rightClicked() : root.clicked()
    }
    ToolTip.visible: tip.length > 0 && mouse.containsMouse
    ToolTip.delay: 600
    ToolTip.text: tip
}
