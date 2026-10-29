import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Neo 1.0

// "Label ........ control" row with an info icon that explains the setting.
RowLayout {
    id: root
    property string label
    property string info
    property string optionDescription
    property bool labelTopAligned: false
    readonly property string effectiveInfo: info.length ? info : optionDescription
    default property alias control: holder.data
    spacing: 8
    implicitHeight: 34
    Layout.fillWidth: true

    // Label with its info icon right next to it.
    Item {
        id: labelBox
        Layout.fillWidth: true
        Layout.alignment: root.labelTopAligned ? Qt.AlignTop : Qt.AlignVCenter
        implicitHeight: 30
        NText {
            id: labelText
            text: root.label
            dim: true
            width: Math.max(0, Math.min(implicitWidth, labelBox.width - (infoIcon.visible ? 22 : 0)))
            anchors.verticalCenter: parent.verticalCenter
        }
        Icon {
            id: infoIcon
            visible: root.effectiveInfo.length > 0
            name: "info"
            size: 14
            x: labelText.width + 6
            anchors.verticalCenter: parent.verticalCenter
            color: infoHover.hovered ? Theme.accent : Theme.textFaint
            HoverHandler { id: infoHover }
            ToolTip.visible: infoHover.hovered
            ToolTip.text: root.effectiveInfo
            ToolTip.delay: 200
        }
    }
    // Control slot. Sized from the control's implicit size (not childrenRect,
    // which feeds back into the layout and loops).
    Item {
        id: holder
        readonly property Item first: children.length > 0 ? children[0] : null
        Layout.preferredWidth: first ? Math.max(first.implicitWidth, first.width) : 0
        Layout.preferredHeight: first ? Math.max(30, first.implicitHeight, first.height) : 30
        Layout.alignment: Qt.AlignVCenter
    }

    Binding {
        target: holder.first && holder.first.inheritsSettingRowLabel ? holder.first : null
        property: "accessibleName"
        value: root.label
    }
}
