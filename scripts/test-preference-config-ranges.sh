#!/usr/bin/env bash
# Confirms QML numeric bounds follow VLC's declared config metadata.
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${NEO_BUILD_DIR:-$HERE/build-fidelity2}"
SANDBOX="${NEO_PREFERENCE_RANGE_TEST_SANDBOX:-${TMPDIR:-/tmp}/neo-preference-config-ranges-${UID}}"
mkdir -p "$SANDBOX"

output=$(NEO_BUILD_DIR="$BUILD_DIR" NEO_SANDBOX="$SANDBOX" NEO_TIMEOUT=15 \
    "$HERE/scripts/run-offscreen.sh" \
    "500:settingsDialog.open(); settingsDialog.page='subtitles'|+200:(() => { const option='freetype-opacity'; const control=settingsDialog.preferenceControl('vlc-option-'+option); const bounds=player.configRange(option); const hasBounds=bounds.minimum !== undefined && bounds.maximum !== undefined; const sliderMatches=hasBounds && Number(control.sliderMin)===Number(bounds.minimum) && Number(control.sliderMax)===Number(bounds.maximum); const acceptsEndpoints=hasBounds && control.parseNumber(String(bounds.minimum))===Number(bounds.minimum) && control.parseNumber(String(bounds.maximum))===Number(bounds.maximum); const rejectsOutside=hasBounds && control.parseNumber(String(Number(bounds.minimum)-1))===undefined && control.parseNumber(String(Number(bounds.maximum)+1))===undefined; return 'rangeAudit=' + JSON.stringify({type:player.configType(option),bounds:bounds,sliderMin:control.sliderMin,sliderMax:control.sliderMax,sliderMatches:sliderMatches,acceptsEndpoints:acceptsEndpoints,rejectsOutside:rejectsOutside}) })()|+100:quit" 2>&1)

printf '%s\n' "$output"
if ! grep -Fq '"sliderMatches":true' <<<"$output"; then
    echo "FAIL VLC bounds and QML slider bounds disagree or VLC did not declare a range." >&2
    exit 1
fi
if ! grep -Fq '"acceptsEndpoints":true' <<<"$output"; then
    echo "FAIL numeric parser rejected a VLC-declared endpoint." >&2
    exit 1
fi
if ! grep -Fq '"rejectsOutside":true' <<<"$output"; then
    echo "FAIL numeric parser accepted a value outside VLC's declared range." >&2
    exit 1
fi
echo "PASS VLC metadata, QML slider bounds, and out-of-range rejection agree"
