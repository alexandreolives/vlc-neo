import QtQuick
import QtQuick.Controls.Basic
import Neo 1.0

// Drop-down with human words (model: [{label, value}]).
Rectangle {
    id: root
    property var model: []
    property var current
    signal picked(var value)
    implicitWidth: 180
    implicitHeight: 30
    radius: Theme.radiusSmall
    color: Theme.field
    border.color: menu.visible ? Theme.accent : Theme.border

    function labelFor(v) {
        for (const m of model) if (String(m.value) === String(v)) return m.label
        return v === undefined ? "" : String(v)
    }
    NText { text: root.labelFor(root.current); x: 10; width: parent.width - 34; anchors.verticalCenter: parent.verticalCenter }
    Icon { name: "chevron-right"; size: 14; rotation: 90; anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter }
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: menu.visible ? menu.close() : menu.open()
    }

    NMenu {
        id: menu
        y: root.height + 2
        width: Math.max(root.width, 220)
        Repeater {
            model: root.model
            delegate: NMenuItem {
                required property var modelData
                text: modelData.label
                checkable: true
                checked: String(modelData.value) === String(root.current)
                onTriggered: root.picked(modelData.value)
            }
        }
    }
}
