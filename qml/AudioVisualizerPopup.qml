import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Neo 1.0

Popup {
    id: root
    property Item currentAnchor: null
    property string selectedMode: "disabled"
    property var modes: [
        { id: "spectrometer", label: "Spectrometer", icon: "spectometer-two-tone", vlc: "spectrometer" },
        { id: "scope", label: "Scope", icon: "scope-two-tone", vlc: "scope" },
        { id: "spectrum", label: "Spectrum", icon: "spectrum-two-tone", vlc: "spectrum" },
        { id: "waveform", label: "Waveform", icon: "waveform-two-tone", vlc: "vuMeter" }
    ]
    parent: currentAnchor && currentAnchor.parent ? currentAnchor.parent : keyCatcher
    width: Math.min(390, parent ? parent.width - 16 : 390)
    height: Math.min(Math.max(260, content.implicitHeight + 28), Math.max(1, keyCatcher.height - 16))
    padding: 0
    modal: false
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
    objectName: "audio-visualizer-popup"

    function modeFromVlc() {
        const visualization = String(player.config("audio-visual") || "none")
        if (visualization === "none") return "disabled"
        if (visualization === "glspectrum") return "spectrum"
        const effect = String(player.config("effect-list") || "spectrum").split(",")[0].trim()
        if (effect === "dummy") return "disabled"
        if (effect === "vuMeter") return "waveform"
        return modes.some(item => item.id === effect) ? effect : "spectrum"
    }
    function openFor(anchor) {
        if (!anchor) return
        if (visible && currentAnchor === anchor) {
            close()
            return
        }
        currentAnchor = anchor
        selectedMode = modeFromVlc()
        place()
        open()
        Qt.callLater(place)
    }
    function place() {
        if (!currentAnchor || !parent) return
        const point = currentAnchor.mapToItem(parent, currentAnchor.width / 2, 0)
        x = Math.max(8, Math.min(point.x - width / 2, parent.width - width - 8))
        y = point.y - height - 10
        let top = parent.mapToItem(keyCatcher, 0, y).y
        if (top < 8) y += 8 - top
        top = parent.mapToItem(keyCatcher, 0, y).y
        const bottom = top + height
        if (bottom > keyCatcher.height - 8)
            y -= bottom - (keyCatcher.height - 8)
    }
    function schedulePlace() { Qt.callLater(place) }
    function selectMode(mode) {
        if (mode === "disabled") {
            player.setConfig("audio-visual", "none")
        } else {
            const selected = modes.find(item => item.id === mode)
            if (!selected) return
            player.setConfig("effect-list", selected.vlc)
            player.setConfig("audio-visual", "visual")
        }
        selectedMode = mode
        close()
    }
    Component.onCompleted: selectedMode = modeFromVlc()
    onClosed: currentAnchor = null

    Connections {
        target: win
        function onWidthChanged() { root.schedulePlace() }
        function onHeightChanged() { root.schedulePlace() }
    }

    background: Item {
        Rectangle {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            anchors.topMargin: 10
            anchors.bottomMargin: 18
            color: Theme.panel
            radius: 6
            border.color: Theme.border
        }
    }
    contentItem: Flickable {
        id: optionsFlickable
        clip: true
        contentWidth: width
        contentHeight: content.implicitHeight + 28

        ColumnLayout {
            id: content
            x: 14
            y: 12
            width: optionsFlickable.width - 28
            implicitHeight: 232
            spacing: 2

            Repeater {
                model: [{ id: "disabled", label: "Disabled", icon: "" }].concat(root.modes)
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    objectName: "audio-visualizer-option-" + modelData.id
                    Layout.fillWidth: true
                    implicitHeight: 44
                    radius: Theme.radiusSmall
                    color: optionMouse.containsMouse ? Theme.hover
                          : (root.selectedMode === modelData.id ? Theme.raised : "transparent")

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 12
                        spacing: 12
                        Item {
                            Layout.preferredWidth: 22
                            Layout.preferredHeight: 22
                            Icon { anchors.centerIn: parent; name: modelData.icon; size: 22; visible: modelData.icon.length > 0 }
                        }
                        NText { text: modelData.label; Layout.fillWidth: true; font.pixelSize: 13 }
                        Icon { name: "check-selected"; size: 16; color: Theme.accent; visible: root.selectedMode === modelData.id }
                    }
                    MouseArea {
                        id: optionMouse
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        onClicked: root.selectMode(modelData.id)
                    }
                }
            }
        }
    }
}
