#!/usr/bin/env bash
# Focused real-VLC check for advanced preference visibility and persistence.
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${NEO_BUILD_DIR:-$HERE/build-fidelity2}"
SANDBOX="${NEO_PREFERENCE_TEST_SANDBOX:-${TMPDIR:-/tmp}/neo-preferences-advanced-persistence-${UID}}"
mkdir -p "$SANDBOX"

run_case() {
    local label="$1" steps="$2" output
    if ! output=$(NEO_BUILD_DIR="$BUILD_DIR" NEO_SANDBOX="$SANDBOX" NEO_TIMEOUT=15 \
        "$HERE/scripts/run-offscreen.sh" "$steps" 2>&1); then
        printf '%s\n' "$output" >&2
        printf 'FAIL %s: focused VLC process failed\n' "$label" >&2
        return 1
    fi
    printf '%s\n' "$output"
}

assert_result() {
    local label="$1" output="$2" expected="$3"
    if ! grep -Fq -- "$expected" <<<"$output"; then
        printf 'FAIL %s: expected %s\n' "$label" "$expected" >&2
        return 1
    fi
    printf 'PASS %s\n' "$label"
}

first=$(run_case "write and collapse" \
    "500:settingsDialog.open(); settingsDialog.page='audio'; Theme.store.advancedOptions=true|+200:'advancedOptionVisible=' + settingsDialog.optionVisible('spatializer-roomsize')|+100:'advancedValueSaved=' + (settingsDialog.setOptionValue('spatializer-roomsize',0.42) && Math.abs(Number(player.config('spatializer-roomsize'))-0.42)<0.0001)|+100:Theme.store.advancedOptions=false|+100:'simpleModeHidesOption=' + (!settingsDialog.optionVisible('spatializer-roomsize'))|+100:'simpleModeKeepsValue=' + (Math.abs(Number(player.config('spatializer-roomsize'))-0.42)<0.0001)|+100:settingsDialog.close()|+100:quit")
assert_result "advanced option is visible when enabled" "$first" "advancedOptionVisible=true"
assert_result "advanced float preference saves through VLC" "$first" "advancedValueSaved=true"
assert_result "Simple mode hides the advanced control" "$first" "simpleModeHidesOption=true"
assert_result "hiding the control preserves its VLC value" "$first" "simpleModeKeepsValue=true"

second=$(run_case "relaunch and reveal" \
    "500:settingsDialog.open(); settingsDialog.page='audio'|+200:'simpleModeRestored=' + (!Theme.store.advancedOptions && !settingsDialog.optionVisible('spatializer-roomsize'))|+100:'hiddenAdvancedValueRestored=' + (Math.abs(Number(player.config('spatializer-roomsize'))-0.42)<0.0001)|+100:Theme.store.advancedOptions=true|+150:'advancedModeRevealsSavedValue=' + (settingsDialog.optionVisible('spatializer-roomsize') && Math.abs(Number(settingsDialog.preferenceControl('vlc-option-spatializer-roomsize').current)-0.42)<0.0001)|+100:settingsDialog.close()|+100:quit")
assert_result "Simple mode persists across relaunch" "$second" "simpleModeRestored=true"
assert_result "advanced VLC value persists while hidden" "$second" "hiddenAdvancedValueRestored=true"
assert_result "Advanced mode reveals the saved value" "$second" "advancedModeRevealsSavedValue=true"
