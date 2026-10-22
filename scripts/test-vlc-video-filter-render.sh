#!/usr/bin/env bash
# Verify a VLC video adjustment changes decoded pixels in the embedded output.
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${NEO_BUILD_DIR:-$HERE/build}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/neo-vlc-filter-render.XXXXXX")"
trap 'python3 -c "import shutil,sys; shutil.rmtree(sys.argv[1], ignore_errors=True)" "$WORK"' EXIT

for tool in ffmpeg convert; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "FAIL required tool not found: $tool" >&2
        exit 2
    fi
done

ffmpeg -loglevel error -y -f lavfi -i "color=c=red:s=320x180:r=25:d=4" \
    -an -c:v libx264 -preset ultrafast -g 25 -pix_fmt yuv420p "$WORK/red.mkv"
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
