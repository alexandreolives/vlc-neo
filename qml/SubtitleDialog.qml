import QtQuick
import QtQuick.Layouts
import QtQuick.Dialogs
import Neo 1.0

// Add subtitles to this file, or to the whole folder (every episode).
Modal {
    id: root
    title: "Add Subtitles"
    subtitle: player.title
    width: 520
    property string target: "file"
    property string linked: ""
    onOpened: linked = player.linkedSubtitleFolder()

    ColumnLayout {
        width: root.width - 36
        spacing: 12
        NText { text: "Add subtitles to"; dim: true }
        Chips {
            model: [{ label: "This file", value: "file" }, { label: "This folder (all episodes)", value: "folder" }]
            current: root.target
            onPicked: (v) => root.target = v
        }
        NText {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            dim: true
            font.pixelSize: 12
            text: root.target === "file"
                  ? "Pick a subtitle file. It is attached to the video that is playing now."
                  : "Pick the folder that holds the subtitles (an extracted zip is fine). Each episode in “"
                    + (player.folderName || "this folder") + "” gets its subtitle automatically, even when the file names "
                    + "differ, by matching episode numbers like S01E05 or “05”. It is remembered for future episodes."
        }
        Rectangle {
            visible: root.target === "folder" && root.linked.length > 0
            Layout.fillWidth: true
            implicitHeight: 40
            radius: Theme.radiusSmall
            color: Theme.surface
            border.color: Theme.accent
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 6
                Icon { name: "check"; size: 15; color: Theme.accent }
                NText { text: "Linked: " + root.linked; Layout.fillWidth: true; font.pixelSize: 12 }
                NButton { text: "Unlink"; flat: true; onClicked: { player.unlinkSubtitleFolder(); root.linked = "" } }
            }
        }
        NText { text: "Source"; dim: true; Layout.topMargin: 4 }
        RowLayout {
            spacing: 8
            NButton {
                text: root.target === "file" ? "Choose file on this computer" : "Choose folder on this computer"
                icon: root.target === "file" ? "file-video" : "folder-open"
                primary: true
                onClicked: root.target === "file" ? fileDialog.open() : folderDialog.open()
            }
            NButton {
                text: "Search OpenSubtitles"
                icon: "link"
                onClicked: Qt.openUrlExternally("https://www.opensubtitles.com/en/search-all/q-"
                                                + encodeURIComponent(player.title.replace(/\.[^.]+$/, "")))
            }
        }
    }

    FileDialog {
        id: fileDialog
        title: "Choose a subtitle file"
        currentFolder: player.folderPath.length ? platform.fileUrl(player.folderPath) : ""
        nameFilters: ["Subtitles (*.srt *.ass *.ssa *.sub *.vtt *.smi *.idx)", "All files (*)"]
        onAccepted: { player.addSubtitleFile(selectedFile); root.close() }
    }
    FolderDialog {
        id: folderDialog
        title: "Choose the subtitles folder"
        currentFolder: player.folderPath.length ? platform.fileUrl(player.folderPath) : ""
        onAccepted: { player.linkSubtitleFolder(selectedFolder); root.close() }
    }
}
