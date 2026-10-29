#!/usr/bin/env bash
# Verify embedded VLC filters and video rendered from an HTTP stream.
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${NEO_BUILD_DIR:-$HERE/build}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/neo-vlc-filter-render.XXXXXX")"
HTTP_SERVER_PID=""
cleanup() {
    if [[ -n "$HTTP_SERVER_PID" ]]; then
        kill "$HTTP_SERVER_PID" 2>/dev/null || true
        wait "$HTTP_SERVER_PID" 2>/dev/null || true
    fi
    python3 -c "import shutil,sys; shutil.rmtree(sys.argv[1], ignore_errors=True)" "$WORK"
}
trap cleanup EXIT

for tool in ffmpeg convert; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "FAIL required tool not found: $tool" >&2
        exit 2
    fi
done

ffmpeg -loglevel error -y -f lavfi -i "color=c=red:s=320x180:r=25:d=4" \
    -an -c:v libx264 -preset ultrafast -g 25 -pix_fmt yuv420p "$WORK/red.mkv"
convert -size 320x180 xc:'#e02010' -fill '#00e0f0' \
    -draw 'rectangle 30,25 120,115' -fill '#f0e020' \
    -draw 'rectangle 180,50 290,150' -fill '#1020e0' \
    -draw 'rectangle 135,0 165,179' "$WORK/effect-pattern.png"
ffmpeg -hide_banner -loglevel error -y -loop 1 -framerate 25 -i "$WORK/effect-pattern.png" \
    -t 12 -an -c:v libx264 -preset ultrafast -pix_fmt yuv420p "$WORK/effects.mkv"
mkdir -p "$WORK/sandbox/config/vlc-neo"
printf '[appearance]\nonboarded=true\n' > "$WORK/sandbox/config/vlc-neo/neo.conf"

output="$(NEO_BUILD_DIR="$BUILD_DIR" NEO_SANDBOX="$WORK/sandbox" NEO_TIMEOUT=15 \
    "$HERE/scripts/run-offscreen.sh" \
    "700:player.openLocation('$WORK/red.mkv',true)|+1000:'filterProbePlayback=' + player.hasVideo + '/' + (player.state===2)|+100:grab:$WORK/before.png|+100:'filterApply=' + player.setVideoFilterChain('adjust') + '/' + player.setVideoAdjustment('saturation',0)|+700:grab:$WORK/after.png|+100:quit" 2>&1)"
printf '%s\n' "$output" | grep 'neo test:' || true
if ! grep -qF 'filterProbePlayback=true/true' <<<"$output" \
    || ! grep -qF 'filterApply=true/true' <<<"$output"; then
    echo "FAIL VLC did not start playback or accept the adjustment" >&2
    exit 1
fi

sample_rgb() {
    convert "$1" -crop 1x1+560+320 txt:- | awk -F '[(),]' 'END { print $3, $4, $5 }'
}
read -r before_r before_g before_b <<<"$(sample_rgb "$WORK/before.png")"
read -r after_r after_g after_b <<<"$(sample_rgb "$WORK/after.png")"
if (( before_r > 180 && before_g < 80 && before_b < 80 \
      && after_r >= 40 && after_r <= 140 \
      && after_g >= 40 && after_g <= 140 \
      && after_b >= 40 && after_b <= 140 \
      && after_r - after_g <= 8 && after_g - after_r <= 8 \
      && after_g - after_b <= 8 && after_b - after_g <= 8 )); then
    echo "PASS VLC adjustment changed red decoded output to grayscale (${before_r},${before_g},${before_b} -> ${after_r},${after_g},${after_b})"
else
    echo "FAIL VLC adjustment did not produce the expected pixel change (${before_r},${before_g},${before_b} -> ${after_r},${after_g},${after_b})" >&2
    exit 1
fi

# Exercise the Network Stream path through HTTP and verify decoded pixels in
# VLC's embedded output, not only the media URL and playing state.
python3 - "$WORK" >"$WORK/http-server.log" 2>&1 <<'PY' &
import http.server
import pathlib
import sys

directory = pathlib.Path(sys.argv[1])
class Handler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, fmt, *args):
        with (directory / "http-requests.log").open("a") as stream:
            stream.write((fmt % args) + "\n")

server = http.server.ThreadingHTTPServer(("127.0.0.1", 0),
    lambda *args, **kwargs: Handler(*args, directory=str(directory), **kwargs))
(directory / "http-port").write_text(str(server.server_address[1]))
server.serve_forever()
PY
HTTP_SERVER_PID=$!
for _ in {1..40}; do
    [[ -s "$WORK/http-port" ]] && break
    sleep 0.1
