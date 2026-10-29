import QtQuick
import QtQuick.Layouts
import Neo 1.0

// A VLC core preference (stored in vlcrc). Hidden when this VLC build lacks it
// or when its advanced level is disabled; hiding never changes the stored value.
SettingRow {
    id: root
    property string option
    property string kind: "bool"          // bool | choice | text | number | color | slider | opacityToggle
    property string placeholderText: ""
    property var choices: []              // [{label, value}]
    property var choiceDisplayAliases: ({}) // maps raw VLC values to equivalent display values
    property int fieldWidth: 160
    property string valueSuffix: ""
    property int minimumDecimalPlaces: 0
    property bool advanced: false
    property bool allowDecimal: false
    property bool showScale: false
    property bool secret: false
    property bool hideValueWhenDisabled: false
    signal optionSaved(var value)
    property real sliderMin: 0
    property real sliderMax: 100
    property real sliderStep: 1
    property var current: player.config(option)
    readonly property var choiceDisplayValue: {
        const key = String(current)
        return Object.prototype.hasOwnProperty.call(choiceDisplayAliases, key)
                ? choiceDisplayAliases[key] : current
    }
    optionDescription: player.configDescription(option)
    readonly property string displayValue: {
        if (hideValueWhenDisabled && !enabled) return ""
        if (current === undefined) return ""
        let value = String(current)
        if (kind === "number" && allowDecimal) {
            const number = Number(current)
            value = String(isFinite(number) ? Number(number.toPrecision(8)) : number)
            const decimalIndex = value.indexOf(".")
            const decimalPlaces = decimalIndex < 0 ? 0 : value.length - decimalIndex - 1
            if (decimalPlaces < minimumDecimalPlaces)
                value = number.toFixed(minimumDecimalPlaces)
        }
        return value + valueSuffix
    }
    objectName: "vlc-option-" + option
    opacity: root.enabled ? 1 : 0.45
    visible: current !== undefined && (!advanced || Theme.store.advancedOptions)

    function save(v) {
        player.setConfig(option, v)
        current = v
        optionSaved(v)
        if (option === "freetype-shadow-opacity" && Number(v) > 0)
            Theme.store.subtitleShadowOpacity = Number(v)
    }
    function setOpacityEnabled(enabled) {
        const remembered = Number(Theme.store.subtitleShadowOpacity) || sliderMax
        save(enabled ? Math.min(sliderMax, Math.max(1, remembered)) : 0)
    }
    function parseNumber(value) {
        const text = String(value).trim()
        if (!text.length)
            return undefined

        if (!allowDecimal) {
            if (!/^[+-]?\d+$/.test(text))
                return undefined
            const integer = Number(text)
            if (!Number.isSafeInteger(integer))
                return undefined
            const bounds = player.configRange(option)
            if ((bounds.minimum !== undefined && integer < Number(bounds.minimum))
                    || (bounds.maximum !== undefined && integer > Number(bounds.maximum)))
                return undefined
            return integer
        }

        if (!/^[+-]?(?:\d+(?:[.,]\d+)?|[.,]\d+)$/.test(text))
            return undefined
        const decimal = Number(text.replace(",", "."))
        if (!Number.isFinite(decimal))
            return undefined
        const bounds = player.configRange(option)
        if ((bounds.minimum !== undefined && decimal < Number(bounds.minimum))
                || (bounds.maximum !== undefined && decimal > Number(bounds.maximum)))
            return undefined
        return decimal
    }
    function colorHex(value) {
        return (Number(value) >>> 0).toString(16).padStart(6, "0").slice(-6).toUpperCase()
    }
    function parseColor(value) {
        const hex = value.trim().replace(/^#/, "")
        return /^[0-9a-fA-F]{6}$/.test(hex) ? parseInt(hex, 16) : undefined
    }
    Component.onCompleted: {
        if (option === "freetype-shadow-opacity" && Number(current) > 0)
            Theme.store.subtitleShadowOpacity = Number(current)
    }

    Connections {
        target: player
        function onConfigChanged(name) {
            if (name === root.option)
                root.current = player.config(root.option)
        }
    }

    Loader {
        sourceComponent: root.kind === "bool" ? boolComp
                         : root.kind === "choice" ? choiceComp
                         : root.kind === "color" ? colorComp
                         : root.kind === "slider" ? (root.showScale ? scaleSliderComp : sliderComp)
                         : root.kind === "opacityToggle" ? opacityToggleComp
                         : root.kind === "opacity" ? opacityComp
                         : textComp
    }
    Component {
        id: boolComp
        NSwitch {
            objectName: "vlc-option-switch-" + root.option
            checked: !!root.current
            onToggled: (on) => root.save(on)
        }
    }
    Component {
        id: choiceComp
        NCombo {
            width: root.fieldWidth
            model: root.choices
            current: root.choiceDisplayValue
            onPicked: (v) => root.save(v)
        }
    }
    Component {
        id: textComp
        NField {
            width: root.fieldWidth
            text: root.displayValue
            placeholderText: root.placeholderText
            echoMode: root.secret ? TextInput.Password : TextInput.Normal
            inputMethodHints: root.kind === "number"
                              ? (root.allowDecimal ? Qt.ImhFormattedNumbersOnly : Qt.ImhDigitsOnly)
                              : Qt.ImhNone
            onEditingFinished: {
                if (root.kind !== "number") {
                    root.save(text)
                    return
                }
                const editableText = root.valueSuffix.length && text.endsWith(root.valueSuffix)
                                     ? text.slice(0, -root.valueSuffix.length).trim() : text
                const parsed = root.parseNumber(editableText)
                if (parsed !== undefined) root.save(parsed)
                else text = root.displayValue
            }
        }
    }
    Component {
        id: colorComp
        RowLayout {
            spacing: 8
            NField {
                id: colorField
                width: root.fieldWidth
                text: "#" + root.colorHex(root.current)
                onEditingFinished: {
                    const parsed = root.parseColor(text)
                    if (parsed !== undefined) root.save(parsed)
                    else text = "#" + root.colorHex(root.current)
                }
            }
            Rectangle {
                implicitWidth: 22
                implicitHeight: 22
                radius: 3
                color: "#" + root.colorHex(root.current)
                border.color: Theme.border
            }
        }
    }
    Component {
        id: sliderComp
        RowLayout {
            spacing: 8
            NSlider {
                Layout.preferredWidth: root.fieldWidth
                from: root.sliderMin
                to: root.sliderMax
                stepSize: root.sliderStep
                value: Number(root.current)
                onMoved: (v) => root.save(v)
            }
            NText {
                text: root.sliderMax > 100
                      ? Math.round(Number(root.current) / root.sliderMax * 100) + "%"
                      : Math.round(Number(root.current)) + "%"
                dim: true
                font.pixelSize: 11
            }
        }
    }
    Component {
        id: scaleSliderComp
        ColumnLayout {
            width: root.fieldWidth
            spacing: 3
            NSlider {
                Layout.fillWidth: true
                trackHeight: 8
                tickCount: 10
                from: root.sliderMin
                to: root.sliderMax
                stepSize: root.sliderStep
                value: Number(root.current)
                onMoved: (v) => root.save(v)
            }
            RowLayout {
                Layout.fillWidth: true
                NText { text: "0%"; dim: true; font.pixelSize: 10 }
                Item { Layout.fillWidth: true }
                NText { text: "50%"; dim: true; font.pixelSize: 10 }
                Item { Layout.fillWidth: true }
                NText { text: "100%"; dim: true; font.pixelSize: 10 }
            }
        }
    }
    Component {
        id: opacityToggleComp
        NSwitch {
            objectName: root.option === "freetype-shadow-opacity" ? "subtitle-shadow-toggle" : ""
            checked: Number(root.current) > 0
            onToggled: (on) => root.setOpacityEnabled(on)
        }
    }
    Component {
        id: opacityComp
        RowLayout {
            spacing: 8
            NSwitch {
                checked: Number(root.current) > 0
                onToggled: (on) => root.save(on ? root.sliderMax : 0)
            }
            NSlider {
                Layout.preferredWidth: root.fieldWidth
                from: root.sliderMin
                to: root.sliderMax
                stepSize: root.sliderStep
                value: Number(root.current)
                enabled: Number(root.current) > 0
                onMoved: (v) => root.save(v)
            }
        }
    }
}
