import QtQuick
import QtQuick.Layouts
import Neo 1.0

// First run: welcome, theme + accent, basic shortcuts.
Modal {
    id: root
    closable: false
    width: 720
    property int step: 0
    onOpened: step = 0

    ColumnLayout {
        width: root.width - 36
        spacing: 16

        // Step 0: welcome
        ColumnLayout {
            visible: root.step === 0
            Layout.fillWidth: true
            Layout.preferredWidth: root.width - 36
            spacing: 14
            Icon { name: "cone"; size: 84; Layout.alignment: Qt.AlignHCenter; Layout.topMargin: 12 }
            NText { text: "Welcome to VLC"; font.pixelSize: 22; font.weight: Font.DemiBold; Layout.alignment: Qt.AlignHCenter }
            NText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                dim: true
                text: "Same VLC engine, new interface. Your codecs, settings and updates stay exactly as they are."
            }
            VlcOption { option: "metadata-network-access"; label: "Allow fetching media information from the internet"; Layout.topMargin: 10 }
        }

        // Step 1: theme and colour
        ColumnLayout {
            visible: root.step === 1
            Layout.fillWidth: true
            Layout.preferredWidth: root.width - 36
            spacing: 16
            NText { text: "Select your preferred theme and color."; Layout.alignment: Qt.AlignHCenter; font.pixelSize: Theme.fontTitle }
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 18
                Repeater {
                    model: [{ id: "light", label: "Light" }, { id: "dark", label: "Dark" }, { id: "system", label: "System" }]
                    delegate: Column {
                        required property var modelData
                        spacing: 8
                        Rectangle {
                            width: 96; height: 96; radius: 8
                            border.width: 2
                            border.color: Theme.store.mode === modelData.id ? Theme.accent : Theme.border
                            color: modelData.id === "light" ? "#E9E9E9" : "#1B1B1B"
                            clip: true
                            Rectangle {
                                visible: modelData.id === "system"
                                width: parent.width * 1.5; height: parent.height
                                color: "#E9E9E9"
                                rotation: -45
                                x: parent.width * 0.35; y: parent.height * 0.1
                            }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Theme.store.mode = modelData.id }
                        }
                        NText { text: modelData.label; dim: true; font.pixelSize: 12; anchors.horizontalCenter: parent.horizontalCenter }
                    }
                }
            }
            AccentPicker { Layout.alignment: Qt.AlignHCenter; Layout.topMargin: 8 }
        }

        // Step 2: shortcuts
        ColumnLayout {
            visible: root.step === 2
            Layout.fillWidth: true
            Layout.preferredWidth: root.width - 36
            spacing: 10
            NText { text: "Learn the basic keyboard shortcuts"; Layout.alignment: Qt.AlignHCenter; font.pixelSize: Theme.fontTitle }
            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: 30
                rowSpacing: 10
                Repeater {
                    model: [["Play / Pause", "Space"], ["Toggle fullscreen", "F"], ["Seek backward / forward", "←  →"],
                            ["Volume down / up", "↓  ↑"], ["Previous / next item", "P  N"], ["Show / hide queue", "Q"],
                            ["Cycle subtitle track", "V"], ["Show / hide library", "L"], ["Cycle audio track", "B"],
                            ["Take a snapshot", "Shift S"], ["Hide the whole UI", "Ctrl H"], ["All shortcuts", "?"]]
                    delegate: RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        NText { text: modelData[0]; dim: true; Layout.fillWidth: true }
                        Rectangle {
                            implicitWidth: kk.implicitWidth + 16; implicitHeight: 24; radius: 3
                            color: Theme.raised; border.color: Theme.border
                            NText { id: kk; anchors.centerIn: parent; text: modelData[1]; font.pixelSize: 11 }
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 8
            Row {
                spacing: 6
                Repeater {
                    model: 3
                    delegate: Rectangle {
                        required property int index
                        width: index === root.step ? 18 : 6; height: 6; radius: 3
                        color: index === root.step ? Theme.accent : Theme.raised
                        Behavior on width { NumberAnimation { duration: 140 } }
                    }
                }
            }
            Item { Layout.fillWidth: true }
            NButton { visible: root.step > 0; text: "Back"; flat: true; onClicked: root.step-- }
            NButton {
                text: root.step === 2 ? "Finish" : "Next"
                primary: true
                onClicked: {
                    if (root.step < 2) { root.step++; return }
                    Theme.store.onboarded = true
                    root.close()
                }
            }
        }
    }
}
