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
    minimumWidth: pip ? 320 : 560
    minimumHeight: pip ? 180 : 340
    visible: true
    flags: windowFlags()   // the title bar is ours (Figma design)
    color: Theme.videoBg
    property bool showMediaTitle: player.config("qt-name-in-title") !== false
    property bool showSystemTray: player.config("qt-system-tray") !== false
    title: showMediaTitle && player.title.length
           ? player.title + " - VLC media player" : "VLC media player"
    font.pixelSize: Theme.fontBody

    // ---------------------------------------------------------------- state
    readonly property bool fullscreen: visibility === Window.FullScreen
    function windowFlags() {
        let result = Qt.Window | Qt.FramelessWindowHint
        if (pip || !!player.config("video-on-top")) result |= Qt.WindowStaysOnTopHint
        return result
    }
    function refreshWindowFlags() { flags = windowFlags() }
    function refreshWindowTitle(show) { showMediaTitle = !!show }
    function refreshSystemTray(show) {
        showSystemTray = !!show
        systemTray.setVisible(showSystemTray)
    }
    property bool uiHidden: false
    property bool pip: false
    property rect pipRestoreGeometry: Qt.rect(0, 0, 0, 0)
    property bool pipWasMaximized: false
    property bool libraryOpen: false
    property bool musicSidebarOpen: false
    property bool folderSidebarOpen: false
    readonly property bool audioVisualizerOpen: audioVisualizerPopup.visible
    readonly property bool audioVisualizerActive: audioVisualizerPopup.selectedMode !== "disabled"
    property string navigationPage: "home"
    property string rightPanel: ""          // "" | queue | settings
    property bool startupVolumePending: true
    property bool restoringWindowGeometry: true
    property bool videoFill: false
    property bool updateCheckRunning: false
    property bool wasMaximized: false
    readonly property bool autoHideActive: Theme.store.autoHideMode === "always"
                                            || (Theme.store.autoHideMode === "fullscreen" && fullscreen)
    readonly property bool overlayMode: uiHidden || pip
                                        || (autoHideActive && !(fullscreen && Theme.store.showControlsFullscreen))
    property bool topHot: false
    property bool bottomHot: false
    readonly property real playlistPaneWidth: Math.max(220, Math.min(375, width * 0.222 - navigationRail.width))
    readonly property real expandedPlaylistPaneWidth: Math.max(playlistPaneWidth,
        Math.min(width * 0.30, playlistPaneWidth * 1.35))
    readonly property bool popupsOpen: tracksPopup.visible || audioVisualizerPopup.visible || contextMenu.visible || mainMenu.visible
    readonly property bool chromeShown: !overlayMode || topHot || bottomHot || popupsOpen
    readonly property bool topShown: !overlayMode || topHot || mainMenu.visible
    readonly property bool bottomShown: !libraryOpen && (!overlayMode || bottomHot || tracksPopup.visible || contextMenu.visible)
    readonly property bool onboardingActive: onboarding.visible
    function saveWindowGeometry() {
        if (restoringWindowGeometry || fullscreen || !Theme.store.rememberWindowGeometry) return
        Theme.store.hasWindowGeometry = true
        Theme.store.windowX = x
        Theme.store.windowY = y
        Theme.store.windowWidth = width
        Theme.store.windowHeight = height
    }
    onClosing: saveWindowGeometry()

    function toast(key, message) {
        if (key.length > 0 && !Theme.store.keyOsd) return
        toastItem.show(key, message)
    }
    function setOnboardingTopHover(hovered) {
        if (hovered) {
            topHot = true
            topHide.stop()
        } else if (topHot && !topHide.running) {
            topHide.start()
        }
    }
    function parsedVersion(version) {
        const match = /^v?(\d+)\.(\d+)\.(\d+)$/.exec(String(version || ""))
        return match ? [Number(match[1]), Number(match[2]), Number(match[3])] : null
    }
    function isVersionNewer(candidate, current) {
        const next = parsedVersion(candidate)
        const installed = parsedVersion(current)
        if (!next || !installed) return false
        for (let i = 0; i < 3; ++i) {
            if (next[i] !== installed[i]) return next[i] > installed[i]
        }
        return false
    }
    function latestStableTag(tags) {
        if (!Array.isArray(tags)) return ""
        let latest = ""
        for (const entry of tags) {
            const name = entry && typeof entry.name === "string" ? entry.name : ""
            if (parsedVersion(name) && (!latest || isVersionNewer(name, latest))) latest = name
        }
        return latest
    }
    function applyUpdateTags(tags) {
        const latest = latestStableTag(tags)
        const available = latest && isVersionNewer(latest, platform.applicationVersion) ? latest : ""
        const changed = available && available !== Theme.store.updateAvailableVersion
        Theme.store.updateAvailableVersion = available
        if (changed) {
            const message = "VLC Neo " + available + " is available on GitHub"
            toast("", message)
            if (visibility === Window.Minimized || !visible)
                systemTray.showNotification("VLC Neo update", message)
        }
        return available
    }
    function checkForUpdates(force) {
        if (!Theme.store.automaticUpdateChecks || updateCheckRunning) return false
        const now = Date.now()
        if (!force && now - Theme.store.lastUpdateCheckAttempt < 86400000) return false
        Theme.store.lastUpdateCheckAttempt = now
        updateCheckRunning = true
        const request = new XMLHttpRequest()
        request.open("GET", "https://api.github.com/repos/AlexandreOlives/vlc-neo/tags?per_page=100")
        request.setRequestHeader("Accept", "application/vnd.github+json")
        request.setRequestHeader("X-GitHub-Api-Version", "2022-11-28")
        request.timeout = 12000
        request.onreadystatechange = function() {
            if (request.readyState !== XMLHttpRequest.DONE) return
            updateCheckRunning = false
            if (request.status !== 200) return
            try {
                applyUpdateTags(JSON.parse(request.responseText))
                Theme.store.lastUpdateCheckSuccess = Date.now()
            } catch (error) {
                console.warn("VLC Neo update check returned invalid tag data")
            }
        }
        request.onerror = function() { updateCheckRunning = false }
        request.ontimeout = function() { updateCheckRunning = false }
        request.send()
        return true
    }
    function applyStartupVolume() {
        if (!startupVolumePending || Theme.store.startupVolumeMode !== "fixed" || !player.hasMedia) return
        player.setVolume(Math.min(Theme.store.startupVolume, Theme.store.maximumVolume))
        startupVolumePending = false
    }
    function chooseStartupVolumeMode(mode) {
        Theme.store.startupVolumeMode = mode
        player.setConfig("volume-save", mode === "remember")
    }
    function setFullscreen(on) {
        if (on === fullscreen) return
        if (on) {
            wasMaximized = visibility === Window.Maximized
            platform.selectFullscreenScreen(win, Number(player.config("qt-fullscreen-screennumber")))
            showFullScreen()
        } else {
            wasMaximized ? showMaximized() : showNormal()
        }
        player.setFullscreenState(on)
    }
    function applyFullscreenPreference() {
        if (player.hasMedia && !!player.config("fullscreen") && !fullscreen)
            setFullscreen(true)
    }
    function notifyMediaChanged() {
        if (!player.hasMedia) return
        const mode = Number(player.config("qt-notification"))
        const minimized = visibility === Window.Minimized || !visible
        if (mode === 2 || (mode === 1 && minimized)) {
            systemTray.showNotification("Now playing", player.title || "VLC Neo")
        }
    }
    function togglePanel(name) { rightPanel = rightPanel === name ? "" : name }
    function navigate(page) {
        musicSidebarOpen = false
        folderSidebarOpen = false
        navigationPage = page
        switch (page) {
        case "home":
            libraryPanel.section = "home"
            libraryPanel.mediaType = "all"
            libraryOpen = false
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
            libraryOpen = false
            rightPanel = ""
            break
        case "music":
            libraryPanel.section = "music"
            libraryPanel.mediaType = "audio"
            mediaLibrary.model.view = "tracks"
            libraryOpen = true
            rightPanel = ""
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
        if (on) {
            tracksPopup.close()
            audioVisualizerPopup.close()
            if (fullscreen) setFullscreen(false)
            pipWasMaximized = visibility === Window.Maximized
            pipRestoreGeometry = Qt.rect(x, y, width, height)
            if (pipWasMaximized) showNormal()
            pip = true
            refreshWindowFlags()
            platform.setPinned(true)
            const area = platform.availableGeometry(win)
            width = Math.min(480, Math.max(320, Math.round(area.width * 0.32)))
            height = Math.round(width * 9 / 16)
            x = area.x + area.width - width - 24
            y = area.y + area.height - height - 24
        } else {
            pip = false
            refreshWindowFlags()
            platform.setPinned(false)
            if (pipWasMaximized) {
                showMaximized()
            } else if (pipRestoreGeometry.width > 0 && pipRestoreGeometry.height > 0) {
                x = pipRestoreGeometry.x
                y = pipRestoreGeometry.y
                width = pipRestoreGeometry.width
                height = pipRestoreGeometry.height
            }
            pipWasMaximized = false
        }
    }
    function openCustomize() { customizeDialog.open() }
    function focusKeys() { keyCatcher.forceActiveFocus() }
    function restoreKeysLater() {
        requestActivate()
        Qt.callLater(() => focusKeys())
    }

    // Control-bar and title-bar actions
    function run(id, source) {
        if (tracksPopup.visible && id !== "audio" && id !== "subtitle")
            tracksPopup.close()
        if (audioVisualizerPopup.visible && id !== "visualizer")
            audioVisualizerPopup.close()
        switch (id) {
        case "prev": player.previous(); break
        case "next": player.next(); break
        case "play": player.togglePause(); break
        case "stop": player.stop(); break
        case "audio": tracksPopup.openFor("audio", source); break
        case "subtitle": tracksPopup.openFor("spu", source); break
        case "visualizer": audioVisualizerPopup.openFor(source); break
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
        case "back15": player.seekBy(-15000); break
        case "fwd15": player.seekBy(15000); break
        case "bookmark": player.addBookmark(); break
        case "chapters": sidePanel.tab = "marks"; togglePanel("settings"); break
        case "bookmarks": sidePanel.tab = "marks"; togglePanel("settings"); break
        case "rightsidebar": togglePanel("settings"); break
        case "vlcsettings": settingsDialog.open(); break
        case "playlists": togglePanel("queue"); break
        case "home":
            libraryOpen = false
            folderSidebarOpen = false
            musicSidebarOpen = false
            rightPanel = ""
            navigationPage = "home"
            break
        case "zoom": sidePanel.tab = "video"; togglePanel("settings"); break
        case "thumbnail":
            Theme.store.showSeekThumbnails = !Theme.store.showSeekThumbnails
            toast("Thumbnail preview", Theme.store.showSeekThumbnails ? "On" : "Off")
            break
        case "favorite":
            if (player.hasMedia) {
                const favorited = Theme.toggleFavorite(player.mediaUrl.toString())
                toast("Favorite", favorited ? "Added to favorites" : "Removed from favorites")
            }
            break
        case "replay": player.jumpTo(0); break
        case "properties": mediaPropertiesDialog.open(); break
        case "quit": close(); break
        case "hideui":
            uiHidden = !uiHidden
            if (uiHidden)
                toastItem.opacity = 0
            else
                toast("Ctrl H", "UI shown")
            break
        case "library":
            musicSidebarOpen = false
            folderSidebarOpen = false
            if (libraryOpen) {
                libraryOpen = false
                navigationPage = "home"
                libraryPanel.section = "home"
            } else {
                libraryPanel.section = "folder"
                libraryPanel.mediaType = "all"
                navigationPage = "folder"
                libraryOpen = true
            }
            break
        case "folder-sidebar":
            libraryOpen = false
            musicSidebarOpen = false
            if (folderSidebarOpen) {
                folderSidebarOpen = false
            } else {
                libraryPanel.section = "folder"
                libraryPanel.mediaType = "video"
                libraryPanel.folder = player.folderPath.length
                    ? platform.fileUrl(player.folderPath)
                    : StandardPaths.writableLocation(StandardPaths.MoviesLocation)
                folderSidebarOpen = true
            }
            rightPanel = ""
            break
        case "music-library":
            libraryOpen = false
            folderSidebarOpen = false
            musicSidebarOpen = !musicSidebarOpen
            libraryPanel.section = "music"
            libraryPanel.mediaType = "all"
            mediaLibrary.model.view = "tracks"
            rightPanel = ""
            break
        case "minimize": showMinimized(); break
        case "maximize": visibility === Window.Maximized ? showNormal() : showMaximized(); break
        case "quit": close(); break
        }
    }

    // --------------------------------------------------------- keyboard
    function jumpStep(ctrl, shift) {
        const option = ctrl ? "long-jump-size" : shift ? "extrashort-jump-size" : "short-jump-size"
        const seconds = Number(player.config(option))
        return isFinite(seconds) && seconds > 0 ? seconds * 1000 : (ctrl ? 60000 : shift ? 3000 : 10000)
    }
    function handleKey(e) {
        const ctrl = e.modifiers & Qt.ControlModifier
        const k = e.key
        const chord = Theme.shortcutChord(k, e.modifiers, e.text)
        const action = Theme.shortcutAction(chord)
        const veryShortJump = action === "veryShortBack" || action === "veryShortForward"
        const longJump = action === "longBack" || action === "longForward"
        const step = veryShortJump ? jumpStep(false, true) : longJump ? jumpStep(true, false) : jumpStep(false, false)
        const stepLabel = longJump ? "1 min" : veryShortJump ? "3 s" : "10 s"
        let label = "", text = ""

        if (k === Qt.Key_Escape) {
            if (tracksPopup.visible) { tracksPopup.close(); return true }
            if (fullscreen) setFullscreen(false)
            else if (pip) setPip(false)
            else if (uiHidden) uiHidden = false
            else if (rightPanel.length) rightPanel = ""
            else if (libraryOpen) libraryOpen = false
            else return player.forwardKey(k, e.modifiers, e.text)
            return true
        }
        if (action === "playPause" || k === Qt.Key_MediaTogglePlayPause) {
            label = "Space"; text = player.playing ? "Pause" : "Play"; player.togglePause()
        } else if (k === Qt.Key_MediaPlay) {
            if (!player.playing) { label = "Media Play"; text = "Play"; player.togglePause() }
            else return true
        } else if (k === Qt.Key_MediaPause) {
            if (player.playing) { label = "Media Pause"; text = "Pause"; player.togglePause() }
            else return true
        } else if (k === Qt.Key_MediaNext) {
            player.next(); label = "Media Next"; text = "Next"
        } else if (k === Qt.Key_MediaPrevious) {
            player.previous(); label = "Media Previous"; text = "Previous"
        } else if (k === Qt.Key_MediaStop) {
            player.stop(); label = "Media Stop"; text = "Stop"
        } else if (action === "seekBack" || action === "veryShortBack" || action === "longBack") {
            player.seekBy(-step); label = chord; text = "Back " + stepLabel
        } else if (action === "seekForward" || action === "veryShortForward" || action === "longForward") {
            player.seekBy(step); label = chord; text = "Forward " + stepLabel
        } else if (action === "volumeUp") { const v = Math.min(Theme.store.maximumVolume, player.volume + 0.05); player.setVolume(v); label = chord; text = "Volume " + Math.round(v * 100) + "%" }
        else if (action === "volumeDown") { const v = Math.max(0, player.volume - 0.05); player.setVolume(v); label = chord; text = "Volume " + Math.round(v * 100) + "%" }
        else if (action === "openFile") { openFilesDialog.open(); return true }
        else if (action === "openNetwork") { networkDialog.open(); return true }
        else if (action === "openClipboard") { openClipboard(); return true }
        else if (action === "preferences") { settingsDialog.open(); return true }
        else if (action === "bookmark") { player.addBookmark(); return true }
        else if (action === "hideUi") { run("hideui"); return true }
        else if (action === "settingsPanel") { togglePanel("settings"); return true }
        else if (action === "quit") { close(); return true }
        else if (action === "snapshot") { player.snapshot(); return true }
        else if (action === "record") { label = chord; text = player.recording ? "Recording stopped" : "Recording"; player.toggleRecord() }
        else if (action === "fullscreen" || k === Qt.Key_F11) { label = chord; text = fullscreen ? "Exit fullscreen" : "Fullscreen"; setFullscreen(!fullscreen) }
        else if (action === "mute") { label = chord; text = player.muted ? "Unmuted" : "Muted"; player.toggleMute() }
        else if (action === "next") { player.next(); label = chord; text = "Next" }
        else if (action === "previous") { player.previous(); label = chord; text = "Previous" }
        else if (action === "stop") { player.stop(); label = chord; text = "Stop" }
        else if (action === "subtitles") { cycleTrack("spu"); return true }
        else if (action === "audio") { cycleTrack("audio"); return true }
        else if (action === "queue") { togglePanel("queue"); label = chord; text = rightPanel === "queue" ? "Queue" : "Queue hidden" }
        else if (action === "library") { libraryOpen = !libraryOpen; label = chord; text = libraryOpen ? "Library" : "Library hidden" }
        else if (action === "previousFrame") {
            const frameDuration = Math.round(1000 / (video.frameRate > 0 ? video.frameRate : 25))
            player.jumpTo(Math.max(0, player.time - frameDuration)); label = chord; text = "Previous frame"
        }
        else if (action === "nextFrame") { player.frameStep(); label = chord; text = "Next frame" }
        else if (action === "subtitleEarlier") { const d = player.subtitleDelay - 50; player.setSubtitleDelay(d); label = chord; text = "Subtitle delay " + (d / 1000).toFixed(2) + " s" }
        else if (action === "subtitleLater") { const d = player.subtitleDelay + 50; player.setSubtitleDelay(d); label = chord; text = "Subtitle delay " + (d / 1000).toFixed(2) + " s" }
        else if (action === "audioEarlier") { const d = player.audioDelay - 50; player.setAudioDelay(d); label = chord; text = "Audio delay " + (d / 1000).toFixed(2) + " s" }
        else if (action === "audioLater") { const d = player.audioDelay + 50; player.setAudioDelay(d); label = chord; text = "Audio delay " + (d / 1000).toFixed(2) + " s" }
        else if (action === "speedDown") { const r = Math.max(0.25, player.rate - 0.1); player.setRate(r); label = chord; text = "Speed " + r.toFixed(2) + "x" }
        else if (action === "speedUp") { const r = Math.min(4, player.rate + 0.1); player.setRate(r); label = chord; text = "Speed " + r.toFixed(2) + "x" }
        else if (action === "speedNormal") { player.setRate(1); label = chord; text = "Normal speed" }
        else if (action === "shortcuts") { shortcutsDialog.open(); return true }
        else if (Theme.isDefaultShortcut(chord) || ctrl) return true
        else return player.forwardKey(k, e.modifiers, e.text)

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
        function onMediaChanged() {
            if (win.navigationPage === "home" && player.hasMedia)
                win.navigationPage = "player"
            win.applyStartupVolume()
            win.applyFullscreenPreference()
            win.notifyMediaChanged()
        }
    }
    Connections {
        target: mediaLibrary
        function onNotify(message) { if (!onboarding.visible) win.toast("", message) }
    }
    Connections {
        target: systemTray
        function onActivated() {
            win.showNormal()
            win.show()
            win.raise()
            win.requestActivate()
        }
    }
    Component.onCompleted: {
        systemTray.setVisible(showSystemTray)
        Qt.callLater(() => checkForUpdates(false))
        if (Theme.store.rememberWindowGeometry && Theme.store.hasWindowGeometry && !Theme.store.compactAtStart) {
            x = Theme.store.windowX
            y = Theme.store.windowY
            width = Theme.store.windowWidth
            height = Theme.store.windowHeight
        }
        Qt.callLater(() => restoringWindowGeometry = false)
        player.setResumeEnabled(Theme.store.resumeMode !== "never")
        Theme.store.showHiddenFiles = !!player.config("show-hiddenfiles")
        startupVolumePending = Theme.store.startupVolumeMode === "fixed"
        player.setConfig("volume-save", Theme.store.startupVolumeMode === "remember")
        applyStartupVolume()
        if (Theme.store.compactAtStart && !fullscreen) {
            width = 560
            height = 340
        }
        if (!Theme.store.onboarded) onboarding.open()
        focusKeys()
    }
    Timer {
        interval: 86400000
        repeat: true
        running: Theme.store.automaticUpdateChecks
        onTriggered: win.checkForUpdates(false)
    }

    // ------------------------------------------------------------- layout
    Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true
        Keys.onPressed: (e) => { e.accepted = win.handleKey(e) }

        Rectangle {
            anchors.fill: parent
            visible: onboarding.themePreviewActive
            color: Theme.onboardingVideoBg
            z: -1
        }

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
            anchors.leftMargin: onboarding.themePreviewActive ? onboarding.themePreviewInset : 0
            anchors.rightMargin: onboarding.themePreviewActive ? onboarding.themePreviewInset : 0
            anchors.top: parent.top
            anchors.topMargin: onboarding.themePreviewActive ? topBar.y + topBar.height
                              : (win.overlayMode || onboarding.visible ? 0 : topBar.height)
            anchors.bottom: parent.bottom
            anchors.bottomMargin: onboarding.themePreviewActive ? parent.height - controlBar.y
                                 : win.overlayMode || (onboarding.visible && onboarding.step === 2)
                                 || win.navigationPage === "home"
                                 ? 0 : parent.height - controlBar.y

            RowLayout {
                anchors.fill: parent
                spacing: 0

                PlaylistsPanel {
                    id: playlistsPanel
                    objectName: "playlists-panel"
                    visible: win.navigationPage === "playlist" && !win.libraryOpen
                    Layout.preferredWidth: playlistsPanel.expanded ? win.expandedPlaylistPaneWidth : win.playlistPaneWidth
                    Layout.fillHeight: true
                    onCreatePlaylist: newPlaylistDialog.open()
                }

                LibraryPanel {
                    id: libraryPanel
                    visible: win.libraryOpen || win.musicSidebarOpen || win.folderSidebarOpen
                    wide: true
                    compactMusicSidebar: win.musicSidebarOpen && !win.libraryOpen
                    compactFolderSidebar: win.folderSidebarOpen && !win.libraryOpen
                    Layout.fillHeight: true
                    Layout.fillWidth: win.libraryOpen
                    Layout.preferredWidth: win.folderSidebarOpen
                        ? Math.max(300, Math.min(500, win.width * 0.20))
                        : (win.musicSidebarOpen ? Math.max(280, Math.min(430, win.width * 0.224)) : 0)
                    onOpenFiles: openFilesDialog.open()
                    onIndexFolder: indexFolderDialog.open()
                }

                Rectangle {
                    id: videoArea
                    visible: !win.libraryOpen
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: onboarding.visible ? Theme.onboardingVideoBg : Theme.videoBg
                    property bool cursorHidden: false

                    MusicView {
                        id: musicView
                        anchors.fill: parent
                        bottomTimelineInset: 0
                        z: 1
                        visible: player.hasMedia && !player.hasVideo && player.state > 1
                    }
                    HomeView {
                        id: homeView
                        anchors.fill: parent
                        z: 1
                        visible: win.navigationPage === "home" && !onboarding.visible && !win.uiHidden
                    }

                    MouseArea {
                        objectName: "video-click-area"
                        anchors.fill: parent
                        z: win.navigationPage === "home" ? 0 : 2
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
                            if (audioVisualizerPopup.visible) audioVisualizerPopup.close()
                            if (win.rightPanel.length) win.rightPanel = ""
                            if (!player.hasMedia) return
                            win.focusKeys()
                            if (e.button === Qt.RightButton) { contextMenu.popup(); return }
                            if (Theme.store.clickToPause) clickTimer.restart()
                        }
                        onDoubleClicked: (e) => {
                            if (e.button !== Qt.LeftButton) return
                            clickTimer.stop()
                            if (Theme.store.doubleClickFullscreen)
                                win.setFullscreen(!win.fullscreen)
                        }
                        onWheel: (e) => {
                            const vertical = e.angleDelta.y
                            const horizontal = e.angleDelta.x
                            if (e.modifiers & Qt.ControlModifier) {
                                if (player.forwardWheel(horizontal, vertical, e.modifiers)) {
                                    e.accepted = true
                                    return
                                }
                            }
                            const delta = vertical !== 0 ? vertical : horizontal
                            const option = vertical !== 0 ? "hotkeys-y-wheel-mode" : "hotkeys-x-wheel-mode"
                            const mode = Number(player.config(option))
                            if (mode === 0) {
                                const v = Math.max(0, Math.min(Theme.store.maximumVolume, player.volume + (delta > 0 ? 0.05 : -0.05)))
                                player.setVolume(v)
                                win.toast("Wheel", "Volume " + Math.round(v * 100) + "%")
                            } else if (mode === 2 || mode === 3) {
                                const direction = (delta > 0 ? 1 : -1) * (mode === 3 ? -1 : 1)
                                player.seekBy(direction * win.jumpStep(false, false))
                            }
                            e.accepted = true
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
            onboardingMode: onboarding.visible
            compactPreview: onboarding.themePreviewActive
            parent: onboarding.visible && !onboarding.themePreviewActive
                    ? onboarding.chromeLayer : keyCatcher
            z: onboarding.visible && !onboarding.themePreviewActive ? 1 : 0
            visible: !onboarding.visible || onboarding.themePreviewActive || win.topHot || opacity > 0.01
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: (parent === keyCatcher && navigationRail.visible ? navigationRail.width : 0)
                                + (onboarding.themePreviewActive ? onboarding.themePreviewInset : 0)
            anchors.rightMargin: onboarding.themePreviewActive ? onboarding.themePreviewInset : 0
            y: onboarding.themePreviewActive ? onboarding.themePreviewTop
               : onboarding.visible ? (win.topHot ? 0 : -height)
               : (win.topShown ? 0 : -height)
            opacity: onboarding.visible && !onboarding.themePreviewActive ? (win.topHot ? 1 : 0)
                     : win.topShown ? (win.overlayMode ? 0.96 : 1) : 0
            Behavior on y { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: 140 } }
            onMenuRequested: (source) => {
                const p = source.mapToItem(keyCatcher, 0, source.height + 4)
                mainMenu.popup(p.x, p.y)
            }
            onAction: (id, source) => win.run(id, source)
            onOnboardingHoverChanged: (hovered) => win.setOnboardingTopHover(hovered)
        }

        ControlBar {
            id: controlBar
            anchors.left: navigationRail.visible ? navigationRail.right : parent.left
            anchors.right: parent.right
            anchors.leftMargin: onboarding.themePreviewActive ? onboarding.themePreviewInset : 0
            anchors.rightMargin: onboarding.themePreviewActive ? onboarding.themePreviewInset : 0
            height: onboarding.visible && onboarding.step === 1 ? 32 : implicitHeight
            y: onboarding.themePreviewActive
               ? onboarding.themePreviewTop + onboarding.themePreviewHeight - height
               : win.bottomShown
               ? parent.height - height - (onboarding.visible && onboarding.step === 1
                                             ? parent.height * (onboarding.compactLayout ? 0.23 : 0.14) : 0)
               : parent.height
            opacity: win.bottomShown ? (win.overlayMode ? 0.96 : 1) : 0
            visible: (!onboarding.visible || onboarding.step === 1)
                     && (win.navigationPage !== "home" || (onboarding.visible && onboarding.step === 1))
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
            expanded: win.libraryOpen || win.navigationPage === "home"
            visible: !onboarding.visible && (!win.overlayMode || win.chromeShown)
                     && (win.navigationPage !== "player" || win.libraryOpen || win.rightPanel.length > 0
                         || win.musicSidebarOpen || win.folderSidebarOpen)
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
        onShowPreferences: (tab) => { sidePanel.tab = tab; win.rightPanel = "settings" }
        onAddSubtitles: subtitleDialog.open()
        onClosed: win.focusKeys()
    }

    AudioVisualizerPopup {
        id: audioVisualizerPopup
        onClosed: win.focusKeys()
    }

    NMenu {
        id: mainMenu
        parent: keyCatcher
        onClosed: win.focusKeys()
        NMenuItem { text: "Open File…"; iconName: "file"; shortcutText: "Ctrl+O"; onTriggered: openFilesDialog.open() }
        NMenuItem { text: "Open Folder…"; iconName: "folder"; onTriggered: openFolderDialog.open() }
        NMenuItem { text: "Open Network Stream…"; iconName: "link"; shortcutText: "Ctrl+N"; onTriggered: networkDialog.open() }
        NMenuItem { text: "Open from Clipboard"; iconName: "clipboard"; shortcutText: "Ctrl+V"; onTriggered: win.openClipboard() }
        NMenuItem { text: "Convert…"; iconName: "refresh-cw"; enabled: player.hasMedia; onTriggered: convertDialog.open() }
        NMenuItem { text: "Stream to Device…"; iconName: "streaming"; enabled: player.hasMedia; onTriggered: streamDialog.open() }
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
        NMenuItem { text: "Open Media"; iconName: "file"; shortcutText: "Ctrl+O"; onTriggered: openFilesDialog.open() }
    }

    // ------------------------------------------------------------ dialogs
    NetworkDialog { id: networkDialog; onClosed: win.focusKeys() }
    MediaPropertiesDialog { id: mediaPropertiesDialog; onClosed: win.focusKeys() }
    ConvertDialog { id: convertDialog; onClosed: win.focusKeys() }
    StreamDialog { id: streamDialog; onClosed: win.focusKeys() }
    SubtitleDialog { id: subtitleDialog; onClosed: win.focusKeys() }
    ShortcutsDialog { id: shortcutsDialog; onClosed: win.focusKeys() }
    SettingsDialog {
        id: settingsDialog
        onClosed: win.focusKeys()
        onShowShortcuts: shortcutsDialog.open()
        onShowOnboarding: onboarding.open()
    }
    Onboarding {
        id: onboarding
        onClosed: win.focusKeys()
        onTopEdgeHoverChanged: (hovered) => win.setOnboardingTopHover(hovered)
    }
    CustomizeDialog { id: customizeDialog; onClosed: win.focusKeys() }
    NewPlaylistDialog { id: newPlaylistDialog; onClosed: win.focusKeys() }

    FileDialog {
        id: openFilesDialog
        title: "Open Media"
        fileMode: FileDialog.OpenFiles
        currentFolder: player.folderPath.length ? platform.fileUrl(player.folderPath) : StandardPaths.writableLocation(StandardPaths.MoviesLocation)
        onAccepted: player.openUrls(selectedFiles, true)
        onVisibleChanged: if (!visible) win.restoreKeysLater()
    }
    FileDialog {
        id: enqueueDialog
        title: "Add to Queue"
        fileMode: FileDialog.OpenFiles
        currentFolder: openFilesDialog.currentFolder
        onAccepted: player.openUrls(selectedFiles, false)
        onVisibleChanged: if (!visible) win.restoreKeysLater()
    }
    FolderDialog {
        id: openFolderDialog
        title: "Open Folder"
        currentFolder: openFilesDialog.currentFolder
        onAccepted: player.openUrls([selectedFolder], true)
        onVisibleChanged: if (!visible) win.restoreKeysLater()
    }
    FolderDialog {
        id: indexFolderDialog
        title: "Add Folder to Music Library"
        currentFolder: StandardPaths.writableLocation(StandardPaths.MusicLocation)
        onAccepted: mediaLibrary.addFolder(selectedFolder)
        onVisibleChanged: if (!visible) win.restoreKeysLater()
    }
    FileDialog {
        id: savePlaylistDialog
        title: "Create Playlist from Queue"
        fileMode: FileDialog.SaveFile
        defaultSuffix: "m3u8"
        nameFilters: ["Playlist (*.m3u8)"]
        currentFolder: platform.fileUrl(platform.playlistLibraryDirectory())
        onAccepted: player.saveQueueAs(selectedFile)
        onVisibleChanged: if (!visible) win.restoreKeysLater()
    }

}
