import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Neo 1.0

// Video / Audio / Subtitles quick picker that opens from the control bar.
Popup {
    id: root
    // Popups are positioned in the full player overlay coordinate space.
    // Anchoring to the control's RowLayout gives the popup only that row's
    // width/height and makes clamping fail on compact or resized windows.
    parent: keyCatcher
    property string tab: "spu"
    property Item currentAnchor: null
    signal showPreferences(string tab)
    signal addSubtitles()

    width: Math.min(340, Math.max(1, keyCatcher.width - 16))
    height: Math.min(440,
                     Math.max(content.implicitHeight + 24, root.tab === "audio" ? 400 : 280),
                     Math.max(1, keyCatcher.height - 16))
    padding: 0
    modal: false
    focus: true
    // Treat the whole control row that opened this popup as its parent. This
    // keeps a press on the trigger available for toggle/switch handling while
    // clicks elsewhere in the window dismiss the popup.
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent

    function openFor(tabName, triggerItem) {
        if (visible && tab === tabName && currentAnchor === triggerItem) {
            close()
            return
        }
        currentAnchor = triggerItem
        tab = tabName
        refresh()
        open()
        Qt.callLater(place)
    }
    function place() {
        if (!currentAnchor || !keyCatcher)
            return
        const p = currentAnchor.mapToItem(keyCatcher, 0, 0)
        const anchorTop = p.y
        const anchorBottom = p.y + currentAnchor.height
        const gap = 10
        const margin = 8
        const maxY = Math.max(margin, keyCatcher.height - height - margin)
        const above = anchorTop - height - gap
        const below = anchorBottom + gap
        const fitsAbove = above >= margin
        const fitsBelow = below + height <= keyCatcher.height - margin

        x = Math.max(margin, Math.min(p.x + currentAnchor.width / 2 - width / 2,
                                       keyCatcher.width - width - margin))
        if (fitsAbove)
            y = above
        else if (fitsBelow)
            y = below
        else
            y = Math.max(margin, Math.min(above, maxY))
    }
    function schedulePlace() { Qt.callLater(place) }
    onWidthChanged: if (visible) schedulePlace()
    onHeightChanged: if (visible) schedulePlace()
    onClosed: currentAnchor = null
    function refresh() {
        trackList.model = player.tracks(tab)
        deviceList.model = tab === "audio" ? player.audioDevices() : []
        if (visible)
            schedulePlace()
    }
    function focusTab(tabName) {
        for (let i = 0; i < tabButtons.count; ++i) {
            const button = tabButtons.itemAt(i)
            if (button && button.tabId === tabName) {
                button.forceActiveFocus()
                return button.activeFocus
            }
        }
        return false
    }
    onTabChanged: {
        refresh()
        schedulePlace()
    }
    Connections {
        target: win
        function onWidthChanged() { root.schedulePlace() }
        function onHeightChanged() { root.schedulePlace() }
    }
    Connections {
        target: root.currentAnchor
        function onXChanged() { root.schedulePlace() }
        function onYChanged() { root.schedulePlace() }
        function onWidthChanged() { root.schedulePlace() }
        function onHeightChanged() { root.schedulePlace() }
    }
    Connections {
        target: root.parent
        function onWidthChanged() { root.schedulePlace() }
        function onHeightChanged() { root.schedulePlace() }
    }
    Connections {
        target: player
        enabled: root.visible
        function onTracksChanged() { root.refresh() }
    }

    background: Rectangle { color: Theme.panel; radius: Theme.radius; border.color: Theme.border }

    contentItem: Flickable {
        id: tracksFlickable
        clip: true
        contentWidth: width
        contentHeight: Math.max(content.implicitHeight, height)
        ColumnLayout {
            id: content
            width: root.width
            height: tracksFlickable.contentHeight
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                spacing: 0
                Repeater {
                    id: tabButtons
                    model: [{ id: "video", label: "Video", icon: "film" },
                            { id: "audio", label: "Audio", icon: "audio-lines" },
                            { id: "spu", label: "Subtitles", icon: "captions" }]
                    delegate: Button {
                        id: tabButton
                        required property var modelData
                        property string tabId: modelData.id
                        Layout.preferredWidth: content.width / 3
                        Layout.minimumWidth: content.width / 3
                        Layout.maximumWidth: content.width / 3
                        implicitHeight: 40
                        padding: 0
                        focusPolicy: Qt.TabFocus
                        Accessible.name: modelData.label
                        objectName: "track-tab-" + modelData.id
                        Keys.onPressed: (event) => {
                            if (event.key !== Qt.Key_Escape) return
                            root.close()
                            event.accepted = true
                        }
                        onClicked: root.tab = modelData.id
                        background: Rectangle {
                            color: tabButton.hovered ? Theme.hover : "transparent"
                            border.width: tabButton.activeFocus ? 1 : 0
                            border.color: Theme.accent
                            Rectangle {
                                anchors.bottom: parent.bottom
                                width: parent.width
                                height: 2
                                color: root.tab === tabButton.tabId ? Theme.accent : Theme.border
                            }
                        }
                        contentItem: Row {
                            anchors.centerIn: parent
                            spacing: 6
                            Icon {
                                name: tabButton.modelData.icon; size: 15
                                color: root.tab === tabButton.tabId ? Theme.accent : Theme.textDim
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            NText {
                                text: tabButton.modelData.label
                                font.pixelSize: 12
                                color: root.tab === tabButton.tabId ? Theme.text : Theme.textDim
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
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

            Item {
                visible: root.tab === "audio"
                Layout.fillHeight: true
                Layout.minimumHeight: 8
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
