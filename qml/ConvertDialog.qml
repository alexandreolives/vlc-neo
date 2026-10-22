import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtQuick.Dialogs
import QtCore
import Neo 1.0

Modal {
    id: root
    title: "Convert Media"
    subtitle: "Transcode the current media with a separate VLC process."
    width: 560
    closable: !vlcTasks.busy
    property string format: "mp4"
    property url outputFile
    property string errorText: ""

    onOpened: {
        format = "mp4"
        outputFile = ""
        errorText = ""
    }

    ColumnLayout {
        width: root.width - 36
        spacing: 12
        SettingRow {
            label: "Source"
            NText { Layout.fillWidth: true; text: player.hasMedia ? player.title : "Open a media file first"; dim: !player.hasMedia; elide: Text.ElideMiddle }
        }
        SectionTitle { text: "Output format" }
        Chips {
            Layout.fillWidth: true
            model: [{ label: "MP4 · H.264", value: "mp4" }, { label: "MP3 · Audio", value: "mp3" }, { label: "WebM", value: "webm" }]
            current: root.format
            onPicked: (v) => {
                root.format = v
                root.outputFile = ""
                root.errorText = ""
            }
        }
        NText {
            Layout.fillWidth: true
            text: root.outputFile.toString().length ? root.outputFile.toString().replace(/^file:\/\//, "") : "Choose where to save the converted file."
            dim: !root.outputFile.toString().length
            elide: Text.ElideMiddle
        }
        NButton {
            objectName: "convert-choose-output"
            text: "Choose output file…"
            icon: "folder"
            Layout.fillWidth: true
            enabledState: !vlcTasks.busy
            onClicked: outputPicker.open()
        }
        NText {
            visible: root.errorText.length > 0 || vlcTasks.status.length > 0
            Layout.fillWidth: true
            text: root.errorText.length ? root.errorText : vlcTasks.status
            color: vlcTasks.status.startsWith("Conversion complete") ? Theme.accent : Theme.textDim
            wrapMode: Text.Wrap
        }
        BusyIndicator { visible: vlcTasks.busy; running: visible; Layout.alignment: Qt.AlignHCenter }
    }

    FileDialog {
        id: outputPicker
        title: "Save converted media"
        fileMode: FileDialog.SaveFile
        nameFilters: root.format === "mp4" ? ["MP4 video (*.mp4)"]
                    : root.format === "mp3" ? ["MP3 audio (*.mp3)"] : ["WebM video (*.webm)"]
        defaultSuffix: root.format
        onAccepted: { root.outputFile = selectedFile; root.errorText = "" }
    }

    footer: [
        Item { Layout.fillWidth: true },
        NButton { text: vlcTasks.busy ? "Stop" : "Close"; flat: true; onClicked: vlcTasks.busy ? vlcTasks.stop() : root.close() },
        NButton {
            objectName: "convert-start"
            text: vlcTasks.busy ? "Converting…" : "Convert"
            primary: true
            enabledState: !vlcTasks.busy && player.hasMedia && root.outputFile.toString().length > 0
            onClicked: {
                root.errorText = ""
                if (!vlcTasks.convert(player.mediaUrl, root.outputFile, root.format))
                    root.errorText = vlcTasks.status
            }
        }
    ]
}
