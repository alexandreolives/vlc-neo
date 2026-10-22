import QtQuick
import Neo 1.0

Row {
    id: root
    property bool compact: false
    spacing: compact ? 2 : 18
    Repeater {
        id: accentRepeater
        model: Theme.accents
        delegate: Item {
            required property string modelData
            property bool selected: String(Theme.accent).toUpperCase() === modelData.toUpperCase()
            width: root.compact ? 26 : 60
            height: width
            Rectangle {
                anchors.centerIn: parent
                width: root.compact ? (selected ? 26 : 22) : (selected ? 60 : 40)
                height: width
                radius: width / 2
                color: "transparent"
                border.width: selected ? 2 : 0
                border.color: Theme.accent
            }
            Rectangle {
                anchors.centerIn: parent
                width: root.compact ? 18 : 40
                height: width
                radius: width / 2
                color: modelData
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: Theme.store.accent = modelData
            }
        }
    }
}
