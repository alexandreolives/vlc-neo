import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Neo 1.0

ColumnLayout {
    id: root
    property bool compact: false
    property bool searchingTimedOut: false
    signal selected(string id)

    spacing: 8

    RowLayout {
        Layout.fillWidth: true
        NText { text: "Available devices"; font.weight: Font.DemiBold }
        Item { Layout.fillWidth: true }
        IconButton {
            objectName: "renderer-refresh"
            icon: "refresh-cw"
            tip: "Search again"
            onClicked: {
                root.searchingTimedOut = false
                player.discoverRenderers(true)
            }
        }
    }

    NText {
        visible: player.rendererDevices.length === 0
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        dim: true
        text: root.searchingTimedOut
              ? "No supported devices found. Check that the TV and computer are on the same network."
              : "Searching for TVs and speakers on your network…"
    }

    Repeater {
        model: player.rendererDevices
        delegate: Button {
            id: deviceButton
            required property var modelData
            objectName: "renderer-device-" + modelData.protocol.toLowerCase()
            Layout.fillWidth: true
            implicitHeight: 54
            padding: 9
            activeFocusOnTab: true
            Accessible.name: modelData.name + ", " + modelData.protocol
            onClicked: root.selected(modelData.id)

            background: Rectangle {
                radius: Theme.radiusSmall
                color: deviceButton.down ? Theme.raised
                     : deviceButton.hovered ? Theme.hover : Theme.surface
                border.width: modelData.selected || deviceButton.activeFocus ? 1 : 0
                border.color: Theme.accent
            }

            contentItem: RowLayout {
                spacing: 10
                Icon { name: "tv"; size: 20; color: modelData.selected ? Theme.accent : Theme.icon }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    NText { Layout.fillWidth: true; text: modelData.name; font.weight: Font.Medium }
                    NText {
                        text: modelData.protocol + (modelData.selected && modelData.status.length ? " · " + modelData.status : "")
                        dim: true
                        font.pixelSize: 10
                    }
                }
                Icon {
                    visible: modelData.selected
                    name: "check"
                    size: 17
                    color: Theme.accent
                }
            }
        }
    }

    Timer {
        interval: 7000
        running: root.visible && player.rendererDevices.length === 0
        repeat: false
        onTriggered: root.searchingTimedOut = true
    }
}
