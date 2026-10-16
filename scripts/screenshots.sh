#!/usr/bin/env bash
# Regenerates docs/screenshots/*.png from a headless run (offscreen Qt, scale 1.5).
# Media: Sintel trailer (c) Blender Foundation, CC BY 3.0 — https://durian.blender.org
#   scripts/screenshots.sh <folder containing Sintel/ (S01E0x trailers, .srt files, Gatekeepers.mp3)>
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
MEDIA="$(cd "$1" && pwd)"
OUT="$HERE/docs/screenshots"
mkdir -p "$OUT"
export NEO_SANDBOX="${TMPDIR:-/tmp}/neo-shots"
rm -rf "$NEO_SANDBOX"; mkdir -p "$NEO_SANDBOX/config/vlc-neo"
printf '[appearance]\nonboarded=true\nresumeMode=never\n' > "$NEO_SANDBOX/config/vlc-neo/neo.conf"
export QT_SCALE_FACTOR=1.5 NEO_TIMEOUT=90
E1="$MEDIA/Sintel/Sintel.S01E01.Trailer.mp4"
E2="$MEDIA/Sintel/Sintel.S01E02.Trailer.mp4"
E3="$MEDIA/Sintel/Sintel.S01E03.Trailer.mp4"
SONG="$MEDIA/Sintel/Gatekeepers.mp3"
run() { "$HERE/scripts/run-offscreen.sh" "$@" --no-osd --no-video-title-show 2>&1 | grep -E "neo test: grab|failed" || true; }

# Player, panels, popups, dialogs (paused on a nice frame, English subtitles).
FRAME=${FRAME:-23500}
EN="player.selectTrack('spu', player.tracks('spu').find(t => t.name.indexOf('English') >= 0).id)"
shot() { printf '|+900:grab:%s/%s.png' "$OUT" "$1"; }
do_() { printf '|+250:%s' "$1"; }
# A track switch only shows cues from the next seek on, so seek again after it.
steps="1500:$EN|+600:player.jumpTo($FRAME)|+1300:player.togglePause()$(shot player)"
steps+="$(do_ "sidePanel.tab = 'spu'; win.rightPanel = 'settings'")$(shot sidebar-subtitles)"
steps+="$(do_ "sidePanel.tab = 'audio'")$(shot sidebar-audio)"
steps+="$(do_ "sidePanel.tab = 'video'")$(shot sidebar-video)"
steps+="$(do_ "sidePanel.tab = 'playback'")$(shot sidebar-playback)"
steps+="$(do_ "win.rightPanel = ''; tracksPopup.openFor('spu', controlBar); tracksPopup.x = win.width - tracksPopup.width - 70")$(shot tracks-popup)"
steps+="$(do_ "tracksPopup.close(); win.rightPanel = 'queue'; win.libraryOpen = true")$(shot library-queue)"
steps+="$(do_ "win.rightPanel = ''; win.libraryOpen = false; contextMenu.popup(560, 140)")$(shot context-menu)"
steps+="$(do_ "contextMenu.close(); mainMenu.popup(40, 34)")$(shot main-menu)"
steps+="$(do_ "mainMenu.close(); settingsDialog.page = 'subtitles'; settingsDialog.open()")$(shot settings)"
steps+="$(do_ "settingsDialog.page = 'performance'")$(shot settings-performance)"
steps+="$(do_ "settingsDialog.close(); customizeDialog.open()")$(shot customize)"
steps+="$(do_ "customizeDialog.close(); subtitleDialog.target = 'folder'; subtitleDialog.open()")$(shot add-subtitles)"
steps+="$(do_ "subtitleDialog.close(); shortcutsDialog.open()")$(shot shortcuts)"
steps+="$(do_ "shortcutsDialog.close(); win.uiHidden = true; win.toast('Ctrl H', 'UI hidden - move to the edges to show controls')")|+150:win.topHot = false; win.bottomHot = false$(shot hidden-ui)"
steps+="$(do_ "win.uiHidden = false; toastItem.opacity = 0; Theme.store.mode = 'light'; Theme.store.accent = '#2F5FC4'; sidePanel.tab = 'spu'; win.rightPanel = 'settings'")$(shot light-theme)"
steps+="$(do_ "Theme.store.mode = 'dark'; Theme.store.accent = '#D9822B'; win.rightPanel = ''; player.openLocation('$SONG', true)")|+1500:grab:$OUT/music.png"
steps+="|+300:quit"
run "$steps" "$E1" "$E2" "$E3"

# Home screen (recents filled by the run above).
run "1500:grab:$OUT/home.png|1600:quit"

# First-run onboarding.
printf '[appearance]\nonboarded=false\n' > "$NEO_SANDBOX/config/vlc-neo/neo.conf"
run "1500:grab:$OUT/onboarding-welcome.png|+300:onboarding.step = 1|+800:grab:$OUT/onboarding-theme.png|+300:onboarding.step = 2|+800:grab:$OUT/onboarding-shortcuts.png|+300:quit"
ls -1 "$OUT"

# Ship as WebP (about 7x smaller than PNG, rendered natively by GitHub).
for f in "$OUT"/*.png; do
    magick "$f" -strip -define webp:method=6 -quality 88 "${f%.png}.webp" && rm "$f"
done
