import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtCore
import Qt.labs.folderlistmodel
import Neo 1.0

// Compact library next to the video: browse folders, play or drag to the queue.
Rectangle {
    id: root
    color: Theme.panel
    property url folder: player.folderPath.length ? platform.fileUrl(player.folderPath)
                                                  : StandardPaths.writableLocation(StandardPaths.MoviesLocation)
    property string section: "folder"   // home | folder
    property string sortBy: "name"

    readonly property var mediaFilters: ["*.mkv", "*.mp4", "*.avi", "*.mov", "*.webm", "*.m4v", "*.wmv", "*.flv", "*.ts",
        "*.m2ts", "*.mpg", "*.mpeg", "*.3gp", "*.ogv", "*.mp3", "*.flac", "*.ogg", "*.opus", "*.m4a", "*.aac", "*.wav",
        "*.wma", "*.alac", "*.ape", "*.m3u", "*.m3u8", "*.pls", "*.xspf", "*.iso"]
    readonly property var audioExt: ["mp3", "flac", "ogg", "opus", "m4a", "aac", "wav", "wma", "alac", "ape"]

    function pinnedList() { return Theme.store.pinned.length ? Theme.store.pinned.split("\n") : [] }
    function togglePin(path) {
        let list = pinnedList()
        const i = list.indexOf(path)
        if (i >= 0) list.splice(i, 1); else list.push(path)
        Theme.store.pinned = list.join("\n")
    }
    function openFolder(url) { root.folder = url; root.section = "folder" }
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
        nameFilters: root.mediaFilters
        showDirsFirst: true
        showDotAndDotDot: false
        caseSensitive: false
        sortField: root.sortBy === "date" ? FolderListModel.Time : (root.sortBy === "size" ? FolderListModel.Size : FolderListModel.Name)
        sortReversed: root.sortBy === "date"
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // Header: back/up + sections
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            implicitHeight: 44
            spacing: 2
            IconButton { icon: "chevron-left"; tip: "Up"; onClicked: root.openFolder(files.parentFolder) }
            Chips {
                model: [{ label: "Home", value: "home" }, { label: "Browse", value: "folder" }]
                current: root.section
                onPicked: (v) => root.section = v
            }
            Item { Layout.fillWidth: true }
            IconButton {
                icon: "arrow-up"; tip: "Sort: " + root.sortBy
                onClicked: root.sortBy = root.sortBy === "name" ? "date" : (root.sortBy === "date" ? "size" : "name")
            }
            IconButton { icon: "x"; tip: "Close"; onClicked: win.libraryOpen = false }
        }

        // Address line (clickable segments)
        Flickable {
            visible: root.section === "folder"
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
            visible: root.section === "folder"
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
        ListView {
            id: listing
            visible: root.section === "folder"
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: files
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {}
            delegate: LibraryRow {
                required property string fileName
                required property url fileUrl
                required property bool fileIsDir
                required property string fileSuffix
                label: fileName
                url: fileUrl
                isDir: fileIsDir
                iconName: fileIsDir ? "folder" : (root.audioExt.indexOf(fileSuffix.toLowerCase()) >= 0 ? "music" : "file-video")
                playing: !fileIsDir && player.mediaUrl.toString() === fileUrl.toString()
            }
            NText {
                anchors.centerIn: parent
                visible: listing.count === 0
                text: "No media in this folder"
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
