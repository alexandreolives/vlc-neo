import QtQuick
import Neo 1.0

Row {
    spacing: 6
    Repeater {
        model: Theme.accents
        delegate: Rectangle {
            required property string modelData
            width: 24; height: 24; radius: 4
            color: modelData
            border.width: 2
            border.color: String(Theme.accent).toUpperCase() === modelData.toUpperCase() ? Theme.text : "transparent"
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Theme.store.accent = modelData }
        }
    }
}
