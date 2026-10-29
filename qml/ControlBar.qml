import QtQuick
import QtQuick.Layouts
import Neo 1.0

Rectangle {
    id: root
    property var items: Theme.layoutList()
    property var renderedItems: {
        const result = items.slice()
        if (player.hasMedia && !player.hasVideo) {
            const previousIndex = result.indexOf("prev")
            if (previousIndex >= 0 && result.indexOf("back15") < 0)
                result.splice(previousIndex + 1, 0, "back15")
            const playIndex = result.indexOf("play")
            if (playIndex >= 0 && result.indexOf("fwd15") < 0)
                result.splice(playIndex + 1, 0, "fwd15")
        }
        let insertAt = result.indexOf("next")
        if (insertAt >= 0) insertAt += 1
        else insertAt = result.indexOf("play") >= 0 ? result.indexOf("play") + 1 : 0
        result.splice(insertAt, 0, "__timeline")
        return result
    }
    property bool preview: false
    property Item timelineBar: null
    signal action(string id, Item source)

    function findControl(id) {
        if (["time", "seek", "length"].includes(id))
            return timelineBar
        for (let i = 0; i < controls.count; ++i) {
            const item = controls.itemAt(i)
            if (item && item.controlId === id)
                return item
        }
        return null
    }
    function focusControl(id) {
        const item = findControl(id)
        if (!item || !item.contentItem)
            return false
        item.contentItem.forceActiveFocus()
        return item.contentItem.activeFocus
    }

    color: Theme.bar
    implicitHeight: Theme.barHeight

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: root.width < 720 ? 6 : 20
        anchors.rightMargin: root.width < 720 ? 6 : 20
        spacing: root.width < 720 ? 2 : 8
        Repeater {
            id: controls
            model: root.renderedItems
            delegate: ControlItem {
                required property string modelData
                required property int index
                objectName: "control-" + (controlId === "__timeline" ? "seek" : controlId)
                controlId: modelData
                preview: root.preview
                compactSpacer: root.width < 720 && controlId === "spacer"
                compactLeadingSpacer: root.width < 720 && controlId === "spacer"
                                      && root.items.indexOf("prev") >= 0 && index < root.items.indexOf("prev")
                Layout.fillWidth: flexible
                Layout.preferredWidth: implicitWidth
                Layout.minimumWidth: controlId === "__timeline" ? (root.width < 400 ? 48 : root.width < 720 ? 150 : 250)
                                     : controlId === "seek" ? (root.width < 720 ? 48 : 80) : implicitWidth
                Layout.alignment: Qt.AlignVCenter
                Layout.leftMargin: controlId === "time" || controlId === "volume" || controlId === "audio" ? 12 : 0
                onAction: (id, source) => root.action(id, source)
                onTimelineBarChanged: if (timelineBar) root.timelineBar = controls.itemAt(index)
            }
        }
    }
}
