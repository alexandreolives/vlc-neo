import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtCore
import Qt.labs.folderlistmodel
import Neo 1.0

// Local media browser with a full-window mode and a compact embedded mode.
Rectangle {
    id: root
    color: root.figmaSidePanel ? Theme.librarySidePanel
                               : root.wide && !root.compactFolderSidebar && !root.compactMusicSidebar ? Theme.window : Theme.panel
    property bool wide: false
    property bool compactMusicSidebar: false
    property bool compactFolderSidebar: false
    property bool figmaSidePanel: false
    property var sideFolderHistory: []
    property string musicSidePage: "categories"
    property string musicSideFolderRoot: ""
    property var musicSideHistory: []
    property bool musicSideSearchOpen: false
    property bool musicSideSortByName: false
    property bool musicSideCompactView: false
    property bool musicSearchOpen: false
    property bool folderSearchOpen: false
    property alias folderSearchButton: compactFolderSearchButton
    property alias folderPinButton: compactFolderPinButton
    property alias compactFolderToolbar: compactFolderToolbarItem
    property alias folderActionsRow: folderActionsRowItem
    property alias musicItemCountText: musicItemCountLabel.text
    property alias figmaMusicItemCountText: musicSidePanelCount.text
    property url folder: StandardPaths.writableLocation(StandardPaths.MoviesLocation)
    property string section: "folder"   // home | folder | recent | music
    property string sortBy: "name"
    property string folderViewMode: "grid"
    property string mediaType: "all"   // all | video | audio
    property string searchText: ""
    property int filteredCount: 0
    property int recentRevision: 0
    property alias miniVideoHost: miniVideoSurface
    property alias miniPlayerItem: miniPlayer
    property alias folderViewToggleItem: folderViewToggleButton
    property alias folderListingItem: listing
    property alias indexedListing: musicListing
    property alias albumViewButton: musicViewAlbums
    signal openFiles()
    signal indexFolder()

    function recentItems() {
        recentRevision
        return player.recentMedia()
    }
    Connections {
        target: player
        function onRecentMediaChanged() { root.recentRevision++ }
    }

    readonly property var mediaFilters: ["*.mkv", "*.mp4", "*.avi", "*.mov", "*.webm", "*.m4v", "*.wmv", "*.flv", "*.ts",
        "*.m2ts", "*.mpg", "*.mpeg", "*.3gp", "*.ogv", "*.mp3", "*.flac", "*.ogg", "*.opus", "*.m4a", "*.aac", "*.wav",
        "*.wma", "*.alac", "*.ape", "*.m3u", "*.m3u8", "*.pls", "*.xspf", "*.iso"]
    readonly property var videoFilters: ["*.mkv", "*.mp4", "*.avi", "*.mov", "*.webm", "*.m4v", "*.wmv", "*.flv", "*.ts",
        "*.m2ts", "*.mpg", "*.mpeg", "*.3gp", "*.ogv", "*.iso"]
    readonly property var videoExtensions: ["mkv", "mp4", "avi", "mov", "webm", "m4v", "wmv", "flv", "ts",
        "m2ts", "mpg", "mpeg", "3gp", "ogv", "iso"]
    readonly property var audioFilters: ["*.mp3", "*.flac", "*.ogg", "*.opus", "*.m4a", "*.aac", "*.wav", "*.wma", "*.alac", "*.ape"]
    readonly property var audioExt: ["mp3", "flac", "ogg", "opus", "m4a", "aac", "wav", "wma", "alac", "ape"]

    function pinnedList() { return Theme.store.pinned.length ? Theme.store.pinned.split("\n") : [] }
    function togglePin(path) {
        let list = pinnedList()
        const i = list.indexOf(path)
        if (i >= 0) list.splice(i, 1); else list.push(path)
        Theme.store.pinned = list.join("\n")
    }
    function sidePanelTitle() {
        if (win.navigationPage === "music") {
            if (musicSidePage === "songs" && musicSideFolderRoot.length)
                return "…  ▸  Songs  ▸  " + musicSideRootLabel(musicSideFolderRoot)
            return musicSidePage === "categories" ? "Music" : "Music  ▸  " + musicSidePage.charAt(0).toUpperCase() + musicSidePage.slice(1)
        }
        if (root.section === "folder" && root.mediaType === "audio") {
            const currentPath = platform.localPath(root.folder)
            const rootPath = root.musicRootForPath(currentPath)
            const nestedPaths = rootPath.length ? currentPath.slice(rootPath.length).split("/").filter(Boolean) : []
            return "Songs  ▸  " + [root.musicSideRootLabel(rootPath || currentPath)].concat(nestedPaths).join("  ▸  ")
        }
        if (win.navigationPage === "recent") return "Recent"
        if (win.navigationPage === "videos") {
            const currentPath = platform.localPath(root.folder)
            const videosPath = platform.localPath(StandardPaths.writableLocation(StandardPaths.MoviesLocation))
            if (currentPath !== videosPath) return currentPath.split("/").filter(Boolean).pop() || "Videos"
            return "Videos"
        }
        return "Library"
    }
    function musicLocalPath(path) {
        const value = path.toString()
        return value.startsWith("file:") ? platform.localPath(path) : value
    }
    function musicRootForPath(path) {
        const normalized = musicLocalPath(path)
        let best = ""
        for (const item of mediaLibrary.roots) {
            const candidate = musicLocalPath(item)
            if ((normalized === candidate || normalized.startsWith(candidate + "/")) && candidate.length > best.length)
                best = candidate
        }
        return best
    }
    function musicSideRootLabel(path) {
        const normalized = musicLocalPath(path)
        const musicLocation = musicLocalPath(StandardPaths.writableLocation(StandardPaths.MusicLocation))
        if (normalized === musicLocation) return "My Songs"
        return normalized.split("/").filter(Boolean).pop() || "My Songs"
    }
    function goBackFromSidePanel() {
        if (win.navigationPage === "music" && musicSideFolderRoot.length) {
            musicSideFolderRoot = ""
            mediaLibrary.model.search = ""
            return
        }
        if (win.navigationPage === "music" && root.section === "folder") {
            const currentPath = platform.localPath(root.folder)
            const musicRoot = root.musicRootForPath(currentPath)
            if (musicRoot.length && currentPath !== musicRoot && sideFolderHistory.length) {
                root.folder = sideFolderHistory[sideFolderHistory.length - 1]
                sideFolderHistory = sideFolderHistory.slice(0, -1)
                return
            }
            if (sideFolderHistory.length) {
                root.folder = sideFolderHistory[sideFolderHistory.length - 1]
                sideFolderHistory = sideFolderHistory.slice(0, -1)
            }
            root.section = "music"
            root.mediaType = "audio"
            return
        }
        if (win.navigationPage === "music" && mediaLibrary.model.grouped) {
            mediaLibrary.model.clearGroup()
            return
        }
        if (win.navigationPage === "music" && musicSideHistory.length) {
            musicSidePage = musicSideHistory[musicSideHistory.length - 1]
            musicSideHistory = musicSideHistory.slice(0, -1)
            if (["albums", "artists", "genres"].includes(musicSidePage))
                mediaLibrary.model.view = musicSidePage
            else
                mediaLibrary.model.view = "tracks"
            return
        }
        if (sideFolderHistory.length) {
            root.folder = sideFolderHistory[sideFolderHistory.length - 1]
            sideFolderHistory = sideFolderHistory.slice(0, -1)
            return
        }
        win.goBack()
    }
    function openMusicSidePage(page) {
        musicSideHistory = musicSideHistory.concat([musicSidePage])
        musicSideFolderRoot = ""
        musicSidePage = page
        mediaLibrary.model.search = ""
        mediaLibrary.model.view = ["albums", "artists", "genres"].includes(page) ? page : "tracks"
    }
    function musicSideItemCount() {
        if (musicSidePage === "categories") return visibleMusicCategories().length
        if (musicSidePage === "songs") return musicSideFolderRoot.length ? musicSideTracks().length : mediaLibrary.roots.length
        return mediaLibrary.model.itemCount()
    }
    function musicSideCountText() {
        const count = musicSideItemCount()
        return count + (count === 1 ? " item" : " items")
               + (mediaLibrary.scanning ? " · Indexing…" : "")
    }
    function musicSideTracks() {
        if (!musicSideFolderRoot.length) return []
        const rootPath = musicLocalPath(musicSideFolderRoot)
        const query = mediaLibrary.model.search.trim().toLowerCase()
        const tracks = []
        for (let index = 0; index < mediaLibrary.model.itemCount(); ++index) {
            const item = mediaLibrary.model.itemAt(index)
            if (item.kind !== "audio" || item.isGroup) continue
            const path = musicLocalPath(item.path)
            if (!path.startsWith(rootPath + "/") || path.slice(rootPath.length + 1).includes("/")) continue
            if (query.length && ![item.title, item.artist, item.album, item.genre, path].join(" ").toLowerCase().includes(query)) continue
            tracks.push(item)
        }
        if (musicSideSortByName) tracks.sort((a, b) => a.title.localeCompare(b.title))
        return tracks
    }
    function visibleMusicCategories() {
        const categories = [
            { page: "songs", label: "Songs", icon: "music" },
            { page: "albums", label: "Albums", icon: "album" },
            { page: "artists", label: "Artists", icon: "artist" },
            { page: "genres", label: "Genres", icon: "genre" }
        ]
        const query = musicSideSearchOpen ? mediaLibrary.model.search.trim().toLowerCase() : ""
        const result = query.length ? categories.filter(item => item.label.toLowerCase().includes(query)) : categories
        if (musicSideSortByName) result.sort((a, b) => a.label.localeCompare(b.label))
        return result
    }
    function openFolder(url) {
        if (root.figmaSidePanel) sideFolderHistory = sideFolderHistory.concat([root.folder])
        win.rememberHomeVisit("folder", platform.localPath(url))
        root.folder = url
        root.section = "folder"
    }
    onFigmaSidePanelChanged: if (figmaSidePanel) sideFolderHistory = []
    Connections {
        target: win
        function onNavigationPageChanged() {
            if (!root.figmaSidePanel) return
            root.sideFolderHistory = []
            if (win.navigationPage === "music") {
                root.musicSidePage = "categories"
                root.musicSideFolderRoot = ""
                root.musicSideHistory = []
                root.musicSideSearchOpen = false
                mediaLibrary.model.search = ""
            }
        }
    }
    function matches(name) { return searchText.length === 0 || name.toLowerCase().includes(searchText.trim().toLowerCase()) }
    function refreshFilteredCount() {
        if (searchText.trim().length === 0) {
            filteredCount = files.count
            return
        }
        let count = 0
        for (let i = 0; i < files.count; ++i)
            if (matches(files.get(i, "fileName"))) ++count
        filteredCount = count
    }
    function matchingFiles() { return filteredCount }
    function fileCount() { return files.count }
    function extension(name) { return name.slice(name.lastIndexOf(".") + 1).toLowerCase() }
    function hasFileName(name) {
        for (let i = 0; i < files.count; ++i)
            if (files.get(i, "fileName") === name) return true
        return false
    }
    function videoThumbnailReady(name) {
        for (let i = 0; i < files.count; ++i) {
            if (files.get(i, "fileName") !== name) continue
            const cell = listing.itemAtIndex(i)
            return !!cell && cell.videoThumbnailReady
        }
        return false
    }
    function videoThumbnailState(name) {
        for (let i = 0; i < files.count; ++i) {
            if (files.get(i, "fileName") !== name) continue
            const cell = listing.itemAtIndex(i)
            return cell ? cell.videoThumbnailState : "missing-cell"
        }
        return "missing-file"
    }
    function visibleVideoThumbnailSummary() {
        let visible = 0, ready = 0, loading = 0, error = 0
        const viewportTop = listing.contentY
        const viewportBottom = viewportTop + listing.height
        for (let i = 0; i < files.count; ++i) {
            const cell = listing.itemAtIndex(i)
            if (!cell || !cell.visible || cell.y + cell.height <= viewportTop || cell.y >= viewportBottom)
                continue
            ++visible
            if (cell.videoThumbnailState === "ready") ++ready
            else if (cell.videoThumbnailState === "loading") ++loading
            else if (cell.videoThumbnailState === "error") ++error
        }
        return visible + "/" + ready + "/" + loading + "/" + error
    }
    function folderListGeometry() {
        const cell = listing.itemAtIndex(0)
        if (!cell) return "missing"
        const frame = cell.mapToItem(win.contentItem, cell.thumbnailRect.x, cell.thumbnailRect.y)
        return Math.round(listing.mapToItem(win.contentItem, 0, 0).y) + "/"
             + Math.round(frame.x) + "/" + Math.round(frame.y) + "/"
             + Math.round(cell.thumbnailRect.width) + "/" + Math.round(cell.thumbnailRect.height) + "/"
             + Math.round(miniPlayer.mapToItem(win.contentItem, 0, 0).x) + "/"
             + Math.round(miniPlayer.mapToItem(win.contentItem, 0, 0).y) + "/"
             + Math.round(miniPlayer.width) + "/" + Math.round(miniPlayer.height)
    }
    function videoProgress(name) {
        for (let i = 0; i < files.count; ++i) {
            if (files.get(i, "fileName") !== name) continue
            const cell = listing.itemAtIndex(i)
            return cell ? cell.progressRatio : 0
        }
        return 0
    }
    function crumbs() {
        const path = platform.localPath(root.folder)
        const home = platform.homePath()
        const inHome = path === home || path.startsWith(home + "/")
        let acc = inHome ? home : ""
        const rest = inHome ? path.slice(home.length) : path
        const list = inHome ? [{ name: "~", path: home }] : []
        for (const p of rest.split("/").filter(p => p.length)) {
            acc += "/" + p
            list.push({ name: p, path: acc })
        }
        return list
    }

    FolderListModel {
        id: files
        folder: root.folder
        nameFilters: root.mediaType === "video" ? root.videoFilters
                   : (root.mediaType === "audio" ? root.audioFilters : root.mediaFilters)
        showDirsFirst: true
        showHidden: Theme.store.showHiddenFiles
        showDotAndDotDot: false
        caseSensitive: false
        sortField: root.sortBy === "date" ? FolderListModel.Time : (root.sortBy === "size" ? FolderListModel.Size : FolderListModel.Name)
        sortReversed: root.sortBy === "date"
        onStatusChanged: if (status === FolderListModel.Ready) filteredCountTimer.restart()
        onCountChanged: if (status === FolderListModel.Ready) filteredCountTimer.restart()
    }
    onSearchTextChanged: filteredCountTimer.restart()
    Timer {
        id: filteredCountTimer
        interval: 180
        onTriggered: root.refreshFilteredCount()
    }
    Timer {
        id: musicSearchTimer
        interval: 160
        onTriggered: mediaLibrary.model.search = librarySearch.text
    }

    ColumnLayout {
        visible: !(root.figmaSidePanel && root.section === "music"
                   && ["categories", "songs"].includes(root.musicSidePage))
        anchors.fill: parent
        spacing: 0

        // Header: navigation, breadcrumbs and local search.
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: root.figmaSidePanel ? 0 : (root.compactFolderSidebar ? 18 : (root.wide && root.section === "folder" ? 8 : 0))
            Layout.leftMargin: root.figmaSidePanel ? 18 : 8
            Layout.rightMargin: root.figmaSidePanel ? 27 : 8
            Layout.preferredHeight: root.figmaSidePanel ? 52 : (root.wide && root.section === "folder" && !root.compactFolderSidebar ? 64 : 42)
            spacing: 2
            IconButton {
                icon: root.figmaSidePanel ? "arrow-left" : "chevron-left"
                tip: root.figmaSidePanel ? "Back" : "Up"
                visible: root.figmaSidePanel || root.section === "folder"
                onClicked: root.figmaSidePanel ? root.goBackFromSidePanel() : root.openFolder(files.parentFolder)
            }
            IconButton { icon: "arrow-right"; tip: "Forward"; visible: root.figmaSidePanel; enabled: false }
            Chips {
                visible: !root.wide
                model: [{ label: "Home", value: "home" }, { label: "Browse", value: "folder" }, { label: "Recent", value: "recent" }]
                current: root.section
                onPicked: (v) => root.section = v
            }
            NText {
                visible: root.wide
                text: root.figmaSidePanel ? root.sidePanelTitle()
                      : root.section === "folder" ? root.crumbs().map(c => c.name).join("  ›  ")
                      : (root.section === "recent" ? "Recent media" : (root.section === "music" ? (root.compactMusicSidebar ? "Songs  ›  My Songs" : "Music library") : "Home"))
                font.pixelSize: root.figmaSidePanel ? 14 : 12
                color: root.figmaSidePanel ? Theme.librarySideTitle : Theme.text
                Layout.leftMargin: 8
                Layout.fillWidth: true
            }
            Item { Layout.fillWidth: true }
            NText { visible: root.wide && root.section === "folder" && !root.compactFolderSidebar && !root.figmaSidePanel; text: root.matchingFiles() + " items"; dim: true; font.pixelSize: 11 }
            NText { id: musicItemCountLabel; visible: root.wide && root.section === "music" && !root.figmaSidePanel; text: mediaLibrary.model.count + " items" + (mediaLibrary.scanning ? " · Indexing…" : ""); dim: true; font.pixelSize: 11 }
            IconButton { objectName: "library-index-folder"; visible: root.wide && root.section === "music" && !root.compactMusicSidebar; icon: "folder"; tip: "Add folder to library"; onClicked: root.indexFolder() }
            IconButton { visible: root.wide && root.section === "music" && !root.compactMusicSidebar; icon: "refresh"; tip: "Rescan library"; enabled: !mediaLibrary.scanning; onClicked: mediaLibrary.refresh() }
            IconButton { visible: root.wide && root.section === "music" && !root.compactMusicSidebar; icon: "trash-2"; tip: "Clear indexed library"; enabled: !mediaLibrary.scanning; onClicked: mediaLibrary.clearLibrary() }
            IconButton {
                icon: "arrow-up"; tip: "Sort: " + root.sortBy
                visible: root.section !== "music" && !root.compactFolderSidebar && !root.figmaSidePanel
                onClicked: root.sortBy = root.sortBy === "name" ? "date" : (root.sortBy === "date" ? "size" : "name")
            }
            IconButton {
                id: folderViewToggleButton
                objectName: "library-folder-view-toggle"
                visible: root.wide && root.section === "folder" && !root.compactFolderSidebar && !root.figmaSidePanel
                icon: root.folderViewMode === "grid" ? "list" : "grid"
                tip: root.folderViewMode === "grid" ? "List view" : "Grid view"
                Accessible.name: tip
                onClicked: root.folderViewMode = root.folderViewMode === "grid" ? "list" : "grid"
            }
            NField {
                id: librarySearch
                visible: root.wide && !root.figmaSidePanel && ((!root.compactMusicSidebar && !root.compactFolderSidebar)
                                       || (root.compactMusicSidebar && root.musicSearchOpen)
                                       || (root.compactFolderSidebar && root.folderSearchOpen))
                objectName: "library-search"
                Layout.preferredWidth: root.compactFolderSidebar ? 105 : (root.compactMusicSidebar ? 125 : 190)
                text: root.section === "music" ? mediaLibrary.model.search : root.searchText
                placeholderText: "Search"
                onTextEdited: root.section === "music" ? musicSearchTimer.restart() : (root.searchText = text)
            }
            IconButton { visible: root.compactMusicSidebar && !root.musicSearchOpen; icon: "search"; tip: "Search songs"; onClicked: root.musicSearchOpen = true }
            IconButton { visible: root.compactMusicSidebar && root.musicSearchOpen; icon: "x"; tip: "Close search"; onClicked: { root.musicSearchOpen = false; mediaLibrary.model.search = "" } }
            IconButton { visible: root.wide && !root.compactFolderSidebar && !root.figmaSidePanel; icon: "plus"; tip: "Add media"; onClicked: root.openFiles() }
            IconButton { visible: root.figmaSidePanel; icon: "more"; tip: "More options" }
            IconButton { visible: root.figmaSidePanel; icon: "open"; tip: "Open full page"; onClicked: win.navigate(win.navigationPage) }
            IconButton { visible: !root.figmaSidePanel; icon: "x"; tip: "Close side panel"; onClicked: win.closeSidePanel() }
        }

        RowLayout {
            visible: root.figmaSidePanel && root.section === "music"
            Layout.fillWidth: true
            Layout.leftMargin: 20
            Layout.rightMargin: 27
            Layout.preferredHeight: 52
            spacing: 4
            NText {
                visible: !root.musicSideSearchOpen
                text: root.musicSideCountText()
                dim: true
                font.pixelSize: 12
                Layout.fillWidth: true
            }
            NField {
                visible: root.musicSideSearchOpen
                Layout.fillWidth: true
                placeholderText: "Search"
                text: mediaLibrary.model.search
                onTextEdited: mediaLibrary.model.search = text
            }
            IconButton { icon: "sort"; tip: "Sort"; checked: root.musicSideSortByName; onClicked: root.musicSideSortByName = !root.musicSideSortByName }
            IconButton { icon: "view"; tip: "View options"; checked: root.musicSideCompactView; onClicked: root.musicSideCompactView = !root.musicSideCompactView }
            IconButton { icon: root.musicSideSearchOpen ? "close" : "search"; tip: root.musicSideSearchOpen ? "Close search" : "Search"; onClicked: { root.musicSideSearchOpen = !root.musicSideSearchOpen; if (!root.musicSideSearchOpen) mediaLibrary.model.search = "" } }
        }

        // The compact player sidebar follows Figma's two-row folder header:
        // breadcrumbs above, then item count and sort/view/search controls.
        RowLayout {
            id: compactFolderToolbarItem
            objectName: "library-compact-folder-toolbar"
            visible: (root.compactFolderSidebar || root.figmaSidePanel) && root.section === "folder"
            Layout.fillWidth: true
            Layout.topMargin: visible && !root.figmaSidePanel ? 15 : 0
            Layout.leftMargin: visible ? (root.figmaSidePanel ? 20 : 10) : 0
            Layout.rightMargin: visible ? (root.figmaSidePanel ? 27 : 10) : 0
            Layout.bottomMargin: visible && !root.figmaSidePanel ? 35 : 0
            Layout.preferredHeight: root.figmaSidePanel ? 52 : 28
            spacing: 4
            NText { visible: !root.folderSearchOpen; text: root.matchingFiles() + " items"; color: root.figmaSidePanel ? Theme.librarySideText : Theme.textDim; font.pixelSize: 12 }
            NField {
                visible: root.figmaSidePanel && root.folderSearchOpen
                Layout.fillWidth: true
                placeholderText: "Search"
                text: root.searchText
                onTextEdited: root.searchText = text
            }
            Item { Layout.fillWidth: true; visible: !root.folderSearchOpen }
            IconButton {
                icon: root.figmaSidePanel ? "sort" : "arrow-up"; tip: "Sort: " + root.sortBy
                onClicked: root.sortBy = root.sortBy === "name" ? "date" : (root.sortBy === "date" ? "size" : "name")
            }
            IconButton {
                objectName: "library-folder-view-toggle"
                icon: root.folderViewMode === "grid" ? "list" : "grid"
                tip: root.folderViewMode === "grid" ? "List view" : "Grid view"
                Accessible.name: tip
                onClicked: root.folderViewMode = root.folderViewMode === "grid" ? "list" : "grid"
            }
            IconButton {
                id: compactFolderPinButton
                objectName: "library-folder-pin"
                icon: "bookmark"; tip: "Pin this folder"
                checked: root.pinnedList().indexOf(platform.localPath(root.folder)) >= 0
                visible: !root.figmaSidePanel
                onClicked: root.togglePin(platform.localPath(root.folder))
            }
            IconButton { id: compactFolderSearchButton; objectName: "library-folder-search-open"; visible: !root.folderSearchOpen; icon: "search"; tip: "Search this folder"; onClicked: root.folderSearchOpen = true }
            IconButton { objectName: "library-folder-search-close"; visible: root.folderSearchOpen; icon: "x"; tip: "Close search"; onClicked: { root.folderSearchOpen = false; root.searchText = "" } }
        }

        // Address line (clickable segments)
        Flickable {
            visible: root.section === "folder" && !root.wide
            Layout.fillWidth: true
            Layout.leftMargin: 10
            Layout.rightMargin: 10
            implicitHeight: 28
            contentWidth: crumbRow.implicitWidth
            clip: true
            flickableDirection: Flickable.HorizontalFlick
            onContentWidthChanged: contentX = Math.max(0, contentWidth - width)
            Row {
                id: crumbRow
                spacing: 2
                Repeater {
                    model: root.crumbs()
                    delegate: Row {
                        required property var modelData
                        required property int index
                        spacing: 2
                        NText { text: index > 0 ? "›" : ""; dim: true; height: 24 }
                        Rectangle {
                            width: crumbText.implicitWidth + 10; height: 24; radius: 3
                            color: crumbMouse.containsMouse ? Theme.hover : "transparent"
                            NText { id: crumbText; anchors.centerIn: parent; text: modelData.name; font.pixelSize: 12; dim: true }
                            MouseArea { id: crumbMouse; anchors.fill: parent; hoverEnabled: true; onClicked: root.openFolder(platform.fileUrl(modelData.path)) }
                        }
                    }
                }
            }
        }
        RowLayout {
            id: folderActionsRowItem
            visible: root.section === "folder" && (!root.wide || root.compactFolderSidebar)
                    && !root.compactFolderSidebar
            Layout.fillWidth: true
            Layout.leftMargin: 10
            Layout.rightMargin: 10
            Layout.bottomMargin: 6
            spacing: 6
            NButton { text: "Play folder"; icon: "play"; Layout.fillWidth: true; onClicked: player.openUrls([root.folder], true) }
            NButton { text: "Queue all"; icon: "plus"; Layout.fillWidth: true; onClicked: player.openUrls([root.folder], false) }
            IconButton {
                objectName: "library-folder-pin-full"
                visible: !root.compactFolderSidebar
                icon: "bookmark"; tip: "Pin this folder"
                checked: root.pinnedList().indexOf(platform.localPath(root.folder)) >= 0
                onClicked: root.togglePin(platform.localPath(root.folder))
            }
        }
        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }

        Item {
            objectName: "library-sidepanel-add"
            visible: root.figmaSidePanel && root.section === "folder"
            Layout.fillWidth: true
            Layout.preferredHeight: 36
            Layout.topMargin: visible && root.figmaSidePanel ? 16 : 0
            Layout.leftMargin: 25
            Icon { anchors.left: parent.left; anchors.leftMargin: 1; anchors.verticalCenter: parent.verticalCenter; name: "plus"; size: 16; color: Theme.icon }
            NText { anchors.left: parent.left; anchors.leftMargin: 36; anchors.verticalCenter: parent.verticalCenter; text: "Add"; font.pixelSize: 13; color: Theme.librarySideText }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.indexFolder() }
        }

        Item {
            objectName: "music-sidepanel-add-library"
            visible: root.figmaSidePanel && root.section === "music"
                     && !["categories", "songs"].includes(root.musicSidePage)
            Layout.fillWidth: true
            Layout.preferredHeight: 36
            Layout.topMargin: visible ? 16 : 0
            Layout.leftMargin: 25
            activeFocusOnTab: true
            Accessible.role: Accessible.Button
            Accessible.name: "Add folder to music library"
            Accessible.focusable: true
            Keys.onPressed: event => {
                if ((event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !event.isAutoRepeat) {
                    root.indexFolder()
                    event.accepted = true
                }
            }
            Rectangle {
                anchors.fill: parent
                radius: Theme.radiusSmall
                color: addLibraryFolderMouse.containsMouse ? Theme.hover : "transparent"
                border.width: parent.activeFocus ? 1 : 0
                border.color: Theme.accent
            }
            Icon { anchors.left: parent.left; anchors.leftMargin: 1; anchors.verticalCenter: parent.verticalCenter; name: "plus"; size: 16; color: Theme.icon }
            NText { anchors.left: parent.left; anchors.leftMargin: 36; anchors.verticalCenter: parent.verticalCenter; text: "Add"; font.pixelSize: 13; color: Theme.librarySideText }
            MouseArea { id: addLibraryFolderMouse; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { parent.forceActiveFocus(); root.indexFolder() } }
        }

        ColumnLayout {
            objectName: "music-sidepanel-categories-legacy"
            visible: false
            Layout.fillWidth: true
            Layout.leftMargin: 26
            Layout.rightMargin: 12
            spacing: 0
            Repeater {
                model: root.visibleMusicCategories()
                delegate: Item {
                    required property var modelData
                    objectName: "music-sidepanel-category-legacy-" + modelData.page
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.musicSideCompactView ? 36 : 44
                    Icon { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; name: modelData.icon; size: 18; color: Theme.icon }
                    NText { anchors.left: parent.left; anchors.leftMargin: 36; anchors.verticalCenter: parent.verticalCenter; text: modelData.label; font.pixelSize: 13; color: Theme.text }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.openMusicSidePage(modelData.page) }
                }
            }
        }

        ColumnLayout {
            objectName: "music-sidepanel-roots-legacy"
            visible: false
            Layout.fillWidth: true
            Layout.leftMargin: 26
            Layout.rightMargin: 12
            spacing: 0
            Repeater {
                model: mediaLibrary.roots
                delegate: Item {
                    required property string modelData
                    objectName: "music-sidepanel-root-legacy-" + root.musicSideRootLabel(modelData)
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.musicSideCompactView ? 36 : 44
                    Icon { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; name: "folder"; size: 18; color: Theme.icon }
                    NText { anchors.left: parent.left; anchors.leftMargin: 36; anchors.verticalCenter: parent.verticalCenter; text: root.musicSideRootLabel(modelData); font.pixelSize: 13; color: Theme.text }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.sideFolderHistory = root.sideFolderHistory.concat([root.folder])
                            root.folder = platform.fileUrl(modelData)
                            root.section = "folder"
                            root.mediaType = "audio"
                        }
                    }
                }
            }
        }

        NText {
            visible: root.figmaSidePanel && root.section === "music" && root.musicSidePage === "songs" && mediaLibrary.roots.length === 0
            Layout.leftMargin: 62
            Layout.topMargin: 6
            text: "No music folders"
            color: Theme.librarySideText
            font.pixelSize: 12
        }

        RowLayout {
            visible: root.section === "music" && !root.compactMusicSidebar
            Layout.fillWidth: true
            Layout.leftMargin: 12
            Layout.rightMargin: 12
            Layout.topMargin: 8
            Layout.bottomMargin: 8
            spacing: 6
            NButton { objectName: "music-view-tracks"; text: "Tracks"; primary: mediaLibrary.model.view === "tracks"; onClicked: mediaLibrary.model.view = "tracks" }
            NButton { id: musicViewAlbums; objectName: "music-view-albums"; text: "Albums"; primary: mediaLibrary.model.view === "albums"; onClicked: mediaLibrary.model.view = "albums" }
            NButton { objectName: "music-view-artists"; text: "Artists"; primary: mediaLibrary.model.view === "artists"; onClicked: mediaLibrary.model.view = "artists" }
            NButton { objectName: "music-view-genres"; text: "Genres"; primary: mediaLibrary.model.view === "genres"; onClicked: mediaLibrary.model.view = "genres" }
            NButton { objectName: "music-view-videos"; text: "Videos"; primary: mediaLibrary.model.view === "videos"; onClicked: mediaLibrary.model.view = "videos" }
            NButton { visible: mediaLibrary.model.grouped; text: "← Tracks"; flat: true; onClicked: mediaLibrary.model.clearGroup() }
        }

        NText {
            objectName: "music-library-query-status"
            visible: root.section === "music" && (mediaLibrary.model.loading || mediaLibrary.model.loadError.length > 0)
            Layout.fillWidth: true
            Layout.leftMargin: 14
            Layout.rightMargin: 14
            Layout.bottomMargin: 6
            wrapMode: Text.Wrap
            dim: true
            text: mediaLibrary.model.loadError.length > 0
                  ? "Could not refresh library results: " + mediaLibrary.model.loadError
                    + (mediaLibrary.model.stale ? " Showing previous results." : "")
                  : (mediaLibrary.model.stale ? "Updating library results; showing previous results…" : "Loading library…")
        }

        // Folder listing
        GridView {
            id: listing
            visible: root.section === "folder"
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.leftMargin: root.figmaSidePanel ? 0 : (root.wide ? 12 : 0)
            Layout.rightMargin: root.figmaSidePanel ? 0 : (root.wide ? 12 : 0)
            Layout.topMargin: root.figmaSidePanel ? 5 : (root.wide && !root.compactFolderSidebar ? 58 : 0)
            clip: true
            model: files
            boundsBehavior: Flickable.StopAtBounds
            cellWidth: root.wide && !root.compactFolderSidebar && !root.figmaSidePanel
                       ? Math.max(180, Math.floor(width / (root.folderViewMode === "grid" ? 5 : 4))) : width
            cellHeight: root.figmaSidePanel ? 42 : root.compactFolderSidebar ? 38 : (root.wide
                ? (root.folderViewMode === "grid" ? Math.max(154, Math.min(244, Math.round(cellWidth * 0.72))) : 44)
                : 34)
            ScrollBar.vertical: ScrollBar {}
            delegate: Rectangle {
                id: mediaCell
                required property string fileName
                required property url fileUrl
                required property bool fileIsDir
                required property string fileSuffix
                width: listing.cellWidth - (root.wide && !root.figmaSidePanel ? 8 : 0)
                height: listing.cellHeight - 2
                visible: root.matches(fileName)
                radius: Theme.radiusSmall
                property bool playing: !fileIsDir && player.mediaUrl.toString() === fileUrl.toString()
                property string extension: root.extension(fileName)
                property bool videoFile: !fileIsDir && root.videoExtensions.indexOf(extension) >= 0
                property bool gridCard: root.wide && !root.compactFolderSidebar && !root.figmaSidePanel && root.folderViewMode === "grid"
                property real savedDuration: player.resumeDurationFor(fileUrl)
                property real savedPoint: player.resumePointFor(fileUrl)
                property real progressRatio: playing
                    ? (player.length > 0 ? Math.max(0, Math.min(1, player.time / player.length)) : 0)
                    : (savedDuration > 0 ? Math.max(0, Math.min(1, savedPoint / savedDuration)) : 0)
                property bool videoThumbnailReady: videoThumbnail.status === Image.Ready
                property rect thumbnailRect: Qt.rect(thumbnailFrame.x, thumbnailFrame.y,
                                                      thumbnailFrame.width, thumbnailFrame.height)
                property string videoThumbnailState: videoThumbnail.status === Image.Null ? "null" :
                                                      videoThumbnail.status === Image.Loading ? "loading" :
                                                      videoThumbnail.status === Image.Ready ? "ready" :
                                                      videoThumbnail.status === Image.Error ? "error" : "unknown"
                color: root.folderViewMode === "list" && playing ? Theme.accentSoft
                     : (cellMouse.containsMouse ? Theme.hover : "transparent")

                Item {
                    id: thumbnailFrame
                    x: mediaCell.gridCard ? 8 : (root.figmaSidePanel ? 26 : root.wide ? 15 : 12)
                    y: mediaCell.gridCard ? 8 : Math.round((parent.height - height) / 2)
                    width: mediaCell.gridCard ? parent.width - 16 : (root.wide && mediaCell.videoFile ? 32 : 16)
                    height: mediaCell.gridCard ? Math.round(width * 9 / 16) : (root.wide ? 32 : 18)
                    Image {
                        id: videoThumbnail
                        objectName: "library-video-thumbnail-" + mediaCell.fileName
                        anchors.fill: parent
                        source: root.wide && mediaCell.videoFile
                                ? "image://thumbnail/frame?path=" + encodeURIComponent(platform.localPath(mediaCell.fileUrl)) + "&t=0"
                                : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: true
                        visible: status === Image.Ready
                    }
                    Icon {
                        anchors.centerIn: parent
                        name: mediaCell.fileIsDir ? "folder" : (root.audioExt.indexOf(mediaCell.extension) >= 0 ? "music" : "video")
                        size: root.wide ? 15 : 16
                        color: mediaCell.playing ? Theme.accent : Theme.icon
                        visible: !mediaCell.videoFile || videoThumbnail.status !== Image.Ready
                    }
                }
                Rectangle {
                    visible: mediaCell.gridCard && mediaCell.progressRatio > 0
                    x: thumbnailFrame.x
                    y: thumbnailFrame.y + thumbnailFrame.height - 3
                    width: thumbnailFrame.width * mediaCell.progressRatio
                    height: 3
                    color: Theme.accent
                }
                NText {
                    text: mediaCell.fileName
                    x: mediaCell.gridCard ? 8 : (root.figmaSidePanel ? 62 : thumbnailFrame.x + thumbnailFrame.width + (root.wide ? 7 : 10))
                    y: mediaCell.gridCard ? thumbnailFrame.y + thumbnailFrame.height + 8 : Math.round((parent.height - height) / 2)
                    width: mediaCell.gridCard ? parent.width - 16 : Math.max(20, parent.width - x - 36)
                    font.pixelSize: root.figmaSidePanel ? 13 : root.wide ? (mediaCell.gridCard ? 13 : 11) : Theme.fontBody
                    color: root.folderViewMode === "list" && mediaCell.playing ? Theme.accent
                           : root.figmaSidePanel ? Theme.librarySideText : Theme.text
                    elide: Text.ElideRight
                }
                IconButton {
                    z: 2
                    x: parent.width - width - 5
                    y: mediaCell.gridCard ? thumbnailFrame.y + 4 : Math.round((parent.height - height) / 2)
                    visible: cellMouse.containsMouse || hovered
                    icon: "plus"; iconSize: 13; tip: "Add to queue"
                    onClicked: player.openUrls([mediaCell.fileUrl], false)
                }
                MouseArea {
                    id: cellMouse
                    anchors.fill: parent
                    anchors.rightMargin: 34
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    drag.target: dragProxy
                    onClicked: mediaCell.fileIsDir ? root.openFolder(mediaCell.fileUrl) : player.openUrls([mediaCell.fileUrl], true)
                }
                Item {
                    id: dragProxy
                    Drag.active: cellMouse.drag.active
                    Drag.dragType: Drag.Automatic
                    Drag.supportedActions: Qt.CopyAction
                    Drag.mimeData: { "text/uri-list": mediaCell.fileUrl.toString() }
                }
            }
            NText {
                anchors.centerIn: parent
                visible: root.matchingFiles() === 0
                text: root.searchText.length ? "No matching media" : "No media in this folder"
                dim: true
            }
        }

        ListView {
            id: musicListing
            objectName: "music-library-list"
            visible: root.section === "music" && (!root.figmaSidePanel || !["categories", "songs"].includes(root.musicSidePage))
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.leftMargin: root.figmaSidePanel ? 0 : (root.wide ? 12 : 0)
            Layout.rightMargin: root.figmaSidePanel ? 0 : (root.wide ? 12 : 0)
            Layout.topMargin: root.figmaSidePanel ? 5 : 0
            clip: true
            model: mediaLibrary.model
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {}
            delegate: Rectangle {
                objectName: isGroup ? "music-library-group-" + index : "music-library-item-" + index
                required property int index
                required property string title
                required property string artist
                required property string album
                required property string genre
                required property string path
                required property string artwork
                required property int duration
                required property int count
                required property string kind
                required property bool isGroup
                width: ListView.view.width
                height: root.figmaSidePanel ? (root.musicSideCompactView ? 38 : 44) : 52
                radius: Theme.radiusSmall
                color: musicRowMouse.containsMouse ? Theme.hover : "transparent"
                border.width: activeFocus ? 1 : 0
                border.color: Theme.accent
                activeFocusOnTab: true
                Accessible.role: Accessible.Button
                Accessible.name: isGroup ? title + ", " + count + " tracks"
                                         : [title, artist].filter(value => value.length).join(" - ")
                Accessible.focusable: true
                Keys.onPressed: event => {
                    if ((event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !event.isAutoRepeat) {
                        if (isGroup) mediaLibrary.model.selectGroup(index)
                        else player.openUrls([platform.fileUrl(path)], true)
                        event.accepted = true
                    }
                }
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: root.figmaSidePanel ? 26 : 8
                    anchors.rightMargin: root.figmaSidePanel ? 12 : 6
                    spacing: root.figmaSidePanel ? 12 : 10
                    Rectangle {
                        Layout.preferredWidth: root.figmaSidePanel ? 32 : 38
                        Layout.preferredHeight: root.figmaSidePanel ? 32 : 38
                        radius: 4
                        color: Theme.raised
                        Image { id: cover; anchors.fill: parent; source: artwork.length ? platform.fileUrl(artwork) : ""; fillMode: Image.PreserveAspectCrop; visible: status === Image.Ready }
                        Icon { anchors.centerIn: parent; name: kind === "video" ? "video-file" : (isGroup ? "album" : "music"); size: 17; color: Theme.icon; visible: cover.status !== Image.Ready }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        NText { text: title; color: root.figmaSidePanel ? Theme.librarySideText : Theme.text; Layout.fillWidth: true; elide: Text.ElideRight }
                        NText {
                            text: isGroup ? (mediaLibrary.model.view === "albums" ? artist : "")
                                          : [artist, album, genre].filter(value => value.length).join(" · ")
                            visible: text.length > 0
                            color: root.figmaSidePanel ? Theme.librarySideText : Theme.textDim
                            font.pixelSize: 10
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                    }
                    NText { text: isGroup ? count + " tracks" : (duration > 0 ? player.formatTime(duration * 1000) : ""); color: root.figmaSidePanel ? Theme.librarySideText : Theme.textDim; font.pixelSize: 10 }
                }
                MouseArea {
                    id: musicRowMouse
                    anchors.fill: parent
                    anchors.rightMargin: 36
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        parent.forceActiveFocus()
                        isGroup ? mediaLibrary.model.selectGroup(index) : player.openUrls([platform.fileUrl(path)], true)
                    }
                    onDoubleClicked: if (!isGroup) player.openUrls([platform.fileUrl(path)], true)
                }
                IconButton {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    visible: musicRowMouse.containsMouse || hovered
                    icon: "plus"
                    iconSize: 14
                    tip: "Add to queue"
                    onClicked: isGroup ? mediaLibrary.model.selectGroup(index) : player.openUrls([platform.fileUrl(path)], false)
                }
            }
            NText {
                anchors.centerIn: parent
                visible: musicListing.count === 0
                text: mediaLibrary.scanning ? "Indexing local media…" : (mediaLibrary.roots.length ? "No matching media" : "Add a folder to build your media library")
                dim: true
            }
        }

        // Home: places, pinned, recent
        ScrollView {
            visible: root.section === "home"
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: availableWidth
            clip: true
            ColumnLayout {
                width: parent.width
                spacing: 2
                NText { text: "Places"; dim: true; font.pixelSize: 11; Layout.leftMargin: 14; Layout.topMargin: 10 }
                Repeater {
                    model: [
                        { label: "Videos", icon: "film", url: StandardPaths.writableLocation(StandardPaths.MoviesLocation) },
                        { label: "Music", icon: "music", url: StandardPaths.writableLocation(StandardPaths.MusicLocation) },
                        { label: "Downloads", icon: "folder", url: StandardPaths.writableLocation(StandardPaths.DownloadLocation) },
                        { label: "Home", icon: "folder", url: StandardPaths.writableLocation(StandardPaths.HomeLocation) }
                    ]
                    delegate: LibraryRow {
                        required property var modelData
                        label: modelData.label; iconName: modelData.icon; url: modelData.url; isDir: true
                    }
                }
                NText { visible: root.pinnedList().length > 0; text: "Pinned"; dim: true; font.pixelSize: 11; Layout.leftMargin: 14; Layout.topMargin: 10 }
                Repeater {
                    model: root.pinnedList()
                    delegate: LibraryRow {
                        required property int index
                        required property string modelData
                        objectName: "pinned-library-folder-" + index
                        label: modelData.split("/").pop(); iconName: "bookmark"; url: platform.fileUrl(modelData); isDir: true
                    }
                }
                NText { text: "Recent"; dim: true; font.pixelSize: 11; Layout.leftMargin: 14; Layout.topMargin: 10 }
                Repeater {
                    model: root.visible && root.section === "home" ? root.recentItems() : []
                    delegate: LibraryRow {
                        required property string modelData
                        label: decodeURIComponent(modelData.split("/").pop()); iconName: "history"; url: modelData; isDir: false
                    }
                }
                NText { text: "Music library"; dim: true; font.pixelSize: 11; Layout.leftMargin: 14; Layout.topMargin: 10 }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 12
                    Layout.rightMargin: 12
                    NButton { objectName: "open-music-library"; text: "Browse music"; icon: "music"; Layout.fillWidth: true; onClicked: root.section = "music" }
                    IconButton { objectName: "index-library-folder-home"; icon: "folder"; tip: "Index a folder"; onClicked: root.indexFolder() }
                }
                NText { text: mediaLibrary.indexedCount + " items in " + mediaLibrary.roots.length + " folders"; dim: true; font.pixelSize: 10; Layout.leftMargin: 14 }
                Repeater {
                    model: mediaLibrary.roots
                    delegate: RowLayout {
                        required property string modelData
                        Layout.fillWidth: true
                        Layout.leftMargin: 14
                        Layout.rightMargin: 8
                        spacing: 7
                        Icon { name: "folder"; size: 13; color: Theme.icon }
                        NText { text: modelData.split("/").pop(); Layout.fillWidth: true; font.pixelSize: 10; elide: Text.ElideMiddle; ToolTip.visible: folderHover.hovered; ToolTip.text: modelData }
                        HoverHandler { id: folderHover }
                        IconButton { icon: "close"; iconSize: 12; tip: "Remove folder from library"; enabled: !mediaLibrary.scanning; onClicked: mediaLibrary.removeFolder(platform.fileUrl(modelData)) }
                    }
                }
            }
        }

        ScrollView {
            visible: root.section === "recent"
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: availableWidth
            clip: true
            ColumnLayout {
                width: parent.width
                spacing: 2
                NText { text: "Recently played"; dim: true; font.pixelSize: 11; Layout.leftMargin: 14; Layout.topMargin: 10; Layout.bottomMargin: 4 }
                Repeater {
                    model: root.visible && root.section === "recent" ? root.recentItems() : []
                    delegate: LibraryRow {
                        required property string modelData
                        label: decodeURIComponent(modelData.split("/").pop())
                        iconName: "recent"
                        url: modelData
                        isDir: false
                    }
                }
                NText {
                    visible: root.visible && root.section === "recent" && root.recentItems().length === 0
                    text: "No recent media"
                    dim: true
                    Layout.leftMargin: 14
                    Layout.topMargin: 8
                }
            }
        }
    }

    ColumnLayout {
        id: musicSidePanelLanding
        objectName: "music-sidepanel-landing"
        anchors.fill: parent
        visible: root.figmaSidePanel && root.section === "music"
                 && ["categories", "songs"].includes(root.musicSidePage)
        spacing: 0
        z: 1

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 52
            Layout.leftMargin: 18
            Layout.rightMargin: 27
            spacing: 2
            IconButton { icon: "arrow-left"; tip: "Back"; onClicked: root.goBackFromSidePanel() }
            IconButton { icon: "arrow-right"; tip: "Forward"; enabled: false }
            NText { text: root.sidePanelTitle(); font.pixelSize: 14; color: Theme.librarySideTitle; Layout.leftMargin: 8; Layout.fillWidth: true }
            IconButton { icon: "more"; tip: "More options" }
            IconButton { icon: "open"; tip: "Open full page"; onClicked: win.navigate(win.navigationPage) }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 52
            Layout.leftMargin: 20
            Layout.rightMargin: 27
            spacing: 4
            NText {
                id: musicSidePanelCount
                objectName: "music-sidepanel-item-count"
                visible: !root.musicSideSearchOpen
                text: root.musicSideCountText()
                color: Theme.librarySideText
                font.pixelSize: 12
                Layout.fillWidth: true
            }
            NField {
                visible: root.musicSideSearchOpen
                Layout.fillWidth: true
                placeholderText: "Search"
                text: mediaLibrary.model.search
                onTextEdited: mediaLibrary.model.search = text
            }
            IconButton { icon: "sort"; tip: "Sort"; checked: root.musicSideSortByName; onClicked: root.musicSideSortByName = !root.musicSideSortByName }
            IconButton { icon: "view"; tip: "View options"; checked: root.musicSideCompactView; onClicked: root.musicSideCompactView = !root.musicSideCompactView }
            IconButton { icon: root.musicSideSearchOpen ? "close" : "search"; tip: root.musicSideSearchOpen ? "Close search" : "Search"; onClicked: { root.musicSideSearchOpen = !root.musicSideSearchOpen; if (!root.musicSideSearchOpen) mediaLibrary.model.search = "" } }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }

        Item {
            objectName: "music-sidepanel-add"
            Layout.fillWidth: true
            Layout.preferredHeight: 36
            Layout.topMargin: 16
            Layout.leftMargin: 25
            activeFocusOnTab: true
            Accessible.role: Accessible.Button
            Accessible.name: "Add folder to music library"
            Accessible.focusable: true
            Keys.onPressed: event => {
                if ((event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !event.isAutoRepeat) {
                    root.indexFolder()
                    event.accepted = true
                }
            }
            Rectangle {
                anchors.fill: parent
                radius: Theme.radiusSmall
                color: addFolderMouse.containsMouse ? Theme.hover : "transparent"
                border.width: parent.activeFocus ? 1 : 0
                border.color: Theme.accent
            }
            Icon { anchors.left: parent.left; anchors.leftMargin: 1; anchors.verticalCenter: parent.verticalCenter; name: "plus"; size: 16; color: Theme.icon }
            NText { anchors.left: parent.left; anchors.leftMargin: 36; anchors.verticalCenter: parent.verticalCenter; text: "Add"; font.pixelSize: 13; color: Theme.librarySideText }
            MouseArea { id: addFolderMouse; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { parent.forceActiveFocus(); root.indexFolder() } }
        }

        ColumnLayout {
            objectName: "music-sidepanel-categories"
            visible: root.musicSidePage === "categories"
            Layout.fillWidth: true
            Layout.preferredHeight: visible ? root.visibleMusicCategories().length * (root.musicSideCompactView ? 36 : 44) : 0
            spacing: 0
            Repeater {
                model: root.visibleMusicCategories()
                delegate: Item {
                    required property var modelData
                    objectName: "music-sidepanel-category-" + modelData.page
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.musicSideCompactView ? 36 : 44
                    activeFocusOnTab: true
                    Accessible.role: Accessible.Button
                    Accessible.name: modelData.label
                    Accessible.focusable: true
                    Keys.onPressed: event => {
                        if ((event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !event.isAutoRepeat) {
                            root.openMusicSidePage(modelData.page)
                            event.accepted = true
                        }
                    }
                    Rectangle {
                        anchors.fill: parent
                        color: categoryMouse.containsMouse ? Theme.hover : "transparent"
                        border.width: parent.activeFocus ? 1 : 0
                        border.color: Theme.accent
                    }
                    Icon { anchors.left: parent.left; anchors.leftMargin: 26; anchors.verticalCenter: parent.verticalCenter; name: modelData.icon; size: 18; color: Theme.icon }
                    NText { anchors.left: parent.left; anchors.leftMargin: 62; anchors.verticalCenter: parent.verticalCenter; text: modelData.label; font.pixelSize: 13; color: Theme.librarySideText }
                    MouseArea { id: categoryMouse; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { parent.forceActiveFocus(); root.openMusicSidePage(modelData.page) } }
                }
            }
        }

        ColumnLayout {
            objectName: "music-sidepanel-roots"
            visible: root.musicSidePage === "songs" && !root.musicSideFolderRoot.length
            Layout.fillWidth: true
            Layout.minimumHeight: 0
            Layout.preferredHeight: visible ? Math.max(1, mediaLibrary.roots.length * (root.musicSideCompactView ? 36 : 44)) : 1
            Layout.maximumHeight: visible ? Math.max(1, mediaLibrary.roots.length * (root.musicSideCompactView ? 36 : 44)) : 1
            spacing: 0
            Repeater {
                model: mediaLibrary.roots
                delegate: Item {
                    required property string modelData
                    objectName: "music-sidepanel-root-" + root.musicSideRootLabel(modelData)
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.musicSideCompactView ? 36 : 44
                    activeFocusOnTab: true
                    Accessible.role: Accessible.Button
                    Accessible.name: root.musicSideRootLabel(modelData)
                    Accessible.focusable: true
                    Keys.onPressed: event => {
                        if ((event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !event.isAutoRepeat) {
                            root.musicSideFolderRoot = modelData
                            mediaLibrary.model.search = ""
                            event.accepted = true
                        }
                    }
                    Rectangle {
                        anchors.fill: parent
                        color: rootItemMouse.containsMouse ? Theme.hover : "transparent"
                        border.width: parent.activeFocus ? 1 : 0
                        border.color: Theme.accent
                    }
                    Icon { anchors.left: parent.left; anchors.leftMargin: 26; anchors.verticalCenter: parent.verticalCenter; name: "folder"; size: 18; color: Theme.icon }
                    NText { anchors.left: parent.left; anchors.leftMargin: 62; anchors.verticalCenter: parent.verticalCenter; text: root.musicSideRootLabel(modelData); font.pixelSize: 13; color: Theme.librarySideText }
                    MouseArea {
                        id: rootItemMouse
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            parent.forceActiveFocus()
                            root.musicSideFolderRoot = modelData
                            mediaLibrary.model.search = ""
                        }
                    }
                }
            }
        }

        NText {
            visible: root.musicSidePage === "songs" && !root.musicSideFolderRoot.length && mediaLibrary.roots.length === 0
            Layout.leftMargin: 62
            Layout.topMargin: 6
            text: "No music folders"
            color: Theme.librarySideText
            font.pixelSize: 12
        }

        ListView {
            objectName: "music-sidepanel-tracks"
            visible: root.musicSidePage === "songs" && root.musicSideFolderRoot.length > 0
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: root.musicSideTracks()
            delegate: Rectangle {
                required property int index
                required property var modelData
                objectName: "music-sidepanel-track-" + index
                width: ListView.view.width
                height: 44
                radius: Theme.radiusSmall
                color: trackMouse.containsMouse ? Theme.hover : "transparent"
                border.width: activeFocus ? 1 : 0
                border.color: Theme.accent
                activeFocusOnTab: true
                Accessible.role: Accessible.Button
                Accessible.name: modelData.title
                                  + (modelData.artist.length ? " by " + modelData.artist : "")
                                  + " (" + platform.localPath(modelData.path).split("/").pop() + ")"
                Accessible.focusable: true
                Keys.onPressed: event => {
                    if ((event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !event.isAutoRepeat) {
                        player.openUrls([platform.fileUrl(modelData.path)], true)
                        event.accepted = true
                    }
                }
                RowLayout {
                    anchors.fill: parent
                    // Match the 36 px cover inset in the Figma track rows.
                    anchors.leftMargin: 36
                    anchors.rightMargin: 18
                    spacing: 6
                    Rectangle {
                        Layout.preferredWidth: 32
                        Layout.preferredHeight: 32
                        radius: 3
                        color: Theme.surface
                        Image {
                            id: trackCover
                            anchors.fill: parent
                            source: modelData.artwork && modelData.artwork.length ? platform.fileUrl(modelData.artwork) : ""
                            fillMode: Image.PreserveAspectCrop
                            visible: status === Image.Ready
                        }
                        Icon { anchors.centerIn: parent; name: "music"; size: 17; color: Theme.icon; visible: trackCover.status !== Image.Ready }
                    }
                    NText {
                        Layout.fillWidth: true
                        text: modelData.title + (modelData.artist.length ? " - " + modelData.artist : "")
                        font.pixelSize: 12
                        color: Theme.librarySideText
                        elide: Text.ElideRight
                    }
                }
                MouseArea {
                    id: trackMouse
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        parent.forceActiveFocus()
                        player.openUrls([platform.fileUrl(modelData.path)], true)
                    }
                }
            }
            NText {
                anchors.centerIn: parent
                visible: parent.visible && parent.count === 0
                text: "No songs in this folder"
                color: Theme.librarySideText
                font.pixelSize: 12
            }
        }

        Item { Layout.fillHeight: true }
    }

    Rectangle {
        id: miniPlayer
        visible: root.wide && win.libraryFullPage && player.hasVideo
        anchors.bottom: parent.bottom
        x: root.folderViewMode === "list" ? root.mapFromItem(win.contentItem, 6, 0).x : parent.width - width - 12
        anchors.bottomMargin: 6
        width: Math.min(390, root.width * 0.34)
        height: width * 0.87
        radius: 12
        color: Theme.bar
        border.color: Theme.border
        z: 2

        HoverHandler { id: miniPlayerHover }

        Item {
            id: miniVideoSurface
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 8
            height: width * 9 / 16
            clip: true

            MouseArea {
                anchors.fill: parent
                z: 1
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: (event) => {
                    if (tracksPopup.visible) tracksPopup.close()
                    if (event.button === Qt.LeftButton) win.navigate("player")
                    else {
                        const point = miniVideoSurface.mapToItem(keyCatcher, event.x, event.y)
                        contextMenu.popup(point.x, point.y)
                    }
                }
            }
        }
        Rectangle {
            anchors.left: miniVideoHost.left
            anchors.right: miniVideoHost.right
            anchors.top: miniVideoHost.bottom
            height: 6
            radius: 3
            color: Theme.field
            Rectangle { width: parent.width * player.position; height: parent.height; radius: 3; color: Theme.accentDim }
        }
        NText {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            anchors.top: miniVideoHost.bottom
            anchors.topMargin: 14
            text: player.title.length ? player.title : "Now playing"
            font.pixelSize: 11
        }
        RowLayout {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: 12
            anchors.rightMargin: 6
            anchors.bottomMargin: 4
            spacing: 6
            Icon { name: "folder"; size: 13; color: Theme.textDim }
            NText { text: player.folderName; dim: true; font.pixelSize: 10; Layout.fillWidth: true }
        }
        IconButton {
            objectName: "mini-player-return"
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: 8
            anchors.rightMargin: 8
            z: 3
            visible: miniPlayerHover.hovered
            icon: "maximize"
            iconSize: 15
            tip: "Expand player"
            Accessible.name: "Expand player"
            onClicked: win.navigate("player")
        }
    }

    component LibraryRow: Rectangle {
        id: row
        property string label
        property string iconName: "video"
        property url url
        property bool isDir: false
        property bool playing: false
        Layout.fillWidth: true
        width: ListView.view ? ListView.view.width : implicitWidth
        implicitHeight: 34
        color: playing ? Theme.accentSoft : (rowMouse.containsMouse ? Theme.hover : "transparent")

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 4
            spacing: 10
            Icon { name: row.iconName; size: 16; color: row.playing ? Theme.accent : Theme.icon }
            NText { text: row.label; Layout.fillWidth: true; color: row.playing ? Theme.accent : Theme.text }
            IconButton {
                visible: rowMouse.containsMouse || hovered
                icon: "plus"; iconSize: 14; tip: "Add to queue"
                onClicked: player.openUrls([row.url], false)
            }
        }
        MouseArea {
            id: rowMouse
            anchors.fill: parent
            anchors.rightMargin: 34
            hoverEnabled: true
            drag.target: dragProxy
            onClicked: row.isDir ? root.openFolder(row.url) : player.openUrls([row.url], true)
        }
        // Drag to the queue (or anywhere that accepts file urls).
        Item {
            id: dragProxy
            Drag.active: rowMouse.drag.active
            Drag.dragType: Drag.Automatic
            Drag.supportedActions: Qt.CopyAction
            Drag.mimeData: { "text/uri-list": row.url.toString() }
        }
    }
}
