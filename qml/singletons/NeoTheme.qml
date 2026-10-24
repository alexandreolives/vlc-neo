pragma Singleton
import QtQuick
import QtCore

// Design tokens taken from the Figma file (VLC Redesign, Juxtopposed).
QtObject {
    id: theme
    property string homeLastArtistMediaUrl: ""

    readonly property var accents: ["#D37918", "#B9443B", "#A08E32", "#2E9E4A", "#2AA3B3",
                                    "#2F5FC4", "#8A3FD1", "#C64AA4", "#9A9A9A"]
    readonly property var defaultLayout: ["prev", "play", "next", "time", "seek", "length",
                                          "volume", "audio", "subtitle", "cast", "settings", "queue"]
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
        visualizer: { label: "Audio Visualizer", icon: "waveform-two-tone" },
        audio: { label: "Audio Tracks", icon: "audio-lines" },
        subtitle: { label: "Subtitles", icon: "captions" },
        cast: { label: "Play on a Device", icon: "cast" },
        settings: { label: "Playback Settings", icon: "settings" },
        queue: { label: "Queue", icon: "list" },
        fullscreen: { label: "Fullscreen", icon: "maximize" },
        pip: { label: "Picture in Picture", icon: "picture-in-picture-2" },
        record: { label: "Record", icon: "circle-dot" },
        snapshot: { label: "Snapshot", icon: "camera" },
        loop: { label: "Repeat", icon: "repeat" },
        shuffle: { label: "Shuffle", icon: "shuffle" },
        speed: { label: "Playback Speed", icon: "gauge" },
        frame: { label: "Next Frame", icon: "chevron-right" },
        back10: { label: "Backward 10s", icon: "rewind" },
        fwd10: { label: "Forward 10s", icon: "fast-forward" },
        back15: { label: "Backward 15s", icon: "rewind" },
        fwd15: { label: "Forward 15s", icon: "fast-forward" },
        bookmark: { label: "Bookmark", icon: "bookmark" },
        chapters: { label: "Chapters", icon: "list-video" },
        rightsidebar: { label: "Right Sidebar", icon: "sidebar-right" },
        vlcsettings: { label: "VLC Settings", icon: "settings" },
        playlists: { label: "Playlists", icon: "playlist" },
        home: { label: "Go Home", icon: "home" },
        zoom: { label: "Zoom Settings", icon: "zoom" },
        thumbnail: { label: "Thumbnail", icon: "thumbnail" },
        properties: { label: "Media Properties", icon: "info" },
        replay: { label: "Replay", icon: "replay" },
        favorite: { label: "Favorite", icon: "favorite" },
        bookmarks: { label: "Bookmarks", icon: "bookmarks" },
        quit: { label: "Quit VLC", icon: "quit" },
        filename: { label: "File Name", icon: "info" },
        artistname: { label: "Artist Name", icon: "info" },
        foldername: { label: "Folder Name", icon: "info" },
        playlistname: { label: "Playlist Name", icon: "info" },
        divider: { label: "Divider", icon: "divider" },
        hideui: { label: "Hide UI", icon: "ui" },
        library: { label: "Library", icon: "panel-left" },
        spacer: { label: "Spacer", icon: "minus" }
    })
    readonly property var customizationIds: [
        "spacer", "divider", "speed", "fwd10", "back10", "fwd15", "back15", "stop", "loop",
        "shuffle", "record", "snapshot", "pip", "zoom", "rightsidebar", "quit", "vlcsettings",
        "home", "thumbnail", "filename", "artistname", "foldername", "playlistname", "properties", "replay",
        "chapters", "favorite", "bookmark", "bookmarks", "playlists", "cast"
    ]
    // Preserve the Figma grid position of the unsupported HDR action.
    readonly property var customizationSlots: [
        "spacer", "divider", "speed", "fwd10", "back10", "fwd15", "back15", "stop", "loop",
        "shuffle", "record", "snapshot", "pip", "hdr", "zoom", "rightsidebar", "quit", "vlcsettings",
        "home", "thumbnail", "filename", "artistname", "foldername", "playlistname", "properties", "replay",
        "chapters", "favorite", "bookmark", "bookmarks", "playlists", "cast"
    ]

    property Settings store: Settings {
        category: "appearance"
        property string mode: "dark"          // dark | light | system
        property string accent: "#D37918"
        property bool onboarded: false
        property string layout: ""
        property string homeFolderVisitCountsJson: "{}"
        property string homePlaylistVisitCountsJson: "{}"
        property string homeArtistListenCountsJson: "{}"
        property int controlLayoutVersion: 0
        property bool showSeekThumbnails: true
        property string favoriteMediaJson: "[]"
        property int hideDelay: 1200
        property string autoHideMode: "fullscreen" // fullscreen | always | never
        property bool showControlsFullscreen: false
        property bool compactAtStart: false
        property bool rememberWindowGeometry: true
        property bool hasWindowGeometry: false
        property int windowX: 0
        property int windowY: 0
        property int windowWidth: 1120
        property int windowHeight: 680
        property bool clickToPause: true
        property bool doubleClickFullscreen: true
        property bool keyOsd: true
        property bool advancedOptions: false
        property bool automaticUpdateChecks: false
        property double lastUpdateCheckAttempt: 0
        property double lastUpdateCheckSuccess: 0
        property string updateAvailableVersion: ""
        property int subtitlePixelFontSize: 24
        property int subtitleShadowOpacity: 255
        property real maximumVolume: 2.0
        property string startupVolumeMode: "remember" // remember | fixed
        property real startupVolume: 2.0
        property string resumeMode: "ask"     // ask | always | never
        property string pinned: ""
        property bool showHiddenFiles: false
        property string profilesJson: "[]"
        property string activeProfile: ""
        property string lastEqualizerPreset: "flat"
        property string shortcutsJson: "{}"
        property string vlcShortcutDefaultsJson: "{}"
        property string globalVlcShortcutDefaultsJson: "{}"
    }

    Component.onCompleted: migrateControlLayout()

    readonly property var defaultShortcuts: ({
        playPause: "Space", fullscreen: "F", seekBack: "Left", seekForward: "Right",
        volumeDown: "Down", volumeUp: "Up", veryShortBack: "Shift+Left", veryShortForward: "Shift+Right",
        longBack: "Ctrl+Left", longForward: "Ctrl+Right", previous: ["<", "P"], next: [">", "N"], mute: "M",
        subtitles: "V", audio: "B", subtitleEarlier: "G", subtitleLater: "H", audioEarlier: "J", audioLater: "K",
        speedDown: "-", speedUp: ["+", "]"], speedNormal: "=", previousFrame: ",", nextFrame: [".", "E"],
        queue: "Q", library: "L", settingsPanel: "Ctrl+E", hideUi: "Ctrl+H", bookmark: "Ctrl+B",
        snapshot: "Shift+S", record: "Shift+R", stop: "S", openFile: "Ctrl+O", openNetwork: "Ctrl+N",
        openClipboard: "Ctrl+V", preferences: "Ctrl+P", quit: "Ctrl+Q", shortcuts: "?"
    })

    function shortcutMap() {
        try {
            const saved = JSON.parse(store.shortcutsJson)
            return saved && typeof saved === "object" && !Array.isArray(saved) ? saved : ({})
        } catch (error) { return ({}) }
    }
    function shortcutKeys(id) {
        const value = shortcutMap()[id]
        if (typeof value === "string" && value.length) return [value]
        if (Array.isArray(value)) return value.filter(key => typeof key === "string" && key.length)
        const fallback = defaultShortcuts[id]
        return Array.isArray(fallback) ? fallback.slice() : (fallback ? [fallback] : [])
    }
    function shortcutText(id) { return shortcutKeys(id).join(" / ") }
    function shortcutAction(chord) {
        const normalized = String(chord)
        const saved = shortcutMap()
        for (const id of Object.keys(defaultShortcuts)) {
            const value = Object.prototype.hasOwnProperty.call(saved, id) ? saved[id] : defaultShortcuts[id]
            const keys = Array.isArray(value) ? value : [value]
            if (keys.includes(normalized)) return id
        }
        return ""
    }
    function isDefaultShortcut(chord) {
        const normalized = String(chord)
        for (const id of Object.keys(defaultShortcuts)) {
            const value = defaultShortcuts[id]
            const keys = Array.isArray(value) ? value : [value]
            if (keys.includes(normalized)) return true
        }
        return false
    }
    function setShortcut(id, chord) {
        if (!Object.prototype.hasOwnProperty.call(defaultShortcuts, id) || !chord) return false
        for (const other of Object.keys(defaultShortcuts)) {
            if (other !== id && shortcutKeys(other).includes(chord)) return false
        }
        const saved = shortcutMap()
        saved[id] = chord
        store.shortcutsJson = JSON.stringify(saved)
        return shortcutAction(chord) === id
    }
    function resetShortcuts() { store.shortcutsJson = "{}" }
    function favoriteMedia() {
        try {
            const value = JSON.parse(store.favoriteMediaJson)
            return Array.isArray(value) ? value.filter(item => typeof item === "string") : []
        } catch (error) { return [] }
    }
    function isFavorite(mediaUrl) { return !!mediaUrl && favoriteMedia().includes(String(mediaUrl)) }
    function toggleFavorite(mediaUrl) {
        const key = String(mediaUrl || "")
        if (!key) return false
        const favorites = favoriteMedia()
        const index = favorites.indexOf(key)
        if (index >= 0) favorites.splice(index, 1)
        else favorites.push(key)
        store.favoriteMediaJson = JSON.stringify(favorites)
        return index < 0
    }
    function shortcutChord(key, modifiers, text) {
        let base = ""
        if (text === "<" || text === ">") base = text
        else if (key >= Qt.Key_A && key <= Qt.Key_Z) base = String.fromCharCode(key)
        else if (key >= Qt.Key_0 && key <= Qt.Key_9) base = String.fromCharCode(key)
        else switch (key) {
        case Qt.Key_Space: base = "Space"; break
        case Qt.Key_Left: base = "Left"; break
        case Qt.Key_Right: base = "Right"; break
        case Qt.Key_Up: base = "Up"; break
        case Qt.Key_Down: base = "Down"; break
        case Qt.Key_Escape: base = "Esc"; break
        case Qt.Key_Return: case Qt.Key_Enter: base = "Enter"; break
        case Qt.Key_Tab: base = "Tab"; break
        case Qt.Key_Backspace: base = "Backspace"; break
        case Qt.Key_Delete: base = "Delete"; break
        case Qt.Key_Home: base = "Home"; break
        case Qt.Key_End: base = "End"; break
        case Qt.Key_PageUp: base = "PageUp"; break
        case Qt.Key_PageDown: base = "PageDown"; break
        case Qt.Key_Minus: base = "-"; break
        case Qt.Key_Plus: base = "+"; break
        case Qt.Key_Equal: base = "="; break
        case Qt.Key_BracketLeft: base = "["; break
        case Qt.Key_BracketRight: base = "]"; break
        case Qt.Key_Comma: base = ","; break
        case Qt.Key_Period: base = "."; break
        case Qt.Key_Less: base = "<"; break
        case Qt.Key_Greater: base = ">"; break
        case Qt.Key_Slash: base = "/"; break
        case Qt.Key_Question: base = "?"; break
        case Qt.Key_F1: base = "F1"; break
        case Qt.Key_F2: base = "F2"; break
        case Qt.Key_F3: base = "F3"; break
        case Qt.Key_F4: base = "F4"; break
        case Qt.Key_F5: base = "F5"; break
        case Qt.Key_F6: base = "F6"; break
        case Qt.Key_F7: base = "F7"; break
        case Qt.Key_F8: base = "F8"; break
        case Qt.Key_F9: base = "F9"; break
        case Qt.Key_F10: base = "F10"; break
        case Qt.Key_F11: base = "F11"; break
        case Qt.Key_F12: base = "F12"; break
        default: base = text && text.length === 1 ? text.toUpperCase() : ""; break
        }
        if (!base) return ""
        if (["?", "+", "-", "=", "[", "]", ",", ".", "/", "<", ">"].includes(base)) return base
        const parts = []
        if (modifiers & Qt.ControlModifier) parts.push("Ctrl")
        if (modifiers & Qt.AltModifier) parts.push("Alt")
        if (modifiers & Qt.ShiftModifier) parts.push("Shift")
        if (modifiers & Qt.MetaModifier) parts.push("Meta")
        parts.push(base)
        return parts.join("+")
    }

    function profileList() {
        try {
            const saved = JSON.parse(store.profilesJson)
            return Array.isArray(saved) ? saved.filter(p => p && typeof p.name === "string") : []
        } catch (error) {
            return []
        }
    }
    function saveProfile(name, layoutOverride, playerFacade) {
        const safeName = String(name).trim().replace(/[\r\n\0]/g, " ").slice(0, 48)
        if (!safeName.length) return false
        const profile = {
            name: safeName,
            mode: store.mode,
            accent: store.accent,
            layout: Array.isArray(layoutOverride) ? layoutOverride.slice() : layoutList(),
            hideDelay: store.hideDelay,
            autoHideMode: store.autoHideMode,
            showControlsFullscreen: store.showControlsFullscreen,
            compactAtStart: store.compactAtStart,
            vlcOptions: playerFacade ? playerFacade.profileOptions() : ({})
        }
        const saved = profileList()
        const index = saved.findIndex(p => p.name.toLowerCase() === safeName.toLowerCase())
        if (index < 0) saved.push(profile)
        else saved[index] = profile
        store.profilesJson = JSON.stringify(saved)
        store.activeProfile = safeName
        return true
    }
    function applyProfile(name, playerFacade) {
        const profile = profileList().find(p => p.name === name)
        if (!profile) return false
        if (["dark", "light", "system"].includes(profile.mode)) store.mode = profile.mode
        if (accents.includes(profile.accent)) store.accent = profile.accent
        if (Array.isArray(profile.layout) && profile.layout.every(id => controls[id] !== undefined)) setLayout(profile.layout)
        if (Number.isFinite(profile.hideDelay)) store.hideDelay = Math.max(0, Math.min(10000, Math.round(profile.hideDelay)))
        if (["fullscreen", "always", "never"].includes(profile.autoHideMode)) store.autoHideMode = profile.autoHideMode
        if (typeof profile.showControlsFullscreen === "boolean") store.showControlsFullscreen = profile.showControlsFullscreen
        if (typeof profile.compactAtStart === "boolean") store.compactAtStart = profile.compactAtStart
        if (playerFacade && profile.vlcOptions && typeof profile.vlcOptions === "object")
            playerFacade.applyProfileOptions(profile.vlcOptions)
        store.activeProfile = profile.name
        return true
    }
    function deleteProfile(name) {
        const saved = profileList().filter(p => p.name !== name)
        store.profilesJson = JSON.stringify(saved)
        if (store.activeProfile === name) store.activeProfile = ""
    }

    readonly property bool dark: store.mode === "system"
                                 ? Qt.styleHints.colorScheme !== Qt.ColorScheme.Light
                                 : store.mode !== "light"

    property color accent: store.accent
    readonly property color accentText: "#FFFFFF"
    readonly property color accentDim: dark ? Qt.rgba(accent.r * 0.28, accent.g * 0.28, accent.b * 0.28, 1)
                                            : Qt.rgba(accent.r * 0.45 + 0.55, accent.g * 0.45 + 0.55, accent.b * 0.45 + 0.55, 1)
    readonly property color accentSoft: Qt.rgba(accent.r, accent.g, accent.b, 0.16)

    readonly property color window: dark ? "#0E0E0E" : "#EDEDED"
    readonly property color librarySidePanel: dark ? "#0E0E0E" : "#E7E7E7" // Figma Dark/Light BG/B1
    readonly property color librarySideTitle: dark ? "#8F8F8F" : "#2E2E2E" // Figma Dark/Light FG/A2
    readonly property color librarySideText: "#6B6B6B" // Figma Dark/Light FG/A3
    readonly property color rail: dark ? "#191919" : Qt.rgba(0.835, 0.835, 0.835, 0.75) // Light/BG/A3 at 75%
    readonly property color bar: dark ? "#1B1B1B" : Qt.rgba(0.835, 0.835, 0.835, 0.75) // Light/BG/A3 at 75%
    readonly property color panel: dark ? "#151515" : Qt.rgba(0.906, 0.906, 0.906, 0.8) // Light/BG/B1 at 80%
    readonly property color surface: dark ? "#1F1F1F" : "#EDEDED"
    readonly property color raised: dark ? "#222222" : "#D5D5D5"
    readonly property color hover: dark ? "#191919" : "#B3B3B3" // Dark/Light BG/A4 button variant
    readonly property color border: dark ? "#373737" : "#ACACAC"
    readonly property color field: dark ? "#090909" : "#FFFFFF"
    readonly property color text: dark ? "#EAEAEA" : "#2E2E2E"
    readonly property color textDim: dark ? "#C6C6C6" : "#6B6B6B"
    readonly property color textFaint: dark ? "#6B6B6B" : "#888888"
    readonly property color icon: dark ? "#8F8F8F" : "#3C3C3C"
    readonly property color seekTrack: dark ? "#090909" : "#B3B3B3"
    readonly property color seekProgress: dark ? "#371F06" : accentDim
    readonly property color videoBg: "#2C2B29"
    readonly property color onboardingVideoBg: "#0E0E0E"
    readonly property color volumeLow: "#7BAF14"
    readonly property color volumeHigh: "#D37918"

    readonly property int radius: 6
    readonly property int radiusSmall: 4
    readonly property int barHeight: 54
    readonly property int topHeight: 34
    readonly property int fontSmall: 11
    readonly property int fontBody: 13
    readonly property int fontTitle: 15

    function migrateControlLayout() {
        if (store.controlLayoutVersion >= 1) return
        const hadSavedLayout = store.layout.length > 0
        const saved = hadSavedLayout ? store.layout.split(",") : defaultLayout.slice()
        if (hadSavedLayout && !saved.includes("cast")) {
            const settingsIndex = saved.indexOf("settings")
            saved.splice(settingsIndex >= 0 ? settingsIndex : saved.length, 0, "cast")
            store.layout = saved.join(",")
        }
        store.controlLayoutVersion = 1
    }
    function layoutList() {
        const saved = store.layout.length > 0 ? store.layout.split(",") : defaultLayout.slice()
        // These timeline controls stay in the footer and are not movable buttons.
        return saved.filter(id => !["time", "seek", "length"].includes(id))
    }
    function setLayout(list) { store.layout = list.filter(id => !["time", "seek", "length"].includes(id)).join(",") }
    function iconUrl(name, color) {
        const c = String(color === undefined ? icon : color)
        return "image://icon/" + name + "?" + c.slice(c.length - 6)
    }
}
