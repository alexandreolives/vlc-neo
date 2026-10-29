#!/usr/bin/env bash
# Focused real-VLC check for the Figma folder sidebar with a 15-item season.
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${NEO_BUILD_DIR:-$HERE/build}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/neo-sidebar-density.XXXXXX")"
trap 'python3 -c "import shutil,sys; shutil.rmtree(sys.argv[1], ignore_errors=True)" "$WORK"' EXIT
MEDIA="$WORK/media"
CAPTURE="${NEO_SIDEBAR_CAPTURE:-$WORK/sidebar.png}"
mkdir -p "$MEDIA"

FIGMA_HOME="$HERE/tests/fixtures/figma-home"
for episode in 05 06 07; do
    ffmpeg -hide_banner -loglevel error -y -loop 1 -framerate 12 \
        -i "$FIGMA_HOME/the-wand-s01e$episode.png" -t 40 \
        -vf "scale=320:180:force_original_aspect_ratio=increase,crop=320:180,format=yuv420p" \
        -an -c:v libx264 -preset ultrafast -tune stillimage \
        "$MEDIA/The_Wand_S01E$episode.mp4"
done

colors=(FF0000 FF7F00 FFFF00 00FF00 00FFFF 0000FF FF00FF 8000FF FFFFFF 808080 FF1493 A52A2A 7FFF00 008080 FFD700)
for number in $(seq 1 15); do
    printf -v episode '%02d' "$number"
    if [[ "$episode" == 05 || "$episode" == 06 || "$episode" == 07 ]]; then
        continue
    fi
    duration=2
    source="color=c=0x${colors[$((number - 1))]}:s=320x180:r=12"
    if [[ "$episode" == 08 ]]; then
        duration=40
        source="color=c=black:s=320x180:r=12"
    fi
    ffmpeg -hide_banner -loglevel error -f lavfi \
        -i "$source" -t "$duration" -an \
        -c:v libx264 -preset ultrafast -pix_fmt yuv420p -movflags +faststart \
        -y "$MEDIA/The_Wand_S01E$episode.mp4"
done

timestamp=1760000000
for episode in 05 06 07 08 09 10 11 12 13 14 15 04 03 02 01; do
    touch -d "@$timestamp" "$MEDIA/The_Wand_S01E$episode.mp4"
    ((timestamp -= 1))
done

states="'thumbnailStates=' + (() => { const states=[]; for(let i=1;i<=15;i++) states.push(libraryPanel.videoThumbnailState('The_Wand_S01E'+String(i).padStart(2,'0')+'.mp4')); return states.join('/') })() + ' ready=' + (() => { const states=[]; for(let i=1;i<=15;i++) states.push(libraryPanel.videoThumbnailState('The_Wand_S01E'+String(i).padStart(2,'0')+'.mp4')); return states.filter(state=>state==='ready').length })()"
steps="1000:onboarding.close(); Theme.store.onboarded=true; Theme.store.mode='light'; win.width=1920; win.height=1080; player.openLocation('$MEDIA/The_Wand_S01E05.mp4',true)|+1200:click-item:folder-chip|+1000:libraryPanel.sortBy='date'; 'sidebarLayout=' + libraryPanel.fileCount() + '/' + Math.round(libraryPanel.width) + '/' + win.folderSidebarOpen + ' rowGeometry=' + Math.round(libraryPanel.compactFolderToolbar.y) + '/' + Math.round(libraryPanel.folderListing.y)|+22000:$states|+100:grab:$CAPTURE|+100:quit"
output=$(NEO_BUILD_DIR="$BUILD_DIR" NEO_SANDBOX="$WORK/sandbox" NEO_TIMEOUT=35 QT_QPA_PLATFORM=offscreen \
    "$HERE/scripts/run-offscreen.sh" "$steps" 2>&1) || {
    printf '%s\n' "$output" >&2
    exit 1
}
printf '%s\n' "$output"
grep -Fq "sidebarLayout=15/377/true" <<<"$output" || {
    echo "FAIL: expected 15 folder entries and a 377 px sidebar at 1920 px" >&2
    exit 1
}
grep -Fq "rowGeometry=63/125" <<<"$output" || {
    echo "FAIL: expected Figma-aligned compact toolbar and folder rows at 1920 px" >&2
    exit 1
}
grep -Fq " ready=15" <<<"$output" || {
    echo "FAIL: expected all 15 visible video thumbnails to decode" >&2
    exit 1
}
echo "PASS: 15 entries and 15 decoded thumbnails in the light sidebar"
