#!/usr/bin/env bash
# Headless smoke run of the Neo interface with an isolated config.
#   scripts/run-offscreen.sh "<NEO_TEST_STEPS>" [media...]
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
SANDBOX="${NEO_SANDBOX:-${TMPDIR:-/tmp}/neo-sandbox}"
mkdir -p "$SANDBOX/config" "$SANDBOX/data" "$SANDBOX/cache"
steps="$1"; shift
export XDG_CONFIG_HOME="$SANDBOX/config" XDG_DATA_HOME="$SANDBOX/data" XDG_CACHE_HOME="$SANDBOX/cache"
export QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen NEO_TEST_STEPS="$steps"
export VLC_PLUGIN_PATH="$HERE/build"
exec timeout "${NEO_TIMEOUT:-40}" "${SYSTEM_VLC:-/usr/bin/vlc}" --no-plugins-cache -I neo --no-qt-privacy-ask --aout=dummy "$@"
