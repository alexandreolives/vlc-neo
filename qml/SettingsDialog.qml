import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Dialogs
import QtQuick.Layouts
import QtCore
import Qt.labs.folderlistmodel
import Neo 1.0

// Preferences, regrouped into human categories. Basic options first,
// advanced ones further down the same page — no separate "All" maze.
Modal {
    id: root
    property bool rendererDiscoveryLeaseHeld: false
    bodyMargin: 0
    width: parent ? parent.width : 1000
    height: parent ? parent.height : 865
    anchors.centerIn: undefined
    x: 0
    y: 0
    property string page: "general"
    readonly property bool compactCategories: root.width < 740
    property string categorySearch: ""
    property string subtitleSizeMode: "relative"
    property string audioFiltersState: ""
    property var equalizerBandValues: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    property real equalizerPreampValue: 12
    property bool equalizerTwoPassEnabled: false
    property bool equalizerEnabledState: false
    property string equalizerPresetState: "off"
    property bool equalizerExpanded: true
    readonly property var equalizerFrequencies: ["60 Hz", "170 Hz", "310 Hz", "600 Hz", "1 kHz", "3 kHz", "6 kHz", "12 kHz", "14 kHz", "16 kHz"]
    property string videoFiltersState: ""
    property var pictureValues: ({ hue: 0, brightness: 1, contrast: 1, saturation: 1, gamma: 1 })
    property int audioDeviceRevision: 0
    property bool reverseScrollDirection: false
    property bool reverseScrollAvailable: false
    property bool resumeMemoryEnabled: true
    property string addonSearch: ""
    property string addonStatus: ""
    property bool addonPackageImportPending: false
    property var addonPackageKnownUuids: []
    property string selectedAddonUuid: ""
    property string addonActionUuid: ""
    property string addonAction: ""
    readonly property var selectedAddon: {
        for (const addon of player.addons)
            if (addon.uuid === selectedAddonUuid) return addon
        return null
    }
    function beginAddonAction(action, uuid) {
        addonAction = action
        addonActionUuid = uuid
        const queued = action === "install" ? player.installAddon(uuid) : player.removeAddon(uuid)
        if (!queued) {
            finishAddonAction(false)
            return false
        }
        addonStatus = action === "install" ? "Installing add-on…" : "Removing add-on…"
        addonActionTimeout.restart()
        return true
    }
    function finishAddonAction(success) {
        if (!addonActionUuid) return
        addonStatus = success
                ? (addonAction === "install" ? "Add-on installed." : "Add-on removed.")
                : (addonAction === "install" ? "VLC could not install this add-on." : "VLC could not remove this add-on.")
        addonActionUuid = ""
        addonAction = ""
        addonActionTimeout.stop()
    }
    function updateAddonAction(addonState) {
        if (!addonActionUuid) return
        const addon = addonState || player.addons.find(item => item.uuid === addonActionUuid)
        if (addon && addon.uuid !== addonActionUuid) return
        if (!addon) return
        if (addon.installing || addon.removing) return
        if (addonAction === "install") finishAddonAction(addon.installed)
        else if (addonAction === "remove") finishAddonAction(!addon.installed)
    }
    function finishAddonPackageImport() {
        if (!addonPackageImportPending) return
        addonPackageImportPending = false
        addonPackageKnownUuids = []
        addonStatus = "VLC could not read or find an installable add-on in the selected package."
    }
    function packageAddonCandidate(addons) {
        const known = addonPackageKnownUuids
        for (const addon of addons) {
            if (known.indexOf(addon.uuid) < 0 && addon.manageable && !addon.installed)
                return addon
        }
        return null
    }
    function handleAddonPackageEntries(addons) {
        if (!addonPackageImportPending) return
        const added = addons.filter(addon => addonPackageKnownUuids.indexOf(addon.uuid) < 0)
        if (!added.length) return
        const candidate = packageAddonCandidate(added)
        addonPackageImportPending = false
        addonPackageKnownUuids = []
        if (candidate) {
            beginAddonAction("install", candidate.uuid)
            return
        }
        addonStatus = added.some(addon => addon.installed)
                ? "Add-on already installed."
                : "VLC found no installable add-on in this package."
    }
    function importAddonPackage(url) {
        addonPackageImportPending = true
        addonPackageKnownUuids = player.addons.map(addon => addon.uuid)
        addonStatus = "Reading package…"
        player.findAddons(url)
        if (!player.addonsLoading)
            finishAddonPackageImport()
    }
    Timer {
        id: addonActionTimeout
        interval: 30000
        repeat: false
        onTriggered: root.finishAddonAction(false)
    }
    property bool lastFmSubmissionEnabled: false
    property string bufferingProfile: "Custom"
    property string otherVlcOptionName: ""
    property string otherVlcOptionType: ""
    property string otherVlcOptionMessage: ""
    property string skinRestartNotice: ""
    readonly property bool skinInterfaceAvailable: player.config("intf") !== undefined
                                                && player.config("skins2-last") !== undefined
    property alias skinUnavailableMessageVisible: skinUnavailableMessage.visible
    property alias otherVlcOptionNameInput: otherVlcOptionField
    property alias logFilePathField: logFilePathInput
    property alias skinFilePathInput: skinFilePathField
    property alias skinFileDialogVisible: skinFileDialog.visible
    property alias logFileDialogVisible: logFileDialog.visible
    property alias languageChoiceControl: interfaceLanguageControl
    property alias categorySearchInput: categoryField
    property alias settingsCategoryPanel: categoryPanel
    property alias settingsPageContent: scroll
    property alias openSubtitlesApiKeyField: openSubtitlesApiKeyInput
    property alias openSubtitlesApiKeySaveAction: openSubtitlesApiKeySaveButton
    property alias openSubtitlesApiKeyRemoveAction: openSubtitlesApiKeyRemoveButton
    readonly property var bufferingProfiles: [
        { label: "Custom", value: "Custom", amount: 0 },
        { label: "Lowest latency", value: "Lowest latency", amount: 100 },
        { label: "Low latency", value: "Low latency", amount: 200 },
        { label: "Normal", value: "Normal", amount: 300 },
        { label: "High latency", value: "High latency", amount: 500 },
        { label: "Higher latency", value: "Higher latency", amount: 1000 }
    ]
    readonly property string pageTitle: {
        if (page === "general") return "Global Settings"
        if (page === "playback") return "Playback Preferences"
        if (page === "video") return "Video Defaults"
        if (page === "audio") return "Audio Defaults"
        if (page === "subtitles") return "Subtitle Defaults"
        if (page === "controls") return "Mouse, Keyboard & Remote Controls"
        if (page === "library") return "Playlists, Folders & Files"
        if (page === "network") return "Network Connections & Security"
        if (page === "recording") return "Recording, Casting & Streaming Out"
        if (page === "extensions") return "Add-ons & Scripts"
        for (const entry of pages)
            if (entry.id === page) return entry.label + " Settings"
        return "Settings"
    }
    signal showShortcuts()
    signal showOnboarding()

    FileDialog {
        id: addonPackageDialog
        title: "Select a VLC add-on package"
        nameFilters: ["VLC add-on packages (*.vlp)", "All files (*)"]
        onAccepted: root.importAddonPackage(selectedFile.toString())
    }

    FileDialog {
        id: logFileDialog
        title: "Choose a VLC log file"
        fileMode: FileDialog.SaveFile
        currentFolder: StandardPaths.writableLocation(StandardPaths.AppLocalDataLocation)
        onAccepted: player.setConfig("logfile", platform.displayPath(selectedFile))
    }

    FileDialog {
        id: skinFileDialog
        objectName: "skin-file-dialog"
        title: "Choose a VLC skin"
        nameFilters: ["VLC skins (*.vlt)", "All files (*)"]
        currentFolder: {
            const currentPath = String(player.config("skins2-last") || "")
            return currentPath.length ? platform.fileUrl(currentPath)
                                      : StandardPaths.writableLocation(StandardPaths.HomeLocation)
        }
        onAccepted: {
            const path = platform.displayPath(selectedFile)
            player.setConfig("skins2-last", path)
            skinFilePathField.text = path
        }
    }

    FolderDialog {
        id: recordingFolderDialog
        title: "Choose a recording folder"
        currentFolder: {
            const path = String(player.config("input-record-path") || "")
            return path.length ? platform.fileUrl(path) : StandardPaths.writableLocation(StandardPaths.MoviesLocation)
        }
        onAccepted: {
            const path = platform.displayPath(selectedFolder)
            player.setConfig("input-record-path", path)
        }
    }

    property real defaultPlaybackRate: 1
    property string defaultRepeatMode: "off"
    property string playbackEndAction: "nothing"
    readonly property bool normalizerTargetVisible: normalizerTargetRow.visible

    background: Rectangle {
        color: Qt.rgba(14 / 255, 14 / 255, 14 / 255, 1)
        radius: 0
        border.color: "transparent"
    }
    Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.72) }

    function syncSubtitleSizeMode() {
        const pixelSize = Number(player.config("freetype-fontsize"))
        subtitleSizeMode = pixelSize > 0 ? "pixels" : "relative"
        if (pixelSize > 0)
            Theme.store.subtitlePixelFontSize = pixelSize
    }
    function setSubtitleSizeMode(mode) {
        if (mode === subtitleSizeMode)
            return
        if (mode === "pixels") {
            const pixelSize = Number(player.config("freetype-fontsize"))
            if (pixelSize > 0)
                Theme.store.subtitlePixelFontSize = pixelSize
            player.setConfig("freetype-fontsize", Math.max(1, Theme.store.subtitlePixelFontSize))
        } else {
            const pixelSize = Number(player.config("freetype-fontsize"))
            if (pixelSize > 0)
                Theme.store.subtitlePixelFontSize = pixelSize
            player.setConfig("freetype-fontsize", 0)
        }
        subtitleSizeMode = mode
    }

    function setSkinInterfaceEnabled(enabled) {
        if (!skinInterfaceAvailable) {
            skinRestartNotice = "This VLC build does not include the skins2 interface."
            return false
        }
        const value = enabled ? "skins2" : "neo"
        player.setConfig("intf", value)
        skinRestartNotice = String(player.config("intf") || "") === value
                ? "Restart VLC from the regular VLC launcher to apply this interface. The vlc-neo command always opens Neo."
                : "VLC could not save the selected interface."
        return String(player.config("intf") || "") === value
    }
    function closeSkinFilePicker() { skinFileDialog.close() }
    function readAudioFilters() {
        const value = player.config("audio-filter")
        audioFiltersState = typeof value === "string" ? value : ""
    }
    function audioFilterList() {
        return audioFiltersState.split(",").map(f => f.trim()).filter(f => f.length > 0)
    }
    function audioFilterEnabled(name) { return audioFilterList().indexOf(name) >= 0 }
    function setAudioFilter(name, enabled) {
        const filters = audioFilterList().filter(f => f !== name)
        if (enabled) filters.push(name)
        audioFiltersState = filters.join(",")
        player.setConfig("audio-filter", audioFiltersState)
        return audioFilterEnabled(name) === enabled
    }
    function syncEqualizerSettings() {
        equalizerPresetState = player.equalizerPreset()
        equalizerEnabledState = equalizerPresetState !== "off"
        const rawBands = String(player.config("equalizer-bands") || "").trim()
        const parsed = rawBands.length ? rawBands.split(/\s+/).map(Number) : []
        equalizerBandValues = parsed.length === equalizerFrequencies.length && parsed.every(Number.isFinite)
                            ? parsed : [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        const preamp = Number(player.config("equalizer-preamp"))
        equalizerPreampValue = Number.isFinite(preamp) ? preamp : 12
        equalizerTwoPassEnabled = !!player.config("equalizer-2pass")
    }
    function setEqualizerEnabled(enabled) {
        if (enabled) {
            const preset = equalizerPresetState !== "off" ? equalizerPresetState
                          : Theme.store.lastEqualizerPreset || "flat"
            equalizerPresetState = preset
            equalizerEnabledState = true
            Theme.store.lastEqualizerPreset = preset
            player.setEqualizerPreset(preset)
        } else {
            if (equalizerPresetState !== "off")
                Theme.store.lastEqualizerPreset = equalizerPresetState
            equalizerEnabledState = false
            equalizerPresetState = "off"
            player.setEqualizerPreset("off")
        }
        Qt.callLater(syncEqualizerSettings)
    }
    function setEqualizerPreset(preset) {
        if (preset === "off") {
            setEqualizerEnabled(false)
            return
        }
        equalizerPresetState = preset
        equalizerEnabledState = true
        Theme.store.lastEqualizerPreset = preset
        player.setEqualizerPreset(preset)
        Qt.callLater(syncEqualizerSettings)
    }
    function setEqualizerBand(index, value) {
        if (index < 0 || index >= equalizerFrequencies.length) return false
        const parsedValue = Number(value)
        if (!Number.isFinite(parsedValue)) return false
        const values = equalizerBandValues.slice()
        values[index] = Math.max(-20, Math.min(20, parsedValue))
        equalizerBandValues = values
        player.setConfig("equalizer-bands", values.map(v => Number(v).toFixed(1)).join(" "))
        return true
    }
    function setEqualizerPreamp(value) {
        const parsedValue = Number(value)
        if (!Number.isFinite(parsedValue)) return false
        equalizerPreampValue = Math.max(-20, Math.min(20, parsedValue))
        player.setConfig("equalizer-preamp", equalizerPreampValue)
        return true
    }
    function setEqualizerTwoPass(enabled) {
        equalizerTwoPassEnabled = enabled
        player.setConfig("equalizer-2pass", enabled)
    }
    function scrollToAudioEffects() {
        equalizerExpanded = true
        Qt.callLater(() => {
            Qt.callLater(() => {
                const target = audioEffectsTitle.mapToItem(scroll.contentItem.contentItem, 0, 0).y
                scroll.contentItem.contentY = Math.max(0, target - 8)
            })
        })
    }
    function videoFilterList() {
        return videoFiltersState.split(",").map(f => f.trim()).filter(f => f.length > 0)
    }
    function setVideoFilter(name, enabled) {
        const filters = videoFilterList().filter(f => f !== name)
        if (enabled) filters.push(name)
        videoFiltersState = filters.join(",")
        player.setConfig("video-filter", videoFiltersState)
        return player.setVideoFilterChain(videoFiltersState)
    }
    function loadPictureValues() {
        pictureValues = {
            hue: Number(player.config("hue")),
            brightness: Number(player.config("brightness")),
            contrast: Number(player.config("contrast")),
            saturation: Number(player.config("saturation")),
            gamma: Number(player.config("gamma"))
        }
        if (!isFinite(pictureValues.hue)) pictureValues.hue = 0
        if (!isFinite(pictureValues.brightness)) pictureValues.brightness = 1
        if (!isFinite(pictureValues.contrast)) pictureValues.contrast = 1
        if (!isFinite(pictureValues.saturation)) pictureValues.saturation = 1
        if (!isFinite(pictureValues.gamma)) pictureValues.gamma = 1
        const filters = player.config("video-filter")
        videoFiltersState = typeof filters === "string" ? filters : ""
    }
    function setPictureValue(name, value) {
        const values = Object.assign({}, pictureValues)
        values[name] = value
        pictureValues = values
        player.setConfig(name, value)
        const adjustmentPreviewReady = player.setVideoAdjustment(name, value)
        let filterPreviewReady = true
        const defaults = { hue: 0, brightness: 1, contrast: 1, saturation: 1, gamma: 1 }
        const pictureAtDefaults = Object.keys(defaults).every(key => pictureValues[key] === defaults[key])
        if (pictureAtDefaults)
            filterPreviewReady = setVideoFilter("adjust", false)
        else if (value !== defaults[name])
            filterPreviewReady = setVideoFilter("adjust", true)
        const saved = Math.abs(Number(player.config(name)) - value) < 0.0001
        return saved && (!player.hasVideo || (filterPreviewReady && adjustmentPreviewReady))
    }
    function resetPicture() {
        const defaults = { hue: 0, brightness: 1, contrast: 1, saturation: 1, gamma: 1 }
        pictureValues = defaults
        Object.keys(defaults).forEach(name => player.setConfig(name, defaults[name]))
        setVideoFilter("adjust", false)
    }
    function syncPlaybackSettings() {
        const rate = Number(player.config("rate"))
        defaultPlaybackRate = isFinite(rate) && rate > 0 ? rate : 1
        const repeat = !!player.config("repeat")
        const loop = !!player.config("loop")
        defaultRepeatMode = repeat ? "one" : loop ? "all" : "off"
        playbackEndAction = !!player.config("play-and-exit") ? "exit"
                            : !!player.config("play-and-pause") ? "pause" : "nothing"
    }
    function setDefaultPlaybackRate(value) {
        defaultPlaybackRate = value
        player.setConfig("rate", value)
    }
    function setDefaultRepeatMode(mode) {
        defaultRepeatMode = mode
        player.setConfig("loop", mode === "all")
        player.setConfig("repeat", mode === "one")
    }
    function setPlaybackEndAction(action) {
        playbackEndAction = action
        player.setConfig("play-and-exit", action === "exit")
        player.setConfig("play-and-pause", action === "pause")
    }
    function syncScrollDirection() {
        const verticalMode = Number(player.config("hotkeys-y-wheel-mode"))
        const horizontalMode = Number(player.config("hotkeys-x-wheel-mode"))
        reverseScrollDirection = verticalMode === 3 || horizontalMode === 3
        reverseScrollAvailable = [2, 3].includes(verticalMode) || [2, 3].includes(horizontalMode)
    }
    function setScrollDirectionReverse(enabled) {
        ["hotkeys-y-wheel-mode", "hotkeys-x-wheel-mode"].forEach(name => {
            const mode = Number(player.config(name))
            if (mode === 2 || mode === 3) player.setConfig(name, enabled ? 3 : 2)
        })
        reverseScrollDirection = enabled
    }
    function syncPrivacySettings() {
        resumeMemoryEnabled = player.resumeEnabled()
        lastFmSubmissionEnabled = String(player.config("lastfm-username") || "").length > 0
    }
    function syncMetadataNetworkAccess() {
        setOptionValue("metadata-network-access", !!player.config("metadata-network-access"))
    }
    function syncBufferingProfile() {
        const file = Number(player.config("file-caching"))
        const disc = Number(player.config("disc-caching"))
        const live = Number(player.config("live-caching"))
        const network = Number(player.config("network-caching"))
        const cacheValues = [
            { name: "file-caching", value: file },
            { name: "disc-caching", value: disc },
            { name: "live-caching", value: live },
            { name: "network-caching", value: network }
        ]
        for (const entry of cacheValues) {
            const control = preferenceControl("vlc-option-" + entry.name)
            if (control) control.current = entry.value
        }
        bufferingProfile = "Custom"
        for (const preset of bufferingProfiles) {
            if (!preset.amount) continue
            if (file === preset.amount && disc === preset.amount && live === preset.amount
                    && network === Math.floor(preset.amount * 10 / 3)) {
                bufferingProfile = preset.value
                break
            }
        }
    }
    function setBufferingProfile(name) {
        const preset = bufferingProfiles.find(item => item.value === name)
        if (!preset) return false
        bufferingProfile = preset.value
        if (!preset.amount) return true
        const cacheValues = [
            { name: "file-caching", value: preset.amount },
            { name: "disc-caching", value: preset.amount },
            { name: "live-caching", value: preset.amount },
            { name: "network-caching", value: Math.floor(preset.amount * 10 / 3) }
        ]
        for (const entry of cacheValues) {
            player.setConfig(entry.name, entry.value)
            const control = preferenceControl("vlc-option-" + entry.name)
            if (control) control.current = entry.value
        }
        return true
    }
    function markCustomBuffering() { bufferingProfile = "Custom" }
    function setResumeMemoryEnabled(enabled) {
        player.setResumeEnabled(enabled)
        resumeMemoryEnabled = enabled
        Theme.store.resumeMode = enabled ? "ask" : "never"
    }
    function setResumeMode(mode) {
        Theme.store.resumeMode = mode
        player.setResumeEnabled(mode !== "never")
        resumeMemoryEnabled = mode !== "never"
    }
    function setLastFmEnabled(enabled) {
        if (!enabled) {
            setOptionValue("lastfm-username", "")
            setOptionValue("lastfm-password", "")
            lastFmSubmissionEnabled = false
        } else if (String(player.config("lastfm-username") || "").length === 0) {
            lastFmSubmissionEnabled = false
            win.toast("", "Enter your Last.fm username and password below")
        } else {
            lastFmSubmissionEnabled = true
        }
    }
    function outputDeviceChoices() {
        audioDeviceRevision
        const devices = player.audioDevices()
        return devices.length ? devices.map(device => ({ label: device.name, value: device.id }))
                              : [{ label: "System default", value: "" }]
    }
    function selectedOutputDevice() {
        audioDeviceRevision
        const devices = player.audioDevices()
        for (const device of devices) if (device.selected) return device.id
        return ""
    }
    onOpened: {
        syncSubtitleSizeMode()
        readAudioFilters()
        syncEqualizerSettings()
        loadPictureValues()
        syncPlaybackSettings()
        syncScrollDirection()
        syncPrivacySettings()
        syncMetadataNetworkAccess()
        syncBufferingProfile()
        rendererDiscoveryLeaseHeld = win.acquireRendererDiscovery("settings-dialog")
    }
    Component.onDestruction: {
        if (rendererDiscoveryLeaseHeld) win.releaseRendererDiscovery("settings-dialog")
    }
    onPageChanged: {
        if (page === "controls") syncScrollDirection()
        if (page === "privacy") syncPrivacySettings()
        if (page === "library" || page === "privacy") syncMetadataNetworkAccess()
        if (page === "network") syncBufferingProfile()
        if (page === "extensions") { addonStatus = ""; player.loadAddons() }
    }
    Connections {
        target: player
        function onMediaChanged() { root.audioDeviceRevision++ }
        function onTracksChanged() { root.audioDeviceRevision++ }
        function onAddonsChanged() {
            if (root.addonPackageImportPending)
                root.handleAddonPackageEntries(player.addons)
            const actionWasPending = root.addonActionUuid.length > 0
            root.updateAddonAction()
            if (!actionWasPending && !player.addonsLoading && player.addons.length > 0)
                root.addonStatus = player.addons.length + " add-ons available."
        }
        function onAddonsLoadingChanged() {
            if (!player.addonsLoading && !root.addonActionUuid && root.addonPackageImportPending) {
                root.finishAddonPackageImport()
            } else if (!player.addonsLoading && !root.addonActionUuid) {
                root.addonStatus = player.addons.length
                        ? player.addons.length + " add-ons available."
                        : "No add-ons found. The VLC catalog may be unavailable; choose Find more extensions to retry."
            }
        }
    }

    readonly property var pages: [
        { id: "general", label: "General", icon: "preferences" },
        { id: "interface", label: "Interface", icon: "interface" },
        { id: "privacy", label: "Privacy", icon: "privacy" },
        { id: "controls", label: "Controls", icon: "hotkeys" },
        { id: "playback", label: "Playback", icon: "playback" },
        { id: "video", label: "Video", icon: "video" },
        { id: "audio", label: "Audio", icon: "audio" },
        { id: "subtitles", label: "Subtitles", icon: "subtitles" },
        { id: "library", label: "Library", icon: "folder" },
        { id: "network", label: "Network", icon: "streaming" },
        { id: "performance", label: "Performance", icon: "preferences" },
        { id: "recording", label: "Recording", icon: "record" },
        { id: "extensions", label: "Extensions", icon: "plugins" }
    ]
    readonly property var categoryGroups: [
        { label: "App", ids: ["general", "interface", "privacy", "controls"] },
        { label: "Media", ids: ["playback", "video", "audio", "subtitles", "library"] },
        { label: "System", ids: ["network", "performance", "recording", "extensions"] }
    ]

    function pagesInGroup(ids) {
        const query = categorySearch.trim().toLowerCase()
        return pages.filter(p => ids.indexOf(p.id) >= 0 && p.label.toLowerCase().includes(query))
    }
    function preferenceControl(objectName) {
        const pending = [root.contentItem]
        while (pending.length) {
            const item = pending.pop()
            if (item.objectName === objectName) return item
            for (const child of item.children || []) pending.push(child)
        }
        return null
    }
    function scrollControlIntoView(objectName) {
        const item = preferenceControl(objectName)
        if (!item)
            return false
        Qt.callLater(() => {
            const flickable = scroll.contentItem
            const content = flickable.contentItem
            const top = item.mapToItem(content, 0, 0).y
            const bottom = top + item.height
            if (top < flickable.contentY)
                flickable.contentY = Math.max(0, top - 8)
            else if (bottom > flickable.contentY + flickable.height)
                flickable.contentY = Math.max(0, bottom - flickable.height + 8)
        })
        return true
    }
    function optionVisible(optionName) {
        const pending = [root.contentItem]
        let foundVisible = false
        while (pending.length) {
            const item = pending.pop()
            if (item.objectName === "vlc-option-" + optionName) {
                let effectivelyVisible = true
                for (let ancestor = item; ancestor; ancestor = ancestor.parent) {
                    if (ancestor.visible === false) {
                        effectivelyVisible = false
                        break
                    }
                    if (ancestor === root) break
                }
                foundVisible = foundVisible || effectivelyVisible
            }
            for (const child of item.children || []) pending.push(child)
        }
        return foundVisible
    }
    function preferenceControlWidth(objectName) {
        const item = preferenceControl(objectName)
        return item ? (typeof item.fieldWidth === "number" ? item.fieldWidth : item.width) : undefined
    }

    function extensionCatalogLayoutMatches() {
        const startupOption = preferenceControl("vlc-option-qt-autoload-extensions")
        return addonCatalogCard.height === 184
                && addonSearchRow.y >= addonCatalogCard.y + addonCatalogCard.height
                && addonSearchField.width === 180
                && addonFindButton.width === 160
                && addonAddButton.width === 86
                && addonRemoveButton.width === 86
                && !!startupOption && startupOption.enabled && startupOption.current === player.config("qt-autoload-extensions")
    }
    function preferenceControlDisplayValue(objectName) {
        const item = preferenceControl(objectName)
        return item && typeof item.displayValue === "string" ? item.displayValue : undefined
    }
    function inspectOtherVlcOption(name) {
        const key = String(name || "").trim()
        if (!/^[a-z][a-z0-9-]*$/i.test(key)) {
            otherVlcOptionName = ""
            otherVlcOptionType = ""
            otherVlcOption.current = undefined
            otherVlcOptionMessage = "Enter a VLC option name without the leading dashes."
            return false
        }
        const type = player.configType(key)
        if (!type.length || player.config(key) === undefined) {
            otherVlcOptionName = ""
            otherVlcOptionType = ""
            otherVlcOption.current = undefined
            otherVlcOptionMessage = "This VLC build does not expose that option."
            return false
        }
        otherVlcOptionName = key
        otherVlcOptionType = type
        otherVlcOption.current = player.config(key)
        otherVlcOptionMessage = "Loaded " + key + " (" + type + "). Changes are saved by VLC."
        return true
    }
    function loadOtherVlcOptionFromField() {
        return inspectOtherVlcOption(otherVlcOptionNameInput.text)
    }
    function setOptionValue(optionName, value) {
        const pending = [root.contentItem]
        let found = false
        while (pending.length) {
            const item = pending.pop()
            if (item.objectName === "vlc-option-" + optionName) {
                item.save(value)
                found = true
            }
            for (const child of item.children || []) pending.push(child)
        }
        return found
    }
    function optionNumberValue(optionName, text) {
        const pending = [root.contentItem]
        while (pending.length) {
            const item = pending.pop()
            if (item.objectName === "vlc-option-" + optionName)
                return item.parseNumber(text)
            for (const child of item.children || []) pending.push(child)
        }
        return undefined
    }
    function optionColorValue(optionName, text) {
        const pending = [root.contentItem]
        while (pending.length) {
            const item = pending.pop()
            if (item.objectName === "vlc-option-" + optionName)
                return item.parseColor(text)
            for (const child of item.children || []) pending.push(child)
        }
        return undefined
    }
    function optionColorHex(optionName, value) {
        const pending = [root.contentItem]
        while (pending.length) {
            const item = pending.pop()
            if (item.objectName === "vlc-option-" + optionName)
                return "#" + item.colorHex(value)
            for (const child of item.children || []) pending.push(child)
        }
        return undefined
    }
    onClosed: {
        if (rendererDiscoveryLeaseHeld) {
            win.releaseRendererDiscovery("settings-dialog")
            rendererDiscoveryLeaseHeld = false
        }
        categorySearch = ""
        categoryField.clear()
    }

    ColumnLayout {
        x: 10
        y: 0
        width: root.width - 10
        height: root.height - 2
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 52
            Layout.minimumHeight: 52
            Layout.maximumHeight: 52
            Layout.rightMargin: 16
            spacing: 32
            Item {
                Layout.preferredWidth: root.compactCategories ? 112 : 200
                Layout.fillHeight: true
                NField {
                    id: categoryField
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 32
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.verticalCenterOffset: -1
                    leftPadding: 32
                    placeholderText: "Search"
                    onTextChanged: root.categorySearch = text
                }
                Icon { name: "search"; size: 16; x: 9; anchors.verticalCenter: parent.verticalCenter; anchors.verticalCenterOffset: 3; color: Theme.textFaint }
            }
            NText { text: root.pageTitle; font.pixelSize: 15; color: Theme.textDim; Layout.fillWidth: true }
            IconButton { icon: "x"; tip: "Close"; onClicked: root.close() }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: 0
            spacing: 0

        // Category list
        Rectangle {
            id: categoryPanel
            Layout.fillHeight: true
            Layout.preferredWidth: root.compactCategories ? 40 : 200
            Layout.bottomMargin: 8
            color: Theme.bar
            radius: Theme.radius
            ScrollView {
                id: categoryScroll
                anchors.fill: parent
                anchors.leftMargin: root.compactCategories ? 4 : 8
                anchors.rightMargin: root.compactCategories ? 4 : 8
                anchors.topMargin: 11
                anchors.bottomMargin: 8
                contentWidth: availableWidth
                clip: true

                ColumnLayout {
                width: categoryScroll.availableWidth
                spacing: 4
                Repeater {
                    model: root.categoryGroups
                    delegate: ColumnLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 2
                        visible: root.pagesInGroup(modelData.ids).length > 0
                        NText {
                            text: modelData.label
                            visible: root.categorySearch.length === 0 && !root.compactCategories
                            color: Theme.textFaint
                            font.pixelSize: 11
                            Layout.leftMargin: 8
                            Layout.topMargin: 6
                            Layout.bottomMargin: 12
                        }
                        Repeater {
                            model: root.pagesInGroup(parent.modelData.ids)
                            delegate: Button {
                                id: categoryButton
                                required property var modelData
                                objectName: "settings-category-" + modelData.id
                                Layout.fillWidth: true
                                implicitHeight: 46
                                padding: 0
                                hoverEnabled: true
                                focusPolicy: Qt.TabFocus
                                Accessible.name: modelData.label
                                Accessible.description: modelData.label
                                background: Rectangle {
                                    radius: Theme.radiusSmall
                                    color: categoryButton.down ? Theme.raised
                                           : (categoryButton.hovered || root.page === modelData.id ? Theme.hover : "transparent")
                                    border.width: categoryButton.activeFocus ? 1 : 0
                                    border.color: Theme.accent
                                }
                                contentItem: Item {
                                    Row {
                                        x: root.compactCategories ? Math.round((parent.width - width) / 2) : 10
                                        spacing: 10
                                        anchors.verticalCenter: parent.verticalCenter
                                        Icon {
                                            objectName: "settings-category-icon-" + modelData.id
                                            name: modelData.icon + (root.page === modelData.id ? "-active" : "")
                                            size: 17
                                            color: categoryButton.activeFocus ? Theme.text : (root.page === modelData.id ? Theme.accent : Theme.icon)
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                        NText { visible: !root.compactCategories; text: modelData.label; color: categoryButton.activeFocus || categoryButton.hovered ? Theme.text : (root.page === modelData.id ? Theme.text : Theme.textDim); anchors.verticalCenter: parent.verticalCenter }
                                    }
                                }
                                onClicked: root.page = modelData.id
                                ToolTip.visible: root.compactCategories && hovered
                                ToolTip.text: modelData.label
                            }
                        }
                    }
                }
                Item { Layout.fillHeight: true }
                }
            }
        }

        ScrollView {
            id: scroll
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.leftMargin: root.compactCategories ? 12 : 32
            Layout.topMargin: root.page === "interface" ? 20 : 12
            contentWidth: availableWidth
            clip: true

            ColumnLayout {
                width: scroll.availableWidth - 12
                spacing: 12

                // ------------------------------------------------ General
                Page_ {
                    id_: "general"
                    SectionTitle { text: "Appearance" }
                    SettingRow {
                        label: "Interface language"
                        info: "Only English interface strings are currently included."
                        NCombo {
                            id: interfaceLanguageControl
                            objectName: "interface-language-choice"
                            width: 320
                            model: [{ label: "English", value: "en" }]
                            current: "en"
                            enabled: false
                            opacity: 0.55
                        }
                    }
                    SettingRow {
                        label: "Theme"
                        Chips {
                            chipWidth: 100
                            model: [{ label: "Dark", value: "dark" }, { label: "Light", value: "light" }, { label: "System", value: "system" }]
                            current: Theme.store.mode
                            onPicked: (v) => Theme.store.mode = v
                        }
                    }
                    SettingRow {
                        label: "Accent color"
                        info: "Replaces VLC orange everywhere in the interface."
                        AccentPicker { compact: true; spacing: 10 }
                    }
                    SectionTitle { text: "Startup" }
                    VlcOption { option: "qt-error-dialogs"; label: "Show confirmation and error dialogs"; info: "Let VLC display confirmation and error dialogs." }
                    SettingRow {
                        label: "Check for updates automatically"
                        info: "Checks public VLC Neo version tags on GitHub once a day. It does not download or install software."
                        RowLayout {
                            spacing: 8
                            NSwitch {
                                objectName: "auto-update-checks"
                                checked: Theme.store.automaticUpdateChecks
                                onToggled: (on) => {
                                    Theme.store.automaticUpdateChecks = on
                                    if (on) win.checkForUpdates(true)
                                }
                            }
                            NButton {
                                visible: Theme.store.updateAvailableVersion.length > 0
                                text: "View tag"
                                onClicked: Qt.openUrlExternally("https://github.com/AlexandreOlives/vlc-neo/tree/"
                                                               + encodeURIComponent(Theme.store.updateAvailableVersion))
                            }
                        }
                    }
                    SectionTitle { text: "Diagnostics"; Layout.topMargin: 12 }
                    SettingRow {
                        objectName: "developer-mode-row"
                        label: "Developer mode"
                        info: "Enable VLC's most detailed core messages for troubleshooting."
                        NSwitch {
                            objectName: "developer-mode-toggle"
                            checked: { player.configRevision; return Number(player.config("verbose")) >= 2 }
                            onToggled: (on) => player.setConfig("verbose", on ? 2 : 0)
                        }
                    }
                    VlcOption { option: "file-logging"; label: "Save a log"; info: "Write VLC core messages to a log file." }
                    SettingRow {
                        objectName: "vlc-option-logfile"
                        label: "Log file"
                        RowLayout {
                            Layout.minimumWidth: 258
                            Layout.preferredWidth: 258
                            spacing: 8
                            NField {
                                id: logFilePathInput
                                Layout.minimumWidth: 180
                                Layout.preferredWidth: 180
                                text: { player.configRevision; return String(player.config("logfile") || "") }
                                onEditingFinished: player.setConfig("logfile", text)
                            }
                            NButton {
                                objectName: "log-file-browse"
                                text: "Browse"
                                onClicked: logFileDialog.open()
                            }
                        }
                    }
                    VlcOption {
                        option: "log-verbose"; kind: "choice"; label: "Log details"
                        choices: [{ label: "Default", value: -1 }, { label: "Information", value: 0 },
                                  { label: "Errors only", value: 1 }, { label: "Warnings", value: 2 }, { label: "Debug", value: 3 }]
                    }
                    Button {
                        id: detailLevel
                        objectName: "preferences-detail-level"
                        Layout.fillWidth: true
                        Layout.topMargin: 12
                        implicitHeight: 38
                        focusPolicy: Qt.TabFocus
                        Accessible.name: Theme.store.advancedOptions ? "Hide advanced preference settings" : "Show advanced preference settings"
                        onClicked: Theme.store.advancedOptions = !Theme.store.advancedOptions
                        background: Rectangle {
                            radius: Theme.radiusSmall
                            color: detailLevel.down ? Theme.raised : (detailLevel.hovered ? Theme.hover : Theme.surface)
                            border.width: detailLevel.activeFocus ? 2 : 1
                            border.color: detailLevel.activeFocus ? Theme.accent : Theme.border
                        }
                        contentItem: Row {
                            spacing: 8
                            anchors.centerIn: parent
                            NText {
                                text: "Advanced Options"
                                color: Theme.textDim
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Icon {
                                name: Theme.store.advancedOptions ? "chevron-up" : "chevron-right"
                                size: 15
                                color: Theme.icon
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                        ToolTip.visible: hovered
                        ToolTip.text: "Show " + (Theme.store.advancedOptions ? "basic" : "advanced") + " VLC settings"
                    }
                    SectionTitle { text: "Advanced"; advanced: true }
                    SettingRow {
                        objectName: "vlc-option-quiet"
                        visible: Theme.store.advancedOptions
                        label: "Show minor warnings"
                        info: "When enabled, VLC does not use quiet mode and can show minor warnings."
                        NSwitch {
                            objectName: "show-minor-warnings-toggle"
                            checked: { player.configRevision; return !player.config("quiet") }
                            onToggled: (on) => player.setConfig("quiet", !on)
                        }
                    }
                    VlcOption {
                        option: "extraintf"; kind: "text"; fieldWidth: 270; label: "Additional VLC interfaces"; advanced: true
                        info: "Comma-separated VLC interface modules to load alongside the main interface."
                    }
                    VlcOption {
                        option: "logmode"; kind: "choice"; fieldWidth: 270; label: "Log format"; advanced: true
                        choices: [{ label: "Plain text", value: "text" }, { label: "HTML", value: "html" }]
                    }
                    VlcOption { option: "stats"; label: "Collect playback statistics"; advanced: true }
                    VlcOption {
                        option: "verbose"; kind: "choice"; label: "Core output verbosity"; advanced: true
                        choices: [{ label: "Default", value: 0 }, { label: "Verbose", value: 1 }, { label: "Debug", value: 2 }]
                    }
                    SettingRow {
                        visible: Theme.store.advancedOptions
                        label: "Other VLC option"
                        info: "Load a less common option by its VLC name, without the leading dashes."
                        RowLayout {
                            spacing: 8
                            TextField {
                                id: otherVlcOptionField
                                objectName: "other-vlc-option-name"
                                Layout.preferredWidth: 210
                                placeholderText: "Option name"
                                onAccepted: root.loadOtherVlcOptionFromField()
                            }
                            NButton {
                                objectName: "other-vlc-option-load"
                                text: "Load"
                                onClicked: root.loadOtherVlcOptionFromField()
                            }
                        }
                    }
                    NText {
                        objectName: "other-vlc-option-message"
                        visible: Theme.store.advancedOptions && root.otherVlcOptionMessage.length > 0
                        text: root.otherVlcOptionMessage
                        color: Theme.textFaint
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                    VlcOption {
                        id: otherVlcOption
                        objectName: "vlc-option-other"
                        option: root.otherVlcOptionName
                        label: root.otherVlcOptionName.length
                               ? root.otherVlcOptionName + " (" + root.otherVlcOptionType + ")" : ""
                        kind: root.otherVlcOptionType === "bool" ? "bool"
                              : (root.otherVlcOptionType === "integer" || root.otherVlcOptionType === "float") ? "number" : "text"
                        allowDecimal: root.otherVlcOptionType === "float"
                        secret: /password|passwd|pwd|secret|token/i.test(root.otherVlcOptionName)
                        info: "Advanced VLC configuration value."
                        advanced: true
                        visible: root.otherVlcOptionName.length > 0
                                 && root.otherVlcOptionType.length > 0
                                 && Theme.store.advancedOptions
                    }
                }

                // ---------------------------------------------- Interface
                Page_ {
                    id_: "interface"
                    SectionTitle { text: "Skin"; visible: root.skinInterfaceAvailable }
                    SettingRow {
                        objectName: "vlc-option-intf"
                        visible: root.skinInterfaceAvailable
                        label: "Use a custom skin"
                        info: "Selects VLC's skins2 interface for the regular VLC launcher. Restart VLC to apply it."
                        NSwitch {
                            objectName: "use-custom-skin-switch"
                            checked: { player.configRevision; return String(player.config("intf") || "") === "skins2" }
                            onToggled: (on) => root.setSkinInterfaceEnabled(on)
                        }
                    }
                    SettingRow {
                        objectName: "vlc-option-skins2-last"
                        visible: root.skinInterfaceAvailable
                        label: "Skin file"
                        info: "Path to a VLC .vlt skin used by the skins2 interface."
                        RowLayout {
                            spacing: 8
                            NField {
                                id: skinFilePathField
                                objectName: "skin-file-path"
                                Layout.preferredWidth: 220
                                text: { player.configRevision; return String(player.config("skins2-last") || "") }
                                placeholderText: "Choose a .vlt skin"
                                onEditingFinished: player.setConfig("skins2-last", text.trim())
                            }
                            NButton {
                                objectName: "skin-file-browse"
                                text: "Browse"
                                onClicked: skinFileDialog.open()
                            }
                        }
                    }
                    NText {
                        id: skinUnavailableMessage
                        objectName: "skin-unavailable-message"
                        visible: !root.skinInterfaceAvailable
                        text: "This VLC build does not include the skins2 interface."
                        color: Theme.textFaint
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                    NText {
                        objectName: "skin-restart-notice"
                        visible: root.skinRestartNotice.length > 0
                        text: root.skinRestartNotice
                        color: Theme.textFaint
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                    SectionTitle { text: "Window"; Layout.topMargin: 16 }
                    VlcOption {
                        option: "embedded-video"
                        label: "Play video inside main window"
                        info: "Saved as a VLC video-output preference. Neo always embeds video in its player window."
                    }
                    VlcOption {
                        option: "qt-video-autoresize"
                        kind: "choice"
                        fieldWidth: 320
                        label: "Resize window to fit video"
                        choices: [{ label: "Never", value: false }, { label: "Always", value: true }]
                    }
                    SettingRow {
                        label: "Remember window size and position"
                        info: "Restore the last window size and position the next time Neo starts."
                        NSwitch {
                            objectName: "remember-window-geometry-switch"
                            checked: Theme.store.rememberWindowGeometry
                            onToggled: (on) => Theme.store.rememberWindowGeometry = on
                        }
                    }
                    VlcOption {
                        option: "video-on-top"
                        label: "Keep the window above other windows"
                        info: "Applies immediately and keeps the player above other windows."
                        onOptionSaved: win.refreshWindowFlags()
                    }
                    VlcOption {
                        option: "video-deco"
                        label: "Show window decorations"
                        info: "Saved as a VLC video-output preference. Neo draws its own title bar and window controls."
                    }
                    VlcOption {
                        option: "qt-name-in-title"
                        label: "Show the media name in the title bar"
                        onOptionSaved: (value) => win.refreshWindowTitle(value)
                    }
                    VlcOption {
                        option: "qt-fullscreen-screennumber"
                        kind: "choice"
                        fieldWidth: 320
                        label: "Open fullscreen on"
                        choices: platform.fullscreenScreenChoices()
                    }
                    SectionTitle { text: "Playback Controls"; Layout.topMargin: 5 }
                    SettingRow {
                        label: "Start in compact mode"
                        info: "The next VLC Neo launch opens in a small window. You can resize it at any time."
                        NSwitch { checked: Theme.store.compactAtStart; onToggled: (on) => Theme.store.compactAtStart = on }
                    }
                    SettingRow {
                        label: "Auto-hide the controls"
                        info: "Choose when the top and bottom bars hide after the pointer leaves them."
                        NCombo {
                            objectName: "auto-hide-mode"
                            width: 320
                            model: [{ label: "Fullscreen only", value: "fullscreen" },
                                    { label: "Always", value: "always" }, { label: "Never", value: "never" }]
                            current: Theme.store.autoHideMode
                            onPicked: (v) => Theme.store.autoHideMode = v
                        }
                    }
                    SettingRow {
                        label: "Hide after"
                        info: "The bars appear when the pointer reaches an edge and hide after this delay."
                        ColumnLayout {
                            width: 320
                            spacing: 2
                            NSlider {
                                id: hideDelaySlider
                                objectName: "auto-hide-delay"
                                Layout.fillWidth: true
                                from: 0; to: 10000; stepSize: 100
                                value: Theme.store.hideDelay
                                onMoved: (v) => Theme.store.hideDelay = Math.round(v)
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                NText { text: "0 s"; dim: true; font.pixelSize: 10; Layout.alignment: Qt.AlignLeft }
                                Item { Layout.fillWidth: true }
                                NText { text: "5 s"; dim: true; font.pixelSize: 10 }
                                Item { Layout.fillWidth: true }
                                NText { text: "10 s"; dim: true; font.pixelSize: 10; Layout.alignment: Qt.AlignRight }
                            }
                        }
                    }
                    SettingRow { label: "Show controls in fullscreen"; NSwitch { checked: Theme.store.showControlsFullscreen; onToggled: (on) => Theme.store.showControlsFullscreen = on } }
                    SectionTitle { text: "Notifications and System Tray"; Layout.topMargin: 18 }
                    VlcOption {
                        option: "qt-system-tray"
                        label: "Show VLC Neo in the system tray"
                        info: "Shows a VLC Neo tray icon; activate it to bring the player back."
                        onOptionSaved: (value) => win.refreshSystemTray(value)
                    }
                    VlcOption {
                        option: "qt-notification"
                        kind: "choice"
                        fieldWidth: 320
                        label: "Show track notifications"
                        choices: [{ label: "Never", value: 0 }, { label: "When minimized", value: 1 }, { label: "Always", value: 2 }]
                    }
                    SectionTitle { text: "Setup" }
                    SettingRow { label: "Show the welcome screens again"; NButton { objectName: "show-onboarding"; text: "Show"; onClicked: { root.close(); root.showOnboarding() } } }
                    SettingRow { label: "Show the key pressed with every action"; info: "Shows a small “F · Fullscreen” message, so an accidental key press is easy to undo."; NSwitch { checked: Theme.store.keyOsd; onToggled: (on) => Theme.store.keyOsd = on } }
                    SettingRow { label: "Control bar layout"; NButton { text: "Customize…"; onClicked: { root.close(); win.openCustomize() } } }
                    SectionTitle { text: "On-screen display" }
                    VlcOption { option: "osd"; label: "Show messages on the video"; info: "VLC's own on-video text: volume, seek position…" }
                    VlcOption { option: "video-title-show"; label: "Show the media title when it starts" }
                    VlcOption { option: "video-title-timeout"; kind: "number"; fieldWidth: 90; label: "Title duration (ms)"; advanced: true }
                }

                // ------------------------------------------------ Privacy
                Page_ {
                    id_: "privacy"
                    SectionTitle { text: "History" }
                    SettingRow {
                        label: "Save recently played items"
                        NSwitch {
                            checked: { player.configRevision; return !!player.config("qt-recentplay") }
                            onToggled: (on) => player.setConfig("qt-recentplay", on)
                        }
                    }
                    SettingRow {
                        label: "Remember the playback position"
                        NSwitch {
                            checked: root.resumeMemoryEnabled
                            onToggled: (on) => root.setResumeMemoryEnabled(on)
                        }
                    }
                    VlcOption { option: "qt-recentplay-filter"; kind: "text"; fieldWidth: 270; label: "Never remember items matching"; info: "Separate matching words with |." }
                    SettingRow { label: "Clear history now"; NButton { text: "Clear"; onClicked: { player.clearPlaybackHistory(); win.toast("", "Playback history cleared") } } }
                    SectionTitle { text: "Network" }
                    VlcOption { option: "metadata-network-access"; label: "Fetch titles and cover art from the internet"; info: "Allow VLC to look up titles and artwork online." }
                    SettingRow {
                        label: "Submit played tracks to last.fm"
                        info: "Enter a Last.fm username and password to enable scrobbling."
                        NSwitch {
                            checked: root.lastFmSubmissionEnabled
                            onToggled: (on) => root.setLastFmEnabled(on)
                        }
                    }
                    VlcOption { option: "lastfm-username"; kind: "text"; fieldWidth: 270; label: "Last.fm username"; onOptionSaved: (value) => root.lastFmSubmissionEnabled = String(value).length > 0 }
                    VlcOption { option: "lastfm-password"; kind: "text"; secret: true; fieldWidth: 270; label: "Last.fm password" }
                    VlcOption { option: "scrobbler-url"; kind: "text"; fieldWidth: 270; label: "Last.fm submission URL" }
                }

                // ----------------------------------------------- Controls
                Page_ {
                    id_: "controls"
                    SectionTitle { text: "Keyboard Shortcuts" }
                    SettingRow { label: "Defaults"; NButton { width: 320; text: "Edit Keyboard Shortcuts"; icon: "keyboard"; onClicked: { root.close(); root.showShortcuts() } } }
                    SettingRow { label: "Reset all shortcuts"; NButton { width: 320; text: "Reset"; onClicked: Theme.resetShortcuts() } }
                    SectionTitle { text: "Skip Amounts" }
                    VlcOption { option: "extrashort-jump-size"; kind: "number"; fieldWidth: 320; valueSuffix: " s"; label: "Very short skip" }
                    VlcOption { option: "short-jump-size"; kind: "number"; fieldWidth: 320; valueSuffix: " s"; label: "Short skip" }
                    VlcOption { option: "medium-jump-size"; kind: "number"; fieldWidth: 320; valueSuffix: " s"; label: "Medium skip" }
                    VlcOption { option: "long-jump-size"; kind: "number"; fieldWidth: 320; valueSuffix: " s"; label: "Long skip" }
                    SectionTitle { text: "Mouse" }
                    SettingRow {
                        label: "Single click on the video"
                        NCombo { width: 320; model: [{ label: "Play / Pause", value: true }, { label: "Do nothing", value: false }]; current: Theme.store.clickToPause; onPicked: (value) => Theme.store.clickToPause = value }
                    }
                    SettingRow {
                        label: "Double click on the video"
                        NCombo { width: 320; model: [{ label: "Toggle fullscreen", value: true }, { label: "Do nothing", value: false }]; current: Theme.store.doubleClickFullscreen; onPicked: (value) => Theme.store.doubleClickFullscreen = value }
                    }
                    VlcOption {
                        option: "hotkeys-y-wheel-mode"; kind: "choice"; fieldWidth: 320; label: "Scroll wheel"
                        choices: [{ label: "Volume", value: 0 }, { label: "Seek", value: 2 }, { label: "Seek", value: 3 }, { label: "Does nothing", value: -1 }]
                        onOptionSaved: root.syncScrollDirection()
                    }
                    VlcOption {
                        option: "hotkeys-x-wheel-mode"; kind: "choice"; fieldWidth: 320; label: "Horizontal scroll"
                        choices: [{ label: "Volume", value: 0 }, { label: "Seek", value: 2 }, { label: "Seek", value: 3 }, { label: "Does nothing", value: -1 }]
                        onOptionSaved: root.syncScrollDirection()
                    }
                    SettingRow {
                        label: "Reverse scroll direction"
                        NSwitch {
                            objectName: "reverse-scroll-direction"
                            checked: root.reverseScrollDirection
                            enabled: root.reverseScrollAvailable
                            onToggled: (on) => root.setScrollDirectionReverse(on)
                        }
                    }
                    SectionTitle { text: "Remotes" }
                    SettingRow {
                        label: "Web remote control"
                        info: "VLC loads its web remote after restart."
                        NSwitch {
                            checked: { player.configRevision; return String(player.config("extraintf") || "").split(",").map(v => v.trim()).includes("http") }
                            onToggled: (on) => {
                                const interfaces = String(player.config("extraintf") || "").split(",").map(v => v.trim()).filter(v => v.length && v !== "http")
                                if (on) interfaces.push("http")
                                player.setConfig("extraintf", interfaces.join(","))
                            }
                        }
                    }
                    VlcOption { option: "http-port"; kind: "number"; fieldWidth: 320; label: "Port" }
                    VlcOption { option: "http-password"; kind: "text"; secret: true; fieldWidth: 320; label: "Password"; advanced: true }
                }

                // ----------------------------------------------- Playback
                Page_ {
                    id_: "playback"
                    SectionTitle { text: "Startup" }
                    SettingRow {
                        label: "Continue where you left off"
                        info: "Choose whether VLC asks to resume, always resumes, or starts at the beginning."
                        NCombo {
                            objectName: "playback-resume-mode"
                            width: 320
                            model: [{ label: "Ask", value: "ask" }, { label: "Always", value: "always" }, { label: "Never", value: "never" }]
                            current: Theme.store.resumeMode
                            onPicked: (value) => root.setResumeMode(value)
                        }
                    }
                    VlcOption { option: "playlist-autostart"; label: "Start playing as soon as a file opens" }
                    SettingRow {
                        objectName: "default-playback-speed-row"
                        label: "Default playback speed"
                        ColumnLayout {
                            width: 320
                            spacing: 3
                            NSlider {
                                objectName: "default-playback-speed-slider"
                                Layout.fillWidth: true
                                from: 0.25; to: 2; stepSize: 0.05
                                value: root.defaultPlaybackRate
                                onMoved: (value) => root.setDefaultPlaybackRate(value)
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                Repeater {
                                    model: [0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2]
                                    delegate: NText {
                                        required property real modelData
                                        Layout.fillWidth: true
                                        text: modelData === 1 ? "1" : String(modelData)
                                        dim: true
                                        font.pixelSize: 9
                                        horizontalAlignment: Text.AlignHCenter
                                    }
                                }
                            }
                        }
                    }
                    SettingRow {
                        label: "Pause when another app uses audio"
                        info: "Let VLC pause automatically when another application takes audio focus."
                        NSwitch {
                            checked: { player.configRevision; return !!player.config("playlist-cork") }
                            onToggled: (on) => player.setConfig("playlist-cork", on)
                        }
                    }

                    SectionTitle { text: "Tracks" }
                    VlcOption {
                        option: "preferred-resolution"; kind: "choice"; fieldWidth: 320; label: "Preferred video quality"
                        choices: [{ label: "Best available", value: -1 }, { label: "1080p", value: 1080 },
                                  { label: "720p", value: 720 }, { label: "576p", value: 576 },
                                  { label: "360p", value: 360 }, { label: "240p", value: 240 }]
                    }
                    VlcOption {
                        option: "menu-language"; kind: "choice"; fieldWidth: 320; label: "Preferred menu language"
                        choices: [{ label: "System default", value: "" }, { label: "English", value: "en" },
                                  { label: "French", value: "fr" }, { label: "Spanish", value: "es" },
                                  { label: "German", value: "de" }, { label: "Italian", value: "it" },
                                  { label: "Portuguese", value: "pt" }, { label: "Japanese", value: "ja" },
                                  { label: "Chinese", value: "zh" }, { label: "Russian", value: "ru" }]
                    }
                    VlcOption { option: "audio-track"; kind: "number"; fieldWidth: 320; label: "Default audio track"; info: "Choose a stream number starting at 0. Use -1 to let VLC choose automatically." }
                    VlcOption { option: "sub-track"; kind: "number"; fieldWidth: 320; label: "Default subtitle track"; info: "Choose a subtitle stream number starting at 0. Use -1 to let VLC choose automatically." }

                    SectionTitle { text: "Order" }
                    SettingRow {
                        label: "Repeat"
                        NCombo {
                            objectName: "playback-repeat-mode"
                            width: 320
                            model: [{ label: "Off", value: "off" }, { label: "All", value: "all" }, { label: "One", value: "one" }]
                            current: root.defaultRepeatMode
                            onPicked: (value) => root.setDefaultRepeatMode(value)
                        }
                    }
                    VlcOption { option: "random"; label: "Shuffle" }
                    VlcOption { option: "play-and-stop"; label: "Stop after each item" }
                    SettingRow {
                        label: "When playback finishes"
                        NCombo {
                            objectName: "playback-end-action"
                            width: 320
                            model: [{ label: "Stop", value: "nothing" }, { label: "Quit VLC", value: "exit" }, { label: "Pause", value: "pause" }]
                            current: root.playbackEndAction
                            onPicked: (value) => root.setPlaybackEndAction(value)
                        }
                    }

                    SectionTitle { text: "Seeking" }
                    SettingRow {
                        label: "Seek precisely"
                        info: "Disable fast seeking for more accurate positioning on long media."
                        NSwitch {
                            objectName: "precise-seeking-toggle"
                            checked: { player.configRevision; return !player.config("input-fast-seek") }
                            onToggled: (on) => player.setConfig("input-fast-seek", !on)
                        }
                    }

                    SectionTitle { text: "Advanced"; advanced: true }
                    VlcOption { option: "start-paused"; label: "Start paused"; advanced: true }
                    VlcOption { option: "auto-preparse"; label: "Read durations and tags of queued files"; advanced: true }
                    VlcOption { option: "input-repeat"; kind: "number"; fieldWidth: 90; label: "Repeat count"; advanced: true }
                }

                // -------------------------------------------------- Video
                Page_ {
                    id_: "video"
                    SectionTitle { text: "Output" }
                    VlcOption { option: "video"; label: "Enable video" }
                    VlcOption { option: "fullscreen"; label: "Start videos in fullscreen"; info: "Newly opened videos use fullscreen mode." }
                    VlcOption { option: "disable-screensaver"; label: "Stop the screensaver during playback" }
                    VlcOption { option: "video-wallpaper"; label: "Play video as desktop wallpaper" }

                    SectionTitle { text: "Picture" }
                    SettingRow {
                        objectName: "video-hue-row"
                        label: "Hue"
                        info: "Shift the colors in the picture."
                        NSlider {
                            objectName: "video-hue-slider"
                            width: 320
                            from: -180; to: 180; stepSize: 1
                            value: root.pictureValues.hue
                            onMoved: (value) => root.setPictureValue("hue", value)
                        }
                    }
                    SettingRow {
                        objectName: "video-brightness-row"
                        label: "Brightness"
                        info: "Adjust the overall lightness of the picture."
                        NSlider {
                            objectName: "video-brightness-slider"
                            width: 320
                            from: 0; to: 2; stepSize: 0.01
                            value: root.pictureValues.brightness
                            onMoved: (value) => root.setPictureValue("brightness", value)
                        }
                    }
                    SettingRow {
                        objectName: "video-contrast-row"
                        label: "Contrast"
                        info: "Adjust the difference between light and dark areas."
                        NSlider {
                            objectName: "video-contrast-slider"
                            width: 320
                            from: 0; to: 2; stepSize: 0.01
                            value: root.pictureValues.contrast
                            onMoved: (value) => root.setPictureValue("contrast", value)
                        }
                    }
                    SettingRow {
                        objectName: "video-saturation-row"
                        label: "Saturation"
                        info: "Adjust the strength of the colors."
                        NSlider {
                            objectName: "video-saturation-slider"
                            width: 320
                            from: 0; to: 3; stepSize: 0.01
                            value: root.pictureValues.saturation
                            onMoved: (value) => root.setPictureValue("saturation", value)
                        }
                    }
                    SettingRow {
                        objectName: "video-gamma-row"
                        label: "Gamma"
                        info: "Adjust brightness in the middle tones."
                        NSlider {
                            objectName: "video-gamma-slider"
                            width: 320
                            from: 0.01; to: 10; stepSize: 0.01
                            value: root.pictureValues.gamma
                            onMoved: (value) => root.setPictureValue("gamma", value)
                        }
                    }
                    SettingRow {
                        label: "Reset picture"
                        NButton { objectName: "video-picture-reset"; text: "Reset"; onClicked: root.resetPicture() }
                    }

                    SectionTitle { text: "Deinterlacing" }
                    VlcOption {
                        option: "deinterlace"; kind: "choice"; fieldWidth: 320; label: "Deinterlace"
                        choices: [{ label: "Automatic", value: -1 }, { label: "Off", value: 0 }, { label: "On", value: 1 }]
                    }
                    VlcOption {
                        option: "deinterlace-mode"; kind: "choice"; fieldWidth: 320; label: "Method"
                        choices: [{ label: "Automatic", value: "auto" }, { label: "Yadif (best)", value: "yadif" }, { label: "Yadif 2x", value: "yadif2x" },
                                  { label: "Blend", value: "blend" }, { label: "Linear", value: "linear" }, { label: "Bob", value: "bob" }]
                    }
                    SectionTitle { text: "Framing" }
                    VlcOption {
                        option: "aspect-ratio"; kind: "choice"; fieldWidth: 320; label: "Aspect ratio"
                        choices: [{ label: "Automatic", value: "" }, { label: "16:9", value: "16:9" },
                                  { label: "4:3", value: "4:3" }, { label: "21:9", value: "21:9" },
                                  { label: "16:10", value: "16:10" }, { label: "2.35:1", value: "2.35:1" },
                                  { label: "1:1", value: "1:1" }, { label: "5:4", value: "5:4" }]
                    }
                    VlcOption {
                        option: "crop"; kind: "choice"; fieldWidth: 320; label: "Crop ratio"
                        choices: [{ label: "Automatic", value: "" }, { label: "16:9", value: "16:9" },
                                  { label: "4:3", value: "4:3" }, { label: "21:9", value: "21:9" },
                                  { label: "16:10", value: "16:10" }, { label: "2.35:1", value: "2.35:1" },
                                  { label: "1:1", value: "1:1" }, { label: "5:4", value: "5:4" }]
                    }
                    SectionTitle { text: "Snapshots"; advanced: true }
                    VlcOption { option: "snapshot-path"; kind: "text"; fieldWidth: 240; label: "Save snapshots to"; advanced: true }
                    VlcOption {
                        option: "snapshot-format"; kind: "choice"; label: "Snapshot format"; advanced: true
                        choices: [{ label: "PNG", value: "png" }, { label: "JPEG", value: "jpg" }, { label: "TIFF", value: "tiff" }]
                    }
                    SectionTitle { text: "Advanced"; advanced: true }
                    VlcOption {
                        option: "vout"; kind: "choice"; label: "Video output module"; advanced: true
                        info: "Neo requires its own embedded video output while playing. This VLC preference is saved for use with other VLC interfaces."
                        choices: [{ label: "Automatic", value: "any" }, { label: "OpenGL", value: "gl" },
                                  { label: "OpenGL ES 2", value: "gles2" }, { label: "X11", value: "xcb_x11" },
                                  { label: "XVideo", value: "xcb_xv" }, { label: "Wayland", value: "wl_shm" },
                                  { label: "Disabled", value: "none" }]
                    }
                    VlcOption { option: "zoom"; kind: "number"; allowDecimal: true; fieldWidth: 90; label: "Zoom"; advanced: true }
                }

                // -------------------------------------------------- Audio
                Page_ {
                    id_: "audio"
                    SectionTitle { text: "Output" }
                    VlcOption { option: "audio"; label: "Enable audio" }
                    SettingRow {
                        label: "Output device"
                        info: "Devices are supplied by VLC while media is playing."
                        NCombo {
                            width: 320
                            model: root.outputDeviceChoices()
                            current: root.selectedOutputDevice()
                            onPicked: (value) => player.setAudioDevice(value)
                        }
                    }
                    VlcOption {
                        option: "stereo-mode"; kind: "choice"; fieldWidth: 320; label: "Speaker setup"
                        choices: [{ label: "Automatic", value: 0 }, { label: "Stereo", value: 1 },
                                  { label: "Reverse stereo", value: 2 }, { label: "Left", value: 3 },
                                  { label: "Right", value: 4 }, { label: "Dolby Surround", value: 5 },
                                  { label: "Headphones", value: 6 }, { label: "Mono", value: 7 }]
                    }
                    SectionTitle { text: "Volume" }
                    SettingRow {
                        objectName: "maximum-volume-row"
                        label: "Maximum volume"
                        ColumnLayout {
                            width: 320
                            NSlider {
                                objectName: "maximum-volume-slider"
                                Layout.fillWidth: true
                                from: 1; to: 3; stepSize: 0.05
                                value: Theme.store.maximumVolume
                                onMoved: (value) => {
                                    Theme.store.maximumVolume = Math.round(value * 100) / 100
                                    if (player.volume > Theme.store.maximumVolume) player.setVolume(Theme.store.maximumVolume)
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                NText { Layout.fillWidth: true; text: "100%"; dim: true; font.pixelSize: 10; horizontalAlignment: Text.AlignLeft }
                                NText { Layout.fillWidth: true; text: "200%"; dim: true; font.pixelSize: 10; horizontalAlignment: Text.AlignHCenter }
                                NText { Layout.fillWidth: true; text: "300%"; dim: true; font.pixelSize: 10; horizontalAlignment: Text.AlignRight }
                            }
                        }
                    }
                    SettingRow {
                        label: "Startup volume"
                        ColumnLayout {
                            width: 320
                            spacing: 4
                            NButton {
                                objectName: "startup-volume-remember"
                                Layout.fillWidth: true
                                text: "Remember last volume"
                                selected: Theme.store.startupVolumeMode === "remember"
                                onClicked: win.chooseStartupVolumeMode("remember")
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                NButton {
                                    objectName: "startup-volume-fixed"
                                    Layout.fillWidth: true
                                    text: "Always starts at"
                                    selected: Theme.store.startupVolumeMode === "fixed"
                                    onClicked: win.chooseStartupVolumeMode("fixed")
                                }
                                NField {
                                    objectName: "startup-volume-value"
                                    Layout.preferredWidth: 140
                                    enabled: Theme.store.startupVolumeMode === "fixed"
                                    horizontalAlignment: Text.AlignHCenter
                                    text: Math.round(Theme.store.startupVolume * 100) + "%"
                                    inputMethodHints: Qt.ImhFormattedNumbersOnly
                                    onEditingFinished: {
                                        const parsed = Number(text.replace("%", "").replace(",", ".")) / 100
                                        if (isFinite(parsed) && parsed >= 0 && parsed <= Theme.store.maximumVolume)
                                            Theme.store.startupVolume = Math.round(parsed * 100) / 100
                                        text = Math.round(Theme.store.startupVolume * 100) + "%"
                                    }
                                }
                            }
                        }
                    }
                    VlcOption { option: "volume-step"; kind: "number"; allowDecimal: true; fieldWidth: 320; label: "Volume step" }
                    SectionTitle { text: "Loudness" }
                    SettingRow {
                        objectName: "audio-normalizer-row"
                        label: "Normalize loudness"
                        info: "Reduce loudness differences between tracks."
                        NSwitch {
                            objectName: "audio-normalizer-toggle"
                            checked: root.audioFilterEnabled("normvol")
                            onToggled: (on) => root.setAudioFilter("normvol", on)
                        }
                    }
                    SettingRow {
                        id: normalizerTargetRow
                        objectName: "normalizer-target-level"
                        label: "Target level"
                        NField {
                            width: 320
                            text: { player.configRevision; return String(player.config("norm-max-level")) }
                            inputMethodHints: Qt.ImhFormattedNumbersOnly
                            onEditingFinished: {
                                const parsed = Number(text.replace(",", "."))
                                if (isFinite(parsed) && parsed > 0) player.setConfig("norm-max-level", parsed)
                                else text = String(player.config("norm-max-level"))
                            }
                        }
                    }
                    SettingRow {
                        objectName: "night-mode-row"
                        label: "Night mode"
                        info: "Compress loud peaks to make quiet passages easier to hear."
                        NSwitch {
                            objectName: "night-mode-toggle"
                            checked: root.audioFilterEnabled("compressor")
                            onToggled: (on) => root.setAudioFilter("compressor", on)
                        }
                    }
                    SettingRow {
                        visible: root.audioFilterEnabled("compressor")
                        objectName: "night-mode-threshold-row"
                        label: "Night mode threshold (dB)"
                        NField {
                            width: 320
                            text: { player.configRevision; return String(player.config("compressor-threshold")) }
                            inputMethodHints: Qt.ImhFormattedNumbersOnly
                            onEditingFinished: {
                                const parsed = Number(text.replace(",", "."))
                                if (isFinite(parsed) && parsed >= -30 && parsed <= 0) player.setConfig("compressor-threshold", parsed)
                                else text = String(player.config("compressor-threshold"))
                            }
                        }
                    }
                    VlcOption {
                        option: "audio-replay-gain-mode"; kind: "choice"; fieldWidth: 320; label: "Replay gain"
                        choices: [{ label: "Off", value: "none" }, { label: "Per track", value: "track" }, { label: "Per album", value: "album" }]
                    }
                    VlcOption { option: "audio-replay-gain-preamp"; kind: "number"; allowDecimal: true; minimumDecimalPlaces: 1; fieldWidth: 320; label: "Replay gain preamp" }
                    SectionTitle { id: audioEffectsTitle; text: "Effects" }
                    SettingRow {
                        objectName: "equalizer-enabled-row"
                        label: "Equalizer"
                        NSwitch {
                            objectName: "equalizer-enabled-toggle"
                            checked: root.equalizerEnabledState
                            onToggled: (on) => root.setEqualizerEnabled(on)
                        }
                    }
                    SettingRow {
                        label: "Preset"
                        NCombo {
                            objectName: "equalizer-preset"
                            width: 320
                            model: [{ label: "None", value: "off" }, { label: "Flat", value: "flat" },
                                    { label: "Classical", value: "classical" }, { label: "Club", value: "club" },
                                    { label: "Dance", value: "dance" }, { label: "Full bass", value: "fullbass" },
                                    { label: "Full bass and treble", value: "fullbasstreble" },
                                    { label: "Full treble", value: "fulltreble" }, { label: "Headphones", value: "headphones" },
                                    { label: "Large hall", value: "largehall" }, { label: "Live", value: "live" },
                                    { label: "Party", value: "party" }, { label: "Pop", value: "pop" },
                                    { label: "Reggae", value: "reggae" }, { label: "Rock", value: "rock" },
                                    { label: "Ska", value: "ska" }, { label: "Soft", value: "soft" },
                                    { label: "Soft rock", value: "softrock" }, { label: "Techno", value: "techno" }]
                            current: root.equalizerPresetState
                            onPicked: (value) => root.setEqualizerPreset(value)
                        }
                    }
                    Item {
                        Layout.fillWidth: true
                        implicitHeight: root.equalizerExpanded ? 420 : 34
                        ColumnLayout {
                            anchors.fill: parent
                            NButton {
                                visible: !root.equalizerExpanded
                                text: "Open Equalizer"
                                onClicked: root.equalizerExpanded = true
                            }
                            Rectangle {
                                visible: root.equalizerExpanded
                                Layout.fillWidth: true
                                Layout.preferredHeight: 420
                                radius: 8
                                color: Theme.panel
                                border.color: Theme.border
                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 16
                                    NButton {
                                        Layout.fillWidth: true
                                        text: "⌄  Close Equalizer"
                                        onClicked: root.equalizerExpanded = false
                                    }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        spacing: 8
                                        Repeater {
                                            model: root.equalizerFrequencies.length + 1
                                            delegate: ColumnLayout {
                                                required property int index
                                                Layout.fillWidth: true
                                                Layout.fillHeight: true
                                                spacing: 8
                                                NVerticalSlider {
                                                    Layout.alignment: Qt.AlignHCenter
                                                    Layout.fillHeight: true
                                                    Layout.preferredWidth: 28
                                                    from: -20; to: 20; stepSize: 0.5
                                                    value: index === 0 ? root.equalizerPreampValue : root.equalizerBandValues[index - 1]
                                                    onMoved: (v) => index === 0 ? root.setEqualizerPreamp(v) : root.setEqualizerBand(index - 1, v)
                                                }
                                                NText {
                                                    Layout.alignment: Qt.AlignHCenter
                                                    text: index === 0 ? "Preamp" : root.equalizerFrequencies[index - 1]
                                                    font.pixelSize: Theme.fontSmall
                                                }
                                                NField {
                                                    Layout.fillWidth: true
                                                    implicitWidth: 60
                                                    text: (index === 0 ? root.equalizerPreampValue : root.equalizerBandValues[index - 1]).toFixed(1)
                                                          + (activeFocus ? "" : " dB")
                                                    horizontalAlignment: Text.AlignHCenter
                                                    inputMethodHints: Qt.ImhFormattedNumbersOnly
                                                    onEditingFinished: {
                                                        const n = Number(text.replace(",", "."))
                                                        if (isFinite(n)) {
                                                            if (index === 0) root.setEqualizerPreamp(n)
                                                            else root.setEqualizerBand(index - 1, n)
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    SettingRow {
                        label: "Two-pass"
                        info: "Improves equalizer precision at a higher processing cost."
                        NSwitch {
                            objectName: "equalizer-two-pass"
                            checked: root.equalizerTwoPassEnabled
                            onToggled: (on) => root.setEqualizerTwoPass(on)
                        }
                    }
                    SettingRow {
                        label: "Spatial audio"
                        info: "VLC 3 provides its headphone spatializer filter."
                        NSwitch {
                            objectName: "spatial-audio-toggle"
                            checked: root.audioFilterEnabled("spatializer")
                            onToggled: (on) => root.setAudioFilter("spatializer", on)
                        }
                    }
                    SettingRow {
                        label: "Spatial audio mode"
                        info: "VLC 3 exposes one spatializer mode."
                        NCombo {
                            objectName: "spatial-audio-mode"
                            width: 320
                            enabled: false
                            model: [{ label: "Headphone virtualization", value: "headphones" }]
                            current: "headphones"
                        }
                    }
                    SettingRow {
                        label: "Stereo widening"
                        NSwitch {
                            objectName: "stereo-widen-toggle"
                            checked: root.audioFilterEnabled("stereo_widen")
                            onToggled: (on) => root.setAudioFilter("stereo_widen", on)
                        }
                    }
                    VlcOption { option: "spatializer-roomsize"; kind: "number"; allowDecimal: true; fieldWidth: 100; label: "Spatializer room size"; advanced: true }
                    VlcOption { option: "spatializer-width"; kind: "number"; allowDecimal: true; fieldWidth: 100; label: "Spatializer width"; advanced: true }
                    VlcOption { option: "spatializer-wet"; kind: "number"; allowDecimal: true; fieldWidth: 100; label: "Spatializer wet"; advanced: true }
                    VlcOption { option: "spatializer-dry"; kind: "number"; allowDecimal: true; fieldWidth: 100; label: "Spatializer dry"; advanced: true }
                    VlcOption { option: "spatializer-damp"; kind: "number"; allowDecimal: true; fieldWidth: 100; label: "Spatializer damping"; advanced: true }
                    VlcOption { option: "stereowiden-delay"; kind: "number"; allowDecimal: true; fieldWidth: 100; label: "Stereo widening delay"; advanced: true }
                    VlcOption { option: "stereowiden-feedback"; kind: "number"; allowDecimal: true; fieldWidth: 100; label: "Stereo widening feedback"; advanced: true }
                    VlcOption { option: "stereowiden-crossfeed"; kind: "number"; allowDecimal: true; fieldWidth: 100; label: "Stereo widening crossfeed"; advanced: true }
                    VlcOption { option: "stereowiden-dry-mix"; kind: "number"; allowDecimal: true; fieldWidth: 100; label: "Stereo widening dry mix"; advanced: true }
                    SectionTitle { text: "Playback"; advanced: true }
                    VlcOption { option: "audio-language"; kind: "text"; fieldWidth: 120; label: "Preferred audio language"; info: "Language codes, e.g. ja,en"; advanced: true }
                    VlcOption { option: "audio-time-stretch"; label: "Keep the pitch when changing speed"; advanced: true }
                    VlcOption { option: "audio-replay-gain-peak-protection"; label: "Prevent clipping"; advanced: true }
                    SectionTitle { text: "Advanced"; advanced: true }
                    VlcOption {
                        option: "aout"; kind: "choice"; label: "Output module"; advanced: true
                        info: "System default lets VLC select the audio output available on this computer."
                        choices: [{ label: "System default", value: "" }, { label: "Automatic", value: "any" },
                                  { label: "PulseAudio", value: "pulse" }, { label: "ALSA", value: "alsa" }]
                    }
                    VlcOption { option: "spdif"; label: "Pass-through to the receiver (S/PDIF / HDMI)"; advanced: true }
                    VlcOption { option: "compressor-threshold"; kind: "number"; allowDecimal: true; fieldWidth: 90; label: "Night mode threshold (dB)"; advanced: true }
                }

                // ---------------------------------------------- Subtitles
                Page_ {
                    id_: "subtitles"
                    SectionTitle { text: "Tracks & Languages" }
                    VlcOption { option: "spu"; label: "Enable subtitles"; info: "Show subtitle tracks when they are available." }
                    VlcOption { option: "sub-language"; kind: "text"; fieldWidth: 310; label: "Preferred language"; placeholderText: "System language"; info: "Preferred subtitle language codes, separated by commas (for example, en,fr)." }
                    VlcOption {
                        option: "subsdec-encoding"; kind: "choice"; fieldWidth: 310
                        label: "Text encoding"
                        info: "Choose how VLC reads the characters in subtitle files. Automatic is recommended unless text appears corrupted."
                        choices: [{ label: "Automatic", value: "" }, { label: "System", value: "system" },
                                  { label: "UTF-8", value: "UTF-8" }, { label: "UTF-16", value: "UTF-16" },
                                  { label: "UTF-16 BE", value: "UTF-16BE" }, { label: "UTF-16 LE", value: "UTF-16LE" },
                                  { label: "GB18030", value: "GB18030" }, { label: "ISO-8859-15", value: "ISO-8859-15" },
                                  { label: "Windows-1252", value: "Windows-1252" }, { label: "IBM850", value: "IBM850" },
                                  { label: "ISO-8859-2", value: "ISO-8859-2" }, { label: "Windows-1250", value: "Windows-1250" },
                                  { label: "ISO-8859-3", value: "ISO-8859-3" }, { label: "ISO-8859-10", value: "ISO-8859-10" },
                                  { label: "Windows-1251", value: "Windows-1251" }, { label: "KOI8-R", value: "KOI8-R" },
                                  { label: "KOI8-U", value: "KOI8-U" }, { label: "ISO-8859-6", value: "ISO-8859-6" },
                                  { label: "Windows-1256", value: "Windows-1256" }, { label: "ISO-8859-7", value: "ISO-8859-7" },
                                  { label: "Windows-1253", value: "Windows-1253" }, { label: "ISO-8859-8", value: "ISO-8859-8" },
                                  { label: "Windows-1255", value: "Windows-1255" }, { label: "ISO-8859-9", value: "ISO-8859-9" },
                                  { label: "Windows-1254", value: "Windows-1254" }, { label: "ISO-8859-11", value: "ISO-8859-11" },
                                  { label: "Windows-874", value: "Windows-874" }, { label: "ISO-8859-13", value: "ISO-8859-13" },
                                  { label: "Windows-1257", value: "Windows-1257" }, { label: "ISO-8859-14", value: "ISO-8859-14" },
                                  { label: "ISO-8859-16", value: "ISO-8859-16" }, { label: "ISO-2022-CN-EXT", value: "ISO-2022-CN-EXT" },
                                  { label: "EUC-CN", value: "EUC-CN" }, { label: "ISO-2022-JP-2", value: "ISO-2022-JP-2" },
                                  { label: "EUC-JP", value: "EUC-JP" }, { label: "Shift_JIS", value: "Shift_JIS" },
                                  { label: "CP949", value: "CP949" }, { label: "ISO-2022-KR", value: "ISO-2022-KR" },
                                  { label: "Big5", value: "Big5" }, { label: "ISO-2022-TW", value: "ISO-2022-TW" },
                                  { label: "Big5-HKSCS", value: "Big5-HKSCS" }, { label: "VISCII", value: "VISCII" },
                                  { label: "Windows-1258", value: "Windows-1258" }]
                    }
                    SectionTitle { text: "Loading Subtitles"; Layout.topMargin: 11 }
                    VlcOption { option: "sub-autodetect-file"; label: "Load subtitle files automatically"; info: "Search for a matching subtitle file beside each video." }
                    VlcOption {
                        option: "sub-autodetect-fuzzy"; kind: "choice"; fieldWidth: 310
                        label: "File name matching"
                        info: "How close the subtitle file name must be to the video file name."
                        choices: [{ label: "None", value: 0 },
                                  { label: "Any subtitle file in the folder", value: 1 },
                                  { label: "Files that contain the video name", value: 2 },
                                  { label: "Title with extra characters", value: 3 },
                                  { label: "Exact video name only", value: 4 }]
                    }
                    SectionTitle { text: "Appearance"; Layout.topMargin: 8 }
                    VlcOption { option: "freetype-font"; kind: "text"; fieldWidth: 310; label: "Font"; info: "Font family used to draw subtitles." }
                    SettingRow {
                        label: "Size values"
                        info: "Choose a size relative to the video or a fixed pixel size."
                        Chips {
                            chipWidth: 153
                            model: [{ label: "Relative", value: "relative" }, { label: "Pixels", value: "pixels" }]
                            current: root.subtitleSizeMode
                            onPicked: (value) => root.setSubtitleSizeMode(value)
                        }
                    }
                    VlcOption {
                        option: "freetype-rel-fontsize"; kind: "choice"; fieldWidth: 310; label: "Font size"; info: "Relative size scales with the video dimensions."
                        visible: root.subtitleSizeMode === "relative"
                        choices: [{ label: "Automatic", value: 0 }, { label: "Smaller", value: 20 }, { label: "Small", value: 18 },
                                  { label: "Normal", value: 16 }, { label: "Large", value: 12 }, { label: "Larger", value: 6 }]
                    }
                    VlcOption { option: "freetype-bold"; label: "Bold"; info: "Use a heavier font weight for subtitle text." }
                    VlcOption { option: "freetype-color"; kind: "color"; fieldWidth: 279; label: "Text color"; info: "Hexadecimal RGB color, for example #FFFFFF." }
                    VlcOption { option: "freetype-opacity"; kind: "slider"; fieldWidth: 310; sliderMax: 255; showScale: true; label: "Text opacity"; info: "Adjust how transparent the subtitle text appears." }
                    VlcOption {
                        option: "freetype-outline-thickness"; kind: "choice"; fieldWidth: 310; label: "Outline thickness"; info: "A text outline can improve readability over bright video."; Layout.topMargin: 5
                        choices: [{ label: "None", value: 0 }, { label: "Thin", value: 2 },
                                  { label: "Normal", value: 4 }, { label: "Thick", value: 6 }]
                    }
                    VlcOption { option: "freetype-outline-color"; kind: "color"; fieldWidth: 279; label: "Outline color"; info: "Hexadecimal RGB color for the text outline." }
                    VlcOption { option: "freetype-shadow-opacity"; kind: "opacityToggle"; sliderMax: 255; label: "Shadow"; info: "Turn the subtitle shadow on or off."; Layout.topMargin: -9 }
                    SectionTitle { text: "Online Subtitles"; Layout.topMargin: 11 }
                    SettingRow {
                        objectName: "opensubtitles-api-key-row"
                        labelTopAligned: true
                        visible: root.width >= 800
                        label: "OpenSubtitles API key"
                        info: "Use your own free API key. VLC Neo stores it in your local app settings and sends it only to OpenSubtitles."
                        ColumnLayout {
                            spacing: 6
                            NField {
                                id: openSubtitlesApiKeyInput
                                objectName: "opensubtitles-api-key"
                                Accessible.name: "OpenSubtitles API key"
                                Layout.minimumWidth: 220
                                Layout.preferredWidth: 320
                                Layout.fillWidth: true
                                placeholderText: openSubtitles.apiKeyConfigured ? "Key saved" : "Paste your API key"
                                echoMode: TextInput.Password
                                onAccepted: {
                                    openSubtitles.setApiKey(text)
                                    clear()
                                }
                            }
                            RowLayout {
                                Layout.alignment: Qt.AlignRight
                                spacing: 8
                                NButton {
                                    id: openSubtitlesApiKeySaveButton
                                    objectName: "opensubtitles-api-key-save"
                                    text: "Save key"
                                    primary: true
                                    onClicked: {
                                        openSubtitles.setApiKey(openSubtitlesApiKeyInput.text)
                                        openSubtitlesApiKeyInput.clear()
                                    }
                                    enabledState: openSubtitlesApiKeyInput.text.trim().length > 0
                                }
                                NButton {
                                    id: openSubtitlesApiKeyRemoveButton
                                    objectName: "opensubtitles-api-key-remove"
                                    text: "Remove key"
                                    flat: true
                                    enabledState: openSubtitles.apiKeyConfigured
                                    onClicked: openSubtitles.clearApiKey()
                                }
                            }
                        }
                    }
                    ColumnLayout {
                        visible: root.width < 800
                        Layout.fillWidth: true
                        spacing: 6
                        NText { text: "OpenSubtitles API key"; dim: true }
                        NText { text: "Use your own free API key. VLC Neo stores it locally and sends it only to OpenSubtitles."; dim: true; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                        NField {
                            id: compactOpenSubtitlesApiKeyInput
                            objectName: "opensubtitles-api-key-compact"
                            Accessible.name: "OpenSubtitles API key"
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            placeholderText: openSubtitles.apiKeyConfigured ? "Key saved" : "Paste your API key"
                            echoMode: TextInput.Password
                            onAccepted: { openSubtitles.setApiKey(text); clear() }
                        }
                        RowLayout {
                            NButton {
                                objectName: "opensubtitles-api-key-save-compact"
                                text: "Save key"
                                primary: true
                                enabledState: compactOpenSubtitlesApiKeyInput.text.trim().length > 0
                                onClicked: { openSubtitles.setApiKey(compactOpenSubtitlesApiKeyInput.text); compactOpenSubtitlesApiKeyInput.clear() }
                            }
                            NButton { objectName: "opensubtitles-api-key-remove-compact"; text: "Remove key"; flat: true; enabledState: openSubtitles.apiKeyConfigured; onClicked: openSubtitles.clearApiKey() }
                        }
                    }
                    SettingRow {
                        label: "Get an API key"
                        info: "Create a personal API key in your OpenSubtitles account."
                        NButton {
                            text: "Open OpenSubtitles"
                            flat: true
                            onClicked: Qt.openUrlExternally("https://www.opensubtitles.com/consumers")
                        }
                    }
                    SectionTitle { text: "Advanced"; advanced: true }
                    VlcOption { option: "freetype-fontsize"; kind: "number"; fieldWidth: 80; label: "Font size (px)"; visible: root.subtitleSizeMode === "pixels" }
                    VlcOption { option: "sub-margin"; kind: "number"; fieldWidth: 80; label: "Distance from the bottom (px)"; advanced: true }
                    VlcOption { option: "freetype-outline-opacity"; kind: "slider"; fieldWidth: 190; sliderMax: 255; label: "Outline opacity"; advanced: true }
                    VlcOption { option: "freetype-shadow-opacity"; kind: "slider"; fieldWidth: 190; sliderMax: 255; label: "Shadow opacity"; advanced: true }
                    VlcOption { option: "freetype-shadow-color"; kind: "color"; fieldWidth: 120; label: "Shadow color"; advanced: true }
                    VlcOption { option: "freetype-shadow-angle"; kind: "number"; allowDecimal: true; fieldWidth: 80; label: "Shadow angle"; advanced: true }
                    VlcOption { option: "freetype-shadow-distance"; kind: "number"; allowDecimal: true; fieldWidth: 80; label: "Shadow distance"; advanced: true }
                    VlcOption { option: "freetype-background-color"; kind: "color"; fieldWidth: 120; label: "Text background"; advanced: true }
                    VlcOption { option: "freetype-background-opacity"; kind: "slider"; fieldWidth: 190; sliderMax: 255; label: "Background opacity"; advanced: true }
                }

                // ------------------------------------------------ Library
                Page_ {
                    id_: "library"
                    SectionTitle { text: "Opening Files" }
                    VlcOption { id: libraryOneInstanceOption; option: "one-instance"; label: "Only allow one VLC window"; info: "Open files in the existing VLC window." }
                    VlcOption {
                        option: "one-instance-when-started-from-file"
                        label: "Apply to files opened from the file manager"
                        info: "Requires Only allow one VLC window."
                        enabled: !!libraryOneInstanceOption.current
                    }
                    VlcOption { option: "playlist-enqueue"; label: "Add to the playlist instead of replacing it" }
                    VlcOption {
                        option: "recursive"; kind: "choice"; fieldWidth: 270; label: "When opening a folder"
                        info: "Controls how deeply VLC pre-parses items in subfolders. Neo's folder browser and library index still scan recursively."
                        choices: [{ label: "No subfolders", value: "none" },
                                  { label: "Collapse; expand on play", value: "collapse" },
                                  { label: "Include subfolders", value: "expand" }]
                    }
                    VlcOption {
                        option: "show-hiddenfiles"; label: "Show hidden files"
                        onOptionSaved: (value) => Theme.store.showHiddenFiles = !!value
                    }
                    SectionTitle { text: "Metadata & Artwork" }
                    VlcOption {
                        option: "metadata-network-access"; kind: "choice"; fieldWidth: 270; label: "Fetch titles and artwork"
                        info: "Allows VLC to look up titles and artwork online. Neo's library scan reads embedded tags and local cover art."
                        choices: [{ label: "From the file only", value: false }, { label: "From the file and internet", value: true }]
                    }
                    VlcOption { option: "media-library"; label: "Use the media library" }
                    SectionTitle { text: "Advanced"; advanced: true }
                    VlcOption { option: "ignore-filetypes"; kind: "text"; fieldWidth: 250; label: "Ignored file types"; advanced: true }
                    SectionTitle { text: "Pinned folders"; advanced: true }
                    Repeater {
                        visible: Theme.store.advancedOptions
                        model: Theme.store.pinned.length ? Theme.store.pinned.split("\n") : []
                        delegate: SettingRow {
                            required property string modelData
                            label: modelData
                            NButton {
                                text: "Remove"; flat: true
                                onClicked: Theme.store.pinned = Theme.store.pinned.split("\n").filter(p => p !== modelData).join("\n")
                            }
                        }
                    }
                    NText { visible: Theme.store.advancedOptions && Theme.store.pinned.length === 0; text: "Pin folders from the library panel (L)."; dim: true }
                    SectionTitle { text: "Playlists"; advanced: true }
                    VlcOption { option: "playlist-tree"; kind: "choice"; label: "Show folders inside playlists"; advanced: true
                        choices: [{ label: "Default", value: 0 }, { label: "Always", value: 1 }, { label: "Never", value: 2 }] }
                }

                // ------------------------------------------------ Network
                Page_ {
                    id_: "network"
                    SectionTitle { text: "Buffering" }
                    SettingRow {
                        label: "Buffering"
                        info: "Choose a latency profile or set each cache value yourself."
                        NCombo {
                            width: 320
                            model: root.bufferingProfiles
                            current: root.bufferingProfile
                            onPicked: (value) => root.setBufferingProfile(value)
                        }
                    }
                    VlcOption { option: "file-caching"; kind: "number"; fieldWidth: 320; label: "Local files"; enabled: root.bufferingProfile === "Custom"; hideValueWhenDisabled: true; onOptionSaved: root.markCustomBuffering() }
                    VlcOption { option: "disc-caching"; kind: "number"; fieldWidth: 320; label: "Discs"; enabled: root.bufferingProfile === "Custom"; hideValueWhenDisabled: true; onOptionSaved: root.markCustomBuffering() }
                    VlcOption { option: "network-caching"; kind: "number"; fieldWidth: 320; label: "Network streams"; enabled: root.bufferingProfile === "Custom"; hideValueWhenDisabled: true; onOptionSaved: root.markCustomBuffering() }
                    VlcOption { option: "live-caching"; kind: "number"; fieldWidth: 320; label: "Live capture"; enabled: root.bufferingProfile === "Custom"; hideValueWhenDisabled: true; onOptionSaved: root.markCustomBuffering() }
                    SectionTitle { text: "Proxy" }
                    VlcOption { option: "http-proxy"; kind: "text"; fieldWidth: 320; label: "HTTP proxy"; placeholderText: "System proxy"; info: "Enter http://host:port or host:port. For authentication, include the username here and enter its password below. Leave blank to use the system proxy." }
                    VlcOption { option: "http-proxy-pwd"; kind: "text"; fieldWidth: 320; label: "HTTP proxy password"; info: "Password used to authenticate with the HTTP proxy. Enter the matching username in the HTTP proxy address field."; secret: true }
                    VlcOption { option: "socks"; kind: "text"; fieldWidth: 220; label: "SOCKS server"; advanced: true }
                    VlcOption { option: "socks-user"; kind: "text"; fieldWidth: 180; label: "SOCKS username"; advanced: true }
                    VlcOption { option: "socks-pwd"; kind: "text"; fieldWidth: 180; label: "SOCKS password"; secret: true; advanced: true }
                    SectionTitle { text: "Security" }
                    VlcOption { option: "gnutls-system-trust"; label: "Verify certificates against the system trust store"; info: "Use the certificates installed for this system." }
                    VlcOption { option: "gnutls-dir-trust"; kind: "text"; fieldWidth: 220; label: "Additional certificate directory"; advanced: true }
                    VlcOption {
                        option: "gnutls-priorities"; kind: "choice"; fieldWidth: 320; label: "Cipher preference"
                        choices: [{ label: "Performance", value: "PERFORMANCE" }, { label: "Balanced", value: "NORMAL" },
                                  { label: "Secure 128-bit", value: "SECURE128" }, { label: "Secure 256-bit", value: "SECURE256" }]
                    }
                    NButton {
                        text: Theme.store.advancedOptions ? "Hide advanced options" : "Advanced Options"
                        Layout.fillWidth: true
                        onClicked: Theme.store.advancedOptions = !Theme.store.advancedOptions
                    }
                    SectionTitle { text: "Connection"; advanced: true }
                    VlcOption { option: "ipv4-timeout"; kind: "number"; fieldWidth: 90; label: "Connection timeout (ms)"; info: "Time VLC waits for a network connection."; advanced: true }
                    VlcOption { option: "http-reconnect"; label: "Reconnect automatically"; advanced: true }
                    VlcOption { option: "mtu"; kind: "number"; fieldWidth: 90; label: "Network packet size (MTU)"; advanced: true }
                    VlcOption { option: "network-synchronisation"; label: "Synchronize playback over the network"; advanced: true }
                }

                // -------------------------------------------- Performance
                Page_ {
                    id_: "performance"
                    SectionTitle { text: "Decoding" }
                    VlcOption {
                        option: "avcodec-hw"; kind: "choice"; label: "Hardware-accelerated decoding"
                        choices: [{ label: "Automatic", value: "any" }, { label: "VDPAU", value: "vdpau_avcodec" },
                                  { label: "Off (software)", value: "none" }]
                    }
                    VlcOption {
                        option: "postproc-q"; kind: "choice"; label: "Video post-processing"
                        choices: [{ label: "Off", value: 0 }, { label: "Very low", value: 1 }, { label: "Low", value: 2 },
                                  { label: "Medium", value: 3 }, { label: "Medium high", value: 4 },
                                  { label: "High", value: 5 }, { label: "Maximum", value: 6 }]
                    }
                    VlcOption {
                        option: "avcodec-skiploopfilter"; kind: "choice"; label: "Skip the H.264 loop filter"
                        choices: [{ label: "Never", value: 0 }, { label: "Non-reference frames", value: 1 },
                                  { label: "Bidirectional frames", value: 2 }, { label: "Non-key frames", value: 3 }, { label: "All frames", value: 4 }]
                    }
                    VlcOption { option: "avcodec-threads"; kind: "number"; fieldWidth: 80; label: "Decoding threads (0 = auto)" }
                    SectionTitle { text: "Smooth Playback" }
                    VlcOption { option: "drop-late-frames"; label: "Drop frames when the system can't keep up" }
                    VlcOption { option: "rt-priority"; label: "Give VLC real-time priority" }
                    VlcOption { option: "rt-offset"; kind: "number"; fieldWidth: 80; label: "Process priority" }
                    SettingRow {
                        label: "Rescan plugins"
                        info: "VLC rebuilds the plugin cache the next time it starts."
                        NButton {
                            text: "Rescan"
                            onClicked: {
                                player.setConfig("reset-plugins-cache", true)
                                win.toast("", "VLC will rescan plugins on next launch")
                            }
                        }
                    }
                    NButton {
                        text: Theme.store.advancedOptions ? "Hide advanced options" : "Advanced Options"
                        objectName: "performance-advanced-options"
                        Layout.fillWidth: true
                        onClicked: Theme.store.advancedOptions = !Theme.store.advancedOptions
                    }
                    SectionTitle { text: "Developer" }
                    VlcOption { option: "encoder"; kind: "text"; fieldWidth: 270; placeholderText: "Automatic"; label: "Encoder"; info: "Preferred VLC encoder module list." }
                    VlcOption { option: "codec"; kind: "text"; fieldWidth: 270; placeholderText: "Automatic"; label: "Decoder"; info: "Preferred VLC decoder module list." }
                    VlcOption {
                        option: "clock-synchro"; kind: "choice"; label: "Clock synchronisation"
                        choices: [{ label: "Default", value: -1 }, { label: "Off", value: 0 }, { label: "On", value: 1 }]
                    }
                    VlcOption { option: "clock-jitter"; kind: "number"; fieldWidth: 90; label: "Clock jitter (ms)" }
                    VlcOption { option: "cr-average"; kind: "number"; fieldWidth: 90; label: "Clock reference averaging" }
                    SectionTitle { text: "Advanced"; advanced: true }
                    VlcOption { option: "avcodec-fast"; label: "Allow decoding speed tricks"; advanced: true }
                    VlcOption { option: "avcodec-hurry-up"; label: "Hurry up decoding"; advanced: true }
                    VlcOption { option: "avcodec-error-resilience"; kind: "number"; fieldWidth: 90; label: "Error resilience"; advanced: true }
                    VlcOption { option: "avcodec-workaround-bugs"; kind: "number"; fieldWidth: 90; label: "Decoder compatibility flags"; advanced: true }
                    VlcOption { option: "avcodec-options"; kind: "text"; fieldWidth: 220; label: "FFmpeg decoder options"; advanced: true }
                    VlcOption { option: "postproc-name"; kind: "text"; fieldWidth: 220; label: "Post-processing filters"; advanced: true }
                    VlcOption { option: "sout-transcode-threads"; kind: "number"; fieldWidth: 90; label: "Transcoding threads"; advanced: true }
                    VlcOption { option: "sout-transcode-pool-size"; kind: "number"; fieldWidth: 90; label: "Transcoding picture pool"; advanced: true }
                }

                // ---------------------------------------------- Recording
                Page_ {
                    id_: "recording"
                    SectionTitle { text: "Recording" }
                    SettingRow {
                        objectName: "vlc-option-input-record-path"
                        label: "Save recordings to"
                        info: "Choose the folder where VLC writes recordings."
                        RowLayout {
                            spacing: 8
                            NField {
                                id: recordingPathField
                                width: 180
                                text: { player.configRevision; return String(player.config("input-record-path") || "~/Videos") }
                                onEditingFinished: player.setConfig("input-record-path", text)
                            }
                            NButton { text: "Browse"; onClicked: recordingFolderDialog.open() }
                        }
                    }
                    VlcOption {
                        option: "input-record-native"
                        label: "Record without re-encoding when possible"
                        info: "Prefer the original stream format when VLC can record it directly."
                    }
                    SectionTitle { text: "Casting" }
                    NText { text: "Choose a screen to play on. Neo keeps its playback controls connected to the selected device."; dim: true; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                    RendererPicker {
                        objectName: "cast-device-list"
                        Layout.fillWidth: true
                        onSelected: (id) => {
                            if (!player.setRenderer(id))
                                win.toast("Could not cast", "This media or device could not be played by VLC Neo.")
                        }
                    }
                    NButton {
                        visible: player.rendererDevices.some(device => device.selected)
                        text: "Disconnect from device"
                        flat: true
                        onClicked: player.setRenderer("")
                    }
                    VlcOption {
                        option: "sout-chromecast-conversion-quality"; kind: "choice"; fieldWidth: 240
                        label: "Cast quality"
                        info: "Automatic uses VLC's built-in desktop default (Medium on supported x86 Linux builds); the other choices select specific Chromecast conversion modes."
                        choices: [{ label: "Automatic", value: 1 },
                                  { label: "High quality, high bandwidth", value: 0 },
                                  { label: "Low quality, low bandwidth", value: 2 },
                                  { label: "Low CPU, high bandwidth", value: 3 }]
                    }
                    SectionTitle { text: "Streaming" }
                    VlcOption { option: "sout-display"; label: "Play locally while streaming" }
                    VlcOption { option: "sout-audio"; label: "Include audio" }
                    VlcOption { option: "sout-video"; label: "Include video" }
                    VlcOption { option: "sout-spu"; label: "Include subtitles" }
                    VlcOption {
                        option: "sout-x264-preset"; kind: "choice"; fieldWidth: 240
                        label: "Encoding preset"
                        choiceDisplayAliases: ({ "": "medium" })
                        choices: [{ label: "Ultrafast", value: "ultrafast" }, { label: "Superfast", value: "superfast" },
                                  { label: "Very fast", value: "veryfast" }, { label: "Faster", value: "faster" },
                                  { label: "Fast", value: "fast" }, { label: "Medium", value: "medium" },
                                  { label: "Slow", value: "slow" }, { label: "Slower", value: "slower" },
                                  { label: "Very slow", value: "veryslow" }, { label: "Placebo", value: "placebo" }]
                    }
                    NButton {
                        text: Theme.store.advancedOptions ? "Hide advanced options" : "Advanced Options"
                        Layout.fillWidth: true
                        onClicked: Theme.store.advancedOptions = !Theme.store.advancedOptions
                    }
                    SectionTitle { text: "Encoding"; advanced: true }
                    VlcOption { option: "sout-transcode-vcodec"; kind: "text"; fieldWidth: 180; label: "Video codec"; advanced: true }
                    VlcOption { option: "sout-transcode-vb"; kind: "number"; fieldWidth: 100; label: "Video bitrate (kb/s)"; advanced: true }
                    VlcOption { option: "sout-transcode-fps"; kind: "text"; fieldWidth: 100; label: "Video frame rate"; advanced: true }
                    VlcOption { option: "sout-transcode-acodec"; kind: "text"; fieldWidth: 180; label: "Audio codec"; advanced: true }
                    VlcOption { option: "sout-transcode-ab"; kind: "number"; fieldWidth: 100; label: "Audio bitrate (kb/s)"; advanced: true }
                    VlcOption { option: "sout-transcode-samplerate"; kind: "number"; fieldWidth: 100; label: "Audio sample rate"; advanced: true }
                    VlcOption {
                        option: "sout-x264-tune"; kind: "choice"; fieldWidth: 180; label: "H.264 tuning"; advanced: true
                        choices: [{ label: "None", value: "" }, { label: "Film", value: "film" },
                                  { label: "Animation", value: "animation" }, { label: "Grain", value: "grain" },
                                  { label: "Still image", value: "stillimage" }, { label: "PSNR", value: "psnr" },
                                  { label: "SSIM", value: "ssim" }, { label: "Fast decode", value: "fastdecode" },
                                  { label: "Zero latency", value: "zerolatency" }]
                    }
                    VlcOption { option: "sout-chromecast-ip"; kind: "text"; fieldWidth: 180; label: "Chromecast address"; info: "IP address of the Chromecast device used for stream output."; advanced: true }
                    VlcOption { option: "sout-chromecast-port"; kind: "number"; fieldWidth: 100; label: "Chromecast port"; info: "Control port VLC uses to communicate with the Chromecast."; advanced: true }
                }

                // --------------------------------------------- Extensions
                Page_ {
                    id_: "extensions"
                    SectionTitle { text: "Add-ons" }
                    Rectangle {
                        id: addonCatalogCard
                        objectName: "addon-catalog-card"
                        Layout.fillWidth: true
                        Layout.preferredHeight: 184
                        color: Theme.field
                        radius: 8
                        clip: true
                        ListView {
                            id: addonCatalogList
                            anchors.fill: parent
                            anchors.margins: 8
                            clip: true
                            spacing: 6
                            model: player.addons
                            delegate: Rectangle {
                                required property var modelData
                                width: addonCatalogList.width
                                visible: root.addonSearch.length === 0
                                         || modelData.name.toLowerCase().includes(root.addonSearch.toLowerCase())
                                         || modelData.summary.toLowerCase().includes(root.addonSearch.toLowerCase())
                                height: visible ? addonRow.implicitHeight + 16 : 0
                                color: root.selectedAddonUuid === modelData.uuid ? Theme.hover : Theme.bar
                                radius: Theme.radiusSmall
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: root.selectedAddonUuid = modelData.uuid
                                }
                                RowLayout {
                                    id: addonRow
                                    anchors.fill: parent
                                    anchors.margins: 10
                                    enabled: false
                                    NText {
                                        Layout.fillWidth: true
                                        text: "<b>" + modelData.name + "</b>  <font color='" + Theme.textFaint + "'>" + modelData.type + "</font><br>" + modelData.summary
                                        textFormat: Text.RichText
                                        wrapMode: Text.WordWrap
                                        color: Theme.textDim
                                    }
                                    NText {
                                        text: modelData.installing ? "Installing…"
                                              : modelData.removing ? "Removing…"
                                              : modelData.installed ? "Installed" : modelData.version
                                        color: Theme.textFaint
                                    }
                                }
                            }
                        }
                        NText {
                            anchors.centerIn: parent
                            visible: player.addonsLoading || (root.addonStatus.length > 0 && player.addons.length === 0)
                            text: player.addonsLoading ? "Loading add-ons…" : root.addonStatus
                            color: Theme.textFaint
                            wrapMode: Text.WordWrap
                            width: parent.width - 24
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }
                    NText {
                        objectName: "addon-action-status"
                        visible: root.addonActionUuid.length > 0
                                 || root.addonStatus === "Add-on installed."
                                 || root.addonStatus === "Add-on removed."
                                 || root.addonStatus === "Add-on already installed."
                                 || root.addonStatus.startsWith("VLC found no installable")
                                 || root.addonStatus.startsWith("VLC could not")
                        text: root.addonStatus
                        dim: true
                        Layout.fillWidth: true
                    }
                    RowLayout {
                        id: addonSearchRow
                        Layout.fillWidth: true
                        NField {
                            id: addonSearchField
                            objectName: "addon-search-field"
                            Layout.preferredWidth: 180
                            Layout.minimumWidth: 180
                            Layout.maximumWidth: 180
                            placeholderText: "Search"
                            onTextChanged: root.addonSearch = text
                        }
                        NButton { id: addonFindButton; text: "Find more extensions"; Layout.preferredWidth: 160; Layout.minimumWidth: 160; Layout.maximumWidth: 160; enabledState: !player.addonsLoading; onClicked: { root.addonStatus = "Searching the VLC add-on catalog…"; player.findAddons("repo://") } }
                        NButton {
                            id: addonAddButton
                            text: "Add"
                            Layout.preferredWidth: 86
                            Layout.minimumWidth: 86
                            Layout.maximumWidth: 86
                            enabledState: !player.addonsLoading
                                          && !(root.selectedAddon && (root.selectedAddon.installing || root.selectedAddon.removing))
                            onClicked: {
                                if (!root.selectedAddon || root.selectedAddon.installed || !root.selectedAddon.manageable) {
                                    addonPackageDialog.open()
                                    return
                                }
                                root.beginAddonAction("install", root.selectedAddon.uuid)
                            }
                        }
                        NButton {
                            id: addonRemoveButton
                            text: "Remove"
                            Layout.preferredWidth: 86
                            Layout.minimumWidth: 86
                            Layout.maximumWidth: 86
                            enabledState: !player.addonsLoading && !!root.selectedAddon && root.selectedAddon.installed
                                          && root.selectedAddon.manageable && !root.selectedAddon.installing && !root.selectedAddon.removing
                            onClicked: {
                                if (root.selectedAddon)
                                    root.beginAddonAction("remove", root.selectedAddon.uuid)
                            }
                        }
                    }
                    VlcOption {
                        option: "qt-autoload-extensions"
                        label: "Load add-ons on startup"
                        info: "Controls whether VLC loads extensions when it starts."
                    }
                    NButton {
                        text: Theme.store.advancedOptions ? "Hide advanced options" : "Advanced Options"
                        Layout.fillWidth: true
                        onClicked: Theme.store.advancedOptions = !Theme.store.advancedOptions
                    }
                }
                Item { implicitHeight: 12 }
            }
        }
        }
    }

    component Page_: ColumnLayout {
        property string id_
        visible: root.page === id_
        Layout.fillWidth: true
        spacing: 14
    }
}
