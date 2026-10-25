import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Dialogs
import QtQuick.Layouts
import Neo 1.0

Modal {
    id: root
    objectName: "new-playlist-dialog"
    title: "New Playlist"
    width: 713
    height: 589
    bodyMargin: 20
    property var mediaFiles: []
    property url coverUrl
    readonly property var audioExtensions: ["mp3", "flac", "ogg", "opus", "m4a", "aac", "wav", "wma", "alac", "ape", "mpc", "wv"]
    property alias nameInput: nameField
    property alias mediaFilesDialog: filesDialog
    property alias mediaDropZone: mediaDropArea
    property alias coverPreview: coverImage

    function iconForMedia(url) {
        const path = platform.localPath(url)
        const extension = path.slice(path.lastIndexOf(".") + 1).toLowerCase()
        return audioExtensions.indexOf(extension) >= 0 ? "music" : "video-file"
    }

    function addFiles(files) {
        const merged = mediaFiles.slice()
        for (const file of files)
            if (merged.indexOf(file) < 0) merged.push(file)
        mediaFiles = merged
    }
    function removeFile(index) {
        const remaining = mediaFiles.slice()
        remaining.splice(index, 1)
        mediaFiles = remaining
    }
    function save() {
        const saved = player.savePlaylist(nameField.text, mediaFiles, coverUrl)
        if (saved) {
            close()
            mediaFiles = []
            coverUrl = ""
            nameField.clear()
        }
        return saved
    }
    onOpened: nameField.forceActiveFocus()

    ColumnLayout {
        width: parent.width
        height: parent.height
        spacing: 14

        NText { text: "Playlist Details"; font.pixelSize: 14; font.weight: Font.Medium }
        RowLayout {
            Layout.fillWidth: true
            spacing: 16
            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                spacing: 10
                NText {
                    text: "The playlist will be saved and displayed with this title and thumbnail."
                    dim: true
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
                NField {
                    id: nameField
                    objectName: "playlist-name"
                    Layout.fillWidth: true
                    placeholderText: "e.g., Favorite Videos"
                    onAccepted: if (mediaFiles.length > 0) root.save()
                }
            }
            Rectangle {
                objectName: "playlist-cover-picker"
                Layout.preferredWidth: 108
                Layout.preferredHeight: 108
                radius: 4
                color: Theme.field
                border.color: Theme.border
                Image {
                    id: coverImage
                    objectName: "playlist-cover-preview"
                    anchors.fill: parent
                    source: root.coverUrl
                    fillMode: Image.PreserveAspectCrop
                    visible: status === Image.Ready
                    clip: true
                }
                Icon { anchors.centerIn: parent; name: "plus"; size: 20; visible: !root.coverUrl.toString().length }
                MouseArea { anchors.fill: parent; onClicked: coverDialog.open() }
                Accessible.name: "Choose playlist thumbnail"
                Accessible.role: Accessible.Button
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }
        NText { text: "Select Files"; font.pixelSize: 14; font.weight: Font.Medium }
        NText { text: "These files will be added to the playlist."; dim: true; font.pixelSize: 12 }

        Rectangle {
            id: mediaDropArea
            objectName: "playlist-media-drop-area"
            Layout.fillWidth: true
            Layout.preferredHeight: 188
            color: Theme.field
            border.color: fileDrop.containsDrag ? Theme.accent : Theme.border
            border.width: fileDrop.containsDrag || mediaFiles.length > 0 ? 1 : 0
            radius: 4
            TapHandler { onTapped: filesDialog.open() }
            Item {
                id: dottedBorder
                anchors.fill: parent
                visible: root.mediaFiles.length === 0 && !fileDrop.containsDrag
                Repeater {
                    model: Math.ceil(dottedBorder.width / 8)
                    Rectangle {
                        required property int index
                        x: index * 8
                        width: 4
                        height: 1
                        color: Theme.border
                    }
                }
                Repeater {
                    model: Math.ceil(dottedBorder.width / 8)
                    Rectangle {
                        required property int index
                        x: index * 8
                        y: dottedBorder.height - height
                        width: 4
                        height: 1
                        color: Theme.border
                    }
                }
                Repeater {
                    model: Math.ceil(dottedBorder.height / 8)
                    Rectangle {
                        required property int index
                        x: 0
                        y: index * 8
                        width: 1
                        height: 4
                        color: Theme.border
                    }
                }
                Repeater {
                    model: Math.ceil(dottedBorder.height / 8)
                    Rectangle {
                        required property int index
                        x: dottedBorder.width - width
                        y: index * 8
                        width: 1
                        height: 4
                        color: Theme.border
                    }
                }
            }
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 8
                Flickable {
                    visible: root.mediaFiles.length > 0
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentHeight: selectedColumn.implicitHeight
                    clip: true
                    Column {
                        id: selectedColumn
                        width: parent.width
                        spacing: 4
                        Repeater {
                            model: root.mediaFiles
                            delegate: Rectangle {
                                required property int index
                                required property var modelData
                                objectName: "playlist-selected-file-" + index
                                width: selectedColumn.width
                                height: 27
                                radius: 3
                                color: Theme.panel
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 4
                                    Icon { objectName: "playlist-selected-file-icon-" + index; name: root.iconForMedia(modelData); size: 13 }
                                    NText { text: decodeURIComponent(modelData.toString().split("/").pop()); Layout.fillWidth: true; font.pixelSize: 11; elide: Text.ElideMiddle }
                                    IconButton { icon: "x"; iconSize: 12; tip: "Remove file"; onClicked: root.removeFile(index) }
                                }
                            }
                        }
                    }
                }
                NText {
                    visible: root.mediaFiles.length === 0
                    text: "Drag files into this box or click here to select files."
                    dim: true
                    font.pixelSize: 12
                    Layout.alignment: Qt.AlignHCenter
                    Layout.fillHeight: true
                    verticalAlignment: Text.AlignVCenter
                }
                NButton {
                    text: root.mediaFiles.length ? "Add files" : "＋"
                    flat: true
                    Layout.alignment: Qt.AlignHCenter
                    onClicked: filesDialog.open()
                }
            }
            DropArea {
                id: fileDrop
                anchors.fill: parent
                keys: ["text/uri-list"]
                onDropped: (drop) => {
                    const files = []
                    for (const url of drop.urls) files.push(url)
                    root.addFiles(files)
                    drop.acceptProposedAction()
                }
            }
            Accessible.name: "Select playlist media files"
            Accessible.role: Accessible.Button
        }
    }

    footer: [
        NButton { text: "Cancel"; Layout.preferredWidth: 98; Layout.preferredHeight: 32; onClicked: root.close() },
        Item { Layout.fillWidth: true },
        NButton { objectName: "playlist-save"; text: "Save"; primary: true; enabledState: nameField.text.trim().length > 0 && root.mediaFiles.length > 0; Layout.preferredWidth: 98; Layout.preferredHeight: 32; onClicked: root.save() }
    ]

    FileDialog {
        id: filesDialog
        title: "Select playlist media"
        fileMode: FileDialog.OpenFiles
        onAccepted: root.addFiles(selectedFiles)
    }
    FileDialog {
        id: coverDialog
        title: "Choose playlist thumbnail"
        fileMode: FileDialog.OpenFile
        nameFilters: ["Images (*.png *.jpg *.jpeg *.webp *.gif)", "All files (*)"]
        onAccepted: root.coverUrl = selectedFile
    }
}
