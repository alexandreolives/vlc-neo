import QtQuick
import QtQuick.Layouts
import Neo 1.0

// Drag buttons into the bar, drag them out to remove, drag inside the bar to reorder.
Modal {
    id: root
    title: "Customize Player"
    subtitle: "Drag items onto the bar below to add them. Drag them within the bar to reorder, or back here to remove."
    width: Math.min(parent ? parent.width - 60 : 980, 980)
    property var items: []
    onOpened: items = Theme.layoutList()

    readonly property var allIds: Object.keys(Theme.controls)
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
    function removeAt(i) { let list = items.slice(); list.splice(i, 1); items = list }
    function indexForX(x) {
        for (let i = 0; i < barRow.children.length; ++i) {
            const c = barRow.children[i]
            if (c.slotIndex === undefined) continue
            const p = c.mapToItem(barArea, 0, 0)
            if (x < p.x + c.width / 2) return c.slotIndex
        }
        return items.length
    }

    ColumnLayout {
        width: root.width - 36
        spacing: 16

        // Palette
        Rectangle {
            id: paletteArea
            Layout.fillWidth: true
            implicitHeight: palette.implicitHeight + 24
            radius: Theme.radius
            color: Theme.bar
            border.color: paletteDrop.containsDrag ? Theme.accent : "transparent"
            Flow {
                id: palette
                anchors.fill: parent
                anchors.margins: 12
                spacing: 10
                Repeater {
                    model: root.available
                    delegate: Tile {
                        required property string modelData
                        controlId: modelData
                        sourceIndex: -1
                    }
                }
            }
            DropArea {
                id: paletteDrop
                anchors.fill: parent
                keys: ["neo/control"]
                onDropped: (e) => { if (e.source.sourceIndex >= 0) root.removeAt(e.source.sourceIndex) }
            }
        }

        // Live preview of the bar
        NText { text: "Control bar"; dim: true }
        Rectangle {
            id: barArea
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
                    model: root.items
                    delegate: Tile {
                        required property string modelData
                        required property int index
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
                onDropped: (e) => root.insertAt(e.source.controlId, root.indexForX(e.x), e.source.sourceIndex)
            }
        }
        NText { text: "The seek bar and spacers stretch to fill the free space."; color: Theme.textFaint; font.pixelSize: 11 }
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
        readonly property var meta: Theme.controls[controlId] || { label: controlId, icon: "minus" }
        width: compact ? (controlId === "seek" ? 120 : 40) : 92
        height: compact ? 40 : 66
        radius: Theme.radiusSmall
        color: dragArea.drag.active ? "transparent" : (dragArea.containsMouse ? Theme.hover : Theme.surface)
        border.width: 1
        border.color: Theme.border

        Column {
            anchors.centerIn: parent
            spacing: 6
            opacity: dragArea.drag.active ? 0.3 : 1
            Icon { name: tile.meta.icon; size: 18; anchors.horizontalCenter: parent.horizontalCenter }
            NText {
                visible: !tile.compact
                text: tile.meta.label
                font.pixelSize: 10
                dim: true
                width: 84
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                maximumLineCount: 2
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
            Drag.active: dragArea.drag.active
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
            drag.target: ghost
            onReleased: {
                ghost.Drag.drop()
                ghost.x = 0; ghost.y = 0
            }
            onDoubleClicked: tile.sourceIndex >= 0 ? root.removeAt(tile.sourceIndex) : root.insertAt(tile.controlId, root.items.length)
        }
    }
}
