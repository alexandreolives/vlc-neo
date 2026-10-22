import QtQuick
import Neo 1.0

// Thick slider with dimmed accent fill and a narrow accent handle (Figma style).
Item {
    id: root
    property real from: 0
    property real to: 1
    property real value: 0
    property real stepSize: 0
    property real origin: from          // fill starts here (use 0 for bipolar sliders)
    property int trackHeight: 12
    property int tickCount: 0
    readonly property bool pressed: mouse.pressed
    signal moved(real value)

    activeFocusOnTab: true
    Accessible.role: Accessible.Slider

    implicitWidth: 200
    implicitHeight: 22

    function ratio(v) { return to === from ? 0 : (Math.min(Math.max(v, from), to) - from) / (to - from) }
    function valueAt(x) {
        let v = from + Math.min(Math.max(x / width, 0), 1) * (to - from)
        if (stepSize > 0) v = Math.round(v / stepSize) * stepSize
        return Math.min(Math.max(v, from), to)
    }

    Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: root.trackHeight
        radius: 3
        color: Theme.seekTrack
        border.width: root.activeFocus ? 1 : 0
        border.color: Theme.accent
        Rectangle {
            x: Math.min(root.ratio(root.origin), root.ratio(root.value)) * parent.width
            width: Math.abs(root.ratio(root.value) - root.ratio(root.origin)) * parent.width
            height: parent.height
            radius: 3
            color: Theme.accentDim
        }
        Repeater {
            model: root.tickCount > 0 ? root.tickCount + 1 : 0
            delegate: Rectangle {
                required property int index
                width: 1
                height: Math.max(2, root.trackHeight - 2)
                y: 1
                x: index / root.tickCount * (track.width - width)
                color: Theme.textFaint
                opacity: 0.55
            }
        }
    }
    Rectangle {
        width: 5
        height: root.trackHeight + 4
        radius: 2
        color: Theme.accent
        anchors.verticalCenter: parent.verticalCenter
        x: root.ratio(root.value) * (root.width - width)
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onPressed: (e) => { root.forceActiveFocus(); root.moved(root.valueAt(e.x)) }
        onPositionChanged: (e) => { if (pressed) root.moved(root.valueAt(e.x)) }
        onWheel: (e) => {
            const step = root.stepSize > 0 ? root.stepSize : (root.to - root.from) / 50
            root.moved(Math.min(Math.max(root.value + (e.angleDelta.y > 0 ? step : -step), root.from), root.to))
        }
    }
    Keys.onPressed: (event) => {
        const step = root.stepSize > 0 ? root.stepSize : (root.to - root.from) / 50
        if (event.key === Qt.Key_Left || event.key === Qt.Key_Down) {
            root.moved(Math.max(root.from, root.value - step))
            event.accepted = true
        } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Up) {
            root.moved(Math.min(root.to, root.value + step))
            event.accepted = true
        } else if (event.key === Qt.Key_Home) {
            root.moved(root.from)
            event.accepted = true
        } else if (event.key === Qt.Key_End) {
            root.moved(root.to)
            event.accepted = true
        }
    }
}
