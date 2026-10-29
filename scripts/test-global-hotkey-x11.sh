#!/usr/bin/env bash
# Verify VLC's global Play/Pause hotkey while another X11 window owns focus.
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${NEO_BUILD_DIR:-$HERE/build}"
for tool in ffmpeg xvfb-run xdotool xmessage; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "Missing required tool: $tool" >&2
        exit 2
    fi
done
if [[ ! -f "$BUILD_DIR/libneo_plugin.so" ]]; then
    echo "VLC Neo plugin not found at $BUILD_DIR/libneo_plugin.so" >&2
    exit 2
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/neo-global-hotkey.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/sandbox/config/vlc" "$WORK/sandbox/config/vlc-neo"
printf '[appearance]\nonboarded=true\n' > "$WORK/sandbox/config/vlc-neo/neo.conf"
printf 'global-key-play-pause=Ctrl+Alt+8\n' > "$WORK/sandbox/config/vlc/vlcrc"
ffmpeg -loglevel error -y -f lavfi -i "testsrc2=size=320x180:rate=12" \
    -t 12 -an -c:v libx264 -preset ultrafast -pix_fmt yuv420p "$WORK/global-hotkey.mkv"

steps="1500:'globalHotkeyBefore=' + player.playing + '/' + String(player.config('global-key-play-pause'))|+2500:'globalHotkeyAfter=' + player.playing|+100:quit"
log="$WORK/vlc.log"
set +e
NEO_BUILD_DIR="$BUILD_DIR" NEO_SANDBOX="$WORK/sandbox" QT_QPA_PLATFORM=xcb \
    xvfb-run -a bash -eu -c '
        HERE="$1"
        STEPS="$2"
        MEDIA="$3"
        LOG="$4"
        xmessage -center -buttons "OK:0" "Focus target for VLC global-hotkey test" >/dev/null 2>&1 &
        message_pid=$!
        cleanup() { kill "$message_pid" 2>/dev/null || true; }
        trap cleanup EXIT
        for _ in $(seq 1 40); do
            message_window="$(xdotool search --onlyvisible --name '^xmessage$' 2>/dev/null | head -n1 || true)"
            [[ -n "$message_window" ]] && break
            sleep 0.05
        done
        [[ -n "${message_window:-}" ]] || { echo "Could not find xmessage focus window" >&2; exit 1; }

        NEO_TIMEOUT=15 "$HERE/scripts/run-offscreen.sh" "$STEPS" "$MEDIA" > "$LOG" 2>&1 &
        vlc_pid=$!
        for _ in $(seq 1 80); do
            grep -q "globalHotkeyBefore=true/Ctrl+Alt+8" "$LOG" && break
            kill -0 "$vlc_pid" 2>/dev/null || break
            sleep 0.05
        done
        grep -q "globalHotkeyBefore=true/Ctrl+Alt+8" "$LOG" || {
            cat "$LOG" >&2
            echo "VLC did not start playback with the configured global key" >&2
            exit 1
        }

        xdotool windowfocus --sync "$message_window"
        [[ "$(xdotool getwindowfocus)" == "$message_window" ]] || {
            echo "xmessage did not retain keyboard focus before hotkey injection" >&2
            exit 1
        }
        xdotool key --clearmodifiers ctrl+alt+8
        wait "$vlc_pid"
    ' _ "$HERE" "$steps" "$WORK/global-hotkey.mkv" "$log"
status=$?
set -e

grep 'neo test' "$log" || true
if (( status != 0 )); then
    echo "FAIL VLC global hotkey process exited with status $status" >&2
    exit "$status"
fi
if ! grep -qF "globalHotkeyBefore=true/Ctrl+Alt+8" "$log"; then
    echo "FAIL VLC did not report the configured global Play/Pause key" >&2
    exit 1
fi
if ! grep -qF "globalHotkeyAfter=false" "$log"; then
    echo "FAIL the global Play/Pause key did not pause VLC from the other window" >&2
    exit 1
fi
echo "PASS global Play/Pause pauses VLC while xmessage owns focus"
