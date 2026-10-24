import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Neo 1.0

MenuItem {
    id: root
    property string iconName: icon.name
    property int iconSize: 15
    property int labelSize: Theme.fontBody
    property string shortcutText: action && action.shortcut ? String(action.shortcut) : ""
    implicitHeight: 32
    leftPadding: 10
    rightPadding: 10

    indicator: null
    arrow: Icon {
        x: root.width - width - 10
        anchors.verticalCenter: parent.verticalCenter
        visible: root.subMenu !== null
        name: "chevron-right"
        size: 14
    }
    contentItem: RowLayout {
        spacing: 10
        Item {
            implicitWidth: 16
            implicitHeight: 16
            Icon {
                anchors.centerIn: parent
                visible: root.checkable ? root.checked : root.iconName.length > 0
                name: root.checkable ? "check" : root.iconName
                size: root.iconSize
                color: root.checkable || root.highlighted ? Theme.accent : Theme.icon
            }
        }
        NText {
            text: root.text
            Layout.fillWidth: true
            font.pixelSize: root.labelSize
            color: root.enabled ? Theme.text : Theme.textFaint
        }
        NText {
            visible: text.length > 0 && root.subMenu === null
            text: root.shortcutText
            dim: true
            font.pixelSize: 11
            Layout.rightMargin: 2
        }
    }
    background: Rectangle {
        radius: Theme.radiusSmall
        color: root.highlighted ? Theme.hover : "transparent"
    }
}
