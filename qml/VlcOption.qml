import QtQuick
import QtQuick.Layouts
import Neo 1.0

// A VLC core preference (stored in vlcrc). Hidden when this VLC build lacks it
// or when its advanced level is disabled; hiding never changes the stored value.
SettingRow {
    id: root
    property string option
    property string kind: "bool"          // bool | choice | text | number
    property var choices: []              // [{label, value}]
    property int fieldWidth: 160
    property bool advanced: false
    property bool allowDecimal: false
    property var current: player.config(option)
    objectName: "vlc-option-" + option
    visible: current !== undefined && (!advanced || Theme.store.advancedOptions)

    function save(v) { player.setConfig(option, v); current = v }
    function parseNumber(value) {
        const parsed = allowDecimal ? Number(value.replace(",", ".")) : parseInt(value, 10)
        return isFinite(parsed) ? parsed : undefined
    }

    Loader {
        sourceComponent: root.kind === "bool" ? boolComp : root.kind === "choice" ? choiceComp : textComp
    }
    Component {
        id: boolComp
        NSwitch { checked: !!root.current; onToggled: (on) => root.save(on) }
    }
    Component {
        id: choiceComp
        NCombo {
            width: root.fieldWidth
            model: root.choices
            current: root.current
            onPicked: (v) => root.save(v)
        }
    }
    Component {
        id: textComp
        NField {
            width: root.fieldWidth
            text: root.current === undefined ? "" : String(root.current)
            inputMethodHints: root.kind === "number"
                              ? (root.allowDecimal ? Qt.ImhFormattedNumbersOnly : Qt.ImhDigitsOnly)
                              : Qt.ImhNone
            onEditingFinished: {
                if (root.kind !== "number") {
                    root.save(text)
                    return
                }
                const parsed = root.parseNumber(text)
                if (parsed !== undefined) root.save(parsed)
                else text = String(root.current)
            }
        }
    }
}
