import QtQuick
import QtQuick.Layouts
import Neo 1.0

Rectangle {
    id: root
    property var items: Theme.layoutList()
    property bool splitTimeline: false
    property Item externalTimelineBar: null
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
        if (!splitTimeline) {
            let insertAt = result.indexOf("next")
            if (insertAt >= 0) insertAt += 1
            else insertAt = result.indexOf("play") >= 0 ? result.indexOf("play") + 1 : 0
            result.splice(insertAt, 0, "__timeline")
        }
        return result
    }
    property bool preview: false
    property Item timelineBar: null
    signal action(string id, Item source)

    function findControl(id) {
        if (["time", "seek", "length"].includes(id))
            return externalTimelineBar || timelineBar
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
    function splitSpacerWidth(index) {
        let firstSpacer = -1
        let secondSpacer = -1
        let leftWidth = 0
        let centerWidth = 0
        let rightWidth = 0
        let leftCount = 0
        let centerCount = 0
        let visibleCount = 0
        for (let i = 0; i < controls.count; ++i) {
            const item = controls.itemAt(i)
            if (!item || !item.visible) continue
            ++visibleCount
            if (item.controlId === "spacer") {
                if (firstSpacer < 0) firstSpacer = i
                else if (secondSpacer < 0) secondSpacer = i
                continue
            }
            if (firstSpacer < 0) { leftWidth += item.implicitWidth; ++leftCount }
            else if (secondSpacer < 0) { centerWidth += item.implicitWidth; ++centerCount }
            else rightWidth += item.implicitWidth
        }
        if (firstSpacer < 0 || secondSpacer < 0) return 0
        const gap = width < 720 ? 2 : 8
        const margin = width < 720 ? 6 : 20
        const free = Math.max(0, width - margin * 2 - gap * Math.max(0, visibleCount - 1)
                              - leftWidth - centerWidth - rightWidth)
        const firstWidth = Math.max(0, Math.min(free,
            width / 2 - margin - leftWidth - gap * (leftCount + 1)
            - centerWidth / 2 - gap * Math.max(0, centerCount - 1) / 2 + 19))
        return index === firstSpacer ? firstWidth : free - firstWidth
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
                Layout.fillWidth: flexible && !root.splitTimeline
                Layout.preferredWidth: root.splitTimeline && controlId === "spacer"
                                      ? root.splitSpacerWidth(index) : implicitWidth
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
