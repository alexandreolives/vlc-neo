import QtQuick
import Neo 1.0

Row {
    id: root
    property bool compact: false
    property bool square: false
    spacing: compact ? 2 : 18
    function swatchForColor(color) {
        for (let i = 0; i < accentRepeater.count; ++i) {
            const item = accentRepeater.itemAt(i)
            if (item && String(item.modelData).toUpperCase() === String(color).toUpperCase())
                return item.colorSwatch
        }
        return null
    }
    Repeater {
        id: accentRepeater
        model: Theme.accents
        delegate: Item {
            required property string modelData
            property bool selected: String(Theme.accent).toUpperCase() === modelData.toUpperCase()
            property alias colorSwatch: colorSwatch
            width: root.compact ? 26 : 60
            height: width
            Rectangle {
                objectName: "accent-outline-" + (root.square ? "settings-" : "onboarding-") + modelData.slice(1)
                anchors.centerIn: parent
                width: root.compact ? (selected ? 26 : 22) : (selected ? 60 : 40)
                height: width
                radius: root.square ? 3 : width / 2
                color: "transparent"
                border.width: selected ? 2 : 0
                border.color: Theme.accent
            }
            Rectangle {
                id: colorSwatch
                objectName: "accent-swatch-" + (root.square ? "settings-" : "onboarding-") + modelData.slice(1)
                anchors.centerIn: parent
                width: root.compact ? 18 : 40
                height: width
                radius: root.square ? 3 : width / 2
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
