#!/usr/bin/env bash
# Headless smoke run of the Neo interface with an isolated config.
#   scripts/run-offscreen.sh "<NEO_TEST_STEPS>" [media...]
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
SANDBOX="${NEO_SANDBOX:-${TMPDIR:-/tmp}/neo-sandbox}"
mkdir -p "$SANDBOX/config" "$SANDBOX/data" "$SANDBOX/cache"
steps="$1"; shift
export XDG_CONFIG_HOME="$SANDBOX/config" XDG_DATA_HOME="$SANDBOX/data" XDG_CACHE_HOME="$SANDBOX/cache"
export QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-offscreen}" NEO_TEST_STEPS="$steps"
NEO_QT_ROOT="${NEO_QT_ROOT:-${QT_ROOT:-}}"
if [ -n "$NEO_QT_ROOT" ]; then
    export LD_LIBRARY_PATH="$NEO_QT_ROOT/lib:$NEO_QT_ROOT/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    export QML_IMPORT_PATH="$NEO_QT_ROOT/qml${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}"
fi
NEO_BUILD_DIR="${NEO_BUILD_DIR:-$HERE/build}"
NEO_PLUGIN="$NEO_BUILD_DIR/libneo_plugin.so"
if [[ ! -f "$NEO_PLUGIN" ]]; then
    echo "VLC Neo plugin not found at $NEO_PLUGIN; build the project or set NEO_BUILD_DIR." >&2
    exit 2
fi
if [[ "$HERE/CMakeLists.txt" -nt "$NEO_PLUGIN" ]] || find "$HERE/qml" "$HERE/src" "$HERE/assets" -type f -newer "$NEO_PLUGIN" -print -quit 2>/dev/null | grep -q .; then
    echo "VLC Neo plugin at $NEO_PLUGIN is older than the source files; rebuild it or set NEO_BUILD_DIR to a current build." >&2
    exit 2
fi
export VLC_PLUGIN_PATH="$NEO_BUILD_DIR"
NEO_TEST_AOUT="${NEO_TEST_AOUT:-dummy}"
exec timeout "${NEO_TIMEOUT:-40}" "${SYSTEM_VLC:-/usr/bin/vlc}" --no-plugins-cache -I neo --no-qt-privacy-ask "--aout=$NEO_TEST_AOUT" "$@"