done
if [[ ! -s "$WORK/http-port" ]]; then
    echo "FAIL local HTTP media server did not start" >&2
    exit 1
fi
HTTP_URL="http://127.0.0.1:$(cat "$WORK/http-port")/red.mkv"
mkdir -p "$WORK/http-sandbox/config/vlc-neo"
printf '[appearance]\nonboarded=true\n' > "$WORK/http-sandbox/config/vlc-neo/neo.conf"
http_output="$(NEO_BUILD_DIR="$BUILD_DIR" NEO_SANDBOX="$WORK/http-sandbox" NEO_TIMEOUT=15 \
    "$HERE/scripts/run-offscreen.sh" \
    "700:networkDialog.open()|+150:networkDialog.sourceText='$HTTP_URL'|+150:networkDialog.go(true)|+1800:'httpPlayback=' + (player.hasVideo && player.state===2 && player.mediaUrl.toString()==='$HTTP_URL')|+100:grab:$WORK/http-playback.png|+100:sidePanel.tab='video';win.rightPanel='settings'|+1500:'httpEffectPreview=' + sidePanel.videoEffectPreviewLoaded('sepia')|+100:quit" 2>&1)"
printf '%s\n' "$http_output" | grep 'neo test:' || true
if ! grep -qF 'httpPlayback=true' <<<"$http_output" \
    || ! grep -qF 'httpEffectPreview=true' <<<"$http_output"; then
    printf '%s\n' "$http_output" >&2
    echo "FAIL VLC did not play the HTTP video or decode its effect preview from the Network Stream dialog" >&2
    exit 1
fi
read -r http_r http_g http_b <<<"$(sample_rgb "$WORK/http-playback.png")"
if (( http_r > 180 && http_g < 80 && http_b < 80 )); then
    echo "PASS Network Stream HTTP video renders in embedded VLC (${http_r},${http_g},${http_b})"
else
    echo "FAIL Network Stream HTTP video was not rendered in embedded VLC (${http_r},${http_g},${http_b})" >&2
    exit 1
fi
if ! grep -q 'GET /red.mkv' "$WORK/http-requests.log"; then
    echo "FAIL VLC did not request the media from the HTTP server" >&2
    exit 1
fi
echo "PASS VLC requested the Network Stream media over HTTP"

# The effect tiles must drive VLC's actual embedded video output. A filter-chain
# setter returning success alone does not prove that the named module rendered.
mkdir -p "$WORK/effects-sandbox/config/vlc-neo"
printf '[appearance]\nonboarded=true\n' > "$WORK/effects-sandbox/config/vlc-neo/neo.conf"
effects=(sepia invert posterize oldmovie gaussianblur sharpen vhs grain)
actions="700:player.openLocation('$WORK/effects.mkv',true)|+1200:grab:$WORK/effect-original.png"
for effect in "${effects[@]}"; do
    # Give VLC time to apply each filter and render a fresh frame on slow CI.
    actions+="|+100:player.setVideoFilterChain('$effect')|+500:grab:$WORK/effect-$effect.png"
done
actions+="|+100:quit"
effect_output="$(NEO_BUILD_DIR="$BUILD_DIR" NEO_SANDBOX="$WORK/effects-sandbox" NEO_TIMEOUT=30 \
    "$HERE/scripts/run-offscreen.sh" "$actions" 2>&1)"
printf '%s\n' "$effect_output" | grep 'neo test:' || true
if ! grep -qF 'player.openLocation(' <<<"$effect_output"; then
    echo "FAIL VLC effect preview fixture did not start" >&2
    exit 1
fi
convert "$WORK/effect-original.png" -crop 450x400+300+100 +repage "$WORK/effect-original-crop.png"
for effect in "${effects[@]}"; do
    if ! grep -qF "player.setVideoFilterChain('$effect') => true" <<<"$effect_output"; then
        echo "FAIL VLC rejected the $effect video filter chain" >&2
        exit 1
    fi
    convert "$WORK/effect-$effect.png" -crop 450x400+300+100 +repage "$WORK/effect-$effect-crop.png"
    changed_pixels="$(compare -metric AE "$WORK/effect-original-crop.png" "$WORK/effect-$effect-crop.png" null: 2>&1 || true)"
    if awk -v diff="$changed_pixels" 'BEGIN { split(diff, parts, /[ (]/); exit !(parts[1] + 0 > 0) }'; then
        echo "PASS VLC $effect filter changes embedded video output ($changed_pixels pixels)"
    else
        echo "FAIL VLC $effect filter did not change embedded video output (${changed_pixels:-no pixel diff})" >&2
        exit 1
    fi
done
