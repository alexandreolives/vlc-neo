import QtQuick
import Neo 1.0

// Keyboard-accessible vertical gain slider used by the audio equalizer.
Item {
    id: root
    property real from: -20
    property real to: 20
    property real value: 0
    property real stepSize: 0.5
    property real origin: 0
    property int trackWidth: 12
    signal moved(real value)

    implicitWidth: 28
    implicitHeight: 220
    activeFocusOnTab: true
    Accessible.role: Accessible.Slider

    function clamped(v) { return Math.min(Math.max(v, from), to) }
    function ratio(v) { return to === from ? 0 : (to - clamped(v)) / (to - from) }
    function valueAt(y) {
        let v = to - Math.min(Math.max(y / height, 0), 1) * (to - from)
        if (stepSize > 0) v = Math.round(v / stepSize) * stepSize
        return clamped(v)
    }

    Rectangle {
        id: track
        width: root.trackWidth
        height: parent.height
        radius: 4
        anchors.horizontalCenter: parent.horizontalCenter
        color: Theme.seekTrack
        border.width: root.activeFocus ? 1 : 0
        border.color: Theme.accent

        Rectangle {
            x: 0
            y: Math.min(root.ratio(root.origin), root.ratio(root.value)) * parent.height
            width: parent.width
            height: Math.abs(root.ratio(root.value) - root.ratio(root.origin)) * parent.height
            radius: 4
            color: Theme.accentDim
        }
    }
    Rectangle {
        width: 20
        height: 6
        radius: 3
        color: Theme.accent
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.ratio(root.value) * (root.height - height)
    }
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onPressed: (e) => { root.forceActiveFocus(); root.moved(root.valueAt(e.y)) }
        onPositionChanged: (e) => { if (pressed) root.moved(root.valueAt(e.y)) }
        onWheel: (e) => {
            const step = root.stepSize > 0 ? root.stepSize : (root.to - root.from) / 50
            root.moved(root.clamped(root.value + (e.angleDelta.y > 0 ? step : -step)))
        }
    }
    Keys.onPressed: (event) => {
        const step = root.stepSize > 0 ? root.stepSize : (root.to - root.from) / 50
        if (event.key === Qt.Key_Up || event.key === Qt.Key_Right) {
            root.moved(root.clamped(root.value + step))
            event.accepted = true
        } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Left) {
            root.moved(root.clamped(root.value - step))
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
