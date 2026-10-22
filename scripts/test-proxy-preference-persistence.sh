#!/usr/bin/env bash
# Focused real-VLC check that the inherited proxy settings survive relaunch.
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${NEO_BUILD_DIR:-$HERE/build-fidelity2}"
SANDBOX="${NEO_PROXY_PREFERENCE_TEST_SANDBOX:-${TMPDIR:-/tmp}/neo-proxy-preference-persistence-${UID}}"
PROXY_URL="http://127.0.0.1:18987"
PROXY_PASSWORD="neo-proxy-persistence-test"
mkdir -p "$SANDBOX"

first=$(NEO_BUILD_DIR="$BUILD_DIR" NEO_SANDBOX="$SANDBOX" NEO_TIMEOUT=15 \
    "$HERE/scripts/run-offscreen.sh" \
    "300:settingsDialog.open(); settingsDialog.page='network'|+200:settingsDialog.setOptionValue('http-proxy','$PROXY_URL'); settingsDialog.setOptionValue('http-proxy-pwd','$PROXY_PASSWORD'); 'proxyControlsSaved=' + (player.config('http-proxy')==='$PROXY_URL' && player.config('http-proxy-pwd')==='$PROXY_PASSWORD')|+100:settingsDialog.close()|+100:quit" 2>&1)
printf '%s\n' "$first"
if ! grep -Fq 'proxyControlsSaved=true' <<<"$first"; then
    echo 'FAIL proxy settings did not update through their visible controls.' >&2
    exit 1
fi

second=$(NEO_BUILD_DIR="$BUILD_DIR" NEO_SANDBOX="$SANDBOX" NEO_TIMEOUT=15 \
    "$HERE/scripts/run-offscreen.sh" \
    "300:settingsDialog.open(); settingsDialog.page='network'|+200:'proxyControlsRestored=' + (settingsDialog.preferenceControl('vlc-option-http-proxy').current==='$PROXY_URL' && settingsDialog.preferenceControl('vlc-option-http-proxy-pwd').current==='$PROXY_PASSWORD' && player.config('http-proxy')==='$PROXY_URL' && player.config('http-proxy-pwd')==='$PROXY_PASSWORD')|+100:settingsDialog.close()|+100:quit" 2>&1)
printf '%s\n' "$second"
if ! grep -Fq 'proxyControlsRestored=true' <<<"$second"; then
    echo 'FAIL proxy settings did not persist across VLC relaunch.' >&2
    exit 1
fi
echo 'PASS inherited HTTP proxy preferences persist across VLC relaunch'
