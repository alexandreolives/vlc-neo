import QtQuick
import QtQuick.Window
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtQuick.Dialogs
import QtCore
import Neo 1.0

ApplicationWindow {
    id: win
    width: 1120
    height: 680
    minimumWidth: 560
    minimumHeight: 340
    visible: true
    flags: Qt.Window | Qt.FramelessWindowHint   // the title bar is ours (Figma design)
    color: Theme.window
    title: player.title.length ? player.title + " - VLC media player" : "VLC media player"
    font.pixelSize: Theme.fontBody

    // ---------------------------------------------------------------- state
    readonly property bool fullscreen: visibility === Window.FullScreen
    property bool uiHidden: false
    property bool pip: false
    property bool libraryOpen: false
    property string navigationPage: "home"
    property string rightPanel: ""          // "" | queue | settings
    property bool videoFill: false
    property bool wasMaximized: false
    readonly property bool autoHideActive: Theme.store.autoHideMode === "always"
                                            || (Theme.store.autoHideMode === "fullscreen" && fullscreen)
    readonly property bool overlayMode: uiHidden || pip
                                        || (autoHideActive && !(fullscreen && Theme.store.showControlsFullscreen))
    property bool topHot: false
    property bool bottomHot: false
    readonly property bool popupsOpen: tracksPopup.visible || contextMenu.visible || mainMenu.visible
    readonly property bool chromeShown: !overlayMode || topHot || bottomHot || popupsOpen
    readonly property bool topShown: !overlayMode || topHot || mainMenu.visible
    readonly property bool bottomShown: !overlayMode || bottomHot || tracksPopup.visible || contextMenu.visible || !player.hasMedia

    function toast(key, message) {
        if (key.length > 0 && !Theme.store.keyOsd) return
        toastItem.show(key, message)
    }
    function setFullscreen(on) {
        if (on === fullscreen) return
        if (on) {
            wasMaximized = visibility === Window.Maximized
            showFullScreen()
        } else {
            wasMaximized ? showMaximized() : showNormal()
        }
        player.setFullscreenState(on)
    }
    function togglePanel(name) { rightPanel = rightPanel === name ? "" : name }
    function navigate(page) {
        navigationPage = page
        switch (page) {
        case "home":
            libraryPanel.section = "home"
            libraryPanel.mediaType = "all"
            libraryOpen = true
            rightPanel = ""
            break
        case "videos":
            libraryPanel.folder = StandardPaths.writableLocation(StandardPaths.MoviesLocation)
            libraryPanel.section = "folder"
            libraryPanel.mediaType = "video"
            libraryOpen = true
            rightPanel = ""
            break
        case "folder":
            libraryPanel.section = "folder"
            libraryPanel.mediaType = "all"
            libraryOpen = true
            rightPanel = ""
            break
        case "streaming":
            networkDialog.open()
            break
        case "playlist":
            togglePanel("queue")
            break
        case "recent":
            libraryPanel.section = "recent"
            libraryPanel.mediaType = "all"
            libraryOpen = true
            rightPanel = ""
            break
        case "add":
            openFilesDialog.open()
            break
        }
    }
    function setPip(on) {
        if (on === pip) return
        if (on && fullscreen) setFullscreen(false)
        pip = on
        platform.setPinned(on)
    }
    function openCustomize() { customizeDialog.open() }
    function focusKeys() { keyCatcher.forceActiveFocus() }

    // Control-bar and title-bar actions
    function run(id, source) {
        switch (id) {
        case "prev": player.previous(); break
        case "next": player.next(); break
        case "play": player.togglePause(); break
        case "stop": player.stop(); break
        case "audio": tracksPopup.openFor("audio", source); break
        case "subtitle": tracksPopup.openFor("spu", source); break
        case "settings": togglePanel("settings"); break
        case "queue": togglePanel("queue"); break
        case "fullscreen": setFullscreen(!fullscreen); break
        case "pip": setPip(!pip); break
        case "record": player.toggleRecord(); break
        case "snapshot": player.snapshot(); break
        case "loop":
            if (player.repeatOne) player.setRepeatOne(false)
            else if (player.loop) { player.setLoop(false); player.setRepeatOne(true) }
            else player.setLoop(true)
            break
        case "shuffle": player.setRandom(!player.random); break
        case "speed": sidePanel.tab = "playback"; rightPanel = "settings"; break
        case "frame": player.frameStep(); break
        case "back10": player.seekBy(-10000); break
        case "fwd10": player.seekBy(10000); break
        case "bookmark": player.addBookmark(); break
        case "hideui": uiHidden = !uiHidden; toast("Ctrl H", uiHidden ? "UI hidden - move to the edges to show controls" : "UI shown"); break
        case "library": libraryOpen = !libraryOpen; break
        case "minimize": showMinimized(); break
        case "maximize": visibility === Window.Maximized ? showNormal() : showMaximized(); break
        case "quit": close(); break
        }
    }

    // --------------------------------------------------------- keyboard
    function handleKey(e) {
        const ctrl = e.modifiers & Qt.ControlModifier
        const shift = e.modifiers & Qt.ShiftModifier
        const k = e.key
        const step = ctrl ? 60000 : (shift ? 3000 : 10000)
        const stepLabel = ctrl ? "1 min" : (shift ? "3 s" : "10 s")
        let label = "", text = ""

        if (k === Qt.Key_Space || k === Qt.Key_MediaTogglePlayPause || k === Qt.Key_MediaPlay) {
            label = "Space"; text = player.playing ? "Pause" : "Play"; player.togglePause()
        } else if (k === Qt.Key_Left) { player.seekBy(-step); label = (ctrl ? "Ctrl " : shift ? "Shift " : "") + "←"; text = "Back " + stepLabel }
        else if (k === Qt.Key_Right) { player.seekBy(step); label = (ctrl ? "Ctrl " : shift ? "Shift " : "") + "→"; text = "Forward " + stepLabel }
        else if (k === Qt.Key_Up) { const v = Math.min(1.25, player.volume + 0.05); player.setVolume(v); label = "↑"; text = "Volume " + Math.round(v * 100) + "%" }
        else if (k === Qt.Key_Down) { const v = Math.max(0, player.volume - 0.05); player.setVolume(v); label = "↓"; text = "Volume " + Math.round(v * 100) + "%" }
        else if (k === Qt.Key_Escape) {
            if (fullscreen) setFullscreen(false)
            else if (pip) setPip(false)
            else if (uiHidden) uiHidden = false
            else if (rightPanel.length) rightPanel = ""
            else if (libraryOpen) libraryOpen = false
            return true
        }
        else if (ctrl && k === Qt.Key_O) { openFilesDialog.open(); return true }
        else if (ctrl && k === Qt.Key_N) { networkDialog.open(); return true }
        else if (ctrl && k === Qt.Key_V) { openClipboard(); return true }
        else if (ctrl && k === Qt.Key_P) { settingsDialog.open(); return true }
        else if (ctrl && k === Qt.Key_B) { player.addBookmark(); return true }
        else if (ctrl && k === Qt.Key_H) { run("hideui"); return true }
        else if (ctrl && k === Qt.Key_E) { togglePanel("settings"); return true }
        else if (ctrl && k === Qt.Key_Q) { close(); return true }
        else if (ctrl) { return player.forwardKey(k, e.modifiers, e.text) }
        else if (shift && k === Qt.Key_S) { player.snapshot(); return true }
        else if (shift && k === Qt.Key_R) { label = "Shift R"; text = player.recording ? "Recording stopped" : "Recording"; player.toggleRecord() }
        else if (k === Qt.Key_F || k === Qt.Key_F11) { label = "F"; text = fullscreen ? "Exit fullscreen" : "Fullscreen"; setFullscreen(!fullscreen) }
        else if (k === Qt.Key_M) { label = "M"; text = player.muted ? "Unmuted" : "Muted"; player.toggleMute() }
        else if (k === Qt.Key_N) { player.next(); label = "N"; text = "Next" }
        else if (k === Qt.Key_P) { player.previous(); label = "P"; text = "Previous" }
        else if (k === Qt.Key_S) { player.stop(); label = "S"; text = "Stop" }
        else if (k === Qt.Key_V) { cycleTrack("spu"); return true }
        else if (k === Qt.Key_B) { cycleTrack("audio"); return true }
        else if (k === Qt.Key_Q) { togglePanel("queue"); label = "Q"; text = rightPanel === "queue" ? "Queue" : "Queue hidden" }
        else if (k === Qt.Key_L) { libraryOpen = !libraryOpen; label = "L"; text = libraryOpen ? "Library" : "Library hidden" }
        else if (k === Qt.Key_E) { player.frameStep(); label = "E"; text = "Next frame" }
        else if (k === Qt.Key_G) { const d = player.subtitleDelay - 50; player.setSubtitleDelay(d); label = "G"; text = "Subtitle delay " + (d / 1000).toFixed(2) + " s" }
        else if (k === Qt.Key_H) { const d = player.subtitleDelay + 50; player.setSubtitleDelay(d); label = "H"; text = "Subtitle delay " + (d / 1000).toFixed(2) + " s" }
        else if (k === Qt.Key_J) { const d = player.audioDelay - 50; player.setAudioDelay(d); label = "J"; text = "Audio delay " + (d / 1000).toFixed(2) + " s" }
        else if (k === Qt.Key_K) { const d = player.audioDelay + 50; player.setAudioDelay(d); label = "K"; text = "Audio delay " + (d / 1000).toFixed(2) + " s" }
        else if (k === Qt.Key_BracketLeft || k === Qt.Key_Minus) { const r = Math.max(0.25, player.rate - 0.1); player.setRate(r); label = e.text; text = "Speed " + r.toFixed(2) + "x" }
        else if (k === Qt.Key_BracketRight || k === Qt.Key_Plus) { const r = Math.min(4, player.rate + 0.1); player.setRate(r); label = e.text; text = "Speed " + r.toFixed(2) + "x" }
        else if (k === Qt.Key_Equal) { player.setRate(1); label = "="; text = "Normal speed" }
        else if (k === Qt.Key_Question || e.text === "?") { shortcutsDialog.open(); return true }
        else { return player.forwardKey(k, e.modifiers, e.text) }

        toast(label, text)
        return true
    }
    function cycleTrack(category) {
        const key = category === "spu" ? "V" : "B"
        const tracks = player.tracks(category)
        if (tracks.length === 0) { toast(key, "No tracks"); return }
        const i = tracks.findIndex(t => t.selected)
        const next = tracks[(i + 1) % tracks.length]
        player.selectTrack(category, next.id)
        toast(key, (category === "spu" ? "Subtitle: " : "Audio: ") + next.name)
    }
    function openClipboard() {
        const text = platform.clipboardText()
        if (text.length === 0) { toast("Ctrl V", "Clipboard is empty"); return }
        player.openLocation(text, true)
        toast("Ctrl V", "Opening from clipboard")
    }

    // --------------------------------------------------------- backend glue
    Connections {
        target: player
        function onNotify(message) { win.toast("", message) }
        function onFullscreenRequested(fs) { win.setFullscreen(fs) }
        function onResumeAvailable(ms) {
            if (Theme.store.resumeMode === "always") player.resume()
            else if (Theme.store.resumeMode === "ask") resumePill.offer(ms)
        }
    }
    Component.onCompleted: {
        if (Theme.store.compactAtStart && !fullscreen) {
            width = 560
            height = 340
        }
        if (!Theme.store.onboarded) onboarding.open()
        focusKeys()
    }

    // ------------------------------------------------------------- layout
    Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true
        Keys.onPressed: (e) => { e.accepted = win.handleKey(e) }

        HoverHandler {
            id: hover
            onPointChanged: {
                const y = point.position.y
                const top = win.overlayMode && y < Theme.topHeight + 28
                if (top) { win.topHot = true; topHide.stop() }
                else if (win.topHot && !topHide.running) topHide.start()
                const hot = win.overlayMode && y > win.height - Theme.barHeight - 44
                if (hot) { win.bottomHot = true; bottomHide.stop() }
                else if (win.bottomHot && !bottomHide.running) bottomHide.start()
                if (win.overlayMode) cursorTimer.restart()
                videoArea.cursorHidden = false
            }
        }
        Timer { id: topHide; interval: Theme.store.hideDelay; onTriggered: win.topHot = false }
        Timer { id: bottomHide; interval: Theme.store.hideDelay; onTriggered: win.bottomHot = false }
        Timer { id: cursorTimer; interval: Theme.store.hideDelay + 800; onTriggered: if (win.overlayMode && !win.chromeShown) videoArea.cursorHidden = true }

        // Main content: either the library browser or the video surface.
        Item {
            id: middle
            anchors.left: navigationRail.visible ? navigationRail.right : parent.left
            anchors.right: parent.right
            anchors.top: win.overlayMode ? parent.top : topBar.bottom
            anchors.bottom: win.overlayMode ? parent.bottom : controlBar.top

            RowLayout {
                anchors.fill: parent
                spacing: 0

                LibraryPanel {
                    id: libraryPanel
                    visible: win.libraryOpen
                    wide: true
                    Layout.fillHeight: true
                    Layout.fillWidth: true
                    onOpenFiles: openFilesDialog.open()
                }

                Rectangle {
                    id: videoArea
                    visible: !win.libraryOpen
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: Theme.videoBg
                    property bool cursorHidden: false

                    MusicView {
                        anchors.fill: parent
                        z: 1
                        visible: player.hasMedia && !player.hasVideo && player.state > 1
                    }
                    HomeView {
                        anchors.fill: parent
                        z: 1
                        visible: !player.hasMedia
                        onOpenFile: openFilesDialog.open()
                        onOpenFolder: openFolderDialog.open()
                        onOpenNetwork: networkDialog.open()
                    }

                    MouseArea {
                        objectName: "video-click-area"
                        anchors.fill: parent
                        z: 2
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        hoverEnabled: true
                        cursorShape: videoArea.cursorHidden ? Qt.BlankCursor : Qt.ArrowCursor
                        // Keep this hit target active even when playback stops:
                        // clicks on the empty video surface must still dismiss
                        // transient track/settings popups.
                        enabled: true
                        onClicked: (e) => {
                            // The video MouseArea consumes clicks before Popup's
                            // outside-press handler can dismiss the track picker.
                            if (tracksPopup.visible) tracksPopup.close()
                            if (win.rightPanel.length) win.rightPanel = ""
                            if (!player.hasMedia) return
                            win.focusKeys()
                            if (e.button === Qt.RightButton) { contextMenu.popup(); return }
                            if (Theme.store.clickToPause) clickTimer.restart()
                        }
                        onDoubleClicked: (e) => {
                            if (e.button !== Qt.LeftButton) return
                            clickTimer.stop()
                            win.setFullscreen(!win.fullscreen)
                        }
                        onWheel: (e) => {
                            const v = Math.max(0, Math.min(1.25, player.volume + (e.angleDelta.y > 0 ? 0.05 : -0.05)))
                            player.setVolume(v)
                            win.toast("Wheel", "Volume " + Math.round(v * 100) + "%")
                        }
                        Timer { id: clickTimer; interval: 230; onTriggered: player.togglePause() }
                    }

                    DropArea {
                        id: fileDrop
                        anchors.fill: parent
                        z: 3
                        keys: ["text/uri-list"]
                        onDropped: (e) => {
                            if (!e.hasUrls) return
                            player.openUrls(e.urls, true)
                            e.acceptProposedAction()
                        }
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 12
                            visible: fileDrop.containsDrag
                            color: "transparent"
                            radius: 8
                            border.width: 2
                            border.color: Theme.accent
                            NText { anchors.centerIn: parent; text: "Drop to play"; color: Theme.accent; font.pixelSize: 18 }
                        }
                    }
                }

                Rectangle { visible: win.rightPanel.length > 0; Layout.fillHeight: true; implicitWidth: 1; color: Theme.border }
                Item {
                    visible: win.rightPanel.length > 0
                    Layout.fillHeight: true
                    Layout.preferredWidth: 360
                    QueuePanel {
                        anchors.fill: parent
                        visible: win.rightPanel === "queue"
                        onAddFiles: enqueueDialog.open()
                        onSavePlaylist: savePlaylistDialog.open()
                    }
                    SidePanel {
                        id: sidePanel
                        anchors.fill: parent
                        visible: win.rightPanel === "settings"
                        onAddSubtitles: subtitleDialog.open()
                    }
                }
            }
        }

        VideoOutput {
            id: video
            parent: win.libraryOpen ? libraryPanel.miniVideoHost : videoArea
            anchors.fill: parent
            fill: win.videoFill
            visible: player.hasVideo
            z: 0
        }

        TopBar {
            id: topBar
            anchors.left: navigationRail.visible ? navigationRail.right : parent.left
            anchors.right: parent.right
            y: win.topShown ? 0 : -height
            opacity: win.topShown ? (win.overlayMode ? 0.96 : 1) : 0
            Behavior on y { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: 140 } }
            onMenuRequested: (source) => {
                const p = source.mapToItem(keyCatcher, 0, source.height + 4)
                mainMenu.popup(p.x, p.y)
            }
            onAction: (id, source) => win.run(id, source)
        }

        ControlBar {
            id: controlBar
            anchors.left: navigationRail.visible ? navigationRail.right : parent.left
            anchors.right: parent.right
            y: win.bottomShown ? parent.height - height : parent.height
            opacity: win.bottomShown ? (win.overlayMode ? 0.96 : 1) : 0
            Behavior on y { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: 140 } }
            onAction: (id, source) => win.run(id, source)
        }

        NavigationRail {
            id: navigationRail
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            currentPage: win.navigationPage
            expanded: win.libraryOpen
            visible: !win.overlayMode || win.chromeShown
            onNavigate: (page) => win.navigate(page)
        }

        ResumePill {
            id: resumePill
            anchors.horizontalCenter: parent.horizontalCenter
            y: (win.bottomShown ? controlBar.y : parent.height) - height - 14
        }
        Toast {
            id: toastItem
            anchors.horizontalCenter: middle.horizontalCenter
            y: (win.topShown ? topBar.y + topBar.height : 0) + 16
        }
    }

    // ------------------------------------------------------------- popups
    TracksPopup {
        id: tracksPopup
        parent: keyCatcher
        onShowPreferences: (tab) => { sidePanel.tab = tab; win.rightPanel = "settings" }
        onAddSubtitles: subtitleDialog.open()
        onClosed: win.focusKeys()
    }

    NMenu {
        id: mainMenu
        parent: keyCatcher
        onClosed: win.focusKeys()
        NMenuItem { text: "Open File…"; iconName: "file-video"; shortcutText: "Ctrl+O"; onTriggered: openFilesDialog.open() }
        NMenuItem { text: "Open Folder…"; iconName: "folder-open"; onTriggered: openFolderDialog.open() }
        NMenuItem { text: "Open Network Stream…"; iconName: "link"; shortcutText: "Ctrl+N"; onTriggered: networkDialog.open() }
        NMenuItem { text: "Open from Clipboard"; iconName: "clipboard"; shortcutText: "Ctrl+V"; onTriggered: win.openClipboard() }
        NMenu {
            id: recentMenu
            title: "Recent Media"
            property var items: []
            onAboutToShow: items = player.recentMedia()
            Instantiator {
                model: recentMenu.items
                delegate: NMenuItem {
                    required property string modelData
                    text: decodeURIComponent(modelData.split("/").pop())
                    onTriggered: player.openLocation(modelData, true)
                }
                onObjectAdded: (index, object) => recentMenu.insertItem(index, object)
                onObjectRemoved: (index, object) => recentMenu.removeItem(object)
            }
            NMenuSeparator {}
            NMenuItem { text: "Clear"; iconName: "trash-2"; onTriggered: player.clearRecentMedia() }
        }
        NMenuSeparator {}
        NMenuItem { text: "Save Queue as Playlist…"; iconName: "list-video"; onTriggered: savePlaylistDialog.open() }
        NMenuItem { text: "Add Subtitles…"; iconName: "captions"; enabled: player.hasMedia; onTriggered: subtitleDialog.open() }
        NMenuSeparator {}
        NMenuItem { text: "Keyboard Shortcuts"; iconName: "keyboard"; shortcutText: "?"; onTriggered: shortcutsDialog.open() }
        NMenuItem { text: "Customize Player…"; iconName: "sliders-horizontal"; onTriggered: customizeDialog.open() }
        NMenuItem { text: "Preferences…"; iconName: "settings"; shortcutText: "Ctrl+P"; onTriggered: settingsDialog.open() }
        NMenuSeparator {}
        NMenuItem { text: "Quit"; iconName: "x"; shortcutText: "Ctrl+Q"; onTriggered: win.close() }
    }

    NMenu {
        id: contextMenu
        parent: keyCatcher
        onClosed: win.focusKeys()
        NMenuItem { text: player.playing ? "Pause" : "Play"; iconName: player.playing ? "pause" : "play"; shortcutText: "Space"; onTriggered: player.togglePause() }
        NMenuItem { text: "Stop"; iconName: "square"; shortcutText: "S"; onTriggered: player.stop() }
        NMenuItem { text: "Previous Item"; iconName: "skip-back"; shortcutText: "P"; onTriggered: player.previous() }
        NMenuItem { text: "Next Item"; iconName: "skip-forward"; shortcutText: "N"; onTriggered: player.next() }
        NMenuItem { text: player.recording ? "Stop Recording" : "Record"; iconName: "circle-dot"; shortcutText: "Shift+R"; onTriggered: player.toggleRecord() }
        NMenuItem { text: win.uiHidden ? "Show UI" : "Hide UI"; iconName: "eye-off"; shortcutText: "Ctrl+H"; onTriggered: win.run("hideui") }
        NMenuSeparator {}
        NMenu {
            id: speedParent
            title: "Playback"
            NMenu {
                id: speedMenu
                title: "Speed"
                Instantiator {
                    model: [0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2, 3]
                    delegate: NMenuItem {
                        required property real modelData
                        text: modelData + "x"
                        checkable: true
                        checked: Math.abs(player.rate - modelData) < 0.01
                        onTriggered: player.setRate(modelData)
                    }
                    onObjectAdded: (index, object) => speedMenu.insertItem(index, object)
                    onObjectRemoved: (index, object) => speedMenu.removeItem(object)
                }
            }
            NMenuItem { text: "Loop All"; checkable: true; checked: player.loop; onTriggered: player.setLoop(!player.loop) }
            NMenuItem { text: "Repeat One"; checkable: true; checked: player.repeatOne; onTriggered: player.setRepeatOne(!player.repeatOne) }
            NMenuItem { text: "Shuffle"; checkable: true; checked: player.random; onTriggered: player.setRandom(!player.random) }
            NMenuItem { text: "Add Bookmark"; iconName: "bookmark"; shortcutText: "Ctrl+B"; onTriggered: player.addBookmark() }
            NMenuItem { text: "Sleep Timer…"; iconName: "clock"; onTriggered: { sidePanel.tab = "playback"; win.rightPanel = "settings" } }
        }
        NMenu {
            title: "Video"
            NMenuItem { text: win.fullscreen ? "Exit Fullscreen" : "Fullscreen"; iconName: "maximize"; shortcutText: "F"; onTriggered: win.setFullscreen(!win.fullscreen) }
            NMenuItem { text: "Picture in Picture"; checkable: true; checked: win.pip; onTriggered: win.setPip(!win.pip) }
            NMenuItem { text: "Take Snapshot"; iconName: "camera"; shortcutText: "Shift+S"; onTriggered: player.snapshot() }
            NMenuItem { text: "Fill Window (crop)"; checkable: true; checked: win.videoFill; onTriggered: win.videoFill = !win.videoFill }
            NMenuItem { text: "Aspect, Rotate, Deinterlace…"; iconName: "film"; onTriggered: { sidePanel.tab = "video"; win.rightPanel = "settings" } }
        }
        NMenu {
            title: "Audio"
            NMenuItem { text: player.muted ? "Unmute" : "Mute"; iconName: "volume-x"; shortcutText: "M"; onTriggered: player.toggleMute() }
            NMenuItem { text: "Tracks & Output…"; iconName: "audio-lines"; onTriggered: { sidePanel.tab = "audio"; win.rightPanel = "settings" } }
        }
        NMenu {
            title: "Subtitle"
            NMenuItem { text: "Add Subtitles…"; iconName: "plus"; onTriggered: subtitleDialog.open() }
            NMenuItem { text: "Next Subtitle Track"; iconName: "captions"; shortcutText: "V"; onTriggered: win.cycleTrack("spu") }
            NMenuItem { text: "Timing & Style…"; iconName: "sliders-horizontal"; onTriggered: { sidePanel.tab = "spu"; win.rightPanel = "settings" } }
        }
        NMenuSeparator {}
        NMenuItem { text: "More Settings"; iconName: "settings"; shortcutText: "Ctrl+E"; onTriggered: win.togglePanel("settings") }
        NMenuItem { text: "Queue"; iconName: "list"; shortcutText: "Q"; onTriggered: win.togglePanel("queue") }
        NMenuItem { text: "Open Media"; iconName: "file-video"; shortcutText: "Ctrl+O"; onTriggered: openFilesDialog.open() }
    }

    // ------------------------------------------------------------ dialogs
    NetworkDialog { id: networkDialog; onClosed: win.focusKeys() }
    SubtitleDialog { id: subtitleDialog; onClosed: win.focusKeys() }
    ShortcutsDialog { id: shortcutsDialog; onClosed: win.focusKeys() }
    SettingsDialog {
        id: settingsDialog
        onClosed: win.focusKeys()
        onShowShortcuts: shortcutsDialog.open()
        onShowOnboarding: onboarding.open()
    }
    Onboarding { id: onboarding; onClosed: win.focusKeys() }
    CustomizeDialog { id: customizeDialog; onClosed: win.focusKeys() }

    FileDialog {
        id: openFilesDialog
        title: "Open Media"
        fileMode: FileDialog.OpenFiles
        currentFolder: player.folderPath.length ? platform.fileUrl(player.folderPath) : StandardPaths.writableLocation(StandardPaths.MoviesLocation)
        onAccepted: player.openUrls(selectedFiles, true)
    }
    FileDialog {
        id: enqueueDialog
        title: "Add to Queue"
        fileMode: FileDialog.OpenFiles
        currentFolder: openFilesDialog.currentFolder
        onAccepted: player.openUrls(selectedFiles, false)
    }
    FolderDialog {
        id: openFolderDialog
        title: "Open Folder"
        currentFolder: openFilesDialog.currentFolder
        onAccepted: player.openUrls([selectedFolder], true)
    }
    FileDialog {
        id: savePlaylistDialog
        title: "Save Queue as Playlist"
        fileMode: FileDialog.SaveFile
        defaultSuffix: "m3u8"
        nameFilters: ["Playlist (*.m3u8)"]
        currentFolder: openFilesDialog.currentFolder
        onAccepted: player.saveQueueAs(selectedFile)
    }
}
