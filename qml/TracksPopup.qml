import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Neo 1.0

// Video / Audio / Subtitles quick picker that opens from the control bar.
Popup {
    id: root
    property string tab: "spu"
    property Item currentAnchor: null
    signal showPreferences(string tab)
    signal addSubtitles()

    width: 340
    height: Math.min(440, content.implicitHeight + 24)
    padding: 0
    modal: false
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    function openFor(tabName, triggerItem) {
        if (visible && tab === tabName && currentAnchor === triggerItem) {
            close()
            return
        }
        currentAnchor = triggerItem
        tab = tabName
        refresh()
        const p = triggerItem.mapToItem(parent, triggerItem.width / 2, 0)
        x = Math.min(Math.max(8, p.x - width / 2), parent.width - width - 8)
        y = p.y - height - 10
        open()
    }
    onClosed: currentAnchor = null
    function refresh() {
        trackList.model = player.tracks(tab)
        deviceList.model = tab === "audio" ? player.audioDevices() : []
    }
    onTabChanged: refresh()
    Connections {
        target: player
        enabled: root.visible
        function onTracksChanged() { root.refresh() }
    }

    background: Rectangle { color: Theme.panel; radius: Theme.radius; border.color: Theme.border }

    contentItem: Flickable {
        clip: true
        contentWidth: width
        contentHeight: content.implicitHeight
        ColumnLayout {
            id: content
            width: root.width
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                spacing: 0
                Repeater {
                    model: [{ id: "video", label: "Video", icon: "film" },
                            { id: "audio", label: "Audio", icon: "audio-lines" },
                            { id: "spu", label: "Subtitles", icon: "captions" }]
                    delegate: Item {
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: 40
                        Row {
                            anchors.centerIn: parent
                            spacing: 6
                            Icon {
                                name: modelData.icon; size: 15
                                color: root.tab === modelData.id ? Theme.accent : Theme.textDim
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            NText {
                                text: modelData.label
                                font.pixelSize: 12
                                color: root.tab === modelData.id ? Theme.text : Theme.textDim
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                        Rectangle {
                            anchors.bottom: parent.bottom
                            width: parent.width; height: 2
                            color: root.tab === modelData.id ? Theme.accent : Theme.border
                        }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.tab = modelData.id }
                    }
                }
            }

            NText { text: "Embedded Tracks"; dim: true; font.pixelSize: 12; Layout.margins: 14; Layout.bottomMargin: 4 }
            Repeater {
                id: trackList
                delegate: TrackRow {
                    required property var modelData
                    label: modelData.name
                    selected: modelData.selected
                    onClicked: { player.selectTrack(root.tab, modelData.id); root.refresh() }
                }
            }
            NText {
                visible: trackList.count === 0
                text: player.hasMedia ? "No tracks" : "Nothing is playing"
                dim: true; Layout.leftMargin: 40; Layout.bottomMargin: 6
            }

            NText {
                visible: root.tab === "audio" && deviceList.count > 0
                text: "Output Device"; dim: true; font.pixelSize: 12
                Layout.margins: 14; Layout.bottomMargin: 4
            }
            Repeater {
                id: deviceList
                delegate: TrackRow {
                    required property var modelData
                    label: modelData.name
                    selected: modelData.selected
                    onClicked: { player.setAudioDevice(modelData.id); root.refresh() }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.margins: 12
                spacing: 8
                NButton {
                    visible: root.tab === "spu"
                    text: "Add Subtitles"
                    icon: "plus"
                    Layout.fillWidth: true
                    onClicked: { root.close(); root.addSubtitles() }
                }
                NButton {
                    text: "Show Preferences"
                    Layout.fillWidth: true
                    onClicked: { root.close(); root.showPreferences(root.tab) }
                }
            }
        }
    }

    component TrackRow: Rectangle {
        id: row
        property string label
        property bool selected
        signal clicked()
        Layout.fillWidth: true
        Layout.leftMargin: 6
        Layout.rightMargin: 6
        implicitHeight: 34
        radius: Theme.radiusSmall
        color: rowMouse.containsMouse ? Theme.hover : "transparent"
        Icon { visible: row.selected; name: "check"; size: 15; color: Theme.accent; x: 14; anchors.verticalCenter: parent.verticalCenter }
        NText { text: row.label; x: 40; width: parent.width - 50; anchors.verticalCenter: parent.verticalCenter }
        MouseArea { id: rowMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: row.clicked() }
    }
}
