import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Neo 1.0

// One element of the control bar, chosen by id (see Theme.controls).
Item {
    id: root
    required property string controlId
    property bool preview: false        // inside the Customize dialog: no actions
    property bool compactLeadingSpacer: false
    property bool compactSpacer: false
    signal action(string id, Item source)
    readonly property bool onboardingCompact: win.onboardingActive && onboarding.step === 1
    readonly property bool compact: (win.onboardingActive && onboarding.step === 1)
                                    || (parent && parent.width < 720)
    readonly property bool audioOnly: player.hasMedia && !player.hasVideo
    readonly property bool compactMetadata: compact
        && ["hideui", "pip", "foldername", "filename", "artistname", "playlistname", "favorite"].includes(controlId)
    readonly property bool compactActionsHidden: parent && parent.width < 400
        && !["prev", "play", "next", "volume", "fullscreen", "__timeline"].includes(controlId)
    readonly property bool visualizerActive: win.audioVisualizerActive
    readonly property var contentItem: controlId === "__timeline" && loader.item
                                       ? loader.item.seekControl : loader.item
    readonly property Item timelineBar: controlId === "__timeline" && loader.item ? loader.item : null
    readonly property string folderLabel: player.folderPath.length
        ? player.folderPath.split(/[\\/]/).filter(part => part.length).slice(-1)[0] : ""
    readonly property string fileLabel: {
        const path = player.mediaUrl.toString().split(/[?#]/)[0]
        const name = path.split("/").filter(part => part.length).slice(-1)[0] || ""
        try { return decodeURIComponent(name) } catch (error) { return name }
    }

    readonly property bool flexible: controlId === "seek" || controlId === "__timeline"
                                     || (controlId === "spacer" && !compactSpacer)
    visible: !compactLeadingSpacer && !compactMetadata && !compactActionsHidden
             && !(audioOnly && ["audio", "subtitle", "settings"].includes(controlId))
             && (controlId !== "visualizer" || audioOnly || visualizerActive)
             && (controlId !== "__timeline" || (!preview && !win.onboardingActive))
    implicitWidth: loader.item ? loader.item.implicitWidth : 0
    implicitHeight: controlId === "__timeline" ? Theme.barHeight : 28

    function fire() { if (!preview) root.action(controlId, root) }

    Loader {
        id: loader
        anchors.fill: parent
        sourceComponent: {
            switch (root.controlId) {
            case "play": return playComp
            case "time": return timeComp
            case "length": return lengthComp
            case "seek": return seekComp
            case "__timeline": return timelineComp
            case "volume": return volumeComp
            case "speed": return speedComp
            case "spacer": return spacerComp
            case "divider": return dividerComp
            case "filename": return fileNameComp
            case "artistname": return artistNameComp
            case "foldername": return folderNameComp
            case "playlistname": return playlistNameComp
            default: return buttonComp
            }
        }
    }

    Component {
        id: buttonComp
        IconButton {
            readonly property var meta: Theme.controls[root.controlId] || { icon: "minus", label: root.controlId }
            icon: root.controlId === "fullscreen" && win.fullscreen ? "minimize-2"
                  : root.controlId === "loop" && player.repeatOne ? "repeat-1" : meta.icon
            tip: meta.label
            iconSize: root.onboardingCompact ? 16 : (root.compact ? 20 : 24)
            iconOffsetX: root.controlId === "cast" ? 1 : 0
            iconOffsetY: root.controlId === "cast" ? -1 : 0
            implicitWidth: 30
            implicitHeight: 30
            checked: (root.controlId === "queue" && win.rightPanel === "queue")
                     || (root.controlId === "settings" && win.rightPanel === "settings")
                     || (root.controlId === "loop" && (player.loop || player.repeatOne))
                     || (root.controlId === "shuffle" && player.random)
                     || (root.controlId === "record" && player.recording)
                     || (root.controlId === "visualizer" && (win.audioVisualizerOpen || win.audioVisualizerActive))
                     || (root.controlId === "cast" && player.rendererDevices.some(device => device.selected))
                     || (root.controlId === "library" && win.libraryOpen)
                     || (root.controlId === "favorite" && Theme.isFavorite(player.mediaUrl.toString()))
                     || (root.controlId === "thumbnail" && Theme.store.showSeekThumbnails)
            iconColor: root.controlId === "record" && player.recording ? "#E0453A"
                       : checked ? Theme.accent : (hovered ? Theme.text : Theme.icon)
            onClicked: root.fire()
        }
    }
    Component {
        id: playComp
        PlayButton {
            compact: root.compact
            onboarding: root.onboardingCompact
            onClicked: root.fire()
        }
    }
    Component {
        id: timeComp
        Item {
            implicitWidth: root.compact ? 56 : 76
            NText {
                anchors.fill: parent
                horizontalAlignment: Text.AlignHCenter
                text: player.formatTime(player.time)
                dim: true
                font.pixelSize: root.onboardingCompact ? 10 : (root.compact ? 12 : 15)
                font.features: { "tnum": 1 }
            }
        }
    }
    Component {
        id: lengthComp
        Item {
            implicitWidth: root.compact ? 56 : 76
            NText {
                anchors.fill: parent
                horizontalAlignment: Text.AlignHCenter
                text: player.formatTime(player.length)
                dim: true
                font.pixelSize: root.compact ? 12 : 15
                font.features: { "tnum": 1 }
            }
        }
    }
    Component {
        id: seekComp
        SeekBar { implicitWidth: root.compact ? 60 : 120; enabled: !root.preview }
    }
    Component {
        id: timelineComp
        TimelineBar {
            compact: root.compact
            tiny: root.parent.width < 400
        }
    }
    Component {
        id: volumeComp
        Row {
            spacing: root.compact ? 2 : 8
            IconButton {
                objectName: "control-volume-mute"
                icon: player.muted || player.volume === 0 ? "volume-x" : (player.volume < 0.5 ? "volume-1" : "volume-2")
                tip: "Mute"
                iconSize: root.onboardingCompact ? 16 : (root.compact ? 20 : 24)
                implicitWidth: 30
                implicitHeight: 30
                anchors.verticalCenter: parent.verticalCenter
                onClicked: if (!root.preview) player.toggleMute()
            }
            ConeVolume { anchors.verticalCenter: parent.verticalCenter; compact: root.compact; enabled: !root.preview }
        }
    }
    Component {
        id: speedComp
        Rectangle {
            implicitWidth: 44
            radius: Theme.radiusSmall
            color: speedMouse.containsMouse ? Theme.hover : "transparent"
            NText {
                anchors.centerIn: parent
                text: player.rate.toFixed(2).replace(/\.?0+$/, "") + "x"
                font.pixelSize: 12
                color: Math.abs(player.rate - 1) > 0.01 ? Theme.accent : Theme.icon
            }
            MouseArea { id: speedMouse; anchors.fill: parent; hoverEnabled: true; onClicked: root.fire() }
        }
    }
    Component {
        id: spacerComp
        Item { implicitWidth: 12 }
    }
    Component {
        id: dividerComp
        Rectangle {
            implicitWidth: 1
            implicitHeight: 22
            color: Theme.border
            anchors.verticalCenter: parent.verticalCenter
        }
    }
    Component {
        id: fileNameComp
        MetadataLabel { text: root.fileLabel.length ? root.fileLabel : "No media"; tip: "File name" }
    }
    Component {
        id: artistNameComp
        MetadataLabel { text: player.artist.length ? player.artist : "Unknown artist"; tip: "Artist" }
    }
    Component {
        id: folderNameComp
        MetadataLabel { text: root.folderLabel.length ? root.folderLabel : "No folder"; tip: "Folder" }
    }
    Component {
        id: playlistNameComp
        MetadataLabel { text: player.playlistName; tip: "Playlist name" }
    }
    component MetadataLabel: Item {
        property string text
        property string tip
        implicitWidth: Math.min(160, Math.max(48, label.implicitWidth + 12))
        implicitHeight: 28
        NText {
            id: label
            anchors.fill: parent
            anchors.leftMargin: 6
            anchors.rightMargin: 6
            verticalAlignment: Text.AlignVCenter
            text: parent.text
            elide: Text.ElideMiddle
            dim: true
            font.pixelSize: 12
            ToolTip.visible: hover.hovered
            ToolTip.text: parent.tip
            HoverHandler { id: hover }
        }
    }
}
