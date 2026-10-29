import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Neo 1.0

Modal {
    id: root
    title: "Keyboard Shortcuts"
    subtitle: ""
    width: Math.min(parent ? parent.width : 1048, 1048)
    height: Math.min(parent ? parent.height : 800, 800)
    property string recordingAction: ""
    property string captureError: ""
    property string captureNotice: ""
    property string shortcutSearch: ""
    property string shortcutScope: "all"
    property var shortcutDraft: ({})
    property var vlcShortcutDraft: ({})

    function filteredShortcuts(items) {
        const query = shortcutSearch.trim().toLowerCase()
        if (!query.length) return items
        return items.filter(item => {
            const name = item.id || item.name
            const local = item.id ? neoShortcutText(item.id) : vlcShortcutText(name)
            const global = item.id ? "" : vlcShortcutText("global-" + name)
            const values = shortcutScope === "action" ? item.label + " " + name
                         : shortcutScope === "hotkey" ? local
                         : shortcutScope === "global" ? global
                         : item.label + " " + name + " " + local + " " + global
            return values.toLowerCase().includes(query)
        })
    }

    function beginRecording(id) {
        recordingAction = id
        captureError = ""
        captureNotice = ""
        Qt.callLater(() => keyCapture.forceActiveFocus(Qt.PopupFocusReason))
    }

    function vlcShortcutText(name) {
        if (Object.prototype.hasOwnProperty.call(vlcShortcutDraft, name))
            return String(vlcShortcutDraft[name] || "").split("\t")[0] || "Unassigned"
        return String(player.config(name) || "").split("\t")[0] || "Unassigned"
    }
    function neoShortcutKeys(id) {
        const value = Object.prototype.hasOwnProperty.call(shortcutDraft, id)
                    ? shortcutDraft[id] : Theme.defaultShortcuts[id]
        if (typeof value === "string" && value.length) return [value]
        if (Array.isArray(value)) return value.filter(key => typeof key === "string" && key.length)
        return []
    }
    function neoShortcutText(id) { return neoShortcutKeys(id).join(" / ") }
    function loadDrafts() {
        try {
            const stored = JSON.parse(Theme.store.shortcutsJson)
            shortcutDraft = stored && typeof stored === "object" && !Array.isArray(stored) ? stored : ({})
        } catch (error) { shortcutDraft = ({}) }
        const values = ({})
        for (const item of vlcShortcuts.concat(globalVlcShortcuts))
            values[item.name] = String(player.config(item.name) || "")
        vlcShortcutDraft = values
    }
    function saveNeoShortcut(id, chord) {
        if (!Object.prototype.hasOwnProperty.call(Theme.defaultShortcuts, id) || !chord) return false
        for (const other of Object.keys(Theme.defaultShortcuts)) {
            if (other !== id && neoShortcutKeys(other).some(key => String(key).toLowerCase() === String(chord).toLowerCase()))
                return false
        }
        const values = Object.assign({}, shortcutDraft)
        values[id] = chord
        shortcutDraft = values
        return neoShortcutText(id) === chord
    }
    function resetAllShortcuts() {
        shortcutDraft = ({})
        resetVlcShortcuts()
        resetGlobalVlcShortcuts()
    }
    function saveChanges() {
        Theme.store.shortcutsJson = JSON.stringify(shortcutDraft)
        let globalChanged = false
        for (const item of vlcShortcuts.concat(globalVlcShortcuts)) {
            const value = String(vlcShortcutDraft[item.name] || "")
            if (String(player.config(item.name) || "") !== value) {
                if (item.name.startsWith("global-")) globalChanged = true
                player.setConfig(item.name, value)
            }
        }
        root.close()
        if (globalChanged) Qt.callLater(() => win.toast("Keyboard shortcuts", "Restart VLC to apply global shortcut changes."))
    }
    function displayShortcutText(value) {
        const chord = String(value)
        if (chord.toLowerCase() === "esc") return "esc"
        return chord.length === 1 && /[a-z]/i.test(chord) ? chord.toUpperCase() : chord
    }
    function vlcShortcutValues() {
        try { return JSON.parse(Theme.store.vlcShortcutDefaultsJson) || ({}) }
        catch (error) { return ({}) }
    }
    function rememberVlcShortcutDefaults() {
        if (Object.keys(vlcShortcutValues()).length) return
        const values = ({})
        for (const item of vlcShortcuts) values[item.name] = String(player.config(item.name) || "")
        Theme.store.vlcShortcutDefaultsJson = JSON.stringify(values)
    }
    function resetVlcShortcuts() {
        const values = Object.assign({}, vlcShortcutDraft)
        const defaults = vlcShortcutValues()
        for (const item of vlcShortcuts)
            if (Object.prototype.hasOwnProperty.call(defaults, item.name)) values[item.name] = defaults[item.name]
        vlcShortcutDraft = values
    }
    function globalVlcShortcutValues() {
        try { return JSON.parse(Theme.store.globalVlcShortcutDefaultsJson) || ({}) }
        catch (error) { return ({}) }
    }
    function rememberGlobalVlcShortcutDefaults() {
        if (Object.keys(globalVlcShortcutValues()).length) return
        const values = ({})
        for (const item of globalVlcShortcuts) values[item.name] = String(player.config(item.name) || "")
        Theme.store.globalVlcShortcutDefaultsJson = JSON.stringify(values)
    }
    function resetGlobalVlcShortcuts() {
        const values = globalVlcShortcutValues()
        const draft = Object.assign({}, vlcShortcutDraft)
        let changed = false
        for (const item of globalVlcShortcuts) {
            if (Object.prototype.hasOwnProperty.call(values, item.name) && String(draft[item.name] || "") !== values[item.name])
                changed = true
            if (Object.prototype.hasOwnProperty.call(values, item.name)) draft[item.name] = values[item.name]
        }
        vlcShortcutDraft = draft
        if (changed) captureNotice = "Restart VLC to apply the restored global shortcuts."
    }
    function saveVlcShortcut(name, chord) {
        const normalizedChord = String(chord).toLowerCase()
        for (const id of Object.keys(Theme.defaultShortcuts)) {
            if (neoShortcutKeys(id).some(key => String(key).toLowerCase() === normalizedChord)) return false
        }
        const counterpart = name.startsWith("global-key-")
                          ? "key-" + name.substring("global-key-".length)
                          : "global-key-" + name.substring("key-".length)
        for (const item of vlcShortcuts.concat(globalVlcShortcuts)) {
            if (item.name !== name && item.name !== counterpart && vlcShortcutText(item.name).toLowerCase() === normalizedChord) return false
        }
        const values = Object.assign({}, vlcShortcutDraft)
        values[name] = chord
        vlcShortcutDraft = values
        const saved = vlcShortcutText(name) === chord
        if (saved && name.startsWith("global-key-"))
            captureNotice = "Restart VLC to activate the changed global shortcut."
        return saved
    }

    readonly property var shortcuts: [
        { id: "playPause", label: "Play / Pause" }, { id: "fullscreen", label: "Toggle fullscreen" },
        { id: "seekBack", label: "Seek backward" }, { id: "seekForward", label: "Seek forward" },
        { id: "veryShortBack", label: "Very short seek backward" }, { id: "veryShortForward", label: "Very short seek forward" },
        { id: "longBack", label: "Long seek backward" }, { id: "longForward", label: "Long seek forward" },
        { id: "volumeDown", label: "Volume down" }, { id: "volumeUp", label: "Volume up" },
        { id: "previous", label: "Previous item" }, { id: "next", label: "Next item" },
        { id: "mute", label: "Mute" }, { id: "subtitles", label: "Cycle subtitle track" },
        { id: "audio", label: "Cycle audio track" }, { id: "subtitleEarlier", label: "Subtitle earlier" },
        { id: "subtitleLater", label: "Subtitle later" }, { id: "audioEarlier", label: "Audio earlier" },
        { id: "audioLater", label: "Audio later" }, { id: "speedDown", label: "Speed down" },
        { id: "speedUp", label: "Speed up" }, { id: "speedNormal", label: "Normal speed" },
        { id: "previousFrame", label: "Previous frame" }, { id: "nextFrame", label: "Next frame" },
        { id: "queue", label: "Show / hide queue" },
        { id: "library", label: "Show / hide library" }, { id: "pinFolder", label: "Pin / unpin current folder" },
        { id: "settingsPanel", label: "Settings panel" },
        { id: "hideUi", label: "Hide the whole UI" }, { id: "bookmark", label: "Add bookmark" },
        { id: "snapshot", label: "Take a snapshot" }, { id: "record", label: "Record" },
        { id: "stop", label: "Stop" }, { id: "openFile", label: "Open file" },
        { id: "openNetwork", label: "Open network stream" }, { id: "openClipboard", label: "Open from clipboard" },
        { id: "preferences", label: "Preferences" }, { id: "quit", label: "Quit" },
        { id: "shortcuts", label: "This list" }
    ]
    readonly property var vlcShortcuts: [
        { name: "key-toggle-fullscreen", label: "Toggle fullscreen" }, { name: "key-leave-fullscreen", label: "Leave fullscreen" },
        { name: "key-play-pause", label: "Play / pause" }, { name: "key-pause", label: "Pause" },
        { name: "key-play", label: "Play" },
        { name: "key-vol-up", label: "Volume up" }, { name: "key-vol-down", label: "Volume down" },
        { name: "key-vol-mute", label: "Mute" }, { name: "key-audio-track", label: "Cycle audio track" },
        { name: "key-audiodevice-cycle", label: "Cycle audio device" }, { name: "key-subtitle-track", label: "Cycle subtitle track" },
        { name: "key-subtitle-toggle", label: "Toggle subtitles" }, { name: "key-subtitle-revtrack", label: "Previous subtitle track" },
        { name: "key-snapshot", label: "Take a snapshot" }, { name: "key-record", label: "Record" },
        { name: "key-stop", label: "Stop playback" }, { name: "key-next", label: "Next item" },
        { name: "key-prev", label: "Previous item" }, { name: "key-jump-extrashort", label: "Very short jump backward" },
        { name: "key-jump+extrashort", label: "Very short jump forward" }, { name: "key-jump-short", label: "Short jump backward" },
        { name: "key-jump+short", label: "Short jump forward" }, { name: "key-jump-medium", label: "Medium jump backward" },
        { name: "key-jump+medium", label: "Medium jump forward" }, { name: "key-jump-long", label: "Long jump backward" },
        { name: "key-jump+long", label: "Long jump forward" }, { name: "key-nav-activate", label: "Activate navigation" },
        { name: "key-nav-up", label: "Navigate up" }, { name: "key-nav-down", label: "Navigate down" },
        { name: "key-nav-left", label: "Navigate left" }, { name: "key-nav-right", label: "Navigate right" },
        { name: "key-disc-menu", label: "Show DVD menu" }, { name: "key-title-prev", label: "Previous title" },
        { name: "key-title-next", label: "Next title" }, { name: "key-chapter-prev", label: "Previous chapter" },
        { name: "key-chapter-next", label: "Next chapter" }, { name: "key-aspect-ratio", label: "Cycle aspect ratio" },
        { name: "key-crop", label: "Cycle crop" }, { name: "key-zoom", label: "Cycle zoom" },
        { name: "key-deinterlace", label: "Toggle deinterlacing" }, { name: "key-deinterlace-mode", label: "Cycle deinterlace mode" },
        { name: "key-wallpaper", label: "Toggle wallpaper mode" },
        { name: "key-subdelay-up", label: "Subtitle delay later" },
        { name: "key-subdelay-down", label: "Subtitle delay earlier" }, { name: "key-subsync-reset", label: "Reset audio and subtitle sync" },
        { name: "key-audiodelay-up", label: "Audio delay later" }, { name: "key-audiodelay-down", label: "Audio delay earlier" },
        { name: "key-faster", label: "Increase playback speed" }, { name: "key-slower", label: "Decrease playback speed" },
        { name: "key-rate-faster-fine", label: "Increase speed slightly" }, { name: "key-rate-slower-fine", label: "Decrease speed slightly" },
        { name: "key-rate-normal", label: "Normal playback speed" }, { name: "key-frame-next", label: "Next frame" },
        { name: "key-loop", label: "Cycle repeat mode"}, { name: "key-random", label: "Toggle random playback" },
        { name: "key-position", label: "Show playback position" }, { name: "key-quit", label: "Quit VLC" },
        { name: "key-intf-show", label: "Show interface" }, { name: "key-intf-popup-menu", label: "Interface menu" },
        { name: "key-toggle-autoscale", label: "Toggle autoscaling" }, { name: "key-incr-scalefactor", label: "Increase video size" },
        { name: "key-decr-scalefactor", label: "Decrease video size" }, { name: "key-unzoom", label: "Reset video zoom" },
        { name: "key-crop-top", label: "Crop one pixel from top" }, { name: "key-uncrop-top", label: "Restore one pixel at top" },
        { name: "key-crop-left", label: "Crop one pixel from left" }, { name: "key-uncrop-left", label: "Restore one pixel at left" },
        { name: "key-crop-bottom", label: "Crop one pixel from bottom" }, { name: "key-uncrop-bottom", label: "Restore one pixel at bottom" },
        { name: "key-crop-right", label: "Crop one pixel from right" }, { name: "key-uncrop-right", label: "Restore one pixel at right" },
        { name: "key-subsync-markaudio", label: "Mark audio sync point" }, { name: "key-subsync-marksub", label: "Mark subtitle sync point" },
        { name: "key-subsync-apply", label: "Apply subtitle sync" }, { name: "key-subpos-up", label: "Move subtitles up" },
        { name: "key-subpos-down", label: "Move subtitles down" }, { name: "key-program-sid-next", label: "Next program" },
        { name: "key-program-sid-prev", label: "Previous program" }, { name: "key-viewpoint-fov-in", label: "Shrink field of view" },
        { name: "key-viewpoint-fov-out", label: "Expand field of view" },
        { name: "key-viewpoint-roll-clock", label: "Rotate viewpoint clockwise" },
        { name: "key-viewpoint-roll-anticlock", label: "Rotate viewpoint counterclockwise" },
        { name: "key-zoom-quarter", label: "Quarter video size" },
        { name: "key-zoom-half", label: "Half video size" }, { name: "key-zoom-original", label: "Original video size" },
        { name: "key-zoom-double", label: "Double video size" }, { name: "key-subtitle-text-scale-normal", label: "Reset subtitle size" },
        { name: "key-subtitle-text-scale-up", label: "Increase subtitle size" },
        { name: "key-subtitle-text-scale-down", label: "Decrease subtitle size" },
        { name: "key-intf-boss", label: "Boss key" }, { name: "key-clear-playlist", label: "Clear playlist" },
        { name: "key-set-bookmark1", label: "Set bookmark 1" }, { name: "key-set-bookmark2", label: "Set bookmark 2" },
        { name: "key-set-bookmark3", label: "Set bookmark 3" }, { name: "key-set-bookmark4", label: "Set bookmark 4" },
        { name: "key-set-bookmark5", label: "Set bookmark 5" }, { name: "key-set-bookmark6", label: "Set bookmark 6" },
        { name: "key-set-bookmark7", label: "Set bookmark 7" }, { name: "key-set-bookmark8", label: "Set bookmark 8" },
        { name: "key-set-bookmark9", label: "Set bookmark 9" }, { name: "key-set-bookmark10", label: "Set bookmark 10" },
        { name: "key-play-bookmark1", label: "Play bookmark 1" }, { name: "key-play-bookmark2", label: "Play bookmark 2" },
        { name: "key-play-bookmark3", label: "Play bookmark 3" }, { name: "key-play-bookmark4", label: "Play bookmark 4" },
        { name: "key-play-bookmark5", label: "Play bookmark 5" }, { name: "key-play-bookmark6", label: "Play bookmark 6" },
        { name: "key-play-bookmark7", label: "Play bookmark 7" }, { name: "key-play-bookmark8", label: "Play bookmark 8" },
        { name: "key-play-bookmark9", label: "Play bookmark 9" }, { name: "key-play-bookmark10", label: "Play bookmark 10" }
    ]
    readonly property var globalVlcShortcuts: vlcShortcuts.map(item => ({
        name: "global-" + item.name,
        label: item.label
    }))
    readonly property var basicVlcShortcutNames: [
        { name: "key-toggle-fullscreen", label: "Toggle fullscreen" },
        { name: "key-leave-fullscreen", label: "Exit fullscreen / close dialog" },
        { name: "key-position", label: "Show playback position and time" },
        { name: "key-intf-show", label: "Show interface controls in fullscreen" }
    ]
    readonly property var playbackVlcShortcutNames: [
        { name: "key-play-pause", label: "Play / pause" },
        { name: "key-stop", label: "Stop playback" },
        { name: "key-next", label: "Next track" },
        { name: "key-prev", label: "Previous track" },
        { name: "key-program-sid-next", label: "Next program / Service ID" }
    ]
    readonly property var basicVlcShortcuts: basicVlcShortcutNames.map(spec => {
        const item = vlcShortcuts.find(entry => entry.name === spec.name)
        return item ? ({ name: item.name, label: spec.label }) : null
    }).filter(Boolean)
    readonly property var playbackVlcShortcuts: playbackVlcShortcutNames.map(spec => {
        const item = vlcShortcuts.find(entry => entry.name === spec.name)
        return item ? ({ name: item.name, label: spec.label }) : null
    }).filter(Boolean)
    readonly property var otherVlcShortcuts: vlcShortcuts.filter(item => !basicVlcShortcutNames.some(spec => spec.name === item.name)
                                                                      && !playbackVlcShortcutNames.some(spec => spec.name === item.name))

    onOpened: {
        recordingAction = ""
        captureError = ""
        shortcutSearch = ""
        shortcutScope = "all"
        loadDrafts()
        rememberVlcShortcutDefaults()
        rememberGlobalVlcShortcutDefaults()
    }
    onClosed: recordingAction = ""
    onRecordingActionChanged: if (recordingAction.length && visible) keyCapture.forceActiveFocus()

    component ShortcutCell: Rectangle {
        id: cell
        property string value
        property bool recording: false
        signal activated()
        implicitWidth: 240
        implicitHeight: 34
        radius: 5
        color: pointer.containsMouse ? Theme.hover : Theme.field
        border.width: activeFocus ? 1 : 0
        border.color: Theme.accent
        activeFocusOnTab: true
        Accessible.name: cell.recording ? "Press a key" : (cell.value === "Unassigned" ? "Unassigned" : cell.value)
        Accessible.role: Accessible.Button
        Accessible.focusable: true
        Behavior on color { ColorAnimation { duration: 90 } }
        NText {
            anchors.left: parent.left
            anchors.right: editIcon.left
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignHCenter
            text: cell.recording ? "Press a key…" : (cell.value === "Unassigned" ? "" : cell.value)
            color: Theme.text
            elide: Text.ElideRight
        }
        Icon {
            id: editIcon
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            name: "edit"
            size: 14
            color: Theme.icon
        }
        MouseArea {
            id: pointer
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: cell.activated()
        }
        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                cell.activated()
                event.accepted = true
            }
        }
    }

    component VlcShortcutRow: RowLayout {
        required property var modelData
        Layout.columnSpan: shortcutGrid.columns
        Layout.fillWidth: true
        spacing: 0
        NText { text: modelData.label; dim: true; Layout.fillWidth: true; Layout.preferredWidth: 350; Layout.maximumWidth: 350; Layout.minimumWidth: 180 }
        Item { Layout.preferredWidth: 30; Layout.minimumWidth: 12 }
        ShortcutCell {
            objectName: "vlc-shortcut-edit-" + modelData.name
            Layout.preferredWidth: 270
            Layout.minimumWidth: 100
            value: root.displayShortcutText(root.vlcShortcutText(modelData.name))
            recording: root.recordingAction === "vlc:" + modelData.name
            onActivated: root.beginRecording("vlc:" + modelData.name)
        }
        Item { Layout.preferredWidth: 88; Layout.minimumWidth: 24 }
        ShortcutCell {
            objectName: "global-vlc-shortcut-edit-" + modelData.name
            Layout.preferredWidth: 270
            Layout.minimumWidth: 100
            value: root.displayShortcutText(root.vlcShortcutText("global-" + modelData.name))
            recording: root.recordingAction === "vlc:global-" + modelData.name
            onActivated: root.beginRecording("vlc:global-" + modelData.name)
        }
    }

    Flickable {
        id: shortcutsScroll
        width: root.width - 36
        height: Math.max(60, root.height - 112)
        interactive: true
        clip: true
        contentWidth: width
        contentHeight: shortcutGrid.implicitHeight
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        GridLayout {
            id: shortcutGrid
            width: shortcutsScroll.width
            columns: 3
            columnSpacing: 16
            rowSpacing: 13
            Item {
                Layout.columnSpan: 2
                Layout.fillWidth: true
                implicitHeight: 30
                NField {
                    id: shortcutSearchField
                    objectName: "shortcut-search"
                    anchors.fill: parent
                    leftPadding: 34
                    placeholderText: "Search Keyboard Shortcuts..."
                    text: root.shortcutSearch
                    onTextEdited: root.shortcutSearch = text
                }
                Icon {
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    name: "search"
                    size: 16
                    color: Theme.icon
                }
            }
            NCombo {
                objectName: "shortcut-search-scope"
                Layout.preferredWidth: 200
                Layout.minimumWidth: 140
                model: [
                    { label: "All Fields", value: "all" },
                    { label: "Action", value: "action" },
                    { label: "Hotkey", value: "hotkey" },
                    { label: "Global Hotkey", value: "global" }
                ]
                current: root.shortcutScope
                accessibleName: "Search fields"
                onPicked: (value) => root.shortcutScope = String(value)
            }
            RowLayout {
                Layout.columnSpan: shortcutGrid.columns
                Layout.fillWidth: true
                Layout.topMargin: 25
                spacing: 0
                NText { text: "Action"; dim: true; Layout.fillWidth: true; Layout.preferredWidth: 350; Layout.maximumWidth: 350 }
                Item { Layout.preferredWidth: 30; Layout.minimumWidth: 12 }
                NText { text: "Hotkey"; dim: true; horizontalAlignment: Text.AlignHCenter; Layout.preferredWidth: 270 }
                Item { Layout.preferredWidth: 88; Layout.minimumWidth: 24 }
                NText { text: "Global Hotkey"; dim: true; horizontalAlignment: Text.AlignHCenter; Layout.preferredWidth: 270 }
            }
            Rectangle { color: Theme.border; implicitHeight: 1; Layout.columnSpan: shortcutGrid.columns; Layout.fillWidth: true }
            NText { visible: root.filteredShortcuts(root.basicVlcShortcuts).length > 0; text: "Basic"; font.pixelSize: 15; font.bold: true; Layout.columnSpan: shortcutGrid.columns; Layout.fillWidth: true; Layout.topMargin: 12; Layout.bottomMargin: 14 }
            Repeater {
                model: root.filteredShortcuts(root.basicVlcShortcuts)
                delegate: VlcShortcutRow {}
            }
            Rectangle { visible: root.filteredShortcuts(root.basicVlcShortcuts).length > 0; color: Theme.border; implicitHeight: 1; Layout.columnSpan: shortcutGrid.columns; Layout.fillWidth: true; Layout.topMargin: 9 }
            NText { visible: root.filteredShortcuts(root.playbackVlcShortcuts).length > 0; text: "Playback"; font.pixelSize: 15; font.bold: true; Layout.columnSpan: shortcutGrid.columns; Layout.fillWidth: true; Layout.topMargin: 8; Layout.bottomMargin: 10 }
            Repeater {
                model: root.filteredShortcuts(root.playbackVlcShortcuts)
                delegate: VlcShortcutRow {}
            }
            NText { visible: root.filteredShortcuts(root.otherVlcShortcuts).length > 0; text: "Other VLC shortcuts"; font.pixelSize: 15; font.bold: true; Layout.columnSpan: shortcutGrid.columns; Layout.fillWidth: true; Layout.topMargin: 28 }
            Repeater {
                model: root.filteredShortcuts(root.otherVlcShortcuts)
                delegate: VlcShortcutRow {}
            }
            NText { visible: root.filteredShortcuts(root.shortcuts).length > 0; text: "VLC Neo"; font.bold: true; Layout.columnSpan: shortcutGrid.columns; Layout.fillWidth: true }
            Repeater {
                model: root.filteredShortcuts(root.shortcuts)
                delegate: RowLayout {
                    required property var modelData
                    Layout.columnSpan: shortcutGrid.columns
                    Layout.fillWidth: true
                    spacing: 0
                    NText { text: modelData.label; dim: true; Layout.fillWidth: true; Layout.preferredWidth: 350; Layout.maximumWidth: 350; Layout.minimumWidth: 180 }
                    Item { Layout.preferredWidth: 30; Layout.minimumWidth: 12 }
                    ShortcutCell {
                        objectName: "shortcut-edit-" + modelData.id
                        Layout.preferredWidth: 270
                        Layout.minimumWidth: 100
                        value: root.neoShortcutText(modelData.id)
                        recording: root.recordingAction === modelData.id
                        onActivated: root.beginRecording(modelData.id)
                    }
                    Item { Layout.preferredWidth: 88; Layout.minimumWidth: 24 }
                    Item { Layout.preferredWidth: 270; Layout.minimumWidth: 100 }
                }
            }
            NText {
                visible: root.filteredShortcuts(root.shortcuts).length === 0
                      && root.filteredShortcuts(root.basicVlcShortcuts).length === 0
                      && root.filteredShortcuts(root.playbackVlcShortcuts).length === 0
                      && root.filteredShortcuts(root.otherVlcShortcuts).length === 0
                text: "No matching shortcuts"
                dim: true
                Layout.columnSpan: shortcutGrid.columns
                Layout.fillWidth: true
            }
            NText {
                visible: root.captureError.length > 0
                text: root.captureError
                color: Theme.textDim
                Layout.columnSpan: shortcutGrid.columns
                Layout.fillWidth: true
            }
            NText {
                visible: root.captureNotice.length > 0
                text: root.captureNotice
                color: Theme.textDim
                Layout.columnSpan: shortcutGrid.columns
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
            }
            Item { Layout.columnSpan: shortcutGrid.columns; Layout.fillWidth: true; Layout.preferredHeight: 0 }
        }
    }

    TextInput {
        id: keyCapture
        objectName: "shortcut-key-capture"
        width: 1
        height: 1
        opacity: 0
        readOnly: true
        focus: root.recordingAction.length > 0
        Keys.priority: Keys.AfterItem
        Keys.onPressed: (event) => {
            if (!root.recordingAction.length) return
            event.accepted = true
            if (event.key === Qt.Key_Escape) {
                root.recordingAction = ""
                return
            }
            const chord = Theme.shortcutChord(event.key, event.modifiers, event.text)
            if (!chord) return
            if (root.recordingAction.startsWith("vlc:")) {
                const option = root.recordingAction.substring(4)
                if (root.saveVlcShortcut(option, chord)) {
                    root.recordingAction = ""
                    root.captureError = ""
                } else root.captureError = "That shortcut is already assigned. Choose another combination."
                return
            }
            if (root.saveNeoShortcut(root.recordingAction, chord)) {
                root.recordingAction = ""
                root.captureError = ""
            } else root.captureError = "That shortcut is already assigned. Choose another combination."
        }
    }

    footer: [
        NButton { objectName: "shortcut-cancel"; text: "Cancel"; flat: true; onClicked: root.close() },
        NButton { objectName: "shortcut-reset-all"; text: "Reset all shortcuts"; flat: true; onClicked: { root.resetAllShortcuts(); root.recordingAction = ""; root.captureError = "" } },
        Item { Layout.fillWidth: true },
        NButton { objectName: "shortcut-save"; text: "Save"; primary: true; onClicked: root.saveChanges() }
    ]
}
