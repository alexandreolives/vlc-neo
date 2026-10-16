pragma Singleton
import QtQuick
import QtCore

// Design tokens taken from the Figma file (VLC Redesign, Juxtopposed).
QtObject {
    id: theme

    readonly property var accents: ["#D9822B", "#B9443B", "#A08E32", "#2E9E4A", "#2AA3B3",
                                    "#2F5FC4", "#8A3FD1", "#C64AA4", "#9A9A9A"]
    readonly property var defaultLayout: ["prev", "play", "next", "time", "seek", "length",
                                          "volume", "audio", "subtitle", "settings", "queue"]
    // Everything that can live on the control bar (Customize Player dialog).
    readonly property var controls: ({
        prev: { label: "Previous", icon: "skip-back" },
        play: { label: "Play / Pause", icon: "play" },
        next: { label: "Next", icon: "skip-forward" },
        stop: { label: "Stop", icon: "square" },
        time: { label: "Elapsed Time", icon: "clock" },
        seek: { label: "Seek Bar", icon: "sliders-horizontal" },
        length: { label: "Total Time", icon: "clock" },
        volume: { label: "Volume", icon: "volume-2" },
        audio: { label: "Audio Tracks", icon: "audio-lines" },
        subtitle: { label: "Subtitles", icon: "captions" },
        settings: { label: "Playback Settings", icon: "settings" },
        queue: { label: "Queue", icon: "list" },
        fullscreen: { label: "Fullscreen", icon: "maximize" },
        pip: { label: "Picture in Picture", icon: "picture-in-picture-2" },
        record: { label: "Record", icon: "circle-dot" },
        snapshot: { label: "Snapshot", icon: "camera" },
        loop: { label: "Loop", icon: "repeat" },
        shuffle: { label: "Shuffle", icon: "shuffle" },
        speed: { label: "Speed", icon: "gauge" },
        frame: { label: "Next Frame", icon: "chevron-right" },
        back10: { label: "Back 10s", icon: "rewind" },
        fwd10: { label: "Forward 10s", icon: "fast-forward" },
        bookmark: { label: "Bookmark", icon: "bookmark" },
        hideui: { label: "Hide UI", icon: "eye-off" },
        library: { label: "Library", icon: "panel-left" },
        spacer: { label: "Spacer", icon: "minus" }
    })

    property Settings store: Settings {
        category: "appearance"
        property string mode: "dark"          // dark | light | system
        property string accent: "#D9822B"
        property bool onboarded: false
        property string layout: ""
        property int hideDelay: 1200
        property bool clickToPause: true
        property bool keyOsd: true
        property string resumeMode: "ask"     // ask | always | never
        property string pinned: ""
    }

    readonly property bool dark: store.mode === "system"
                                 ? Qt.styleHints.colorScheme !== Qt.ColorScheme.Light
                                 : store.mode !== "light"

    property color accent: store.accent
    readonly property color accentText: "#FFFFFF"
    readonly property color accentDim: dark ? Qt.rgba(accent.r * 0.28, accent.g * 0.28, accent.b * 0.28, 1)
                                            : Qt.rgba(accent.r * 0.45 + 0.55, accent.g * 0.45 + 0.55, accent.b * 0.45 + 0.55, 1)
    readonly property color accentSoft: Qt.rgba(accent.r, accent.g, accent.b, 0.16)

    readonly property color window: dark ? "#0E0E0E" : "#DADADA"
    readonly property color bar: dark ? "#1B1B1B" : "#EDEDED"
    readonly property color panel: dark ? "#151515" : "#F6F6F6"
    readonly property color surface: dark ? "#202020" : "#FFFFFF"
    readonly property color raised: dark ? "#2A2A2A" : "#E4E4E4"
    readonly property color hover: dark ? "#2C2C2C" : "#E0E0E0"
    readonly property color border: dark ? "#2B2B2B" : "#D2D2D2"
    readonly property color field: dark ? "#0C0C0C" : "#FFFFFF"
    readonly property color text: dark ? "#E4E4E4" : "#1C1C1C"
    readonly property color textDim: dark ? "#8F8F8F" : "#6A6A6A"
    readonly property color textFaint: dark ? "#5E5E5E" : "#9C9C9C"
    readonly property color icon: dark ? "#B4B4B4" : "#4A4A4A"
    readonly property color seekTrack: dark ? "#0A0A0A" : "#C9C9C9"
    readonly property color videoBg: "#000000"
    readonly property color volumeLow: "#7BAF14"
    readonly property color volumeHigh: "#D9822B"

    readonly property int radius: 6
    readonly property int radiusSmall: 4
    readonly property int barHeight: 44
    readonly property int topHeight: 34
    readonly property int fontSmall: 11
    readonly property int fontBody: 13
    readonly property int fontTitle: 15

    function layoutList() {
        return store.layout.length > 0 ? store.layout.split(",") : defaultLayout.slice()
    }
    function setLayout(list) { store.layout = list.join(",") }
    function iconUrl(name, color) {
        const c = String(color === undefined ? icon : color)
        return "image://icon/" + name + "?" + c.slice(c.length - 6)
    }
}
