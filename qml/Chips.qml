import QtQuick
import Neo 1.0

// Segmented choice row. model: [{label, value}] or plain strings.
Flow {
    id: root
    property var model: []
    property var current
    signal picked(var value)
    spacing: 4

    Repeater {
        model: root.model
        delegate: Rectangle {
            required property var modelData
            readonly property var val: typeof modelData === "object" ? modelData.value : modelData
            readonly property string label: typeof modelData === "object" ? modelData.label : String(modelData)
            readonly property bool active: String(val) === String(root.current)
            width: Math.max(44, chipText.implicitWidth + 18)
            height: 28
            radius: Theme.radiusSmall
            color: active ? Theme.accentSoft : (chipMouse.containsMouse ? Theme.hover : Theme.raised)
            border.width: 1
            border.color: active ? Theme.accent : "transparent"
            NText {
                id: chipText
                anchors.centerIn: parent
                text: parent.label
                font.pixelSize: 12
                color: parent.active ? Theme.accent : Theme.text
            }
            MouseArea {
                id: chipMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.picked(parent.val)
            }
        }
    }
}
