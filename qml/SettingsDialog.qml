import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtCore
import Qt.labs.folderlistmodel
import Neo 1.0

// Preferences, regrouped into human categories. Basic options first,
// advanced ones further down the same page — no separate "All" maze.
Modal {
    id: root
    bodyMargin: 8
    width: Math.min(parent ? parent.width - 40 : 1000, 1000)
    height: Math.min(parent ? parent.height - 40 : 820, 820)
    property string page: "general"
    property string categorySearch: ""
    property bool advancedOpen: false
    signal showShortcuts()
    signal showOnboarding()

    readonly property var pages: [
        { id: "general", label: "General", icon: "preferences" },
        { id: "interface", label: "Interface", icon: "interface" },
        { id: "privacy", label: "Privacy", icon: "privacy" },
        { id: "controls", label: "Controls", icon: "hotkeys" },
        { id: "playback", label: "Playback", icon: "playback" },
        { id: "video", label: "Video", icon: "video" },
        { id: "audio", label: "Audio", icon: "audio" },
        { id: "subtitles", label: "Subtitles", icon: "subtitles" },
        { id: "library", label: "Library", icon: "folder" },
        { id: "network", label: "Network", icon: "streaming" },
        { id: "performance", label: "Performance", icon: "preferences" },
        { id: "recording", label: "Recording", icon: "record" },
        { id: "extensions", label: "Extensions", icon: "plugins" }
    ]
    readonly property var categoryGroups: [
        { label: "App", ids: ["general", "interface", "privacy", "controls"] },
        { label: "Media", ids: ["playback", "video", "audio", "subtitles", "library"] },
        { label: "System", ids: ["network", "performance", "recording", "extensions"] }
    ]

    function pagesInGroup(ids) {
        const query = categorySearch.trim().toLowerCase()
        return pages.filter(p => ids.indexOf(p.id) >= 0 && p.label.toLowerCase().includes(query))
    }

    ColumnLayout {
        width: root.width - 36
        height: root.height - 36
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 34
            spacing: 30
            Item {
                Layout.preferredWidth: 190
                Layout.fillHeight: true
                NField {
                    id: categoryField
                    anchors.fill: parent
                    leftPadding: 32
                    placeholderText: "Search"
                    onTextChanged: root.categorySearch = text
                }
                Icon { name: "search"; size: 16; x: 9; anchors.verticalCenter: parent.verticalCenter; color: Theme.textFaint }
            }
            NText { text: "Global Settings"; font.pixelSize: 15; color: Theme.textDim; Layout.fillWidth: true }
            IconButton { icon: "x"; tip: "Close"; onClicked: root.close() }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

        // Category list
        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: 190
            color: Theme.bar
            radius: Theme.radius
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 4
                Repeater {
                    model: root.categoryGroups
                    delegate: ColumnLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 2
                        visible: root.pagesInGroup(modelData.ids).length > 0
                        NText {
                            text: modelData.label
                            visible: root.categorySearch.length === 0
                            color: Theme.textFaint
                            font.pixelSize: 11
                            Layout.leftMargin: 8
                            Layout.topMargin: 6
                            Layout.bottomMargin: 2
                        }
                        Repeater {
                            model: root.pagesInGroup(parent.modelData.ids)
                            delegate: Rectangle {
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: 34
                                radius: Theme.radiusSmall
                                color: root.page === modelData.id || categoryMouse.containsMouse ? Theme.hover : "transparent"
                                Row {
                                    x: 10; spacing: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    Icon { name: modelData.icon; size: 17; color: root.page === modelData.id ? Theme.accent : Theme.icon; anchors.verticalCenter: parent.verticalCenter }
                                    NText { text: modelData.label; color: root.page === modelData.id ? Theme.text : Theme.textDim; anchors.verticalCenter: parent.verticalCenter }
                                }
                                MouseArea { id: categoryMouse; anchors.fill: parent; hoverEnabled: true; onClicked: root.page = modelData.id }
                            }
                        }
                    }
                }
                Item { Layout.fillHeight: true }
            }
        }

        ScrollView {
            id: scroll
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.leftMargin: 30
            contentWidth: availableWidth
            clip: true

            ColumnLayout {
                width: scroll.availableWidth - 12
                spacing: 12

                // ------------------------------------------------ General
                Page_ {
                    id_: "general"
                    SectionTitle { text: "Appearance" }
                    SettingRow {
                        label: "Theme"
                        Chips {
                            chipWidth: 100
                            model: [{ label: "Dark", value: "dark" }, { label: "Light", value: "light" }, { label: "System", value: "system" }]
                            current: Theme.store.mode
                            onPicked: (v) => Theme.store.mode = v
                        }
                    }
                    SettingRow {
                        label: "Accent color"
                        info: "Replaces VLC orange everywhere in the interface."
                        AccentPicker { spacing: 10 }
                    }
                    SectionTitle { text: "Startup" }
                    VlcOption { option: "one-instance"; label: "Allow only one instance"; info: "Opening a file from the file manager reuses the running player." }
                    VlcOption { option: "playlist-enqueue"; label: "Enqueue items into the queue in one instance mode" }
                    SectionTitle { text: "Diagnostics" }
                    VlcOption { option: "file-logging"; label: "Save a log"; info: "Write VLC core messages to a log file." }
                    VlcOption { option: "logfile"; kind: "text"; fieldWidth: 220; label: "Log file" }
                    VlcOption {
                        option: "log-verbose"; kind: "choice"; label: "Log details"
                        choices: [{ label: "Default", value: -1 }, { label: "Information", value: 0 },
                                  { label: "Errors", value: 1 }, { label: "Warnings", value: 2 }, { label: "Debug", value: 3 }]
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 36
                        radius: Theme.radiusSmall
                        color: advancedMouse.containsMouse ? Theme.hover : Theme.raised
                        Row {
                            anchors.centerIn: parent
                            spacing: 8
                            NText { text: "Advanced Options"; color: Theme.textDim; anchors.verticalCenter: parent.verticalCenter }
                            Icon { name: "chevron-right"; size: 14; rotation: root.advancedOpen ? 90 : 0; color: Theme.icon; anchors.verticalCenter: parent.verticalCenter }
                        }
                        MouseArea { id: advancedMouse; anchors.fill: parent; hoverEnabled: true; onClicked: root.advancedOpen = !root.advancedOpen }
                    }
                    ColumnLayout {
                        visible: root.advancedOpen
                        Layout.fillWidth: true
                        VlcOption {
                            option: "verbose"; kind: "choice"; label: "Core output verbosity"
                            choices: [{ label: "Default", value: 0 }, { label: "Verbose", value: 1 }, { label: "Debug", value: 2 }]
                        }
                        SettingRow { label: "Show the welcome screens again"; NButton { text: "Show"; onClicked: { root.close(); root.showOnboarding() } } }
                    }
                }

                // ---------------------------------------------- Interface
                Page_ {
                    id_: "interface"
                    SectionTitle { text: "Behaviour" }
                    SettingRow {
                        label: "Hide controls after"
                        info: "In fullscreen and hidden-UI mode the bars appear when the pointer comes near them."
                        Chips {
                            model: [{ label: "0.6 s", value: 600 }, { label: "1.2 s", value: 1200 }, { label: "2.5 s", value: 2500 }, { label: "5 s", value: 5000 }]
                            current: Theme.store.hideDelay
                            onPicked: (v) => Theme.store.hideDelay = v
                        }
                    }
                    SettingRow { label: "Click on the video to pause"; NSwitch { checked: Theme.store.clickToPause; onToggled: (on) => Theme.store.clickToPause = on } }
                    SettingRow { label: "Show the key pressed with every action"; info: "Shows a small “F · Fullscreen” message, so an accidental key press is easy to undo."; NSwitch { checked: Theme.store.keyOsd; onToggled: (on) => Theme.store.keyOsd = on } }
                    SettingRow {
                        label: "Continue where you left off"
                        Chips {
                            model: [{ label: "Ask", value: "ask" }, { label: "Always", value: "always" }, { label: "Never", value: "never" }]
                            current: Theme.store.resumeMode
                            onPicked: (v) => Theme.store.resumeMode = v
                        }
                    }
                    SettingRow { label: "Control bar layout"; NButton { text: "Customize…"; onClicked: { root.close(); win.openCustomize() } } }
                    SectionTitle { text: "On-screen display" }
                    VlcOption { option: "osd"; label: "Show messages on the video"; info: "VLC's own on-video text: volume, seek position…" }
                    VlcOption { option: "video-title-show"; label: "Show the media title when it starts" }
                    VlcOption { option: "video-title-timeout"; kind: "number"; fieldWidth: 90; label: "Title duration (ms)" }
                }

                // ------------------------------------------------ Privacy
                Page_ {
                    id_: "privacy"
                    SectionTitle { text: "History" }
                    SettingRow { label: "Recent media"; NButton { text: "Clear"; onClicked: { player.clearRecentMedia(); win.toast("", "Recent media cleared") } } }
                    SectionTitle { text: "Network" }
                    VlcOption { option: "metadata-network-access"; label: "Fetch covers and info from the internet"; info: "Album art and metadata lookups for files you play." }
                }

                // ----------------------------------------------- Controls
                Page_ {
                    id_: "controls"
                    SectionTitle { text: "Keyboard" }
                    SettingRow { label: "Shortcuts"; NButton { text: "Show all"; icon: "keyboard"; onClicked: { root.close(); root.showShortcuts() } } }
                    SectionTitle { text: "Mouse" }
                    VlcOption {
                        option: "hotkeys-y-wheel-mode"; kind: "choice"; label: "Mouse wheel over the video"
                        choices: [{ label: "Changes volume", value: 0 }, { label: "Seeks", value: 1 }, { label: "Does nothing", value: -1 }]
                    }
                    VlcOption { option: "extrashort-jump-size"; kind: "number"; fieldWidth: 80; label: "Very short jump (seconds)" }
                    VlcOption { option: "short-jump-size"; kind: "number"; fieldWidth: 80; label: "Short jump (seconds)" }
                    VlcOption { option: "medium-jump-size"; kind: "number"; fieldWidth: 80; label: "Medium jump (seconds)" }
                }

                // ----------------------------------------------- Playback
                Page_ {
                    id_: "playback"
                    SectionTitle { text: "Basic" }
                    VlcOption { option: "start-paused"; label: "Start paused" }
                    VlcOption { option: "play-and-exit"; label: "Quit at the end of the queue" }
                    VlcOption { option: "play-and-pause"; label: "Pause at the end of every item" }
                    VlcOption { option: "playlist-autostart"; label: "Play automatically on startup" }
                    SectionTitle { text: "Advanced" }
                    VlcOption { option: "auto-preparse"; label: "Read durations and tags of queued files" }
                    VlcOption { option: "rate"; kind: "number"; fieldWidth: 80; label: "Default speed" }
                }

                // -------------------------------------------------- Video
                Page_ {
                    id_: "video"
                    SectionTitle { text: "Picture" }
                    VlcOption {
                        option: "deinterlace"; kind: "choice"; label: "Deinterlace"
                        choices: [{ label: "Automatic", value: -1 }, { label: "Off", value: 0 }, { label: "On", value: 1 }]
                    }
                    VlcOption {
                        option: "deinterlace-mode"; kind: "choice"; label: "Deinterlace method"
                        choices: [{ label: "Automatic", value: "auto" }, { label: "Yadif (best)", value: "yadif" }, { label: "Yadif 2x", value: "yadif2x" },
                                  { label: "Blend", value: "blend" }, { label: "Linear", value: "linear" }, { label: "Bob", value: "bob" }]
                    }
                    SectionTitle { text: "Snapshots" }
                    VlcOption { option: "snapshot-path"; kind: "text"; fieldWidth: 240; label: "Save snapshots to" }
                    VlcOption {
                        option: "snapshot-format"; kind: "choice"; label: "Format"
                        choices: [{ label: "PNG", value: "png" }, { label: "JPEG", value: "jpg" }, { label: "TIFF", value: "tiff" }]
                    }
                }

                // -------------------------------------------------- Audio
                Page_ {
                    id_: "audio"
                    SectionTitle { text: "Basic" }
                    VlcOption { option: "audio-language"; kind: "text"; fieldWidth: 120; label: "Preferred audio language"; info: "Language codes, e.g. ja,en" }
                    VlcOption { option: "audio-time-stretch"; label: "Keep the pitch when changing speed" }
                    VlcOption {
                        option: "audio-replay-gain-mode"; kind: "choice"; label: "Volume normalization (ReplayGain)"
                        choices: [{ label: "Off", value: "none" }, { label: "Per track", value: "track" }, { label: "Per album", value: "album" }]
                    }
                    SectionTitle { text: "Advanced" }
                    VlcOption { option: "spdif"; label: "Pass-through to the receiver (S/PDIF / HDMI)" }
                    VlcOption { option: "volume-step"; kind: "number"; fieldWidth: 80; label: "Volume step" }
                }

                // ---------------------------------------------- Subtitles
                Page_ {
                    id_: "subtitles"
                    SectionTitle { text: "Basic" }
                    VlcOption { option: "spu"; label: "Show subtitles" }
                    VlcOption { option: "sub-language"; kind: "text"; fieldWidth: 120; label: "Preferred subtitle language"; info: "Language codes, e.g. ar,en" }
                    VlcOption { option: "sub-autodetect-file"; label: "Load subtitle files found next to the video" }
                    VlcOption {
                        option: "sub-autodetect-fuzzy"; kind: "choice"; fieldWidth: 260
                        label: "Which subtitle files count as a match"
                        info: "How close the subtitle file name must be to the video file name."
                        choices: [{ label: "None", value: 0 },
                                  { label: "Any subtitle file in the folder", value: 1 },
                                  { label: "Files that contain the video name", value: 2 },
                                  { label: "Video name plus extra characters", value: 3 },
                                  { label: "Exact video name only", value: 4 }]
                    }
                    SectionTitle { text: "Text" }
                    VlcOption { option: "freetype-font"; kind: "text"; label: "Font" }
                    VlcOption {
                        option: "freetype-rel-fontsize"; kind: "choice"; label: "Size"
                        choices: [{ label: "Auto", value: 0 }, { label: "Smaller", value: 20 }, { label: "Small", value: 18 },
                                  { label: "Normal", value: 16 }, { label: "Large", value: 12 }, { label: "Larger", value: 6 }]
                    }
                    VlcOption { option: "freetype-fontsize"; kind: "number"; fieldWidth: 80; label: "Exact size in pixels"; info: "Overrides the relative size when not 0." }
                    VlcOption { option: "sub-margin"; kind: "number"; fieldWidth: 80; label: "Distance from the bottom (px)" }
                }

                // ------------------------------------------------ Library
                Page_ {
                    id_: "library"
                    SectionTitle { text: "Pinned folders" }
                    Repeater {
                        model: Theme.store.pinned.length ? Theme.store.pinned.split("\n") : []
                        delegate: SettingRow {
                            required property string modelData
                            label: modelData
                            NButton {
                                text: "Remove"; flat: true
                                onClicked: Theme.store.pinned = Theme.store.pinned.split("\n").filter(p => p !== modelData).join("\n")
                            }
                        }
                    }
                    NText { visible: Theme.store.pinned.length === 0; text: "Pin folders from the library panel (L)."; dim: true }
                    SectionTitle { text: "Playlists" }
                    VlcOption { option: "playlist-tree"; kind: "choice"; label: "Show folders inside playlists"
                        choices: [{ label: "Default", value: 0 }, { label: "Always", value: 1 }, { label: "Never", value: 2 }] }
                }

                // ------------------------------------------------ Network
                Page_ {
                    id_: "network"
                    SectionTitle { text: "Connection" }
                    VlcOption { option: "network-caching"; kind: "number"; fieldWidth: 90; label: "Network buffer (ms)"; info: "Raise it if streams stutter." }
                    VlcOption { option: "http-proxy"; kind: "text"; fieldWidth: 220; label: "HTTP proxy" }
                    VlcOption { option: "http-reconnect"; label: "Reconnect automatically" }
                }

                // -------------------------------------------- Performance
                Page_ {
                    id_: "performance"
                    SectionTitle { text: "Decoding" }
                    VlcOption {
                        option: "avcodec-hw"; kind: "choice"; label: "Hardware decoding"
                        choices: [{ label: "Automatic", value: "any" }, { label: "Off (software)", value: "none" },
                                  { label: "VA-API", value: "vaapi" }, { label: "VDPAU", value: "vdpau" }]
                    }
                    VlcOption { option: "avcodec-threads"; kind: "number"; fieldWidth: 80; label: "Decoding threads (0 = auto)" }
                    VlcOption {
                        option: "avcodec-skiploopfilter"; kind: "choice"; label: "Skip H.264 loop filter (faster, lower quality)"
                        choices: [{ label: "None", value: 0 }, { label: "Non-reference frames", value: 1 }, { label: "Bidirectional", value: 2 },
                                  { label: "Non-key frames", value: 3 }, { label: "All", value: 4 }]
                    }
                    SectionTitle { text: "Caching" }
                    VlcOption { option: "file-caching"; kind: "number"; fieldWidth: 90; label: "Local file buffer (ms)" }
                    VlcOption { option: "disc-caching"; kind: "number"; fieldWidth: 90; label: "Disc buffer (ms)" }
                }

                // ---------------------------------------------- Recording
                Page_ {
                    id_: "recording"
                    SectionTitle { text: "Recording" }
                    VlcOption { option: "input-record-path"; kind: "text"; fieldWidth: 240; label: "Save recordings to" }
                    VlcOption { option: "input-record-native"; label: "Keep the original format" }
                }

                // --------------------------------------------- Extensions
                Page_ {
                    id_: "extensions"
                    SectionTitle { text: "Lua extensions" }
                    NText {
                        Layout.fillWidth: true; wrapMode: Text.WordWrap; dim: true
                        text: "Installable add-ons (extensions, playlist parsers). Plugins are VLC's internal modules and are not listed here."
                    }
                    Repeater {
                        model: FolderListModel {
                            folder: StandardPaths.writableLocation(StandardPaths.GenericDataLocation) + "/vlc/lua/extensions"
                            nameFilters: ["*.lua", "*.luac"]
                        }
                        delegate: SettingRow {
                            required property string fileName
                            label: fileName
                        }
                    }
                    NText { text: "Folder: ~/.local/share/vlc/lua/extensions"; color: Theme.textFaint; font.pixelSize: 11 }
                }
                Item { implicitHeight: 12 }
            }
        }
        }
    }

    component Page_: ColumnLayout {
        property string id_
        visible: root.page === id_
        Layout.fillWidth: true
        spacing: 10
    }
}
