import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtCore
import Qt.labs.folderlistmodel
import Neo 1.0

// Local media browser with a full-window mode and a compact embedded mode.
Rectangle {
    id: root
    color: root.wide ? Theme.window : Theme.panel
    property bool wide: false
    property url folder: player.folderPath.length ? platform.fileUrl(player.folderPath)
                                                  : StandardPaths.writableLocation(StandardPaths.MoviesLocation)
    property string section: "folder"   // home | folder | recent
    property string sortBy: "name"
    property string mediaType: "all"   // all | video | audio
    property string searchText: ""
    property int filteredCount: 0
    property alias miniVideoHost: miniVideoSurface
    signal openFiles()

    readonly property var mediaFilters: ["*.mkv", "*.mp4", "*.avi", "*.mov", "*.webm", "*.m4v", "*.wmv", "*.flv", "*.ts",
        "*.m2ts", "*.mpg", "*.mpeg", "*.3gp", "*.ogv", "*.mp3", "*.flac", "*.ogg", "*.opus", "*.m4a", "*.aac", "*.wav",
        "*.wma", "*.alac", "*.ape", "*.m3u", "*.m3u8", "*.pls", "*.xspf", "*.iso"]
    readonly property var videoFilters: ["*.mkv", "*.mp4", "*.avi", "*.mov", "*.webm", "*.m4v", "*.wmv", "*.flv", "*.ts",
        "*.m2ts", "*.mpg", "*.mpeg", "*.3gp", "*.ogv", "*.iso"]
    readonly property var audioFilters: ["*.mp3", "*.flac", "*.ogg", "*.opus", "*.m4a", "*.aac", "*.wav", "*.wma", "*.alac", "*.ape"]
    readonly property var audioExt: ["mp3", "flac", "ogg", "opus", "m4a", "aac", "wav", "wma", "alac", "ape"]

    function pinnedList() { return Theme.store.pinned.length ? Theme.store.pinned.split("\n") : [] }
    function togglePin(path) {
        let list = pinnedList()
        const i = list.indexOf(path)
        if (i >= 0) list.splice(i, 1); else list.push(path)
        Theme.store.pinned = list.join("\n")
    }
    function openFolder(url) { root.folder = url; root.section = "folder"; root.mediaType = "all" }
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

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // Header: navigation, breadcrumbs and local search.
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            implicitHeight: 42
            spacing: 2
            IconButton { icon: "chevron-left"; tip: "Up"; visible: root.section === "folder"; onClicked: root.openFolder(files.parentFolder) }
            Chips {
                visible: !root.wide
                model: [{ label: "Home", value: "home" }, { label: "Browse", value: "folder" }, { label: "Recent", value: "recent" }]
                current: root.section
                onPicked: (v) => root.section = v
            }
            NText {
                visible: root.wide
                text: root.section === "folder" ? root.crumbs().map(c => c.name).join("  ›  ")
                      : (root.section === "recent" ? "Recent media" : "Home")
                font.pixelSize: 12
                Layout.leftMargin: 8
                Layout.fillWidth: true
            }
            Item { Layout.fillWidth: true }
            NText { visible: root.wide; text: root.matchingFiles() + " items"; dim: true; font.pixelSize: 11 }
            IconButton {
                icon: "arrow-up"; tip: "Sort: " + root.sortBy
                onClicked: root.sortBy = root.sortBy === "name" ? "date" : (root.sortBy === "date" ? "size" : "name")
            }
            NField {
                visible: root.wide
                objectName: "library-search"
                Layout.preferredWidth: 190
                text: root.searchText
                placeholderText: "Search"
                onTextEdited: root.searchText = text
            }
            IconButton { visible: root.wide; icon: "plus"; tip: "Add media"; onClicked: root.openFiles() }
            IconButton { icon: "x"; tip: "Close"; onClicked: win.libraryOpen = false }
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
            visible: root.section === "folder" && !root.wide
            Layout.fillWidth: true
            Layout.leftMargin: 10
            Layout.rightMargin: 10
            Layout.bottomMargin: 6
            spacing: 6
            NButton { text: "Play folder"; icon: "play"; Layout.fillWidth: true; onClicked: player.openUrls([root.folder], true) }
            NButton { text: "Queue all"; icon: "plus"; Layout.fillWidth: true; onClicked: player.openUrls([root.folder], false) }
            IconButton {
                icon: "bookmark"; tip: "Pin this folder"
                checked: root.pinnedList().indexOf(platform.localPath(root.folder)) >= 0
                onClicked: root.togglePin(platform.localPath(root.folder))
            }
        }
        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }

        // Folder listing
        GridView {
            id: listing
            visible: root.section === "folder"
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.leftMargin: root.wide ? 12 : 0
            Layout.rightMargin: root.wide ? 12 : 0
            clip: true
            model: files
            boundsBehavior: Flickable.StopAtBounds
            cellWidth: root.wide ? Math.max(180, Math.floor(width / 4)) : width
            cellHeight: root.wide ? 36 : 34
            ScrollBar.vertical: ScrollBar {}
            delegate: Rectangle {
                id: mediaCell
                required property string fileName
                required property url fileUrl
                required property bool fileIsDir
                required property string fileSuffix
                width: listing.cellWidth - (root.wide ? 8 : 0)
                height: listing.cellHeight - 2
                visible: root.matches(fileName)
                radius: Theme.radiusSmall
                property bool playing: !fileIsDir && player.mediaUrl.toString() === fileUrl.toString()
                color: playing ? Theme.accentSoft : (cellMouse.containsMouse ? Theme.hover : "transparent")

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: root.wide ? 8 : 12
                    anchors.rightMargin: 5
                    spacing: root.wide ? 7 : 10
                    Icon { name: mediaCell.fileIsDir ? "folder" : (root.audioExt.indexOf(mediaCell.fileSuffix.toLowerCase()) >= 0 ? "music" : "file-video"); size: root.wide ? 15 : 16; color: mediaCell.playing ? Theme.accent : Theme.icon }
                    NText { text: mediaCell.fileName; Layout.fillWidth: true; font.pixelSize: root.wide ? 11 : Theme.fontBody; color: mediaCell.playing ? Theme.accent : Theme.text }
                    IconButton {
                        visible: cellMouse.containsMouse || hovered
                        icon: "plus"; iconSize: 13; tip: "Add to queue"
                        onClicked: player.openUrls([mediaCell.fileUrl], false)
                    }
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
                        required property string modelData
                        label: modelData.split("/").pop(); iconName: "bookmark"; url: platform.fileUrl(modelData); isDir: true
                    }
                }
                NText { text: "Recent"; dim: true; font.pixelSize: 11; Layout.leftMargin: 14; Layout.topMargin: 10 }
                Repeater {
                    model: root.visible && root.section === "home" ? player.recentMedia() : []
                    delegate: LibraryRow {
                        required property string modelData
                        label: decodeURIComponent(modelData.split("/").pop()); iconName: "history"; url: modelData; isDir: false
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
                    model: root.visible && root.section === "recent" ? player.recentMedia() : []
                    delegate: LibraryRow {
                        required property string modelData
                        label: decodeURIComponent(modelData.split("/").pop())
                        iconName: "recent"
                        url: modelData
                        isDir: false
                    }
                }
                NText {
                    visible: root.visible && root.section === "recent" && player.recentMedia().length === 0
                    text: "No recent media"
                    dim: true
                    Layout.leftMargin: 14
                    Layout.topMargin: 8
                }
            }
        }
    }

    Rectangle {
        id: miniPlayer
        visible: root.wide && player.hasVideo
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 12
        anchors.bottomMargin: 12
        width: Math.min(270, root.width * 0.34)
        height: 220
        radius: 12
        color: Theme.bar
        border.color: Theme.border
        z: 2

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
                    if (event.button === Qt.LeftButton) win.libraryOpen = false
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
            IconButton { icon: "maximize"; tip: "Return to player"; onClicked: win.libraryOpen = false }
        }
    }

    component LibraryRow: Rectangle {
        id: row
        property string label
        property string iconName: "file-video"
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
