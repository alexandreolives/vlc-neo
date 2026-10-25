import QtQuick
import QtQuick.Layouts
import Neo 1.0

Modal {
    id: root
    objectName: "cast-device-dialog"
    title: "Play on a device"
    subtitle: "Choose a TV or speaker. VLC Neo will keep playback controls connected to it."
    width: Math.min(460, win.width - 32)
    height: Math.min(440, win.height - 32)
    bodyMargin: 18
    property string requestedRendererId: ""
    property double connectStartedAt: 0

    function rendererReadyForPlayback(device) {
        return !!device && device.selected
                && ["Connected", "Playing", "Paused"].includes(device.status)
    }

    onOpened: {
        picker.searchingTimedOut = false
        player.discoverRenderers(true)
    }
    onClosed: win.focusKeys()

    RendererPicker {
        id: picker
        width: root.width - 36
        onSelected: (id) => {
            if (player.setRenderer(id)) {
                root.requestedRendererId = id
                root.connectStartedAt = Date.now()
            } else {
                win.toast("Could not cast", "This media or device could not be played by VLC Neo.")
            }
        }
    }

    Timer {
        interval: 300
        repeat: true
        running: root.requestedRendererId.length > 0
        onTriggered: {
            const device = player.rendererDevices.find(item => item.id === root.requestedRendererId)
            if (root.rendererReadyForPlayback(device)) {
                root.requestedRendererId = ""
                win.toast("Casting", "Playback controls are connected to " + device.name + ".")
                root.close()
            } else if (Date.now() - root.connectStartedAt > 1500 && (!device || !device.selected)) {
                root.requestedRendererId = ""
                win.toast("Could not cast", "VLC Neo could not start playback on that device.")
            } else if (Date.now() - root.connectStartedAt > 12000) {
                root.requestedRendererId = ""
                win.toast("Could not cast", "The device did not start playback. Check that it is ready.")
            }
        }
    }

    footer: [
        Item { Layout.fillWidth: true },
        NButton {
            visible: player.rendererDevices.some(device => device.selected)
            text: "Disconnect"
            flat: true
            onClicked: {
                if (player.setRenderer("")) {
                    win.toast("Casting", "Disconnected from the playback device.")
                    root.close()
                }
            }
        },
        NButton { text: "Close"; onClicked: root.close() }
    ]
}
