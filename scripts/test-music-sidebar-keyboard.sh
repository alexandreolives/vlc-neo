#!/usr/bin/env bash
# Verify keyboard access and focus order for the Figma Music side pane.
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${NEO_BUILD_DIR:-$HERE/build-fidelity2}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/neo-music-sidebar-keyboard.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/My Songs"
cp "$HERE/test-artifacts/neo-smoke-recheck/music/Neon Track 01.m4a" "$WORK/My Songs/"
cp "$HERE/test-artifacts/neo-smoke-recheck/music/Neon Track 02.m4a" "$WORK/My Songs/"

steps="500:onboarding.close(); Theme.store.onboarded=true; Theme.store.mode='dark'; win.width=1920; win.height=1080; mediaLibrary.addFolder(platform.fileUrl('$WORK/My Songs')); win.navigate('music'); win.libraryFullPage=false; win.libraryOpen=true|+1800:focus-item:music-sidepanel-category-songs|+100:key:Tab|+100:'tabForward=' + win.activeFocusItem.objectName|+100:key:Return|+100:'openedCategory=' + libraryPanel.musicSidePage|+100:libraryPanel.openMusicSidePage('songs')|+200:focus-item:music-sidepanel-root-My Songs|+100:key:Return|+150:'openedRoot=' + (libraryPanel.musicSideFolderRoot.endsWith('/My Songs')) + '/' + libraryPanel.musicSideItemCount()|+100:focus-item:music-sidepanel-track-0|+100:key:Return|+500:'playingTrack=' + player.mediaUrl.toString().includes('Neon Track')|+100:libraryPanel.openMusicSidePage('albums')|+1200:'albumGroups=' + mediaLibrary.model.itemCount()|+100:focus-item:music-library-group-0|+100:key:Return|+100:'albumKeyboard=' + mediaLibrary.model.grouped|+100:libraryPanel.goBackFromSidePanel()|+200:libraryPanel.openMusicSidePage('artists')|+900:focus-item:music-library-group-0|+100:key:Return|+100:'artistKeyboard=' + mediaLibrary.model.grouped|+100:libraryPanel.goBackFromSidePanel()|+200:libraryPanel.openMusicSidePage('genres')|+900:focus-item:music-library-group-0|+100:key:Return|+100:'genreKeyboard=' + mediaLibrary.model.grouped|+100:libraryPanel.openMusicSidePage('songs')|+200:focus-item:music-sidepanel-add|+100:key:Space|+100:'addDialog=' + indexFolderDialog.visible|+100:quit"
output="$(NEO_BUILD_DIR="$BUILD_DIR" NEO_SANDBOX="$WORK/sandbox" NEO_TIMEOUT=35 \
    "$HERE/scripts/run-offscreen.sh" "$steps" 2>&1)" || {
    printf '%s\n' "$output" >&2
    exit 1
}
printf '%s\n' "$output" | grep 'neo test:' || true

for expected in \
    'tabForward=music-sidepanel-category-albums' \
    'openedCategory=albums' \
    'openedRoot=true/2' \
    'playingTrack=true' \
    'albumGroups=1' \
    'albumKeyboard=true' \
    'artistKeyboard=true' \
    'genreKeyboard=true' \
    'addDialog=true'; do
    if ! grep -Fq "$expected" <<<"$output"; then
        echo "FAIL: expected keyboard sidebar state: $expected" >&2
        exit 1
    fi
done

echo "PASS: Music categories, song roots and Add are reachable and activatable by keyboard"
