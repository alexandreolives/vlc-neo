import QtQuick
import QtQuick.Shapes
import Neo 1.0

// VLC's wedge volume, completed into a cone: green to orange gradient (Figma/video).
Item {
    id: root
    property bool compact: false
    implicitWidth: compact ? 50 : 88
    implicitHeight: compact ? 22 : 28
    readonly property real maxVolume: Theme.store.maximumVolume
    readonly property real level: player.muted ? 0 : Math.min(player.volume / maxVolume, 1)

    Shape {
        id: wedge
        anchors.fill: parent
        anchors.topMargin: 3
        anchors.bottomMargin: 3
        preferredRendererType: Shape.CurveRenderer
        // Background cone (full range)
        ShapePath {
            strokeWidth: 0
            fillColor: Theme.seekTrack
            startX: 0; startY: wedge.height * 0.38
            PathLine { x: wedge.width; y: 0 }
            PathLine { x: wedge.width; y: wedge.height }
            PathLine { x: 0; y: wedge.height * 0.62 }
            PathLine { x: 0; y: wedge.height * 0.38 }
        }
    }
    // Filled part: the same cone cut at the current level.
    Shape {
        id: fillShape
        anchors.fill: wedge
        visible: root.level > 0.001
        preferredRendererType: Shape.CurveRenderer
        readonly property real w: width
        readonly property real h: height
        readonly property real fx: w * root.level
        readonly property real slope: 0.38 * h * (1 - root.level)
        ShapePath {
            strokeWidth: 0
            fillGradient: LinearGradient {
                x1: 0; y1: 0; x2: wedge.width; y2: 0
                GradientStop { position: 0.0; color: Theme.volumeLow }
                GradientStop { position: 0.75; color: "#B39A1A" }
                GradientStop { position: 1.0; color: Theme.volumeHigh }
            }
            startX: 0; startY: wedge.height * 0.38
            PathLine { x: fillShape.fx; y: fillShape.slope }
            PathLine { x: fillShape.fx; y: fillShape.h - fillShape.slope }
            PathLine { x: 0; y: wedge.height * 0.62 }
            PathLine { x: 0; y: wedge.height * 0.38 }
        }
    }
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        function apply(x) { player.setVolume(Math.max(0, Math.min(1, x / width)) * root.maxVolume) }
        onPressed: (e) => apply(e.x)
        onPositionChanged: (e) => { if (pressed) apply(e.x) }
        onWheel: (e) => player.setVolume(Math.max(0, Math.min(root.maxVolume, player.volume + (e.angleDelta.y > 0 ? 0.05 : -0.05))))
    }
}
