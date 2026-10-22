#!/usr/bin/env bash
# Focused real-VLC check for the Figma folder sidebar with a 15-item season.
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${NEO_BUILD_DIR:-$HERE/build-fidelity2}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/neo-sidebar-density.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
MEDIA="$WORK/media"
mkdir -p "$MEDIA"

colors=(FF0000 FF7F00 FFFF00 00FF00 00FFFF 0000FF FF00FF 8000FF FFFFFF 808080 FF1493 A52A2A 7FFF00 008080 FFD700)
for index in "${!colors[@]}"; do
    number=$((index + 1))
    ffmpeg -hide_banner -loglevel error -f lavfi \
        -i "color=c=0x${colors[$index]}:s=320x180:r=12" -t 2 -an \
        -c:v libx264 -preset ultrafast -pix_fmt yuv420p -movflags +faststart \
        -y "$MEDIA/episode-${number}.mp4"
done

states="'thumbnailStates=' + (() => { const states=[]; for(let i=1;i<=15;i++) states.push(libraryPanel.videoThumbnailState('episode-'+i+'.mp4')); return states.join('/') })() + ' ready=' + (() => { const states=[]; for(let i=1;i<=15;i++) states.push(libraryPanel.videoThumbnailState('episode-'+i+'.mp4')); return states.filter(state=>state==='ready').length })()"
steps="1000:onboarding.close(); Theme.store.onboarded=true; Theme.store.mode='light'; win.width=1920; win.height=1080; player.openLocation('$MEDIA/episode-1.mp4',true)|+1200:click-item:folder-chip|+300:'sidebarLayout=' + libraryPanel.fileCount() + '/' + Math.round(libraryPanel.width) + '/' + win.folderSidebarOpen|+22000:$states|+100:quit"
output=$(NEO_BUILD_DIR="$BUILD_DIR" NEO_SANDBOX="$WORK/sandbox" NEO_TIMEOUT=35 QT_QPA_PLATFORM=offscreen \
    "$HERE/scripts/run-offscreen.sh" "$steps" 2>&1) || {
    printf '%s\n' "$output" >&2
    exit 1
}
printf '%s\n' "$output"
grep -Fq "sidebarLayout=15/384/true" <<<"$output" || {
    echo "FAIL: expected 15 folder entries and a 384 px sidebar at 1920 px" >&2
    exit 1
}
grep -Fq " ready=15" <<<"$output" || {
    echo "FAIL: expected all 15 visible video thumbnails to decode" >&2
    exit 1
}
echo "PASS: 15 entries and 15 decoded thumbnails in the light sidebar"
