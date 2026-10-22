import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Dialogs
import QtQuick.Layouts
import Neo 1.0

// First run: welcome, theme + accent, basic shortcuts.
Modal {
    id: root
    signal topEdgeHoverChanged(bool hovered)
    property alias chromeLayer: onboardingChromeLayer
    closable: false
    bodyMargin: 0
    width: parent ? parent.width : 1090
    height: parent ? parent.height : 759
    property int step: 0
    property string mediaFolderPath: "~/Videos"
    readonly property bool folderPickerVisible: mediaFolderDialog.visible
    readonly property bool compactLayout: root.width < 760 || root.height < 600
    readonly property bool themePreviewActive: root.visible && root.step === 1 && !root.compactLayout
    readonly property real themePreviewInset: root.themePreviewActive ? 18 : 0
    readonly property real themePreviewTop: root.themePreviewActive ? 20 : 0
    readonly property real themePreviewWidth: root.themePreviewActive ? root.width - 36 : root.width
    readonly property real themePreviewHeight: root.themePreviewActive ? root.themePreviewWidth * 9 / 16 : root.height
    readonly property real themeContentTop: themeContent.y
    readonly property real themeContentHeight: themeContent.height
    readonly property real themeContentBottom: themeContent.y + themeContent.height
    readonly property bool themeContentVisible: themeContent.visible
    readonly property real accentPickerRight: accentPicker.x + accentPicker.width
    readonly property real accentPickerCenterY: accentPicker.y + accentPicker.height / 2
    readonly property real footerTop: footer.y
    readonly property real footerCenterY: footer.y + footer.height / 2
    readonly property var shortcutEntries: [
        { label: "Play / Pause", keys: ["Space"] },
        { label: "Toggle Fullscreen", keys: ["F"] },
        { label: "Seek Backward / Forward", keys: ["←", "→"] },
        { label: "Increase / Decrease Volume", keys: ["↑", "↓"] },
        { label: "Previous / Next Item", keys: ["<", ">"] },
        { label: "Show / Hide Queue", keys: ["Q"] },
        { label: "Previous / Next Frame", keys: [",", "."] },
        { label: "Show / Hide File Browser", keys: ["L"] },
        { label: "Cycle Subtitle Track", keys: ["V"] },
        { label: "Take a Snapshot", keys: ["SHIFT", "S"] },
        { label: "Cycle Audio Track", keys: ["B"] },
        { label: "Record", keys: ["SHIFT", "R"] }
    ]
    onOpened: step = 0

    // The Figma onboarding is a full-window step over the player, not a dimmed card.
    Overlay.modal: Item {}
    background: Item {}

    function expandedMediaFolder() {
        const path = mediaFolderPath.trim()
        if (path === "~") return platform.homePath()
        if (path.startsWith("~/")) return platform.homePath() + path.slice(1)
        return path
    }
    function continueFromWelcome() {
        const folder = expandedMediaFolder()
        if (folder.length > 0 && !mediaLibrary.addFolder(platform.fileUrl(folder)))
            return
        step = 1
    }
    function selectAdjacentTheme(currentIndex, offset) {
        const count = themeRepeater.count
        if (count < 1)
            return
        const next = themeRepeater.itemAt((currentIndex + offset + count) % count)
        if (!next)
            return
        next.optionItem.forceActiveFocus()
        Theme.store.mode = next.modelData.id
    }
    function themeOptionPointerState(themeId) {
        for (let i = 0; i < themeRepeater.count; ++i) {
            const delegate = themeRepeater.itemAt(i)
            if (delegate && delegate.modelData.id === themeId) {
                return {
                    hovered: delegate.optionItem.pointerHovered,
                    pointingHand: delegate.optionItem.pointerCursorShape === Qt.PointingHandCursor
                }
            }
        }
        return { hovered: false, pointingHand: false }
    }

    FolderDialog {
        id: mediaFolderDialog
        title: "Choose your media folder"
        currentFolder: platform.fileUrl(root.expandedMediaFolder())
        onAccepted: root.mediaFolderPath = platform.displayPath(selectedFolder)
    }

    Item {
        anchors.fill: parent

        HoverHandler {
            onPointChanged: root.topEdgeHoverChanged(point.position.y < 52)
        }

        // Welcome stays vertically centered like the reference frame.
        ColumnLayout {
            id: welcomeContent
            visible: root.step === 0
            x: (parent.width - width) / 2
            y: parent.height * 0.214
            width: Math.min(600, parent.width - 32)
            spacing: 18
            Icon { name: "cone"; size: 68; Layout.alignment: Qt.AlignHCenter; Layout.topMargin: 0 }
            NText { text: "Welcome to VLC!"; font.pixelSize: 30; font.weight: Font.Normal; Layout.alignment: Qt.AlignHCenter; Layout.topMargin: 12 }
            NText {
                Layout.fillWidth: true
                Layout.topMargin: 17
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                dim: true
                font.pixelSize: 15
                lineHeight: 30
                lineHeightMode: Text.FixedHeight
                text: "VLC is a free and open source cross-platform multimedia player and framework that plays most multimedia files as well as DVDs, Audio CDs, VCDs, and various streaming protocols."
            }
            NText { Layout.fillWidth: true; text: "Choose a Media Folder to get started with"; dim: true; Layout.topMargin: 28 }
            RowLayout {
                Layout.preferredWidth: 584
                Layout.alignment: Qt.AlignLeft
                spacing: 8
                NField {
                    id: mediaFolderField
                    objectName: "onboarding-media-folder"
                    Layout.fillWidth: true
                    text: root.mediaFolderPath
                    onTextEdited: root.mediaFolderPath = text
                    Accessible.name: "Media folder"
                }
                NButton {
                    objectName: "onboarding-browse-media-folder"
                    text: "Browse"
                    Layout.preferredWidth: 110
                    onClicked: mediaFolderDialog.open()
                }
            }
        }

        // Theme choice sits in the upper-middle of the player; colors and actions
        // share the bottom row as they do in the Figma frames.
        ColumnLayout {
            id: themeContent
            visible: root.step === 1
            anchors.horizontalCenter: parent.horizontalCenter
            y: root.themePreviewActive
               ? root.themePreviewTop + root.themePreviewHeight * 0.266
               : parent.height * (root.height < 500 ? 0.18 : 0.30)
            width: parent.width - 32
            spacing: 0
            NText {
                text: "Select your preferred theme and color."
                Layout.alignment: Qt.AlignHCenter
                font.pixelSize: root.compactLayout ? 16 : 24
                dim: true
            }
            RowLayout {
                id: themeCards
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: root.compactLayout ? 18 : 69
                spacing: root.height < 500 ? 14 : 32
                Repeater {
                    id: themeRepeater
                    model: [{ id: "light", label: "Light" }, { id: "dark", label: "Dark" }, { id: "system", label: "System" }]
                    delegate: Column {
                        id: themeDelegate
                        required property int index
                        required property var modelData
                        property alias optionItem: themeOption
                        width: root.height < 500 ? 78 : 124
                        spacing: root.height < 500 ? 8 : 18
                        Item {
                            id: themeOption
                            objectName: "onboarding-theme-" + modelData.id
                            readonly property bool pointerHovered: pointerArea.containsMouse
                            readonly property int pointerCursorShape: pointerArea.cursorShape
                            width: root.height < 500 ? 78 : 124
                            height: width
                            activeFocusOnTab: true
                            readonly property bool focusIndicatorVisible: activeFocus && Theme.store.mode !== modelData.id
                            Accessible.role: Accessible.RadioButton
                            Accessible.name: modelData.label
                            Accessible.checked: Theme.store.mode === modelData.id
                            Keys.onSpacePressed: event => {
                                Theme.store.mode = modelData.id
                                event.accepted = true
                            }
                            Keys.onReturnPressed: event => {
                                Theme.store.mode = modelData.id
                                event.accepted = true
                            }
                            Keys.onEnterPressed: event => {
                                Theme.store.mode = modelData.id
                                event.accepted = true
                            }
                            Keys.onLeftPressed: event => {
                                root.selectAdjacentTheme(themeDelegate.index, -1)
                                event.accepted = true
                            }
                            Keys.onUpPressed: event => {
                                root.selectAdjacentTheme(themeDelegate.index, -1)
                                event.accepted = true
                            }
                            Keys.onRightPressed: event => {
                                root.selectAdjacentTheme(themeDelegate.index, 1)
                                event.accepted = true
                            }
                            Keys.onDownPressed: event => {
                                root.selectAdjacentTheme(themeDelegate.index, 1)
                                event.accepted = true
                            }
                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: -4
                                radius: 8
                                color: "transparent"
                                border.width: 1
                                border.color: Theme.accent
                                visible: themeOption.focusIndicatorVisible
                            }
                            Rectangle {
                                anchors.centerIn: parent
                                width: Theme.store.mode === modelData.id ? parent.width : parent.width * (root.height < 500 ? 0.79 : 0.81)
                                height: width
                                radius: Theme.store.mode === modelData.id ? width * 0.13 : width * 0.12
                                color: Theme.raised
                                border.width: Theme.store.mode === modelData.id ? (root.height < 500 ? 3 : 4) : 0
                                border.color: Theme.accent
                            }
                            Rectangle {
                                id: preview
                                anchors.centerIn: parent
                                width: root.height < 500 ? 60 : 100
                                height: width
                                radius: Theme.store.mode === modelData.id ? width * 0.12 : width * 0.10
                                color: modelData.id === "light" ? "#E9E9E9" : "#1B1B1B"
                                clip: true
                                Canvas {
                                    visible: modelData.id === "system"
                                    anchors.fill: parent
                                    onPaint: {
                                        const context = getContext("2d")
                                        const radius = width * 0.10
                                        context.clearRect(0, 0, width, height)
                                        context.beginPath()
                                        context.moveTo(width * 0.17, 0)
                                        context.lineTo(width - radius, 0)
                                        context.quadraticCurveTo(width, 0, width, radius)
                                        context.lineTo(width, height - radius)
                                        context.quadraticCurveTo(width, height, width - radius, height)
                                        context.lineTo(width * 0.75, height)
                                        context.closePath()
                                        context.fillStyle = "#E9E9E9"
                                        context.fill()
                                    }
                                }
                            }
                            MouseArea {
                                id: pointerArea
                                objectName: "onboarding-theme-pointer-" + modelData.id
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onPressed: themeOption.forceActiveFocus()
                                onClicked: Theme.store.mode = modelData.id
                            }
                        }
                        NText {
                            text: modelData.label
                            dim: true
                            font.pixelSize: root.compactLayout ? 11 : 16
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                    }
                }
            }
        }

        // Shortcut list occupies the same open player canvas on the final step.
        ColumnLayout {
            id: shortcutContent
            visible: root.step === 2
            x: (parent.width - width) / 2
            y: parent.height * 0.084
            width: Math.min(970, parent.width - 48)
            spacing: 18
            NText {
                text: "Learn the basic keyboard shortcuts."
                Layout.alignment: Qt.AlignHCenter
                font.pixelSize: 24
                dim: true
            }
            GridLayout {
                Layout.fillWidth: true
                Layout.topMargin: 38
                columns: 2
                columnSpacing: 178
                rowSpacing: 38
                Repeater {
                    model: root.shortcutEntries
                    delegate: RowLayout {
                        required property int index
                        required property var modelData
                        Layout.fillWidth: true
                        NText {
                            text: modelData.label
                            dim: true
                            font.pixelSize: 15
                            Layout.preferredWidth: index % 2 === 0 ? 190 : 210
                        }
                        Item { Layout.preferredWidth: index % 2 === 0 ? 42 : 29 }
                        RowLayout {
                            spacing: 6
                            Repeater {
                                model: modelData.keys
                                delegate: Rectangle {
                                    required property string modelData
                                    implicitWidth: Math.max(52, keyLabel.implicitWidth + 24,
                                                             modelData === "Space" || modelData === "SHIFT" ? 90 : 0)
                                    implicitHeight: 42
                                    radius: 10
                                    color: Theme.raised
                                    border.width: 2
                                    border.color: Theme.border
                                    NText {
                                        id: keyLabel
                                        anchors.centerIn: parent
                                        text: modelData
                                        font.pixelSize: 13
                                    }
                                }
                            }
                        }
                    }
                }
            }
            NText {
                text: "Find the full list in the menu."
                dim: true
                font.pixelSize: 15
                Layout.topMargin: 51
            }
        }

        Row {
            id: progress
            visible: false
            anchors.left: parent.left
            anchors.leftMargin: 22
            anchors.verticalCenter: footer.verticalCenter
            spacing: 6
            Repeater {
                model: [0, 1, 2]
                delegate: Rectangle {
                    required property int modelData
                    width: modelData === root.step ? 16 : 6
                    height: 6
                    radius: 3
                    color: modelData === root.step ? Theme.accent : Theme.textFaint
                }
            }
        }

        AccentPicker {
            id: accentPicker
            visible: root.step === 1
            compact: root.compactLayout
            anchors.left: parent.left
            anchors.leftMargin: root.compactLayout ? 8 : 41
            anchors.bottom: parent.bottom
            anchors.bottomMargin: root.compactLayout ? 7 : 54
        }

        RowLayout {
            id: footer
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 60
            anchors.leftMargin: 22
            anchors.rightMargin: 61
            anchors.bottomMargin: root.compactLayout ? 5 : 54
            spacing: 8

            Item { Layout.fillWidth: true }
            NButton {
                visible: root.step > 0
                text: "Back"
                Layout.preferredWidth: 100
                onClicked: root.step--
            }
            NButton {
                objectName: "onboarding-next"
                text: root.step === 2 ? "Finish" : "Next"
                primary: true
                Layout.preferredWidth: 100
                onClicked: {
                    if (root.step === 0) { root.continueFromWelcome(); return }
                    if (root.step < 2) { root.step++; return }
                    Theme.store.onboarded = true
                    root.close()
                }
            }
        }
    }

    Item {
        id: onboardingChromeLayer
        anchors.fill: parent
        z: 100
    }
}
