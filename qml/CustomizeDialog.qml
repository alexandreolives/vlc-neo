import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Neo 1.0

// Drag buttons into the bar, drag them out to remove, drag inside the bar to reorder.
// Previous, Play and Next are permanent transport controls and stay outside the palette.
Modal {
    id: root
    title: "Customize Player"
    subtitle: "Drag items onto the bar below to add them. Drag them within the bar to reorder, or back here to remove. Previous, Play and Next stay on the bar."
    width: Math.min(parent ? parent.width - 60 : 1060, 1060)
    height: Math.min(parent ? parent.height - 20 : 666, 666)
    property var items: []
    property var profiles: []
    property alias profileNameInput: profileName
    property alias paletteArea: paletteArea
    property alias contentScroller: bodyScroller
    onOpened: {
        items = Theme.layoutList()
        profiles = Theme.profileList()
    }

    readonly property var allIds: Theme.customizationIds
    readonly property var available: allIds.filter(id => id === "spacer" || items.indexOf(id) < 0)

    function insertAt(id, index, fromIndex) {
        let list = items.slice()
        if (fromIndex !== undefined && fromIndex >= 0) {
            list.splice(fromIndex, 1)
            if (index > fromIndex) index--
        }
        index = Math.max(0, Math.min(index, list.length))
        list.splice(index, 0, id)
        items = list
    }
    function removeAt(i) {
        if (["prev", "play", "next"].includes(items[i])) return
        let list = items.slice()
        list.splice(i, 1)
        items = list
    }
    function indexForX(x) {
        for (let i = 0; i < barRow.children.length; ++i) {
            const c = barRow.children[i]
            if (c.slotIndex === undefined) continue
            const p = c.mapToItem(barArea, 0, 0)
            if (x < p.x + c.width / 2) return c.slotIndex
        }
        return items.length
    }
    function paletteControl(controlId) {
        for (let i = 0; i < paletteTiles.count; ++i) {
            const slot = paletteTiles.itemAt(i)
            if (slot && slot.slotId === controlId && slot.tileItem.visible)
                return slot.tileItem
        }
        return null
    }
    function focusPaletteControl(controlId) {
        const tile = paletteControl(controlId)
        if (tile)
            tile.forceActiveFocus()
        return tile
    }
    function focusBarControl(controlId) {
        for (let i = 0; i < barTiles.count; ++i) {
            const tile = barTiles.itemAt(i)
            if (tile && tile.controlId === controlId) {
                tile.forceActiveFocus()
                return tile
            }
        }
        return null
    }

    Flickable {
        id: bodyScroller
        Layout.fillWidth: true
        Layout.fillHeight: true
        implicitWidth: root.width - 36
        implicitHeight: 520
        contentWidth: width
        contentHeight: bodyContent.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        ColumnLayout {
            id: bodyContent
            width: bodyScroller.width
            spacing: 16

        // Palette
        Rectangle {
            id: paletteArea
            objectName: "customize-palette-drop-target"
            Layout.fillWidth: true
            implicitHeight: palette.height + 24
            radius: Theme.radius
            color: Theme.bar
            border.color: paletteDrop.containsDrag ? Theme.accent : "transparent"
            Flow {
                id: palette
                anchors.top: parent.top
                anchors.topMargin: 12
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(parent.width - 24, 9 * 64 + 8 * 10)
                spacing: 10
                height: childrenRect.height
                Repeater {
                    id: paletteTiles
                    model: Theme.customizationSlots
                    delegate: Item {
                        required property string modelData
                        property string slotId: modelData
                        property alias tileItem: paletteTile
                        width: 64
                        height: 66
                        Tile {
                            id: paletteTile
                            anchors.fill: parent
                            visible: root.available.indexOf(modelData) >= 0
                            objectName: visible ? "customize-control-" + modelData + "-available" : ""
                            controlId: modelData
                            sourceIndex: -1
                        }
                    }
                }
            }
            DropArea {
                id: paletteDrop
                anchors.fill: parent
                keys: ["neo/control"]
            }
        }

        // Live preview of the bar
        NText { text: "Control bar"; dim: true }
        Rectangle {
            id: barArea
            objectName: "customize-bar-drop-target"
            Layout.fillWidth: true
            implicitHeight: 56
            radius: Theme.radius
            color: Theme.bar
            border.width: 1
            border.color: barDrop.containsDrag ? Theme.accent : Theme.border
            Row {
                id: barRow
                anchors.verticalCenter: parent.verticalCenter
                x: 10
                spacing: 4
                Repeater {
                    id: barTiles
                    model: root.items
                    delegate: Tile {
                        required property string modelData
                        required property int index
                        objectName: "customize-control-" + modelData + "-" + index
                        property int slotIndex: index
                        controlId: modelData
                        sourceIndex: index
                        compact: true
                    }
                }
            }
            Rectangle {
                id: insertMarker
                visible: barDrop.containsDrag
                width: 2; height: parent.height - 16; y: 8
                color: Theme.accent
                x: {
                    const i = root.indexForX(barDrop.drag.x)
                    for (let k = 0; k < barRow.children.length; ++k) {
                        const c = barRow.children[k]
                        if (c.slotIndex === i) return c.mapToItem(barArea, 0, 0).x - 3
                    }
                    return barRow.x + barRow.width + 2
                }
            }
            DropArea {
                id: barDrop
                anchors.fill: parent
                keys: ["neo/control"]
            }
        }
        NText { text: "The seek bar and spacers stretch to fill the free space."; color: Theme.textFaint; font.pixelSize: 11 }

        NText { text: "Profiles"; font.weight: Font.DemiBold }
        RowLayout {
            Layout.fillWidth: true
            NField { id: profileName; objectName: "customization-profile-name"; Layout.fillWidth: true; placeholderText: "Name this profile" }
            NButton {
                objectName: "save-customization-profile"
                text: "Save current"
                primary: true
                enabledState: profileName.text.trim().length > 0
                onClicked: {
                    if (Theme.saveProfile(profileName.text, root.items, player)) {
                        profileName.text = ""
                        root.profiles = Theme.profileList()
                    }
                }
            }
        }
        Repeater {
            model: root.profiles
            delegate: RowLayout {
                required property var modelData
                Layout.fillWidth: true
                NText {
                    Layout.fillWidth: true
                    text: modelData.name + (Theme.store.activeProfile === modelData.name ? " · Active" : "")
                    elide: Text.ElideRight
                }
                NButton {
                    objectName: "apply-customization-profile-" + modelData.name
                    text: "Apply"
                    onClicked: {
                        if (Theme.applyProfile(modelData.name, player)) root.items = Theme.layoutList()
                    }
                }
                NButton {
                    objectName: "delete-customization-profile-" + modelData.name
                    text: "Delete"
                    flat: true
                    onClicked: {
                        Theme.deleteProfile(modelData.name)
                        root.profiles = Theme.profileList()
                    }
                }
            }
        }
        }
    }

    footer: [
        NButton { text: "Reset"; flat: true; onClicked: root.items = Theme.defaultLayout.slice() },
        Item { Layout.fillWidth: true },
        NButton { text: "Cancel"; onClicked: root.close() },
        NButton { text: "Save"; primary: true; onClicked: { Theme.setLayout(root.items); root.close() } }
    ]

    component Tile: Rectangle {
        id: tile
        property string controlId
        property int sourceIndex: -1
        property bool compact: false
        readonly property bool fixedTransport: sourceIndex >= 0 && ["prev", "play", "next"].includes(controlId)
        readonly property var meta: Theme.controls[controlId] || { label: controlId, icon: "minus" }
        readonly property string accessibleAction: sourceIndex < 0 ? "Add " : (fixedTransport ? "Fixed " : "Remove ")
        width: compact ? (controlId === "seek" ? 120 : 40) : 64
        height: compact ? 40 : 66
        radius: Theme.radiusSmall
        color: dragArea.drag.active ? "transparent"
              : activeFocus || dragArea.containsMouse ? Theme.hover
              : compact ? Theme.surface : "transparent"
        border.width: activeFocus ? 1 : (compact ? 1 : 0)
        border.color: activeFocus ? Theme.accent : (compact ? Theme.border : "transparent")
        activeFocusOnTab: !fixedTransport
        Accessible.name: accessibleAction + meta.label
        Accessible.role: Accessible.Button
        Accessible.focusable: !fixedTransport

        Keys.onPressed: (event) => {
            if (fixedTransport || (event.key !== Qt.Key_Space && event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter))
                return
            if (!event.isAutoRepeat) {
                if (sourceIndex < 0)
                    root.insertAt(controlId, root.items.length)
                else
                    root.removeAt(sourceIndex)
            }
            event.accepted = true
        }

        function dropAtPointer() {
            const barPoint = dragArea.mapToItem(barArea, dragArea.mouseX, dragArea.mouseY)
            if (barPoint.x >= 0 && barPoint.y >= 0 && barPoint.x <= barArea.width && barPoint.y <= barArea.height) {
                root.insertAt(tile.controlId, root.indexForX(barPoint.x), tile.sourceIndex)
                return
            }
            const palettePoint = dragArea.mapToItem(paletteArea, dragArea.mouseX, dragArea.mouseY)
            if (tile.sourceIndex >= 0 && palettePoint.x >= 0 && palettePoint.y >= 0
                    && palettePoint.x <= paletteArea.width && palettePoint.y <= paletteArea.height)
                root.removeAt(tile.sourceIndex)
        }

        Column {
            anchors.centerIn: parent
            spacing: 6
            opacity: dragArea.drag.active ? 0.3 : 1
            Icon { name: tile.meta.icon; size: 18; anchors.horizontalCenter: parent.horizontalCenter }
            NText {
                visible: !tile.compact
                text: tile.meta.label
                font.pixelSize: 9
                dim: true
                width: 58
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                maximumLineCount: 3
            }
        }

        // Floating copy that follows the pointer.
        Rectangle {
            id: ghost
            width: tile.width; height: tile.height
            radius: tile.radius
            color: Theme.raised
            border.color: Theme.accent
            visible: dragArea.drag.active
            property string controlId: tile.controlId
            property int sourceIndex: tile.sourceIndex
            Drag.active: dragArea.drag.active && !tile.fixedTransport
            Drag.keys: ["neo/control"]
            Drag.hotSpot.x: width / 2
            Drag.hotSpot.y: height / 2
            Icon { anchors.centerIn: parent; name: tile.meta.icon; size: 18; color: Theme.accent }
            states: State {
                when: dragArea.drag.active
                ParentChange { target: ghost; parent: root.contentItem }
            }
        }
        MouseArea {
            id: dragArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            drag.target: tile.fixedTransport ? null : ghost
            onReleased: {
                if (drag.active) tile.dropAtPointer()
                ghost.Drag.drop()
                ghost.x = 0; ghost.y = 0
            }
            onDoubleClicked: tile.sourceIndex >= 0 ? root.removeAt(tile.sourceIndex) : root.insertAt(tile.controlId, root.items.length)
        }
    }
}
