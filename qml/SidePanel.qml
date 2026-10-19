import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtQuick.Dialogs
import Neo 1.0

// Right sidebar replacing VLC's "Adjustments and Effects" window.
// Everything applies live while the video keeps playing.
Rectangle {
    id: root
    property string tab: "spu"
    signal addSubtitles()
    color: Theme.panel

    readonly property var eqPresets: ["off", "flat", "classical", "club", "dance", "fullbass", "fullbasstreble",
        "fulltreble", "headphones", "largehall", "live", "party", "pop", "reggae", "rock", "ska", "soft",
        "softrock", "techno"]
    readonly property var eqLabels: ({ off: "Off", flat: "Flat", classical: "Classical", club: "Club", dance: "Dance",
        fullbass: "Bass Boost", fullbasstreble: "Bass + Treble", fulltreble: "Treble Boost", headphones: "Headphones",
        largehall: "Large Hall", live: "Live", party: "Party", pop: "Pop", reggae: "Reggae", rock: "Rock", ska: "Ska",
        soft: "Soft", softrock: "Soft Rock", techno: "Techno" })

    property var spuTracks: []
    property var audioTracks: []
    property var videoTracks: []
    property var marks: []
    property var chapterList: []
    property int subScale: 100
    property int subMargin: 0
    property string aspect: ""
    property bool fillMode: false
    property string rotation_: ""
    property bool deinterlace: false

    function refresh() {
        spuTracks = player.tracks("spu")
        audioTracks = player.tracks("audio")
        videoTracks = player.tracks("video")
        marks = player.bookmarks()
        chapterList = player.chapters()
        subScale = player.subtitleScale()
        subMargin = player.subtitleMargin()
        aspect = player.aspectRatio()
    }
    onVisibleChanged: if (visible) refresh()
    Connections {
        target: player
        enabled: root.visible
        function onTracksChanged() { root.refresh() }
        function onMediaChanged() { root.refresh() }
        function onBookmarksChanged() { root.marks = player.bookmarks() }
        function onChaptersChanged() { root.chapterList = player.chapters() }
    }

    function delayLabel(ms) { return (ms > 0 ? "+" : "") + (ms / 1000).toFixed(2) + " s" }
    function focusTab(tabId) {
        for (let i = 0; i < tabButtons.count; ++i) {
            const button = tabButtons.itemAt(i)
            if (button && button.tabId === tabId) {
                button.forceActiveFocus()
                return button.activeFocus
            }
        }
        return false
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // Tabs
        RowLayout {
            Layout.fillWidth: true
            spacing: 0
            Repeater {
                id: tabButtons
                model: [{ id: "spu", label: "Subtitles", icon: "captions" },
                        { id: "audio", label: "Audio", icon: "audio-lines" },
                        { id: "video", label: "Video", icon: "film" },
                        { id: "playback", label: "Playback", icon: "gauge" },
                        { id: "marks", label: "Marks", icon: "bookmark" }]
                delegate: Button {
                    id: tabButton
                    required property var modelData
                    property string tabId: modelData.id
                    Layout.fillWidth: true
                    implicitHeight: 46
                    padding: 0
                    focusPolicy: Qt.TabFocus
                    Accessible.name: modelData.label
                    Accessible.description: modelData.label + " settings"
                    objectName: "settings-tab-" + modelData.id
                    onClicked: root.tab = modelData.id
                    background: Rectangle {
                        color: tabButton.hovered ? Theme.hover : "transparent"
                        border.width: tabButton.activeFocus ? 1 : 0
                        border.color: Theme.accent
                        radius: Theme.radiusSmall
                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            height: 2
                            color: root.tab === tabButton.tabId ? Theme.accent : Theme.border
                        }
                    }
                    contentItem: Column {
                        anchors.centerIn: parent
                        spacing: 3
                        Icon {
                            name: tabButton.modelData.icon; size: 16
                            color: root.tab === tabButton.tabId ? Theme.accent : Theme.textDim
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                        NText {
                            text: tabButton.modelData.label; font.pixelSize: 10
                            color: root.tab === tabButton.tabId ? Theme.text : Theme.textDim
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                    }
                }
            }
        }

        ScrollView {
            id: scroll
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: availableWidth
            clip: true

            ColumnLayout {
                width: scroll.availableWidth
                spacing: 10

                Item { implicitHeight: 4 }

                // ---------------------------------------------------- Subtitles
                ColumnLayout {
                    visible: root.tab === "spu"
                    Layout.fillWidth: true
                    Layout.leftMargin: 16
                    Layout.rightMargin: 16
                    spacing: 10

                    SectionTitle { text: "Track" }
                    TrackChooser { tracks: root.spuTracks; category: "spu" }
                    NButton { text: "Add Subtitles"; icon: "plus"; Layout.fillWidth: true; onClicked: root.addSubtitles() }

                    SectionTitle { text: "Timing" }
                    DelayEditor {
                        label: "Subtitle delay"
                        value: player.subtitleDelay
                        onChanged: (v) => player.setSubtitleDelay(v)
                    }
                    NText { text: "Shortcuts: G earlier · H later"; dim: true; font.pixelSize: 11 }

                    SectionTitle { text: "Size" }
                    Chips {
                        id: sizeMode
                        property string mode: [50, 75, 100, 125, 150, 200].indexOf(root.subScale) >= 0 ? "relative" : "precise"
                        model: [{ label: "Relative", value: "relative" }, { label: "Precise", value: "precise" }]
                        current: mode
                        onPicked: (v) => mode = v
                    }
                    Chips {
                        visible: sizeMode.mode === "relative"
                        model: [{ label: "Tiny", value: 50 }, { label: "Small", value: 75 }, { label: "Normal", value: 100 },
                                { label: "Large", value: 125 }, { label: "Larger", value: 150 }, { label: "Huge", value: 200 }]
                        current: root.subScale
                        onPicked: (v) => { player.setSubtitleScale(v); root.subScale = v }
                    }
                    RowLayout {
                        visible: sizeMode.mode === "precise"
                        Layout.fillWidth: true
                        NSlider {
                            Layout.fillWidth: true
                            from: 25; to: 400; stepSize: 5
                            value: root.subScale
                            onMoved: (v) => { player.setSubtitleScale(v); root.subScale = v }
                        }
                        NText { text: root.subScale + " %"; dim: true; Layout.preferredWidth: 48; horizontalAlignment: Text.AlignRight }
                    }

                    SectionTitle { text: "Position" }
                    RowLayout {
                        Layout.fillWidth: true
                        NSlider {
                            Layout.fillWidth: true
                            from: 0; to: 300; stepSize: 5
                            value: root.subMargin
                            onMoved: (v) => { player.setSubtitleMargin(v); root.subMargin = v }
                        }
                        NText { text: root.subMargin + " px"; dim: true; Layout.preferredWidth: 48; horizontalAlignment: Text.AlignRight }
                    }

                    SectionTitle { text: "Appearance" }
                    NText { text: "Applies from the next file."; dim: true; font.pixelSize: 11 }
                    SettingRow {
                        label: "Subtitle font"
                        NField {
                            width: 150
                            text: player.config("freetype-font") || ""
                            placeholderText: "Default"
                            onEditingFinished: player.setConfig("freetype-font", text)
                        }
                    }
                    SettingRow {
                        label: "Text color"
                        Row {
                            spacing: 4
                            Repeater {
                                model: [0xFFFFFF, 0xFFFF00, 0xB8B8B8, 0x00FFFF, 0x00FF00]
                                delegate: Rectangle {
                                    required property int modelData
                                    width: 22; height: 22; radius: 3
                                    color: "#" + ("000000" + modelData.toString(16)).slice(-6)
                                    border.width: 2
                                    border.color: player.config("freetype-color") === modelData ? Theme.accent : Theme.border
                                    MouseArea { anchors.fill: parent; onClicked: { player.setConfig("freetype-color", modelData); parent.border.color = Theme.accent } }
                                }
                            }
                        }
                    }
                    SettingRow {
                        label: "Outline thickness"
                        Chips {
                            property int cur: player.config("freetype-outline-thickness") || 4
                            model: [{ label: "None", value: 0 }, { label: "Thin", value: 2 }, { label: "Normal", value: 4 }, { label: "Thick", value: 6 }]
                            current: cur
                            onPicked: (v) => { player.setConfig("freetype-outline-thickness", v); cur = v }
                        }
                    }
                    SettingRow {
                        label: "Background box"
                        info: "Draw a dark box behind subtitle text."
                        NSwitch {
                            checked: (player.config("freetype-background-opacity") || 0) > 0
                            onToggled: (on) => { player.setConfig("freetype-background-opacity", on ? 160 : 0); checked = on }
                        }
                    }

                    SectionTitle { text: "Default language" }
                    SettingRow {
                        label: "Prefer subtitles in"
                        info: "Comma separated language codes, e.g. ar,en. VLC picks this track automatically for every file."
                        NField {
                            width: 120
                            text: player.config("sub-language") || ""
                            placeholderText: "ar,en"
                            onEditingFinished: player.setConfig("sub-language", text)
                        }
                    }

                    PresetBox {}
                }

                // -------------------------------------------------------- Audio
                ColumnLayout {
                    visible: root.tab === "audio"
                    Layout.fillWidth: true
                    Layout.leftMargin: 16
                    Layout.rightMargin: 16
                    spacing: 10

                    SectionTitle { text: "Track" }
                    TrackChooser { tracks: root.audioTracks; category: "audio" }

                    SectionTitle { text: "Output" }
                    Repeater {
                        model: root.visible && root.tab === "audio" ? player.audioDevices() : []
                        delegate: OptionRow {
                            required property var modelData
                            label: modelData.name
                            selected: modelData.selected
                            onClicked: { player.setAudioDevice(modelData.id); root.tab = ""; root.tab = "audio" }
                        }
                    }

                    SectionTitle { text: "Timing" }
                    DelayEditor {
                        label: "Audio delay"
                        value: player.audioDelay
                        onChanged: (v) => player.setAudioDelay(v)
                    }
                    NText { text: "Shortcuts: J earlier · K later"; dim: true; font.pixelSize: 11 }

                    SectionTitle { text: "Equalizer" }
                    Chips {
                        Layout.fillWidth: true
                        property string cur: player.equalizerPreset()
                        model: root.eqPresets.map(p => ({ label: root.eqLabels[p], value: p }))
                        current: cur
                        onPicked: (v) => { player.setEqualizerPreset(v); cur = v }
                    }

                    SectionTitle { text: "Default language" }
                    SettingRow {
                        label: "Prefer audio in"
                        info: "Comma separated language codes, e.g. ja,en."
                        NField {
                            width: 120
                            text: player.config("audio-language") || ""
                            placeholderText: "en"
                            onEditingFinished: player.setConfig("audio-language", text)
                        }
                    }
                    PresetBox {}
                }

                // -------------------------------------------------------- Video
                ColumnLayout {
                    visible: root.tab === "video"
                    Layout.fillWidth: true
                    Layout.leftMargin: 16
                    Layout.rightMargin: 16
                    spacing: 10

                    SectionTitle { text: "Track" }
                    TrackChooser { tracks: root.videoTracks; category: "video" }

                    SectionTitle { text: "Aspect ratio" }
                    Chips {
                        Layout.fillWidth: true
                        model: [{ label: "Auto", value: "" }, "16:9", "4:3", "21:9", "16:10", "2.35:1", "1:1", "5:4"]
                        current: root.aspect
                        onPicked: (v) => { player.setAspectRatio(v); root.aspect = v }
                    }
                    SectionTitle { text: "Scaling" }
                    Chips {
                        model: [{ label: "Fit", value: false }, { label: "Fill / Crop", value: true }]
                        current: win.videoFill
                        onPicked: (v) => win.videoFill = v
                    }

                    SectionTitle { text: "Rotate & flip" }
                    Chips {
                        Layout.fillWidth: true
                        model: [{ label: "None", value: "" }, { label: "90°", value: "90" }, { label: "180°", value: "180" },
                                { label: "270°", value: "270" }, { label: "Flip H", value: "hflip" }, { label: "Flip V", value: "vflip" }]
                        current: root.rotation_
                        onPicked: (v) => { player.setTransform(v); root.rotation_ = v }
                    }

                    SectionTitle { text: "Picture" }
                    SettingRow {
                        label: "Deinterlace"
                        info: "Removes comb lines on interlaced TV recordings (yadif)."
                        NSwitch { checked: root.deinterlace; onToggled: (on) => { player.setDeinterlace(on); root.deinterlace = on } }
                    }
                    NButton { text: "Take Snapshot"; icon: "camera"; Layout.fillWidth: true; onClicked: player.snapshot() }
                }

                // ----------------------------------------------------- Playback
                ColumnLayout {
                    visible: root.tab === "playback"
                    Layout.fillWidth: true
                    Layout.leftMargin: 16
                    Layout.rightMargin: 16
                    spacing: 10

                    SectionTitle { text: "Speed" }
                    RowLayout {
                        Layout.fillWidth: true
                        NSlider {
                            Layout.fillWidth: true
                            from: 0.25; to: 4; stepSize: 0.05
                            origin: 1
                            value: player.rate
                            onMoved: (v) => player.setRate(v)
                        }
                        NText { text: player.rate.toFixed(2) + "x"; dim: true; Layout.preferredWidth: 48; horizontalAlignment: Text.AlignRight }
                    }
                    Chips {
                        model: [0.5, 0.75, 1, 1.25, 1.5, 2].map(r => ({ label: r + "x", value: r }))
                        current: Math.round(player.rate * 100) / 100
                        onPicked: (v) => player.setRate(v)
                    }

                    SectionTitle { text: "Repeat" }
                    Chips {
                        model: [{ label: "Off", value: "off" }, { label: "All", value: "all" }, { label: "One", value: "one" }]
                        current: player.repeatOne ? "one" : (player.loop ? "all" : "off")
                        onPicked: (v) => { player.setRepeatOne(v === "one"); player.setLoop(v === "all") }
                    }
                    SettingRow {
                        label: "Shuffle"
                        NSwitch { checked: player.random; onToggled: (on) => player.setRandom(on) }
                    }

                    SectionTitle { text: "Sleep timer" }
                    Chips {
                        model: [{ label: "Off", value: 0 }, { label: "15 min", value: 15 }, { label: "30 min", value: 30 },
                                { label: "45 min", value: 45 }, { label: "1 h", value: 60 }, { label: "1.5 h", value: 90 }]
                        current: player.sleepRemaining > 0 ? -1 : 0
                        onPicked: (v) => player.setSleepTimer(v)
                    }
                    NText {
                        visible: player.sleepRemaining > 0
                        text: "Pausing in " + player.formatTime(player.sleepRemaining * 1000)
                        color: Theme.accent
                    }

                    SectionTitle { text: "Frame by frame" }
                    RowLayout {
                        NButton { text: "Next Frame (E)"; icon: "chevron-right"; onClicked: player.frameStep() }
                    }

                    SectionTitle { text: "Media info" }
                    GridLayout {
                        columns: 2
                        columnSpacing: 12
                        rowSpacing: 6
                        Layout.fillWidth: true
                        NText { text: "Title"; dim: true }
                        NText { text: player.title || "—"; Layout.fillWidth: true; wrapMode: Text.WrapAnywhere; maximumLineCount: 2 }
                        NText { text: "Artist"; dim: true; visible: player.artist.length > 0 }
                        NText { text: player.artist; visible: player.artist.length > 0; Layout.fillWidth: true }
                        NText { text: "Duration"; dim: true }
                        NText { text: player.formatTime(player.length) }
                        NText { text: "Location"; dim: true }
                        NText {
                            text: player.mediaUrl.toString().length ? platform.displayPath(player.mediaUrl) : "—"
                            Layout.fillWidth: true; wrapMode: Text.WrapAnywhere; maximumLineCount: 3; font.pixelSize: 11
                        }
                    }
                }

                // ----------------------------------------------------- Bookmarks
                ColumnLayout {
                    visible: root.tab === "marks"
                    Layout.fillWidth: true
                    Layout.leftMargin: 16
                    Layout.rightMargin: 16
                    spacing: 8

                    SectionTitle { text: "Bookmarks" }
                    NButton {
                        text: "Add Bookmark  (Ctrl+B)"; icon: "plus"; Layout.fillWidth: true
                        enabledState: player.hasMedia
                        onClicked: player.addBookmark()
                    }
                    Repeater {
                        model: root.marks
                        delegate: Rectangle {
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: 34
                            radius: Theme.radiusSmall
                            color: markMouse.containsMouse ? Theme.hover : Theme.surface
                            Row {
                                anchors.verticalCenter: parent.verticalCenter
                                x: 10; spacing: 10
                                Icon { name: "bookmark"; size: 14; color: Theme.accent; anchors.verticalCenter: parent.verticalCenter }
                                NText { text: modelData.label; anchors.verticalCenter: parent.verticalCenter }
                            }
                            MouseArea { id: markMouse; anchors.fill: parent; hoverEnabled: true; onClicked: player.jumpTo(modelData.time) }
                            IconButton {
                                anchors.right: parent.right; anchors.rightMargin: 4; anchors.verticalCenter: parent.verticalCenter
                                icon: "trash-2"; iconSize: 14; tip: "Remove"
                                onClicked: player.removeBookmark(modelData.time)
                            }
                        }
                    }
                    NText { visible: root.marks.length === 0; text: "No bookmarks for this file yet."; dim: true }

                    SectionTitle { text: "Chapters" }
                    Repeater {
                        model: root.chapterList
                        delegate: OptionRow {
                            required property var modelData
                            label: modelData.name
                            selected: modelData.selected
                            onClicked: player.selectChapter(modelData.index)
                        }
                    }
                    NText { visible: root.chapterList.length === 0; text: "This file has no chapters."; dim: true }
                }

                Item { implicitHeight: 16 }
            }
        }
    }

    // ------------------------------------------------------------ helpers

    component OptionRow: Rectangle {
        id: opt
        property string label
        property bool selected
        signal clicked()
        Layout.fillWidth: true
        implicitHeight: 32
        radius: Theme.radiusSmall
        color: optMouse.containsMouse ? Theme.hover : "transparent"
        Icon { visible: opt.selected; name: "check"; size: 14; color: Theme.accent; x: 8; anchors.verticalCenter: parent.verticalCenter }
        NText { text: opt.label; x: 30; width: parent.width - 36; anchors.verticalCenter: parent.verticalCenter }
        MouseArea { id: optMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: opt.clicked() }
    }

    component TrackChooser: ColumnLayout {
        id: chooser
        property var tracks: []
        property string category
        Layout.fillWidth: true
        spacing: 0
        Repeater {
            model: chooser.tracks
            delegate: OptionRow {
                required property var modelData
                label: modelData.name
                selected: modelData.selected
                onClicked: { player.selectTrack(chooser.category, modelData.id); root.refresh() }
            }
        }
        NText { visible: chooser.tracks.length === 0; text: "No tracks"; dim: true }
    }

    component DelayEditor: ColumnLayout {
        id: delay
        property string label
        property int value
        signal changed(int value)
        Layout.fillWidth: true
        spacing: 6
        RowLayout {
            Layout.fillWidth: true
            NText { text: delay.label; dim: true; Layout.fillWidth: true }
            NText { text: root.delayLabel(delay.value); color: delay.value !== 0 ? Theme.accent : Theme.text }
        }
        NSlider {
            Layout.fillWidth: true
            from: -10000; to: 10000; stepSize: 50
            origin: 0
            value: delay.value
            onMoved: (v) => delay.changed(v)
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 4
            Repeater {
                model: [{ label: "−0.5 s", step: -500 }, { label: "−50 ms", step: -50 }, { label: "Reset", step: 0 },
                        { label: "+50 ms", step: 50 }, { label: "+0.5 s", step: 500 }]
                delegate: NButton {
                    required property var modelData
                    text: modelData.label
                    flat: modelData.step === 0
                    implicitWidth: 40
                    Layout.fillWidth: true
                    onClicked: delay.changed(modelData.step === 0 ? 0 : delay.value + modelData.step)
                }
            }
        }
    }

    component PresetBox: Rectangle {
        Layout.fillWidth: true
        Layout.topMargin: 8
        implicitHeight: presetCol.implicitHeight + 20
        radius: Theme.radius
        color: Theme.surface
        border.color: player.presetActive ? Theme.accent : Theme.border
        ColumnLayout {
            id: presetCol
            anchors.fill: parent
            anchors.margins: 10
            spacing: 6
            NText {
                text: player.presetActive ? "Preset active for “" + player.folderName + "”" : "Show preset"
                font.weight: Font.DemiBold
                color: player.presetActive ? Theme.accent : Theme.text
            }
            NText {
                text: "Saves delays, subtitle size and chosen tracks for every episode in this folder."
                dim: true; font.pixelSize: 11; wrapMode: Text.WordWrap; Layout.fillWidth: true
            }
            RowLayout {
                NButton { text: player.presetActive ? "Update Preset" : "Save Preset"; primary: true; enabledState: player.folderName.length > 0; onClicked: player.savePresetForFolder() }
                NButton { visible: player.presetActive; text: "Remove"; flat: true; onClicked: player.forgetPresetForFolder() }
            }
        }
    }
}
