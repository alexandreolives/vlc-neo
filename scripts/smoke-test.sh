#!/usr/bin/env bash
# End-to-end checks of the Neo interface against the real VLC 3 core (headless).
# Generates its own media, runs VLC with -I neo offscreen, asserts on the results.
set -uo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
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
export NEO_BUILD_DIR
WORK="${NEO_SMOKE_DIR:-${TMPDIR:-/tmp}/neo-smoke}"
rm -rf "$WORK" && mkdir -p "$WORK/show" "$WORK/subs" "$WORK/music"
export NEO_SANDBOX="$WORK/sandbox"
pass=0; fail=0
declare -A seen_run_failures=()
check() { # name, haystack, needle
    if [[ "$2" =~ neo\ test:\ subprocess\ failed\ status=([0-9]+)\ run=([0-9]+) ]]; then
        local status="${BASH_REMATCH[1]}" run_id="${BASH_REMATCH[2]}"
        if [[ -z "${seen_run_failures[$run_id]+x}" ]]; then
            seen_run_failures[$run_id]=1
            echo "FAIL  $1  (VLC subprocess exited with status $status)"
            fail=$((fail + 1))
        fi
        return
    fi
    if grep -qF -- "$3" <<<"$2"; then echo "PASS  $1"; pass=$((pass + 1))
    else echo "FAIL  $1  (expected: $3; got: $2)"; fail=$((fail + 1)); fi
}
run() {
    local output status run_id timeout=40
    if [[ "${1:-}" == "--timeout" ]]; then
        timeout="$2"
        shift 2
    fi
    run_id="$BASHPID"
    output=$(NEO_TIMEOUT="$timeout" "$HERE/scripts/run-offscreen.sh" "$@" 2>&1)
    status=$?
    grep "neo test" <<<"$output" || true
    if (( status != 0 )); then
        printf 'neo test: subprocess failed status=%d run=%s\n' "$status" "$run_id"
        tail -n 4 <<<"$output"
    fi
    return 0
}
runExpectedExit() {
    local output status
    output=$(NEO_TIMEOUT=12 "$HERE/scripts/run-offscreen.sh" "$@" 2>&1)
    status=$?
    grep "neo test" <<<"$output" || true
    if (( status == 0 )); then
        echo "neo test: VLC exited naturally after playlist completion"
    else
        echo "neo test: VLC did not exit naturally (status=$status)"
        tail -n 4 <<<"$output"
    fi
    return 0
}

echo "== preparing media"
ffmpeg -loglevel error -y -f lavfi -i "testsrc2=size=640x360:rate=25" -f lavfi -i "sine=frequency=440" \
    -t 40 -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest "$WORK/base.mkv"
ffmpeg -loglevel error -y -f lavfi -i "color=c=red:s=320x180:r=25:d=4" \
    -f lavfi -i "color=c=blue:s=320x180:r=25:d=4" \
    -filter_complex "[0:v][1:v]concat=n=2:v=1:a=0,format=yuv420p[v]" \
    -map "[v]" -c:v libx264 -preset ultrafast -g 1 -t 8 "$WORK/seek-scenes.mkv"
ffmpeg -loglevel error -y -i "$WORK/base.mkv" -t 3 -c copy "$WORK/convert-video.mkv"
ffmpeg -loglevel error -y -i "$WORK/base.mkv" -t 20 -c:v libx264 -preset ultrafast \
    -g 12 -keyint_min 12 -sc_threshold 0 -c:a copy "$WORK/recording-test.mkv"
mkdir -p "$WORK/recursive-root/nested/deeper"
cp "$WORK/base.mkv" "$WORK/recursive-root/nested/deeper/Nested Video.mkv"
ffmpeg -loglevel error -y -f lavfi -i "aevalsrc=0.8*sin(2*PI*660*t)*(0.1+0.9*abs(sin(2*PI*0.12*t))):s=48000:d=40" \
    -af "afade=t=out:st=20:d=20" -c:a aac -vn \
    -metadata "title=Neon Track" -metadata "artist=Demo Artist" -metadata "album=Demo Album" -metadata "genre=Electronic" "$WORK/audio-only.m4a"
ffmpeg -loglevel error -y -f lavfi -i "sine=frequency=440:sample_rate=48000" \
    -t 3600 -af "afade=t=out:st=3000:d=600" \
    -c:a libmp3lame -b:a 24k -write_xing 0 "$WORK/long-waveform.mp3"
for i in 01 02; do
    cp "$WORK/base.mkv" "$WORK/show/My.Show.S01E$i.1080p.mkv"
    printf '1\n00:00:00,500 --> 00:00:30,000\nEpisode %s\n' "$i" > "$WORK/subs/myshow_1x${i}_ar.srt"
done
mkdir -p "$WORK/navigation-history/Season 1"
cp "$WORK/base.mkv" "$WORK/navigation-history/Season 1/History.Episode.mkv"
printf '1\n00:00:00,500 --> 00:00:04,000\nEnglish\n' > "$WORK/track-en.srt"
printf '1\n00:00:00,500 --> 00:00:04,000\nSpanish\n' > "$WORK/track-es.srt"
printf '1\n00:00:00,500 --> 00:00:05,500\nFrench subtitle\n' > "$WORK/track-fr.srt"
printf '1\n00:00:00,500 --> 00:00:19,000\nRecording subtitle\n' > "$WORK/recording-subtitle.srt"
ffmpeg -loglevel error -y -i "$WORK/recording-test.mkv" -i "$WORK/recording-subtitle.srt" \
    -map 0 -map 1 -c copy -c:s srt "$WORK/recording-subtitle.mkv"
mkdir -p "$WORK/embedded"
ffmpeg -loglevel error -y -i "$WORK/recording-test.mkv" -i "$WORK/recording-subtitle.srt" \
    -map 0 -map 1 -c copy -c:s srt "$WORK/embedded/embedded-only.mkv"
ffmpeg -loglevel error -y -f lavfi -i "testsrc2=size=320x180:rate=25" \
    -f lavfi -i "sine=frequency=440:sample_rate=48000" \
    -f lavfi -i "sine=frequency=880:sample_rate=48000" \
    -i "$WORK/track-en.srt" -i "$WORK/track-es.srt" -t 6 \
    -map 0:v -map 1:a -map 2:a -map 3:s -map 4:s \
    -metadata:s:a:0 language=eng -metadata:s:a:1 language=spa \
    -metadata:s:s:0 language=eng -metadata:s:s:1 language=spa \
    -c:v libx264 -pix_fmt yuv420p -c:a aac -c:s srt "$WORK/multi-track.mkv"
ffmpeg -threads 1 -loglevel error -y -f lavfi -i "testsrc2=size=320x180:rate=25" \
    -f lavfi -i "sine=frequency=330:sample_rate=48000" \
    -f lavfi -i "sine=frequency=550:sample_rate=48000" \
    -f lavfi -i "sine=frequency=770:sample_rate=48000" \
    -i "$WORK/track-en.srt" -i "$WORK/track-fr.srt" -t 6 \
    -map 0:v -map 1:a -map 2:a -map 3:a -map 4:s -map 5:s \
    -metadata:s:a:0 language=eng -metadata:s:a:0 title=English \
    -metadata:s:a:1 language=spa -metadata:s:a:1 title=Spanish \
    -metadata:s:a:2 language=fra -metadata:s:a:2 title=French \
    -metadata:s:s:0 language=eng -metadata:s:s:0 title=English \
    -metadata:s:s:1 language=fra -metadata:s:s:1 title=French \
    -c:v libx264 -pix_fmt yuv420p -c:a aac -c:s srt "$WORK/multi-track-alt.mkv"
cp "$WORK/audio-only.m4a" "$WORK/music/Neon Track 01.m4a"
cp "$WORK/audio-only.m4a" "$WORK/music/Neon Track 02.m4a"
mkdir -p "$WORK/music with spaces"
cp "$WORK/audio-only.m4a" "$WORK/music with spaces/Space Track.m4a"
touch "$WORK/music/.NeoHiddenTest.mkv"
ffmpeg -loglevel error -y -f lavfi -i "sine=frequency=330:sample_rate=48000" -t 2 -c:a pcm_s16le "$WORK/music/Untitled Track.wav"
cp "$WORK/base.mkv" "$WORK/music/Sample Video.mkv"
cp "$HERE/tests/fixtures/music-cover.png" "$WORK/music/cover.png"
cp "$WORK/music/cover.png" "$WORK/cover.png"
ffmpeg -loglevel error -y -f lavfi -i "color=c=blue:s=128x128" -frames:v 1 -update 1 "$WORK/cover-replacement.jpg"
mkdir -p "$NEO_SANDBOX/config/vlc-neo"
printf '[appearance]\nonboarded=true\n' > "$NEO_SANDBOX/config/vlc-neo/neo.conf"
E1="$WORK/show/My.Show.S01E01.1080p.mkv"; E2="$WORK/show/My.Show.S01E02.1080p.mkv"
mkdir -p "$WORK/show-one" "$WORK/show-two"
cp "$E1" "$WORK/show-one/My.Show.S01E01.1080p.mkv"
cp "$E2" "$WORK/show-two/My.Show.S01E02.1080p.mkv"
E1_DISTINCT="$WORK/show-one/My.Show.S01E01.1080p.mkv"; E2_DISTINCT="$WORK/show-two/My.Show.S01E02.1080p.mkv"
printf '1\n00:00:00,500 --> 00:00:30,000\nEnglish\n' > "$WORK/show/My.Show.S01E01.English.srt"
printf '1\n00:00:00,500 --> 00:00:30,000\nSpanish\n' > "$WORK/show/My.Show.S01E01.Spanish.srt"
mkdir -p "$WORK/Videos/Shows/The Wand"
ln -s "$WORK/show" "$WORK/Videos/Shows/The Wand/S01"
cp "$WORK/subs/myshow_1x02_ar.srt" "$WORK/show/My.Show.S01E02.ar.srt"

echo "== existing control layout migration"
legacyLayoutSandbox="$WORK/legacy-layout-sandbox"
mkdir -p "$legacyLayoutSandbox/config/vlc-neo"
printf '[appearance]\nonboarded=true\n' > "$legacyLayoutSandbox/config/vlc-neo/neo.conf"
out=$(NEO_SANDBOX="$legacyLayoutSandbox" run "600:Theme.store.layout='play,volume,settings,queue'; Theme.store.controlLayoutVersion=0; Theme.migrateControlLayout(); 'layoutMigration=' + (Theme.store.controlLayoutVersion === 1 && Theme.store.layout === 'play,volume,cast,settings,queue' && Theme.layoutList().join(',') === 'play,volume,cast,settings,queue')|+100:quit")
check "existing control layouts migrate the cast action without changing other controls" "$out" "layoutMigration=true"
if grep -qF 'Binding loop detected for property "items"' <<<"$out"; then
    echo "FAIL  control-layout migration does not trigger a QML binding loop"; fail=$((fail + 1))
else
    echo "PASS  control-layout migration does not trigger a QML binding loop"; pass=$((pass + 1))
fi

echo "== first-run media folder selection"
out=$(NEO_SANDBOX="$WORK/onboarding-picker-sandbox" run "500:click-item:onboarding-browse-media-folder|+150:'folderPickerVisible=' + onboarding.folderPickerVisible|+100:quit")
check "Browse opens the native onboarding folder picker" "$out" "folderPickerVisible=true"
out=$(NEO_SANDBOX="$WORK/onboarding-sandbox" run "500:Theme.store.hideDelay=100; win.width=1090; win.height=759|+100:move:545,379|+250:'welcome=' + onboarding.visible + '/' + onboarding.step + '/' + onboarding.mediaFolderPath|+100:'welcomeCanvas=' + (onboarding.visible && videoArea.color === Theme.onboardingVideoBg && !navigationRail.visible && !topBar.visible)|+100:grab:$WORK/onboarding-welcome.png|+100:move:100,5|+250:'welcomeChromeRevealed=' + (topBar.visible && Math.round(topBar.y) === 0)|+100:move:1069,17|+150:'welcomeChromeHover=' + (topBar.quitButton.hovered && topBar.quitButton.color === Theme.hover)|+100:click-item:topbar-maximize|+250:'welcomeWindowMaximized=' + (win.visibility === Window.Maximized)|+100:move:100,5|+250:click-item:topbar-maximize|+250:'welcomeWindowRestored=' + (win.visibility !== Window.Maximized && win.width === 1090 && win.height === 759)|+100:move:545,379|+300:'welcomeChromeHiddenAgain=' + !topBar.visible|+100:onboarding.mediaFolderPath='$WORK/music'; 'folderSet=' + onboarding.mediaFolderPath|+100:onboarding.continueFromWelcome(); 'folderQueued=' + (onboarding.step === 1) + '/' + mediaLibrary.scanning + '/' + mediaLibrary.roots.length|+900:'folderIndexDone=' + (!mediaLibrary.scanning) + '/' + mediaLibrary.roots.length|+100:onboarding.step=0; onboarding.mediaFolderPath='$WORK/music with spaces'; 'spacedFolderSet=' + onboarding.mediaFolderPath|+100:onboarding.continueFromWelcome(); 'spacedFolderQueued=' + mediaLibrary.scanning + '/' + mediaLibrary.roots.length|+900:'spacedFolderIndexDone=' + (!mediaLibrary.scanning) + '/' + mediaLibrary.roots.length|+100:onboarding.step=1|+100:Theme.store.mode='system'; Theme.store.accent='#D37918'; 'themeCanvas=' + (onboarding.visible && onboarding.step === 1 && win.onboardingActive && onboarding.themePreviewActive && !navigationRail.visible && controlBar.visible && videoArea.color === Theme.onboardingVideoBg && topBar.parent === keyCatcher && Math.round(topBar.x) === 18 && Math.round(topBar.y) === 20 && Math.round(topBar.height) === 24 && !topBar.pipButton.visible && Math.round(topBar.width) === Math.round(onboarding.themePreviewWidth) && Math.round(middle.y + videoArea.y) === Math.round(topBar.y + topBar.height) && Math.round(middle.y + videoArea.y + videoArea.height) === Math.round(controlBar.y) && Math.round(controlBar.y + controlBar.height) === Math.round(onboarding.themePreviewTop + onboarding.themePreviewHeight) && Math.abs(onboarding.themePreviewWidth / onboarding.themePreviewHeight - 16 / 9) < 0.001)|+100:'themeFooterY=' + Math.round(onboarding.footerCenterY) + '/' + Math.round(onboarding.accentPickerCenterY)|+500:grab:$WORK/onboarding-theme.png|+100:'accentPalette=' + (Theme.accents.join(',') === '#D37918,#B9443B,#A08E32,#2E9E4A,#2AA3B3,#2F5FC4,#8A3FD1,#C64AA4,#9A9A9A')|+100:'accentSelection=' + (() => { const current=Theme.store.accent; const ok=Theme.accents.every(color => { Theme.store.accent=color; return String(Theme.accent).toUpperCase()===color.toUpperCase() }); Theme.store.accent=current; return ok })()|+100:win.width=560; win.height=340|+300:'compactThemeLayout=' + (onboarding.compactLayout && onboarding.themeContentBottom < controlBar.y - 8 && controlBar.y + controlBar.height < onboarding.footerTop && onboarding.accentPickerRight <= win.width)|+100:win.width=1090; win.height=759; Theme.store.accent='#D37918'; onboarding.step=2|+100:'shortcutCanvas=' + (onboarding.visible && onboarding.step === 2 && !controlBar.visible && !navigationRail.visible && !topBar.visible)|+100:'shortcutFooterY=' + Math.round(onboarding.footerCenterY)|+200:grab:$WORK/onboarding-shortcuts.png|+100:'shortcutReference=' + (onboarding.shortcutEntries.length === 12 && onboarding.shortcutEntries.some(e => e.label === 'Previous / Next Frame' && e.keys[0] === ',') && onboarding.shortcutEntries.some(e => e.label === 'Record' && e.keys[0] === 'SHIFT'))|+100:click-item:onboarding-next|+150:'finished=' + (!onboarding.visible && Theme.store.onboarded)|+100:quit")
check "first launch opens the welcome screen with the Figma folder default" "$out" "welcome=true/0/~/Videos"
check "welcome step uses the Figma canvas without navigation or titlebar" "$out" "welcomeCanvas=true"
check "onboarding reveals frameless window controls at the top edge" "$out" "welcomeChromeRevealed=true"
check "revealed onboarding window buttons show the Figma hover state" "$out" "welcomeChromeHover=true"
check "the revealed onboarding maximize button maximizes the window" "$out" "welcomeWindowMaximized=true"
check "the revealed onboarding maximize button restores window geometry" "$out" "welcomeWindowRestored=true"
check "onboarding hides window controls again when the pointer leaves" "$out" "welcomeChromeHiddenAgain=true"
check "the welcome screen accepts a media folder path" "$out" "folderSet=$WORK/music"
check "Next handling advances while the selected folder indexes in the background" "$out" "folderQueued=true/true/1"
check "the selected folder finishes indexing in the background" "$out" "folderIndexDone=true/1"
check "onboarding accepts a media-folder path with spaces" "$out" "spacedFolderSet=$WORK/music with spaces"
check "the path with spaces indexes as a second media root" "$out" "spacedFolderQueued=true/2"
check "the second root finishes indexing without blocking onboarding" "$out" "spacedFolderIndexDone=true/2"
check "theme step shows the dark player canvas and transport bar behind its controls" "$out" "themeCanvas=true"
check "onboarding theme and shortcut footer align to the Figma lower row" "$out" "themeFooterY=675/675"
check "onboarding accent palette matches all nine Figma colors" "$out" "accentPalette=true"
check "onboarding accent selection applies every Figma swatch color" "$out" "accentSelection=true"
check "onboarding theme cards, controls and footer reflow in a short window" "$out" "compactThemeLayout=true"
check "shortcut step matches Figma entries without player chrome" "$out" "shortcutCanvas=true"
check "shortcut screen footer aligns to the Figma lower row" "$out" "shortcutFooterY=675"
check "onboarding lists the Figma frame and record shortcuts" "$out" "shortcutReference=true"
check "the Figma Finish button marks onboarding complete and closes it" "$out" "finished=true"
out=$(NEO_SANDBOX="$WORK/onboarding-sandbox" run "500:'onboardingClosedAfterRelaunch=' + (!onboarding.visible && Theme.store.onboarded)|+100:quit")
check "onboarding stays closed after relaunch" "$out" "onboardingClosedAfterRelaunch=true"
out=$(NEO_SANDBOX="$WORK/onboarding-keyboard-sandbox" run "500:onboarding.step=1; Theme.store.mode='dark'|+100:click-item:onboarding-theme-light|+100:Theme.store.mode='dark'; 'themeOptionFocused=' + (win.activeFocusItem.objectName === 'onboarding-theme-light' && win.activeFocusItem.activeFocus && win.activeFocusItem.focusIndicatorVisible)|+100:key:Space|+100:'themeKeyboardSelection=' + (Theme.store.mode === 'light' && win.activeFocusItem.objectName === 'onboarding-theme-light' && !win.activeFocusItem.focusIndicatorVisible)|+100:key:Return|+100:'themeReturnSelection=' + (Theme.store.mode === 'light')|+100:key:Right|+100:'arrowMovesAndSelects=' + (Theme.store.mode === 'dark' && win.activeFocusItem.objectName === 'onboarding-theme-dark')|+100:key:Left|+100:'arrowMovesBackAndSelects=' + (Theme.store.mode === 'light' && win.activeFocusItem.objectName === 'onboarding-theme-light')|+100:quit")
check "onboarding theme choices receive keyboard focus" "$out" "themeOptionFocused=true"
check "Space selects the focused onboarding theme choice" "$out" "themeKeyboardSelection=true"
check "Return selects the focused onboarding theme choice" "$out" "themeReturnSelection=true"
check "arrow keys move focus and selection through onboarding themes" "$out" "arrowMovesAndSelects=true"
check "left arrow returns to the previous onboarding theme" "$out" "arrowMovesBackAndSelects=true"
out=$(NEO_SANDBOX="$WORK/onboarding-hover-sandbox" run "500:win.width=1090; win.height=759; onboarding.step=1; Theme.store.mode='dark'|+100:move-item:onboarding-theme-light|+150:'themeHoverAffordance=' + (() => { const state=onboarding.themeOptionPointerState('light'); return state.hovered + '/' + state.pointingHand + '/' + (Theme.store.mode === 'dark') })()|+100:quit")
check "onboarding theme choices expose the Figma pointer affordance without changing selection" "$out" "themeHoverAffordance=true/true/true"
for screenshot in onboarding-welcome.png onboarding-theme.png onboarding-shortcuts.png; do
    if [ -s "$WORK/$screenshot" ]; then echo "PASS  $screenshot written"; pass=$((pass + 1))
    else echo "FAIL  $screenshot missing"; fail=$((fail + 1)); fi
done

echo "== playback, video output, queue"
out=$(run "2500:'state=' + player.state + ' video=' + player.hasVideo + ' queue=' + player.queue.count + ' len=' + player.length + ' playerChrome=' + navigationPage + '/' + navigationRail.visible + '/' + (topBar.x === 0 && controlBar.x === 0) + ' figmaControlBarHeight=' + (Math.round(controlBar.height) === 54 && controlBar.height === Theme.barHeight) + ' figmaControlBarTextColors=' + (controlBar.findControl('time').timelineBar.elapsedText.color === Theme.icon && controlBar.findControl('length').timelineBar.durationText.color === Theme.icon) + ' timeline=' + (controlBar.findControl('seek').visible && controlBar.findControl('seek').objectName === 'control-seek' && Math.abs(controlBar.findControl('seek').mapToItem(controlBar,0,0).y) < 1 && Math.abs(controlBar.findControl('seek').height - controlBar.height) < 1 && controlBar.height === Theme.barHeight && controlBar.findControl('prev').x < controlBar.findControl('play').x && controlBar.findControl('play').x < controlBar.findControl('next').x && controlBar.findControl('next').x < controlBar.findControl('seek').x && controlBar.findControl('seek').x < controlBar.findControl('volume').x)|2700:quit" "$E1" "$E2")
check "plays (state 2)" "$out" "state=2"
check "frames reach the QML video item" "$out" "video=true"
check "queue has both episodes" "$out" "queue=2"
check "duration known" "$out" "len=40"
check "player control bar matches the Figma reference height of 54 px" "$out" "figmaControlBarHeight=true"
check "player elapsed and duration labels use the Figma secondary foreground color" "$out" "figmaControlBarTextColors=true"
check "player frame hides the navigation rail and aligns the chrome like Figma 247:445" "$out" "playerChrome=player/false/true"
check "the timeline stays inside its single footer row" "$out" "timeline=true"
out=$(run "1000:'noSubtitleCues=' + (player.subtitleCues.length === 0)|+100:quit" "$E1")
check "media without subtitles produces an empty timeline" "$out" "noSubtitleCues=true"
out=$(run "1500:player.next()|2600:'next=' + player.mediaUrl.toString().endsWith('My.Show.S01E02.1080p.mkv')|2800:quit" "$E1" "$E2")
check "next advances to the following queue item" "$out" "next=true"

echo "== transport controls"
out=$(run "1500:player.togglePause()|2300:'paused=' + player.state|2400:player.togglePause()|3300:'resumed=' + player.state|3500:quit" "$E1")
check "pause control pauses playback" "$out" "paused=3"
check "play control resumes playback" "$out" "resumed=2"
out=$(run "1000:Theme.store.mode='dark'; Theme.setLayout(Theme.defaultLayout.concat(['favorite'])); 'playFocus=' + controlBar.focusControl('play')|+150:key:Space|+250:'playActivated=' + !player.playing|+100:controlBar.focusControl('favorite'); 'iconFocus=' + controlBar.findControl('favorite').contentItem.activeFocus|+100:(() => { const b=controlBar.findControl('favorite').contentItem; return 'iconFocusStyle=' + (b.activeFocus && b.border.width === 1 && b.border.color === Theme.accent && b.color === Theme.hover && String(Theme.hover).toUpperCase() === '#191919') })()|+100:key:Space|+200:'iconActivated=' + Theme.isFavorite(player.mediaUrl.toString())|+100:key:Space|+200:'iconDeactivated=' + !Theme.isFavorite(player.mediaUrl.toString())|+100:quit" "$E1")
check "play button receives keyboard focus" "$out" "playFocus=true"
check "Space activates the focused play button" "$out" "playActivated=true"
check "icon buttons receive keyboard focus" "$out" "iconFocus=true"
check "focused player buttons show the Figma focus ring and hover surface" "$out" "iconFocusStyle=true"
check "Space toggles the focused favorite button" "$out" "iconActivated=true"
check "Space toggles the focused favorite button off" "$out" "iconDeactivated=true"
out=$(run "100:onboarding.close(); Theme.store.mode='dark'; win.width=1120; win.height=680; Theme.setLayout(Theme.defaultLayout.slice()); player.openLocation('$E1', true)|+1100:move-item:control-settings|+250:'settingsHover=' + (() => { const b=controlBar.findControl('settings').contentItem; return b.hovered && b.color === Theme.hover && b.iconColor === Theme.text })()|+100:move-item:control-queue|+100:'queueHover=' + (() => { const b=controlBar.findControl('queue').contentItem; return b.hovered && b.color === Theme.hover && b.iconColor === Theme.text })()|+100:move-item:control-audio|+180:'audioHover=' + (() => { const b=controlBar.findControl('audio').contentItem; return b.hovered && b.color === Theme.hover && b.iconColor === Theme.text })()|+100:move-item:control-subtitle|+300:'subtitleHover=' + (() => { const b=controlBar.findControl('subtitle').contentItem; return b.hovered && b.color === Theme.hover && b.iconColor === Theme.text })()|+100:move-item:control-play|+100:'playHover=' + (controlBar.findControl('play').contentItem.color === Qt.lighter(Theme.accent, 1.1) && !controlBar.findControl('play').contentItem.activeFocus)|+100:move-item:control-prev|+250:'prevHover=' + (() => { const b=controlBar.findControl('prev').contentItem; return b.hovered && b.color === Theme.hover && b.iconColor === Theme.text })()|+100:move-item:control-next|+300:'nextHover=' + (() => { const b=controlBar.findControl('next').contentItem; return b.hovered && b.color === Theme.hover && b.iconColor === Theme.text })()|+100:move-item:control-volume-mute|+150:'volumeMuteHover=' + (() => { const b=controlBar.findControl('volume').contentItem.children[0]; return b.hovered && b.color === Theme.hover && b.iconColor === Theme.text && String(Theme.hover).toUpperCase() === '#191919' })()|+100:Theme.store.mode='light'|+100:move-item:control-settings|+250:'settingsLightHover=' + (() => { const b=controlBar.findControl('settings').contentItem; return b.hovered && b.color === Theme.hover && b.iconColor === Theme.text && String(Theme.hover).toUpperCase() === '#B3B3B3' && String(Theme.text).toUpperCase() === '#2E2E2E' })()|+100:move-item:control-volume-mute|+150:'volumeMuteLightHover=' + (() => { const b=controlBar.findControl('volume').contentItem.children[0]; return b.hovered && b.color === Theme.hover && b.iconColor === Theme.text && String(Theme.hover).toUpperCase() === '#B3B3B3' && String(Theme.text).toUpperCase() === '#2E2E2E' })()|+100:quit" "$E1")
check "settings control uses the Figma hover fill and icon color" "$out" "settingsHover=true"
check "queue control uses the Figma hover fill and icon color" "$out" "queueHover=true"
check "audio control uses the Figma hover fill and icon color" "$out" "audioHover=true"
check "subtitle control uses the Figma hover fill and icon color" "$out" "subtitleHover=true"
check "play control uses its Figma hover accent" "$out" "playHover=true"
check "previous control uses the Figma hover fill and icon color" "$out" "prevHover=true"
check "next control uses the Figma hover fill and icon color" "$out" "nextHover=true"
check "volume mute control uses the dark Figma hover fill and icon color" "$out" "volumeMuteHover=true"
check "settings control uses the Figma light-theme hover fill and icon color" "$out" "settingsLightHover=true"
check "volume mute control uses the light Figma hover fill and icon color" "$out" "volumeMuteLightHover=true"
echo "== optional control hover states"
optional_hover_ids=(stop loop shuffle record snapshot pip zoom rightsidebar quit vlcsettings home thumbnail properties replay chapters favorite bookmark bookmarks playlists fullscreen frame back10 fwd10 back15 fwd15)
optional_hover_steps="100:onboarding.close(); win.width=1120; win.height=680; win.navigationPage='player'; Theme.store.mode='dark'"
for id in "${optional_hover_ids[@]}"; do
    optional_hover_steps+="|+120:Theme.setLayout(Theme.defaultLayout.concat(['$id']))|+140:move-item:control-$id|+150:'optionalHover-$id=' + (() => { const item=controlBar.findControl('$id'); return !!item && item.visible && !!item.contentItem.hovered && item.contentItem.color === Theme.hover })()"
    optional_hover_steps+="|+80:controlBar.focusControl('$id')|+100:'optionalFocus-$id=' + (() => { const item=controlBar.findControl('$id'); const button=item && item.contentItem; return !!button && button.activeFocus && button.border.width === 1 && button.border.color === Theme.accent && button.color === Theme.hover })()"
done
optional_hover_steps+='|+100:quit'
out=$(run "$optional_hover_steps")
for id in "${optional_hover_ids[@]}"; do
    check "optional $id control uses the Figma hover fill" "$out" "optionalHover-$id=true"
    check "optional $id control shows the Figma focus ring" "$out" "optionalFocus-$id=true"
done
out=$(run "100:onboarding.close(); win.width=560; win.height=340; Theme.setLayout(Theme.defaultLayout.slice()); player.openLocation('$E1', true)|+1100:'compactControlBar=' + (['prev','play','next','volume'].every(id => controlBar.findControl(id).visible) && topBar.fullscreenButton.visible) + '/' + (['hideui','pip','foldername','filename','favorite'].every(id => controlBar.items.indexOf(id) < 0)) + '/' + (controlBar.findControl('play').x < 120) + '/' + (Math.max.apply(null, controlBar.items.map(id => controlBar.findControl(id)).concat([controlBar.findControl('seek')]).filter(item => item && item.visible).map(item => item.x + item.width)) <= controlBar.width - 6) + '/' + (controlBar.findControl('seek').visible && controlBar.findControl('seek').timelineBar.compact && !controlBar.findControl('seek').timelineBar.tiny && controlBar.findControl('seek').width >= 150 && controlBar.findControl('seek').contentItem.enabled)|+150:grab:$WORK/compact-control-bar.png|+100:'compactSeekFocus=' + controlBar.focusControl('seek')|+100:key:Right|+400:'compactSeekKeyboard=' + (player.time >= 5000)|+100:quit" "$E1")
check "compact control bar keeps transport and seek visible without metadata overflow" "$out" "compactControlBar=true/true/true/true/true"
check "the compact seek bar accepts keyboard focus" "$out" "compactSeekFocus=true"
check "Right seeks while the compact seek bar is focused" "$out" "compactSeekKeyboard=true"
if [ -s "$WORK/compact-control-bar.png" ]; then echo "PASS  compact control-bar screenshot written"; pass=$((pass + 1))
else echo "FAIL  compact control-bar screenshot missing"; fail=$((fail + 1)); fi
out=$(run "100:onboarding.close(); Theme.setLayout(Theme.defaultLayout.slice()); player.openLocation('$E1', true)|+800:win.setPip(true); win.width=320; win.height=180|+300:'tinyControlBar=' + (win.width === 320 && ['prev','play','next','volume'].every(id => controlBar.findControl(id).visible)) + '/' + (controlBar.items.indexOf('visualizer') < 0 && !controlBar.findControl('audio').visible && !controlBar.findControl('subtitle').visible && !controlBar.findControl('settings').visible && !controlBar.findControl('queue').visible) + '/' + (Math.max.apply(null, controlBar.items.map(id => controlBar.findControl(id)).concat([controlBar.findControl('seek')]).filter(item => item && item.visible).map(item => item.x + item.width)) <= controlBar.width - 6) + '/' + (controlBar.findControl('seek').visible && controlBar.findControl('seek').timelineBar.tiny && controlBar.findControl('seek').contentItem.enabled)|+100:quit" "$E1")
check "picture-in-picture control bar retains transport and seek within 320 px" "$out" "tinyControlBar=true/true/true/true"
out=$(run "100:onboarding.close(); win.width=1120; win.height=680; win.x=40; win.y=50; player.openLocation('$E1', true)|+1000:tracksPopup.openFor('spu', controlBar.findControl('subtitle')); 'popupBeforePip=' + tracksPopup.visible|+100:win.setPip(true); 'pipCompact=' + (win.pip && win.overlayMode && player.hasVideo && win.width <= 480 && win.height <= 270 && win.minimumWidth <= win.width) + '/' + !tracksPopup.visible + '/' + !!(win.flags & Qt.WindowStaysOnTopHint)|+150:'pipTopBar=' + topBar.titleLabel.visible + '/' + (topBar.titleLabel.x >= 40 && topBar.titleLabel.x + topBar.titleLabel.width <= win.width - 60) + '/' + (topBar.pipButton.visible && topBar.quitButton.visible && !topBar.minimizeButton.visible && !topBar.maximizeButton.visible && !topBar.fullscreenButton.visible)|+100:grab:$WORK/pip.png|+100:topBar.pipButton.clicked(); 'pipRestored=' + (!win.pip && win.width === 1120 && win.height === 680 && win.x === 40 && win.y === 50 && !(win.flags & Qt.WindowStaysOnTopHint))|+100:quit" "$E1")
check "PiP entry closes the open track picker" "$out" "popupBeforePip=true"
check "Picture in Picture shrinks, stays on top and dismisses popups" "$out" "pipCompact=true/true/true"
check "Picture in Picture top bar keeps its title clear and only shows exit and quit" "$out" "pipTopBar=true/true/true"
check "the PiP exit button restores the previous window geometry" "$out" "pipRestored=true"
if [ -s "$WORK/pip.png" ]; then echo "PASS  Picture in Picture screenshot written"; pass=$((pass + 1))
else echo "FAIL  Picture in Picture screenshot missing"; fail=$((fail + 1)); fi

echo "== folder subtitles + show preset"
out=$(run "1500:'matched=' + player.linkSubtitleFolder(platform.fileUrl('$WORK/subs'))|2500:player.setSubtitleDelay(-400); player.setSubtitleScale(160)|2800:player.savePresetForFolder()|3000:quit" "$E1" "$E2")
check "folder link matches both episodes" "$out" "matched=2"
out=$(run "3500:'sub=' + player.linkedSubtitleFile() + ' shown=' + player.tracks('spu').some(t => t.selected && t.id >= 0) + ' delay=' + player.subtitleDelay + ' scale=' + player.subtitleScale() + ' cues=' + player.subtitleCues.length + ' cueText=' + (player.subtitleCues.length ? player.subtitleCues[0].text : '')|+100:'cueLookup=' + (controlBar.findControl('seek').contentItem.cueAt(1500) ? controlBar.findControl('seek').contentItem.cueAt(1500).text : '')|+100:grab:$WORK/subtitle-timeline.png|+200:quit" "$E2")
check "episode 2 gets its own subtitle file" "$out" "sub=myshow_1x02_ar.srt"
check "that subtitle is the active track" "$out" "shown=true"
check "preset restores subtitle delay" "$out" "delay=-400"
check "preset restores subtitle size" "$out" "scale=160"
check "linked subtitles populate the text timeline" "$out" "cues=1 cueText=Episode 02"
check "hover lookup finds the subtitle text at the matching time" "$out" "cueLookup=Episode 02"
out=$(run "1000:subtitleDialog.open()|+250:subtitleDialog.target='playlist'; subtitleDialog.sourcePath='$WORK/subs'; 'subtitlePairs=' + subtitleDialog.matches.length + '/' + subtitleDialog.matches.filter(row => row.matched).length|+100:subtitleDialog.saveSelection()|+600:'playlistSubtitleSave=' + (player.linkedSubtitleFolder() === '$WORK/subs') + '/' + (!subtitleDialog.visible)|+100:player.unlinkSubtitleFolderFromPlaylist(); 'playlistSubtitleUnlink=' + (player.linkedSubtitleFolder().length === 0)|+100:quit" "$E1" "$E2")
check "the Figma dialog previews each queued episode and its matching subtitle" "$out" "subtitlePairs=2/2"
check "Save links subtitle folders to the whole playlist" "$out" "playlistSubtitleSave=true/true"
check "playlist unlink removes those subtitle links" "$out" "playlistSubtitleUnlink=true"
out=$(run "1200:subtitleDialog.target='playlist'; subtitleDialog.open()|+200:subtitleDialog.sourcePath='$WORK/subs'; 'distinctFolderPreview=' + subtitleDialog.matches.length + '/' + subtitleDialog.matches.filter(row => row.matched).length|+150:subtitleDialog.saveSelection()|+600:'distinctFirstSaved=' + (player.linkedSubtitleFolder() === '$WORK/subs') + '/' + (!subtitleDialog.visible)|+150:player.next()|+650:'distinctSecondLinked=' + (player.linkedSubtitleFolder() === '$WORK/subs') + '/' + player.linkedSubtitleFile().split('/').pop()|+100:player.unlinkSubtitleFolderFromPlaylist()|+100:player.previous()|+650:'distinctFirstUnlinked=' + (player.linkedSubtitleFolder().length === 0)|+100:quit" "$E1_DISTINCT" "$E2_DISTINCT")
check "playlist subtitle matching includes episodes from separate media folders" "$out" "distinctFolderPreview=2/2"
check "playlist subtitle Save links the first distinct media folder" "$out" "distinctFirstSaved=true/true"
check "the second distinct folder loads its matching playlist subtitle" "$out" "distinctSecondLinked=true/myshow_1x02_ar.srt"
check "playlist unlink removes links from every distinct media folder" "$out" "distinctFirstUnlinked=true"
out=$(run "1200:subtitleDialog.open()|+250:subtitleDialog.sourcePath='$WORK/show'; subtitleDialog.target='file'; 'subtitleVariants=' + subtitleDialog.candidateFiles.map(file => file.name).join(',')|+100:subtitleDialog.toggleSubtitle(subtitleDialog.candidateFiles[0].path); subtitleDialog.toggleSubtitle(subtitleDialog.candidateFiles[1].path); 'subtitleSelection=' + subtitleDialog.selectedSubtitlePaths.length|+100:subtitleDialog.saveSelection()|+300:'subtitleVariantsAdded=' + (!subtitleDialog.visible && player.tracks('spu').filter(track => track.id >= 0).length >= 2)|+100:quit" "$E1")
check "single-file subtitles list all language variants for the current episode" "$out" "subtitleVariants=My.Show.S01E01.English.srt,My.Show.S01E01.Spanish.srt"
check "multiple subtitle variants can be selected together" "$out" "subtitleSelection=2"
check "Save adds the selected subtitle variants to VLC" "$out" "subtitleVariantsAdded=true"
if [ -s "$WORK/subtitle-timeline.png" ]; then echo "PASS  subtitle timeline screenshot written"; pass=$((pass + 1))
else echo "FAIL  subtitle timeline screenshot missing"; fail=$((fail + 1)); fi
out=$(run "1000:win.width=1080; win.height=832; subtitleDialog.target='file'; subtitleDialog.open()|+250:subtitleDialog.sourcePath='$WORK/Videos/Shows/The Wand/S01'; subtitleDialog.toggleSubtitle(subtitleDialog.candidateFiles[0].path); subtitleDialog.toggleSubtitle(subtitleDialog.candidateFiles[1].path); 'subtitleDialogFrame=' + subtitleDialog.width + '/' + subtitleDialog.height + '/' + subtitleDialog.selectedSubtitlePaths.length + '/' + subtitleDialog.displaySourcePath()|+100:grab:$WORK/subtitle-dialog-figma.png|+100:win.width=1120; win.height=680|+100:quit" "$E1")
check "single-file subtitle dialog matches the Figma 1048×800 frame, path and selected state" "$out" "subtitleDialogFrame=1048/800/2/Videos / Shows / The Wand / S01"
if [ -s "$WORK/subtitle-dialog-figma.png" ]; then echo "PASS  Figma-sized subtitle dialog screenshot written"; pass=$((pass + 1))
else echo "FAIL  Figma-sized subtitle dialog screenshot missing"; fail=$((fail + 1)); fi
out=$(run "1000:win.width=1080; win.height=832; subtitleDialog.target='folder'; subtitleDialog.open()|+250:subtitleDialog.sourcePath='$WORK/Videos/Shows/The Wand/S01'; 'folderSubtitleFrame=' + subtitleDialog.width + '/' + subtitleDialog.height + '/' + subtitleDialog.matches.length + '/' + subtitleDialog.matches.filter(x => x.matched).length + '/' + subtitleDialog.displaySourcePath()|+100:grab:$WORK/subtitle-folder-figma.png|+100:win.width=1120; win.height=680|+100:quit" "$E1" "$E2")
check "folder subtitle matches use the Figma column layout and file path" "$out" "folderSubtitleFrame=1048/800/2/2/Videos / Shows / The Wand / S01"
if [ -s "$WORK/subtitle-folder-figma.png" ]; then echo "PASS  Figma folder-match screenshot written"; pass=$((pass + 1))
else echo "FAIL  Figma folder-match screenshot missing"; fail=$((fail + 1)); fi
echo "== OpenSubtitles populated results"
python3 - "$WORK" >"$WORK/opensubtitles-fixture.log" 2>&1 <<'PY' &
import http.server
import json
import pathlib
import sys

work = pathlib.Path(sys.argv[1])
response = {"data": [{"attributes": {
    "feature_details": {"movie_name": "Interstellar"},
    "release": "Interstellar.2014.1080p.BluRay",
    "language": "en",
    "hearing_impaired": True,
    "download_count": 1234,
    "ratings": 9.2,
    "moviehash_match": True,
    "url": "https://www.opensubtitles.com/en/subtitles/987654",
    "files": [{"file_id": 987654}]
}}]}

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        (work / "opensubtitles-request.txt").write_text(self.path + "\nApi-Key: " + self.headers.get("Api-Key", ""))
        body = json.dumps(response).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass

server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
(work / "opensubtitles-port").write_text(str(server.server_address[1]))
server.serve_forever()
PY
opensubtitlesFixturePid=$!
for _ in {1..40}; do
    [ -s "$WORK/opensubtitles-port" ] && break
    sleep 0.1
done
if [ -s "$WORK/opensubtitles-port" ]; then
    opensubtitlesApi="http://127.0.0.1:$(cat "$WORK/opensubtitles-port")/api/v1/"
    out=$(NEO_TEST_OPENSUBTITLES_API_URL="$opensubtitlesApi" run "1000:onboarding.close(); win.width=1080; win.height=832; player.openLocation('$E1',true)|+900:openSubtitles.setApiKey('local-smoke-key'); subtitleDialog.target='file'; subtitleDialog.open()|+250:subtitleDialog.onlineLanguage='en'; subtitleDialog.onlineSourceSelector.picked('opensubtitles')|+300:subtitleDialog.onlineQuery='Interstellar'; openSubtitles.search(subtitleDialog.onlineQuery,subtitleDialog.onlineLanguage,player.mediaUrl)|+800:'onlineSubtitleResults=' + openSubtitles.results.length + '/' + subtitleDialog.resultList.count + '/' + (subtitleDialog.resultList.itemAtIndex(0).displayTitle === 'Interstellar.2014.1080p.BluRay') + '/' + (subtitleDialog.resultList.itemAtIndex(0).modelData.movieHashMatch)|+100:grab:$WORK/opensubtitles-results.png|+100:move-item:opensubtitles-result-987654|+100:click-item:opensubtitles-result-987654|+100:'onlineSubtitleSelected=' + (subtitleDialog.selectedOnlineFileId === 987654 && subtitleDialog.resultList.itemAtIndex(0).onlineChosen)|+100:openSubtitles.clearApiKey()|+100:quit" "$E1")
    kill "$opensubtitlesFixturePid" 2>/dev/null || true
    wait "$opensubtitlesFixturePid" 2>/dev/null || true
    check "OpenSubtitles populated results render in the Figma-sized dialog" "$out" "onlineSubtitleResults=1/1/true/true"
    check "the OpenSubtitles row selects its online file id for the current-file target" "$out" "onlineSubtitleSelected=true"
    if grep -qF "Api-Key: local-smoke-key" "$WORK/opensubtitles-request.txt"; then
        echo "PASS  local OpenSubtitles results request used the fixture API key"; pass=$((pass + 1))
    else echo "FAIL  local OpenSubtitles results request used the fixture API key"; fail=$((fail + 1)); fi
    if [ -s "$WORK/opensubtitles-results.png" ]; then echo "PASS  populated OpenSubtitles dialog screenshot written"; pass=$((pass + 1))
    else echo "FAIL  populated OpenSubtitles dialog screenshot missing"; fail=$((fail + 1)); fi
else
    kill "$opensubtitlesFixturePid" 2>/dev/null || true
    wait "$opensubtitlesFixturePid" 2>/dev/null || true
    echo "FAIL  local OpenSubtitles fixture did not start"; fail=$((fail + 1))
fi

echo "== resume"
out=$(run "1500:player.jumpTo(20000)|2500:win.close()" "$E1")
check "resume point playback exits cleanly" "$out" "player.jumpTo(20000)"
out=$(run "1800:'resume=' + (resumePill.visible ? Math.round(resumePill.point / 1000) : 0)|2000:quit" "$E1")
check "resume offered at ~20 s" "$out" "resume=2"

echo "== hotkeys, bookmarks, rate"
out=$(run "1500:win.handleKey({key: Qt.Key_Right, modifiers: 0, text: ''})|2200:'t=' + Math.round(player.time / 1000)|2300:player.addBookmark()|2500:'marks=' + player.bookmarks().length|2600:player.setRate(1.5)|3000:'rate=' + player.rate|3100:quit" "$E1")
check "→ seeks forward 10 s" "$out" "t=1"
check "bookmark stored" "$out" "marks=1"
check "speed applied" "$out" "rate=1.5"

echo "== multimedia keyboard events"
out=$(run "800:'mediaKeyBase=' + player.mediaUrl.toString().endsWith('My.Show.S01E01.1080p.mkv')|+100:win.focusKeys()|+100:key:MediaNext|+600:'mediaNext=' + player.mediaUrl.toString().endsWith('My.Show.S01E02.1080p.mkv')|+100:win.focusKeys()|+100:key:MediaPrevious|+600:'mediaPrevious=' + player.mediaUrl.toString().endsWith('My.Show.S01E01.1080p.mkv')|+100:player.togglePause(); win.focusKeys()|+100:key:MediaPlay|+200:'mediaPlay=' + player.playing|+100:win.focusKeys()|+100:key:MediaPlay|+200:'mediaPlayIdempotent=' + player.playing|+100:win.focusKeys()|+100:key:MediaPause|+200:'mediaPause=' + !player.playing|+100:win.focusKeys()|+100:key:MediaPause|+200:'mediaPauseIdempotent=' + !player.playing|+100:win.focusKeys()|+100:key:MediaTogglePlayPause|+200:'mediaToggle=' + player.playing|+100:win.focusKeys()|+100:key:MediaStop|+200:'mediaStop=' + (player.state === 0)|+100:quit" "$E1" "$E2")
check "multimedia test starts on the first queue item" "$out" "mediaKeyBase=true"
check "Media Next selects the following queue item" "$out" "mediaNext=true"
check "Media Previous selects the prior queue item" "$out" "mediaPrevious=true"
check "Media Play resumes paused playback" "$out" "mediaPlay=true"
check "Media Play leaves active playback running" "$out" "mediaPlayIdempotent=true"
check "Media Pause pauses active playback" "$out" "mediaPause=true"
check "Media Pause leaves paused playback unchanged" "$out" "mediaPauseIdempotent=true"
check "Media Toggle Play Pause toggles playback" "$out" "mediaToggle=true"
check "Media Stop stops playback" "$out" "mediaStop=true"

echo "== VLC core config round trip"
out=$(run "1000:player.setConfig('network-caching', 1500)|1200:'cache=' + player.config('network-caching')|1300:quit")
check "vlcrc option written and read back" "$out" "cache=1500"
out=$(run "1000:'cache=' + player.config('network-caching')|1200:quit")
check "vlcrc preference persists across VLC launches" "$out" "cache=1500"

echo "== appearance, window sizes and persistent settings"
out=$(run "1000:Theme.store.rememberWindowGeometry=false; win.width=1120; win.height=680; Theme.store.mode='dark'; Theme.store.accent='#D9822B'; 'videoBg=' + videoArea.color|+350:grab:$WORK/dark.png|+200:Theme.store.mode='light'; Theme.store.accent='#2F5FC4'; 'lightChrome=' + Theme.rail.a.toFixed(2) + '/' + Theme.bar.a.toFixed(2) + '/' + Theme.panel.a.toFixed(2) + '/' + win.color|+350:grab:$WORK/light.png|+200:win.width=560; win.height=340|+350:grab:$WORK/compact.png|+200:quit" "$E1")
check "dark theme captured at standard size" "$out" "window 1120x680"
check "video canvas uses the Figma charcoal in both themes" "$out" "videoBg=#2c2b29"
check "light rail and panel use Figma transparent styles over the charcoal canvas" "$out" "lightChrome=0.75/0.75/0.80/#2c2b29"
check "light theme captured at standard size" "$out" "window 1120x680"
check "compact window size captured" "$out" "window 560x340"
for image in dark light compact; do
    if [ -s "$WORK/$image.png" ]; then echo "PASS  $image screenshot written"; pass=$((pass + 1))
    else echo "FAIL  $image screenshot missing"; fail=$((fail + 1)); fi
done
out=$(run "1000:'mode=' + Theme.store.mode + ' accent=' + Theme.store.accent|1200:quit" "$E1")
check "theme and accent persist across VLC launches" "$out" "mode=light accent=#2F5FC4"
echo "== update check preference and version logic"
out=$(NEO_SANDBOX="$WORK/update-sandbox" run "1000:'updateDefault=' + (!Theme.store.automaticUpdateChecks) + '/' + !win.checkForUpdates(true) + '/' + !win.updateCheckRunning|+100:'versionLogic=' + (win.latestStableTag([{name:'v0.2.0'},{name:'v1.10.0'},{name:'preview'},{name:'v2.0'}]) === 'v1.10.0') + '/' + win.isVersionNewer('v0.1.1', platform.applicationVersion) + '/' + !win.isVersionNewer('v0.1.0', platform.applicationVersion)|+100:Theme.store.automaticUpdateChecks=true; Theme.store.lastUpdateCheckAttempt=Date.now(); 'updateCooldown=' + (!win.checkForUpdates(false) && !win.updateCheckRunning)|+100:quit")
check "update checks are opt-in and disabled by default" "$out" "updateDefault=true/true/true"
check "stable GitHub tags use numeric version ordering" "$out" "versionLogic=true/true/true"
check "daily cooldown prevents repeated background requests" "$out" "updateCooldown=true"
out=$(NEO_SANDBOX="$WORK/update-sandbox" run "1000:'updatePreferencePersisted=' + Theme.store.automaticUpdateChecks + '/' + (Date.now() - Theme.store.lastUpdateCheckAttempt < 86400000) + '/' + !win.updateCheckRunning|+100:Theme.store.automaticUpdateChecks=false|+100:quit")
check "the update preference and last attempt persist across launches" "$out" "updatePreferencePersisted=true/true/true"
out=$(run "1000:Theme.store.mode='dark'; Theme.store.accent='#B9443B'; Theme.store.hideDelay=2400; Theme.store.autoHideMode='always'; Theme.setLayout(['play','seek','volume']); customizeDialog.open()|+150:customizeDialog.contentScroller.contentY = Math.max(0,customizeDialog.contentScroller.contentHeight - customizeDialog.contentScroller.height)|+100:customizeDialog.profileNameInput.text='Movie night'|+100:click-item:save-customization-profile|+100:'profileSaved=' + Theme.profileList().length + '/' + Theme.store.activeProfile|+100:Theme.store.mode='light'; Theme.store.accent='#2F5FC4'; Theme.store.hideDelay=900; Theme.store.autoHideMode='never'; Theme.setLayout(Theme.defaultLayout.slice()); 'profileApplied=' + Theme.applyProfile('Movie night'); 'profileState=' + [Theme.store.mode, Theme.store.accent, Theme.store.hideDelay, Theme.store.autoHideMode, Theme.layoutList().join(',')].join('/')|+150:customizeDialog.close()|+100:quit" "$E1")
check "the customization dialog saves a named profile" "$out" "profileSaved=1/Movie night"
check "applying a profile restores its UI preferences and control layout" "$out" "profileState=dark/#B9443B/2400/always/play,volume"
out=$(run "1000:'storedProfile=' + Theme.profileList().length + '/' + Theme.store.activeProfile + '/' + Theme.layoutList().join(',')|+100:Theme.deleteProfile('Movie night'); 'profileDeleted=' + Theme.profileList().length|+100:quit" "$E1")
check "named profiles persist across VLC launches" "$out" "storedProfile=1/Movie night/play,volume"
check "profiles can be deleted" "$out" "profileDeleted=0"
mkdir -p "$WORK/profile-capture"
NEO_SANDBOX="$WORK/vlc-profile-sandbox" out=$(run "500:player.setConfig('aout','dummy'); player.setConfig('vout','dummy'); player.configType('alsa-audio-device') ? player.setConfig('alsa-audio-device','null') : false; player.setConfig('snapshot-path','$WORK/profile-capture'); player.setConfig('snapshot-prefix','ProfileShot'); player.setConfig('snapshot-format','png'); player.setConfig('snapshot-preview',false); player.setConfig('snapshot-sequential',true); player.setConfig('snapshot-width',640); player.setConfig('snapshot-height',360); player.setConfig('sout-transcode-vb',1450); player.setConfig('sout-transcode-ab',160); player.setConfig('network-caching',777); player.setConfig('avcodec-hw','none'); player.setConfig('freetype-color',0xD37918); player.setConfig('video-filter','sepia'); player.setConfig('play-and-exit',true); customizeDialog.open()|+150:customizeDialog.contentScroller.contentY = Math.max(0,customizeDialog.contentScroller.contentHeight - customizeDialog.contentScroller.height)|+100:customizeDialog.profileNameInput.text='Cinema'|+100:click-item:save-customization-profile|+100:customizeDialog.contentScroller.contentY = Math.max(0,customizeDialog.contentScroller.contentHeight - customizeDialog.contentScroller.height)|+100:player.setConfig('network-caching',2222); player.setConfig('avcodec-hw','any'); player.setConfig('freetype-color',0xFFFFFF); player.setConfig('video-filter',''); player.setConfig('play-and-exit',false); player.setConfig('snapshot-path','$WORK'); player.setConfig('snapshot-prefix','Changed'); player.setConfig('snapshot-format','jpg'); player.setConfig('snapshot-preview',true); player.setConfig('snapshot-sequential',false); player.setConfig('snapshot-width',320); player.setConfig('snapshot-height',180); player.setConfig('sout-transcode-vb',9000); player.setConfig('sout-transcode-ab',320); player.setConfig('aout',''); player.setConfig('vout',''); player.configType('alsa-audio-device') ? player.setConfig('alsa-audio-device','default') : false; Theme.store.activeProfile=''; const options=Theme.profileList()[0].vlcOptions; 'profileVlcSaved=' + (options['network-caching']===777 && options['avcodec-hw']==='none' && options['freetype-color']===0xD37918 && options['video-filter']==='sepia' && options['play-and-exit']===true && options['aout']==='dummy' && options['vout']==='dummy' && (player.configType('alsa-audio-device') === '' ? true : options['alsa-audio-device']==='null') && options['snapshot-path']==='$WORK/profile-capture' && options['snapshot-prefix']==='ProfileShot' && options['snapshot-format']==='png' && options['snapshot-preview']===false && options['snapshot-sequential']===true && options['snapshot-width']===640 && options['snapshot-height']===360 && options['sout-transcode-vb']===1450 && options['sout-transcode-ab']===160 && !JSON.stringify(options).includes('proxy'))|+100:click-item:apply-customization-profile-Cinema|+100:'profileVlcApplied=' + (Theme.store.activeProfile === 'Cinema') + '/' + [player.config('network-caching'),player.config('avcodec-hw'),player.config('freetype-color'),player.config('video-filter'),player.config('play-and-exit')].join('/') + '/outputsRestored=' + (player.config('aout')==='dummy' && player.config('vout')==='dummy' && (player.configType('alsa-audio-device') === '' ? true : player.config('alsa-audio-device')==='null')) + '/captureAndTranscodeRestored=' + (player.config('snapshot-path')==='$WORK/profile-capture' && player.config('snapshot-prefix')==='ProfileShot' && player.config('snapshot-format')==='png' && player.config('snapshot-preview')===false && player.config('snapshot-sequential')===true && player.config('snapshot-width')===640 && player.config('snapshot-height')===360 && player.config('sout-transcode-vb')===1450 && player.config('sout-transcode-ab')===160) + '/secretRejected=' + !player.applyProfileOptions({'http-proxy-pwd':'secret'})|+100:player.snapshot()|+1500:quit" "$E1")
check "named profiles capture supported VLC options without credentials" "$out" "profileVlcSaved=true"
check "applying a profile restores VLC buffering, decoding, subtitle and playback options" "$out" "profileVlcApplied=true/777/none/13859096/sepia/true/outputsRestored=true/captureAndTranscodeRestored=true/secretRejected=true"
NEO_SANDBOX="$WORK/vlc-profile-sandbox" out=$(run "500:'profileVlcPersists=' + Theme.applyProfile('Cinema',player) + '/' + [player.config('network-caching'),player.config('avcodec-hw'),player.config('freetype-color'),player.config('video-filter'),player.config('play-and-exit')].join('/') + '/outputsRestored=' + (player.config('aout')==='dummy' && player.config('vout')==='dummy' && (player.configType('alsa-audio-device') === '' ? true : player.config('alsa-audio-device')==='null')) + '/captureAndTranscodeRestored=' + (player.config('snapshot-path')==='$WORK/profile-capture' && player.config('snapshot-prefix')==='ProfileShot' && player.config('snapshot-format')==='png' && player.config('snapshot-width')===640 && player.config('snapshot-height')===360 && player.config('sout-transcode-vb')===1450 && player.config('sout-transcode-ab')===160)|+100:quit" "$E1")
check "VLC options in named profiles survive a VLC relaunch" "$out" "profileVlcPersists=true/777/none/13859096/sepia/true/outputsRestored=true/captureAndTranscodeRestored=true"
if find "$WORK/profile-capture" -maxdepth 1 -type f -name 'ProfileShot*.png' -size +0c -print -quit | grep -q .; then echo "PASS  applying profile creates a PNG snapshot in its saved folder"; pass=$((pass + 1))
else echo "FAIL  applying profile did not create a PNG snapshot in its saved folder"; fail=$((fail + 1)); fi

echo "== player customization palette drag interactions"
out=$(run "100:Theme.setLayout(Theme.defaultLayout.slice()); customizeDialog.open()|+300:customizeDialog.removeAt(customizeDialog.items.indexOf('play')); 'transportControlsFixed=' + (['prev','play','next'].every(id => customizeDialog.items.includes(id) && !customizeDialog.available.includes(id)) && customizeDialog.items.includes('play')) + ' defaultLayoutFigma=' + (customizeDialog.items.join(',') === 'prev,play,next,volume,audio,subtitle,cast,settings,queue')|+100:quit" "$E1")
check "previous, play and next stay on the customization bar because they are not palette items" "$out" "transportControlsFixed=true"
check "the default player layout follows the Figma control bar" "$out" "defaultLayoutFigma=true"
out=$(run "100:Theme.store.mode='dark'; Theme.setLayout(Theme.defaultLayout.slice()); customizeDialog.open()|+250:(() => { const tile=customizeDialog.focusPaletteControl('back15'); return 'paletteTileFocusStyle=' + (tile && tile.activeFocus && tile.border.width === 1 && tile.border.color === Theme.accent && tile.color === Theme.hover) })()|+100:key:Space|+150:'paletteTileKeyboardAdd=' + customizeDialog.items.includes('back15')|+100:(() => { const tile=customizeDialog.focusBarControl('back15'); return 'barTileFocusStyle=' + (tile && tile.activeFocus && tile.border.width === 1 && tile.border.color === Theme.accent && tile.color === Theme.hover) })()|+100:key:Space|+150:'barTileKeyboardRemove=' + !customizeDialog.items.includes('back15')|+100:customizeDialog.close(); Theme.setLayout(Theme.defaultLayout.slice())|+100:quit" "$E1")
check "customization palette tiles show the Figma focus surface and accent ring" "$out" "paletteTileFocusStyle=true"
check "Space adds a focused control from the customization palette" "$out" "paletteTileKeyboardAdd=true"
check "customization bar tiles show the Figma focus surface and accent ring" "$out" "barTileFocusStyle=true"
check "Space removes a focused control from the customization bar" "$out" "barTileKeyboardRemove=true"
out=$(run "100:Theme.store.mode='dark'; win.width=1120; win.height=680; Theme.setLayout(['play','volume']); customizeDialog.open()|+350:'customizePalette=' + (Theme.customizationIds.length === 31 && Theme.customizationSlots.length === 32 && customizeDialog.available.length === 31 && customizeDialog.items.join(',') === 'play,volume' && !customizeDialog.allIds.some(id => ['time','seek','length'].includes(id)) && Theme.customizationIds.every(id => !!Theme.controls[id]) && Theme.controls.quit.label === 'Quit VLC' && Theme.customizationSlots.indexOf('hdr') === 13 && Theme.customizationSlots.indexOf('playlistname') === 23 && !customizeDialog.paletteControl('hdr') && !!customizeDialog.paletteControl('playlistname') && !!customizeDialog.paletteControl('cast'))|+100:'customizePaletteFigmaSlots=' + (() => { const pos=id => customizeDialog.paletteControl(id).mapToItem(customizeDialog.paletteArea,0,0); const zoom=pos('zoom'), side=pos('rightsidebar'), home=pos('home'), thumb=pos('thumbnail'), properties=pos('properties'), chapters=pos('chapters'), favorite=pos('favorite'), playlists=pos('playlists'); return Math.round(side.x-zoom.x)===74 && Math.round(thumb.x-home.x)===74 && Math.round(chapters.x-properties.x)===148 && Math.round(playlists.x-favorite.x)===222 && home.y>zoom.y && favorite.y>chapters.y })()|+100:drag-item:customize-control-back15-available:customize-bar-drop-target:990,28|+150:'controlAdded=' + (customizeDialog.items.join(',') === 'play,volume,back15')|+100:drag-item:customize-control-volume-1:customize-bar-drop-target:12,28|+150:'controlReordered=' + (customizeDialog.items.join(',') === 'volume,play,back15')|+100:drag-item:customize-control-volume-0:customize-palette-drop-target:500,100|+150:'controlRemoved=' + (customizeDialog.items.join(',') === 'play,back15')|+100:customizeDialog.close(); 'customizeLayoutRestored=' + (Theme.layoutList().join(',') === 'play,volume')|+100:quit" "$E1")
check "the customization palette offers the implemented Figma controls" "$out" "customizePalette=true"
check "customization palette preserves Figma's HDR slot and Playlist Name position" "$out" "customizePaletteFigmaSlots=true"
check "dragging a palette control onto the bar adds it" "$out" "controlAdded=true"
check "dragging a bar control reorders it" "$out" "controlReordered=true"
check "dragging a bar control back to the palette removes it" "$out" "controlRemoved=true"
check "canceling customization leaves the saved control layout unchanged" "$out" "customizeLayoutRestored=true"

echo "== customized player actions"
out=$(run "100:Theme.setLayout(['seek','thumbnail','favorite','properties','bookmarks','replay']); player.openLocation('$E1', true)|+800:win.run('favorite'); 'favoriteAdded=' + Theme.isFavorite(player.mediaUrl.toString())|+100:win.run('favorite'); 'favoriteRemoved=' + !Theme.isFavorite(player.mediaUrl.toString())|+100:win.run('thumbnail'); 'thumbnailOff=' + (!Theme.store.showSeekThumbnails && !controlBar.findControl('seek').contentItem.requestThumbnail(1000))|+100:win.run('thumbnail'); 'thumbnailOn=' + Theme.store.showSeekThumbnails|+100:win.run('properties'); 'properties=' + (mediaPropertiesDialog.visible && mediaPropertiesDialog.subtitle.length > 0)|+100:mediaPropertiesDialog.close(); win.run('bookmarks'); 'bookmarks=' + (sidePanel.tab === 'marks' && win.rightPanel === 'settings')|+100:player.jumpTo(18000)|+800:win.run('replay')|+700:'replay=' + (player.time < 5000)|+100:Theme.setLayout(Theme.defaultLayout.slice())|+100:quit" "$E1")
check "the Favorite control adds and removes the current media" "$out" "favoriteAdded=true"
check "the Favorite control removes a saved media" "$out" "favoriteRemoved=true"
check "the Thumbnail control disables seek previews" "$out" "thumbnailOff=true"
check "the Thumbnail control can restore seek previews" "$out" "thumbnailOn=true"
check "the Properties control opens real current-media details" "$out" "properties=true"
check "the Bookmarks control opens the chapter and bookmark panel" "$out" "bookmarks=true"
check "the Replay control seeks the current media to its beginning" "$out" "replay=true"

echo "== preferences global screen"
out=$(run "1000:win.width=1048; win.height=865; Theme.store.mode='dark'; Theme.store.accent='#D37918'; settingsDialog.open()|+150:'globalFrame=' + win.width + 'x' + win.height + ' settingsBounds=' + Math.round(settingsDialog.x) + ',' + Math.round(settingsDialog.y) + ',' + Math.round(settingsDialog.width) + ',' + Math.round(settingsDialog.height)|+100:'settings=' + settingsDialog.visible + ' page=' + settingsDialog.page|+150:settingsDialog.categorySearch='audio'|+100:'search=' + settingsDialog.pagesInGroup(settingsDialog.categoryGroups[1].ids).length|+100:settingsDialog.categorySearch=''|+100:grab:$WORK/settings-global.png|+100:'languageChoice=' + settingsDialog.languageChoiceControl.current + '/' + settingsDialog.languageChoiceControl.enabled|+100:'logFieldWidth=' + settingsDialog.logFilePathField.width|+100:click-item:log-file-browse|+100:'logPickerOpens=' + settingsDialog.logFileDialogVisible|+100:settingsDialog.logFileDialogVisible=false|+100:settingsDialog.close(); Theme.store.mode='light'; Theme.store.accent='#2F5FC4'|+150:settingsDialog.open()|+100:'searchReset=' + (settingsDialog.categorySearch.length === 0)|+100:settingsDialog.close(); settingsDialog.open()|+100:'logTypes=' + typeof player.config('file-logging') + '/' + typeof player.config('logfile') + '/' + typeof player.config('log-verbose') + '/' + typeof player.config('verbose') + '/' + typeof player.config('qt-error-dialogs')|+100:'errorDialogRoundTrip=' + (() => { const old = player.config('qt-error-dialogs'); player.setConfig('qt-error-dialogs', false); const off = player.config('qt-error-dialogs') === false; player.setConfig('qt-error-dialogs', true); const on = player.config('qt-error-dialogs') === true; player.setConfig('qt-error-dialogs', old); return off && on })()|+100:'developerModeRoundTrip=' + (() => { const old=player.config('verbose'), mode=Theme.store.advancedOptions, toggle=settingsDialog.preferenceControl('developer-mode-toggle'); Theme.store.advancedOptions=true; player.setConfig('verbose',2); const on=player.config('verbose')===2 && toggle && toggle.checked; const controls=settingsDialog.optionVisible('verbose') && settingsDialog.optionVisible('logfile'); player.setConfig('verbose',0); const off=player.config('verbose')===0 && !toggle.checked; player.setConfig('verbose',old); Theme.store.advancedOptions=mode; return on && off && controls })()|+100:'globalAdvancedOptions=' + (() => { const names=['quiet','extraintf','logmode','stats'], old=names.map(n=>player.config(n)), mode=Theme.store.advancedOptions; Theme.store.advancedOptions=false; const hidden=names.every(n=>!settingsDialog.optionVisible(n)); Theme.store.advancedOptions=true; const shown=names.every(n=>settingsDialog.optionVisible(n)); const toggle=settingsDialog.preferenceControl('show-minor-warnings-toggle'); player.setConfig('quiet',true); const warningsOff=toggle && !toggle.checked; player.setConfig('quiet',false); const warningsOn=toggle && toggle.checked; const log=settingsDialog.preferenceControl('vlc-option-logmode'); player.setConfig('logmode','html'); const html=log && log.current==='html'; player.setConfig('logmode',old[2]); const stats=settingsDialog.preferenceControl('vlc-option-stats'); player.setConfig('stats',!old[3]); const statsChanged=stats && stats.current===!old[3]; names.forEach((n,i)=>player.setConfig(n,old[i])); Theme.store.advancedOptions=mode; return hidden && shown && warningsOff && warningsOn && html && statsChanged })()|+100:quit" "$E1")
check "global settings use the Figma 1048×865 frame" "$out" "globalFrame=1048x865"
check "settings fill the Figma frame edge to edge" "$out" "settingsBounds=0,0,1048,865"
check "log file path field keeps its intended 180 px width" "$out" "logFieldWidth=180"
check "the English-only language choice matches the Figma row without implying other translations" "$out" "languageChoice=en/false"
check "global settings opens on the General page" "$out" "settings=true page=general"
check "settings search filters the category list" "$out" "search=1"
check "settings search resets when reopened" "$out" "searchReset=true"
check "log-file Browse opens the native save picker" "$out" "logPickerOpens=true"
check "diagnostic fields map to VLC config options" "$out" "logTypes=boolean/string/number/number"
check "confirmation and error dialogs round-trip through VLC config" "$out" "errorDialogRoundTrip=true"
check "Developer mode controls VLC verbose logging and log paths stay editable" "$out" "developerModeRoundTrip=true"
check "advanced global controls map warning, extra-interface, log-format and statistics options to VLC" "$out" "globalAdvancedOptions=true"
if [ -s "$WORK/settings-global.png" ]; then echo "PASS  global settings screenshot written"; pass=$((pass + 1))
else echo "FAIL  global settings screenshot missing"; fail=$((fail + 1)); fi
out=$(run "1000:Theme.store.mode='dark'; 'darkHoverToken=' + Theme.hover + '/' + (Theme.hover !== Theme.surface)|+100:Theme.store.mode='light'; 'lightHoverToken=' + Theme.hover + '/' + (Theme.hover !== Theme.surface)|+100:quit" "$E1")
check "dark buttons use a distinct Figma hover color" "$out" "darkHoverToken=#191919/true"
check "light buttons use a distinct Figma hover color" "$out" "lightHoverToken=#b3b3b3/true"
preferenceOut=$(run "1000:win.width=1048; win.height=865; settingsDialog.open(); settingsDialog.page='audio'|+150:'simpleHidesAdvanced=' + !settingsDialog.optionVisible('aout')|+150:'autoDescriptionFallback=' + (() => { settingsDialog.page='interface'; const item=settingsDialog.preferenceControl('vlc-option-qt-name-in-title'); return player.configDescription('qt-name-in-title').length > 0 && item && item.info.length === 0 && item.effectiveInfo === player.configDescription('qt-name-in-title') })()|+150:settingsDialog.page='audio'|+150:settingsDialog.page='general'|+150:click-item:preferences-detail-level|+150:'buttonEnablesAdvanced=' + Theme.store.advancedOptions|+150:settingsDialog.page='audio'|+150:'advancedShowsOption=' + settingsDialog.optionVisible('aout')|+150:'advancedValueRead=' + (player.config('aout') !== undefined)|+150:'fractionalInput=' + settingsDialog.optionNumberValue('volume-step', '1.75')|+150:'integerInput=' + settingsDialog.optionNumberValue('network-caching', '1500')|+150:'boundControlRefresh=' + (() => { const control=settingsDialog.preferenceControl('vlc-option-volume-step'); const previous=player.config('volume-step'); player.setConfig('volume-step',1.625); const refreshed=control && Math.abs(Number(control.current)-1.625)<0.001; player.setConfig('volume-step',previous); return refreshed })()|+150:'floatRoundTrip=' + (() => { const previous = player.config('volume-step'); player.setConfig('volume-step', 1.75); const ok = Math.abs(player.config('volume-step') - 1.75) < 0.001; player.setConfig('volume-step', previous); return ok })()|+150:settingsDialog.page='general'|+150:click-item:preferences-detail-level|+150:'buttonReturnsToSimple=' + !Theme.store.advancedOptions|+150:settingsDialog.page='audio'|+150:'simpleKeepsValue=' + (player.config('volume-step') !== undefined && settingsDialog.optionVisible('volume-step') && !settingsDialog.optionVisible('aout'))|+150:Theme.store.advancedOptions=true; settingsDialog.page='general'|+100:'genericOptionTypes=' + [player.configType('brightness'),player.configType('network-caching'),player.configType('video-wallpaper'),player.configType('http-proxy')].join('/')|+100:settingsDialog.otherVlcOptionNameInput.text='brightness'; 'genericFloatLoaded=' + settingsDialog.loadOtherVlcOptionFromField() + '/' + settingsDialog.otherVlcOptionType + '/' + settingsDialog.optionVisible('other')|+100:'genericFloatRoundTrip=' + (() => { const previous = player.config('brightness'); settingsDialog.setOptionValue('other', 1.25); const ok = Math.abs(player.config('brightness') - 1.25) < 0.001; player.setConfig('brightness', previous); return ok })()|+100:settingsDialog.otherVlcOptionNameInput.text='not-a-real-vlc-option'; 'genericUnknownLoad=' + settingsDialog.loadOtherVlcOptionFromField()|+100:'genericUnknownRejected=' + (!settingsDialog.otherVlcOptionName.length && !settingsDialog.optionVisible('other'))|+100:settingsDialog.otherVlcOptionNameInput.text='--brightness'; 'genericInvalidLoad=' + settingsDialog.loadOtherVlcOptionFromField()|+100:'genericInvalidSyntaxRejected=' + (!settingsDialog.otherVlcOptionName.length && !settingsDialog.optionVisible('other'))|+150:settingsDialog.close()|+100:quit" "$E1")
check "VLC descriptions fill an empty preference help field" "$preferenceOut" "autoDescriptionFallback=true"
out=$(run "300:settingsDialog.open()|+200:'preferenceHelpCoverage=' + (() => { const names=['http-proxy-pwd','sout-chromecast-ip','sout-chromecast-port']; return names.every(name => { const item=settingsDialog.preferenceControl('vlc-option-'+name); return item && item.effectiveInfo.length > 0 }) })()|+100:'customHelpOverridesVlc=' + (() => { const item=settingsDialog.preferenceControl('vlc-option-video-on-top'); return item && item.info.length > 0 && item.effectiveInfo === item.info })()|+100:quit")
check "Proxy and Chromecast preferences have useful help text" "$out" "preferenceHelpCoverage=true"
check "Custom preference help takes precedence over VLC text" "$out" "customHelpOverridesVlc=true"
categoryOut=$(run "300:settingsDialog.open(); settingsDialog.page='video'|+200:'selectedCategoryIcons=' + (() => { const categories=[['general','preferences'],['interface','interface'],['privacy','privacy'],['controls','hotkeys'],['playback','playback'],['video','video'],['audio','audio'],['subtitles','subtitles'],['library','folder'],['network','streaming'],['performance','preferences'],['recording','record'],['extensions','plugins']]; return categories.every(pair => { settingsDialog.page=pair[0]; const icon=settingsDialog.preferenceControl('settings-category-icon-'+pair[0]); return icon && icon.name === pair[1]+'-active' }) })()|+100:quit")
check "Selected preference categories use the exact Figma active SVG" "$categoryOut" "selectedCategoryIcons=true"
check "simple preferences hide advanced VLC options" "$preferenceOut" "simpleHidesAdvanced=true"
check "the detail-level button enables advanced mode" "$preferenceOut" "buttonEnablesAdvanced=true"
check "the detail-level button switches back to simple mode" "$preferenceOut" "buttonReturnsToSimple=true"
check "advanced preferences reveal the mapped VLC option" "$preferenceOut" "advancedShowsOption=true"
check "advanced option values remain readable" "$preferenceOut" "advancedValueRead=true"
check "switching back to simple preserves the option value" "$preferenceOut" "simpleKeepsValue=true"
check "visible preference controls refresh when VLC config changes elsewhere" "$preferenceOut" "boundControlRefresh=true"
check "float VLC settings round-trip without losing fractional precision" "$preferenceOut" "floatRoundTrip=true"
check "advanced editor detects VLC option types" "$preferenceOut" "genericOptionTypes=float/integer/bool/string"
check "advanced editor loads an option by its exact VLC name" "$preferenceOut" "genericFloatLoaded=true/float/true"
check "advanced editor saves and restores a float option" "$preferenceOut" "genericFloatRoundTrip=true"
check "advanced editor rejects unknown VLC option names" "$preferenceOut" "genericUnknownRejected=true"
check "advanced editor rejects leading dashes" "$preferenceOut" "genericInvalidSyntaxRejected=true"
check "decimal VLC options parse fractional values within VLC bounds" "$preferenceOut" "fractionalInput=1.75"
check "integer VLC options keep whole-number input" "$preferenceOut" "integerInput=1500"
out=$(run "1000:settingsDialog.open(); settingsDialog.page='audio'|+150:'strictNumericValidation=' + (settingsDialog.optionNumberValue('volume-step','1.2oops')===undefined && settingsDialog.optionNumberValue('volume-step','')===undefined && settingsDialog.optionNumberValue('volume-step','1,75')===1.75 && settingsDialog.optionNumberValue('network-caching','1500.5')===undefined && settingsDialog.optionNumberValue('network-caching','9007199254740992')===undefined)|+100:quit")
check "VLC numeric fields reject malformed, empty, fractional integer and unsafe integer inputs" "$out" "strictNumericValidation=true"
out=$(run "1000:'advancedModePersists=' + Theme.store.advancedOptions|+100:Theme.store.advancedOptions=false|+100:quit")
check "the preference detail level persists across launches" "$out" "advancedModePersists=true"
echo "== privacy preferences map to stored behavior"
out=$(run "1000:win.width=1048; win.height=865; Theme.store.mode='dark'; Theme.store.accent='#D37918'; settingsDialog.open(); settingsDialog.page='privacy'|+150:'privacyTitle=' + settingsDialog.pageTitle|+100:'privacyOptions=' + ['qt-recentplay','qt-recentplay-filter','metadata-network-access','lastfm-username','lastfm-password','scrobbler-url'].every(x => player.config(x) !== undefined)|+100:'resumeDisable=' + (() => { const old=player.resumeEnabled(); player.setResumeEnabled(false); const disabled=!player.resumeEnabled(); player.setResumeEnabled(old); return disabled && player.resumeEnabled()===old })()|+100:'privacyConfigRoundTrip=' + (() => { const names=['qt-recentplay','qt-recentplay-filter','metadata-network-access','lastfm-username','lastfm-password','scrobbler-url']; const old=names.map(x=>player.config(x)); player.setConfig(names[0],false); player.setConfig(names[1],'sample'); player.setConfig(names[2],!old[2]); const ok=player.config(names[0])===false && player.config(names[1])==='sample' && player.config(names[2])===!old[2]; names.forEach((x,i)=>player.setConfig(x,old[i])); return ok })()|+100:grab:$WORK/settings-privacy.png|+100:settingsDialog.close()|+100:quit" "$E1")
check "privacy screen includes history, metadata and Last.fm VLC options" "$out" "privacyOptions=true"
check "disabling playback position memory takes effect and restores its setting" "$out" "resumeDisable=true"
check "privacy VLC options round-trip through VLC configuration" "$out" "privacyConfigRoundTrip=true"
if [ -s "$WORK/settings-privacy.png" ]; then echo "PASS  privacy preferences screenshot written"; pass=$((pass + 1))
else echo "FAIL  privacy preferences screenshot missing"; fail=$((fail + 1)); fi
out=$(run "1000:settingsDialog.open(); settingsDialog.page='privacy'|+100:'resumeSwitchUpdates=' + (() => { const old=player.resumeEnabled(), oldMode=Theme.store.resumeMode; settingsDialog.setResumeMemoryEnabled(!old); const changed=settingsDialog.resumeMemoryEnabled===!old; settingsDialog.setResumeMode(oldMode); return changed && settingsDialog.resumeMemoryEnabled===old })()|+100:'lastFmSwitchUpdates=' + (() => { const user=player.config('lastfm-username'), password=player.config('lastfm-password'); settingsDialog.setOptionValue('lastfm-username','neo-smoke-user'); settingsDialog.setOptionValue('lastfm-password','neo-smoke-password'); const enabled=settingsDialog.lastFmSubmissionEnabled; settingsDialog.setLastFmEnabled(false); const disabled=!settingsDialog.lastFmSubmissionEnabled && player.config('lastfm-username')==='' && player.config('lastfm-password')===''; settingsDialog.setOptionValue('lastfm-username',user); settingsDialog.setOptionValue('lastfm-password',password); settingsDialog.syncPrivacySettings(); return enabled && disabled })()|+100:settingsDialog.close()|+100:quit")
check "the resume-memory switch updates immediately and stays in sync with Playback" "$out" "resumeSwitchUpdates=true"
check "the Last.fm switch follows credentials and clears them when disabled" "$out" "lastFmSwitchUpdates=true"
echo "== library preferences control VLC and the local browser"
out=$(run "1000:win.width=1048; win.height=865; Theme.store.mode='dark'; Theme.store.accent='#D37918'; settingsDialog.open(); settingsDialog.page='library'|+150:'libraryTitle=' + settingsDialog.pageTitle|+100:'libraryGeometry=' + (()=>{const p=o=>o.mapToItem(win.contentItem,0,0); const s=p(settingsDialog.categorySearchInput), n=p(settingsDialog.settingsCategoryPanel), c=p(settingsDialog.settingsPageContent); const near=(a,b)=>Math.abs(a-b)<1; return near(s.x,10)&&near(s.y,9)&&near(settingsDialog.categorySearchInput.width,200)&&near(n.x,10)&&near(n.y,60)&&near(settingsDialog.settingsCategoryPanel.width,200)&&near(c.x,242)&&near(c.y,72)})()|+100:'libraryOptions=' + ['one-instance','one-instance-when-started-from-file','playlist-enqueue','recursive','show-hiddenfiles','metadata-network-access','media-library','ignore-filetypes','playlist-tree'].every(x => player.config(x) !== undefined)|+100:'libraryConfigRoundTrip=' + (() => { const names=['one-instance','one-instance-when-started-from-file','playlist-enqueue','recursive','show-hiddenfiles','metadata-network-access','media-library','ignore-filetypes']; const old=names.map(x=>player.config(x)); player.setConfig(names[0],true); player.setConfig(names[1],false); player.setConfig(names[2],true); player.setConfig(names[3],'collapse'); player.setConfig(names[4],true); player.setConfig(names[5],true); player.setConfig(names[6],true); player.setConfig(names[7],'tmp,aux'); const ok=player.config(names[0])===true && player.config(names[1])===false && player.config(names[2])===true && player.config(names[3])==='collapse' && player.config(names[4])===true && player.config(names[5])===true && player.config(names[6])===true && player.config(names[7])==='tmp,aux'; names.forEach((x,i)=>player.setConfig(x,old[i])); return ok })()|+100:settingsDialog.setOptionValue('show-hiddenfiles',false); libraryPanel.folder=platform.fileUrl('$WORK/music'); libraryPanel.section='folder'|+350:'hiddenFilesInitiallyHidden=' + !libraryPanel.hasFileName('.NeoHiddenTest.mkv')|+100:settingsDialog.setOptionValue('show-hiddenfiles',true)|+350:'hiddenFilesShow=' + (Theme.store.showHiddenFiles && libraryPanel.hasFileName('.NeoHiddenTest.mkv'))|+100:settingsDialog.setOptionValue('show-hiddenfiles',false); Theme.store.showHiddenFiles=false; 'hiddenFilesRestore=' + (player.config('show-hiddenfiles')===false)|+100:(() => { settingsDialog.setOptionValue('one-instance',false); settingsDialog.setOptionValue('one-instance-when-started-from-file',false); settingsDialog.setOptionValue('playlist-enqueue',false); settingsDialog.setOptionValue('recursive','expand'); settingsDialog.setOptionValue('show-hiddenfiles',false); settingsDialog.setOptionValue('metadata-network-access',false); settingsDialog.setOptionValue('media-library',true); const labels=[]; const pending=[settingsDialog.contentItem]; while(pending.length){const item=pending.pop(); if(typeof item.text==='string') labels.push(item.text); for(let i=0;i<(item.children?item.children.length:0);i++) pending.push(item.children[i])} const recursive=settingsDialog.preferenceControl('vlc-option-recursive'); const copyMatches=labels.indexOf('Opening Files')>=0 && recursive.choices.some(choice=>choice.label==='Include subfolders'); return 'libraryFigmaValues=' + (player.config('one-instance')===false && player.config('one-instance-when-started-from-file')===false && player.config('playlist-enqueue')===false && player.config('recursive')==='expand' && player.config('show-hiddenfiles')===false && player.config('metadata-network-access')===false && player.config('media-library')===true) + ';libraryFigmaCopy=' + copyMatches })()|+100:grab:$WORK/settings-library.png|+100:settingsDialog.close()|+100:quit" "$E1")
check "library preferences use the Figma page title" "$out" "libraryTitle=Playlists, Folders & Files"
check "library preferences header, navigation and content align with the 1048x865 Figma frame" "$out" "libraryGeometry=true"
check "library preferences screenshot uses the visible Figma values and exact Figma labels" "$out" "libraryFigmaValues=true;libraryFigmaCopy=true"
check "opening, metadata and artwork settings map to VLC options" "$out" "libraryOptions=true"
check "folder, queue, metadata and media-library options round-trip" "$out" "libraryConfigRoundTrip=true"
check "hidden files stay filtered when the preference is off" "$out" "hiddenFilesInitiallyHidden=true"
check "the hidden-files preference updates the local folder browser" "$out" "hiddenFilesShow=true"
check "the hidden-files preference restores to its original value" "$out" "hiddenFilesRestore=true"
pinSandbox="$WORK/pinned-folder-sandbox"
mkdir -p "$pinSandbox/config/vlc-neo"
printf '[appearance]\nonboarded=true\n' > "$pinSandbox/config/vlc-neo/neo.conf"
NEO_SANDBOX="$pinSandbox" out=$(run "500:Theme.store.pinned=''; player.openLocation('$E1',true)|+1400:win.folderSidebarOpen=true|+100:click-item:library-folder-pin|+100:'libraryFolderPinned=' + (libraryPanel.pinnedList().includes(platform.localPath(libraryPanel.folder)))|+100:win.libraryOpen=true; win.folderSidebarOpen=false; libraryPanel.section='home'|+250:click-item:pinned-library-folder-0|+250:'pinnedFolderNavigation=' + (libraryPanel.section==='folder' && platform.localPath(libraryPanel.folder)===libraryPanel.pinnedList()[0])|+100:quit" "$E1")
check "the folder sidebar pins the current folder" "$out" "libraryFolderPinned=true"
check "the pinned folder opens from the Home library sidebar" "$out" "pinnedFolderNavigation=true"
NEO_SANDBOX="$pinSandbox" out=$(run "700:'pinnedFolderPersists=' + (libraryPanel.pinnedList().length===1)|+100:Theme.store.pinned=''|+100:quit")
check "pinned library folders persist across VLC launches" "$out" "pinnedFolderPersists=true"
libraryOptionsSandbox="$WORK/library-options-sandbox"
mkdir -p "$libraryOptionsSandbox/config/vlc-neo"
printf '[appearance]\nonboarded=true\n' > "$libraryOptionsSandbox/config/vlc-neo/neo.conf"
NEO_SANDBOX="$libraryOptionsSandbox" out=$(run "500:settingsDialog.open(); settingsDialog.page='library'|+200:'libraryChoiceControls=' + (!!settingsDialog.preferenceControl('vlc-option-recursive') && !!settingsDialog.preferenceControl('vlc-option-metadata-network-access'))|+100:'instanceOptionDependency=' + (() => { const parent=settingsDialog.preferenceControl('vlc-option-one-instance'), child=settingsDialog.preferenceControl('vlc-option-one-instance-when-started-from-file'); const oldParent=parent.current, oldChild=child.current; child.save(true); parent.save(false); const disabled=!child.enabled && Math.abs(child.opacity-0.45)<0.01 && player.config('one-instance-when-started-from-file')===true; parent.save(true); const enabled=child.enabled && child.opacity===1 && player.config('one-instance-when-started-from-file')===true; parent.save(oldParent); child.save(oldChild); return disabled && enabled })()|+100:'recursiveChoices=' + (() => { const control=settingsDialog.preferenceControl('vlc-option-recursive'); let ok=true; for (const value of ['none','collapse','expand']) { settingsDialog.setOptionValue('recursive',value); ok=ok && player.config('recursive')===value && control.current===value } return ok })()|+100:'metadataChoice=' + (() => { const control=settingsDialog.preferenceControl('vlc-option-metadata-network-access'); settingsDialog.setOptionValue('metadata-network-access',false); const disabled=player.config('metadata-network-access')===false && control.current===false; settingsDialog.setOptionValue('metadata-network-access',true); return disabled && player.config('metadata-network-access')===true && control.current===true })()|+100:quit")
check "library preference controls expose both shared settings" "$out" "libraryChoiceControls=true"
check "file-manager instance option follows the one-instance switch and keeps its value" "$out" "instanceOptionDependency=true"
check "folder recursion choices write VLC options through their controls" "$out" "recursiveChoices=true"
check "metadata lookup choice writes VLC's shared privacy option" "$out" "metadataChoice=true"
NEO_SANDBOX="$libraryOptionsSandbox" out=$(run "700:'libraryChoicesPersist=' + (player.config('recursive')==='expand' && player.config('metadata-network-access')===true)|+100:quit")
check "folder recursion and metadata choices persist after relaunch" "$out" "libraryChoicesPersist=true"
NEO_SANDBOX="$libraryOptionsSandbox" out=$(run "500:mediaLibrary.clearLibrary(); player.setConfig('recursive','none'); mediaLibrary.addFolder(platform.fileUrl('$WORK/recursive-root'))|+1400:mediaLibrary.model.view='videos'|+250:'recursiveNoneIndexesNested=' + (!mediaLibrary.model.loading && mediaLibrary.indexedCount===1 && mediaLibrary.model.itemCount()===1)|+100:mediaLibrary.clearLibrary(); player.setConfig('recursive','collapse'); mediaLibrary.addFolder(platform.fileUrl('$WORK/recursive-root'))|+1400:mediaLibrary.model.view='videos'|+250:'recursiveCollapseIndexesNested=' + (!mediaLibrary.model.loading && mediaLibrary.indexedCount===1 && mediaLibrary.model.itemCount()===1)|+100:mediaLibrary.clearLibrary(); player.setConfig('recursive','expand'); mediaLibrary.addFolder(platform.fileUrl('$WORK/recursive-root'))|+1400:mediaLibrary.model.view='videos'|+250:'recursiveExpandIndexesNested=' + (!mediaLibrary.model.loading && mediaLibrary.indexedCount===1 && mediaLibrary.model.itemCount()===1)|+100:quit")
check "Neo's library indexes nested media with VLC folder recursion disabled" "$out" "recursiveNoneIndexesNested=true"
check "Neo's library indexes nested media with VLC folder recursion collapsed" "$out" "recursiveCollapseIndexesNested=true"
check "Neo's library indexes nested media with VLC folder recursion expanded" "$out" "recursiveExpandIndexesNested=true"
if [ -s "$WORK/settings-library.png" ]; then echo "PASS  library preferences screenshot written"; pass=$((pass + 1))
else echo "FAIL  library preferences screenshot missing"; fail=$((fail + 1)); fi
echo "== network preferences expose proxy and TLS security options"
out=$(run "1000:win.width=1048; win.height=865; Theme.store.mode='dark'; Theme.store.accent='#D37918'; Theme.store.advancedOptions=false; settingsDialog.open(); settingsDialog.page='network'|+150:'networkTitle=' + settingsDialog.pageTitle|+100:'networkOptions=' + ['file-caching','disc-caching','network-caching','live-caching','ipv4-timeout','http-proxy','http-proxy-pwd','http-reconnect','socks','socks-user','socks-pwd','gnutls-system-trust','gnutls-dir-trust','gnutls-priorities','mtu','network-synchronisation'].every(x => player.config(x) !== undefined)|+100:'networkAdvanced=' + (!settingsDialog.optionVisible('socks') && !settingsDialog.optionVisible('gnutls-dir-trust') && settingsDialog.optionVisible('gnutls-priorities') && settingsDialog.optionVisible('http-proxy'))|+100:'bufferingProfiles=' + (() => { const names=['file-caching','disc-caching','network-caching','live-caching']; const old=names.map(x=>player.config(x)); settingsDialog.setBufferingProfile('Low latency'); const lowControls=names.map(name=>settingsDialog.preferenceControl('vlc-option-'+name)); const low=player.config('file-caching')===200 && player.config('disc-caching')===200 && player.config('live-caching')===200 && player.config('network-caching')===666 && lowControls.map(control=>control.current).join(',')==='200,200,666,200' && lowControls.every(control=>!control.enabled && control.displayValue===''); settingsDialog.setBufferingProfile('Normal'); const normalControls=names.map(name=>settingsDialog.preferenceControl('vlc-option-'+name)); const normal=player.config('file-caching')===300 && player.config('disc-caching')===300 && player.config('live-caching')===300 && player.config('network-caching')===1000 && normalControls.map(control=>control.current).join(',')==='300,300,1000,300' && normalControls.every(control=>!control.enabled && control.displayValue===''); settingsDialog.setBufferingProfile('Custom'); const customControls=names.map(name=>settingsDialog.preferenceControl('vlc-option-'+name)); const custom=customControls.every(control=>control.enabled && control.displayValue===String(control.current)); names.forEach((x,i)=>player.setConfig(x,old[i])); settingsDialog.syncBufferingProfile(); const resynced=names.every(name=>settingsDialog.preferenceControl('vlc-option-'+name).current===player.config(name)); return low && normal && custom && resynced })()|+100:'networkConfigRoundTrip=' + (() => { const names=['network-caching','ipv4-timeout','http-proxy','http-proxy-pwd','http-reconnect','socks','socks-user','socks-pwd','gnutls-system-trust','gnutls-dir-trust','gnutls-priorities','mtu','network-synchronisation']; const old=names.map(x=>player.config(x)); const values=[1350,6500,'http://127.0.0.1:8111','proxy-secret',true,'127.0.0.1:1080','neo-test','secret-test',false,'/tmp/neo-trust','SECURE128',1450,true]; names.forEach((x,i)=>player.setConfig(x,values[i])); const ok=names.every((x,i)=>player.config(x)===values[i]); names.forEach((x,i)=>player.setConfig(x,old[i])); return ok })()|+100:settingsDialog.setBufferingProfile('Normal')|+100:grab:$WORK/settings-network.png|+100:settingsDialog.close()|+100:quit" "$E1")
check "network preferences use their exact Figma title" "$out" "networkTitle=Network Connections & Security"
check "proxy, TLS trust, cipher and connection options map to VLC" "$out" "networkOptions=true"
check "advanced network options stay hidden in Simple mode" "$out" "networkAdvanced=true"
check "buffering profiles update all four VLC cache options" "$out" "bufferingProfiles=true"
check "network and TLS options round-trip through VLC configuration" "$out" "networkConfigRoundTrip=true"
if [ -s "$WORK/settings-network.png" ]; then echo "PASS  network preferences screenshot written"; pass=$((pass + 1))
else echo "FAIL  network preferences screenshot missing"; fail=$((fail + 1)); fi
echo "== performance preferences expose decoding and playback controls"
out=$(run "1000:win.width=1048; win.height=865; Theme.store.mode='dark'; Theme.store.accent='#D37918'; Theme.store.advancedOptions=false; settingsDialog.open(); settingsDialog.page='performance'|+150:'performanceTitle=' + settingsDialog.pageTitle|+100:'performanceOptions=' + (() => { const names=['avcodec-hw','postproc-q','avcodec-skiploopfilter','avcodec-threads','drop-late-frames','rt-priority','rt-offset','reset-plugins-cache','encoder','codec','clock-synchro','clock-jitter','cr-average','avcodec-fast','avcodec-hurry-up','avcodec-error-resilience','avcodec-workaround-bugs','avcodec-options','postproc-name','sout-transcode-threads','sout-transcode-pool-size']; const required=['avcodec-hw','avcodec-threads','drop-late-frames','codec']; return required.every(x => player.config(x) !== undefined) && names.every(x => player.config(x) !== undefined ? true : !settingsDialog.optionVisible(x)) })()|+100:'performanceVisibility=' + (!settingsDialog.optionVisible('avcodec-fast') && settingsDialog.optionVisible('drop-late-frames') && settingsDialog.optionVisible('codec'))|+100:'performanceConfigRoundTrip=' + (() => { const names=['avcodec-hw','postproc-q','avcodec-skiploopfilter','avcodec-threads','drop-late-frames','rt-priority','rt-offset','codec','encoder','clock-synchro','clock-jitter','cr-average']; const values=['none',2,1,2,false,true,3,'','',0,250,20]; const supported=names.map((name,i)=>({name,value:values[i],old:player.config(name)})).filter(option => option.old !== undefined); supported.forEach(option => player.setConfig(option.name,option.value)); const ok=supported.length >= 4 && supported.every(option => player.config(option.name)===option.value); supported.forEach(option => player.setConfig(option.name,option.old)); return ok })()|+100:'pluginRescanFlag=' + (() => { const old=player.config('reset-plugins-cache'); player.setConfig('reset-plugins-cache',true); const ok=player.config('reset-plugins-cache')===true; player.setConfig('reset-plugins-cache',old); return ok })()|+100:grab:$WORK/settings-performance.png|+100:click-item:performance-advanced-options|+100:'performanceAdvanced=' + (Theme.store.advancedOptions && settingsDialog.optionVisible('avcodec-fast'))|+100:settingsDialog.close()|+100:quit" "$E1")
check "performance preferences use the exact Figma page title" "$out" "performanceTitle=Performance Settings"
check "decoding, playback, developer and advanced options map to VLC" "$out" "performanceOptions=true"
check "advanced decoder tuning stays hidden in Simple mode" "$out" "performanceVisibility=true"
check "performance VLC options round-trip through configuration" "$out" "performanceConfigRoundTrip=true"
check "plugin rescan sets the VLC cache-reset option" "$out" "pluginRescanFlag=true"
check "Advanced Options reveals decoder tuning controls" "$out" "performanceAdvanced=true"
performanceSandbox="$WORK/performance-persistence-sandbox"
mkdir -p "$performanceSandbox/config/vlc-neo"
printf '[appearance]\nonboarded=true\n' > "$performanceSandbox/config/vlc-neo/neo.conf"
NEO_SANDBOX="$performanceSandbox" out=$(run "500:player.setConfig('avcodec-hw','none'); 'softwareDecoderSaved=' + (player.config('avcodec-hw') === 'none')|+100:quit")
check "software decoding preference saves through VLC" "$out" "softwareDecoderSaved=true"
NEO_SANDBOX="$performanceSandbox" out=$(run "2200:'softwareDecoderRestored=' + (player.config('avcodec-hw') === 'none')|+100:'softwareDecodedVideoPlays=' + (player.config('avcodec-hw') === 'none' && player.hasVideo && player.state === 2)|+100:quit" "$E1")
check "software decoding preference persists across VLC restarts" "$out" "softwareDecoderRestored=true"
check "VLC plays video after restoring software-only decoding" "$out" "softwareDecodedVideoPlays=true"
if [ -s "$WORK/settings-performance.png" ]; then echo "PASS  performance preferences screenshot written"; pass=$((pass + 1))
else echo "FAIL  performance preferences screenshot missing"; fail=$((fail + 1)); fi
echo "== recording, casting and streaming preferences"
out=$(run "1000:win.width=1048; win.height=865; Theme.store.mode='dark'; Theme.store.accent='#D37918'; Theme.store.advancedOptions=false; settingsDialog.open(); settingsDialog.page='recording'|+150:'recordingTitle=' + settingsDialog.pageTitle|+100:'recordingOptions=' + ['input-record-path','input-record-native','sout-chromecast-conversion-quality','sout-display','sout-audio','sout-video','sout-spu','sout-x264-preset','sout-x264-tune','sout-transcode-vcodec','sout-transcode-vb','sout-transcode-fps','sout-transcode-acodec','sout-transcode-ab','sout-transcode-samplerate','sout-chromecast-ip','sout-chromecast-port'].every(x => player.config(x) !== undefined)|+100:'castQualityFigmaValue=' + (() => { const c=settingsDialog.preferenceControl('vlc-option-sout-chromecast-conversion-quality'); return !!c && c.current === 1 && c.choices.some(x=>x.label==='Automatic' && x.value===1) && c.choices.map(x=>x.value).sort().join(',')==='0,1,2,3' })()|+100:'encodingPresetFigmaValue=' + (() => { const c=settingsDialog.preferenceControl('vlc-option-sout-x264-preset'); return !!c && c.current === '' && c.choiceDisplayValue === 'medium' && c.choices.some(x=>x.label==='Medium' && x.value==='medium') })()|+100:'recordingVisibility=' + (!settingsDialog.optionVisible('sout-transcode-vcodec') && settingsDialog.optionVisible('sout-display') && settingsDialog.optionVisible('input-record-path'))|+100:grab:$WORK/settings-recording.png|+100:settingsDialog.close()|+100:quit")
check "recording preferences match the Figma section title" "$out" "recordingTitle=Recording, Casting & Streaming Out"
check "recording and streaming controls map to VLC options" "$out" "recordingOptions=true"
check "cast quality shows Figma's Automatic label for VLC's default mode and keeps all four real values" "$out" "castQualityFigmaValue=true"
check "encoding preset shows Figma's Medium label for VLC's unchanged empty default" "$out" "encodingPresetFigmaValue=true"
check "advanced transcoding options stay hidden in Simple mode" "$out" "recordingVisibility=true"
out=$(run "1000:'recordingRoundTrip=' + (() => { const names=['input-record-path','input-record-native','sout-chromecast-conversion-quality','sout-display','sout-audio','sout-video','sout-spu','sout-x264-preset','sout-x264-tune','sout-transcode-vcodec','sout-transcode-vb','sout-transcode-fps','sout-transcode-acodec','sout-transcode-ab','sout-transcode-samplerate','sout-chromecast-ip','sout-chromecast-port']; const old=names.map(x=>player.config(x)); const values=['/tmp/neo-recordings',!old[1],(Number(old[2])+1)%4,!old[3],!old[4],!old[5],!old[6],'veryfast','zerolatency','h264',1400,'25','mp4a',160,44100,'192.0.2.10',8009]; names.forEach((x,i)=>player.setConfig(x,values[i])); const ok=names.every((x,i)=>player.config(x)===values[i]); names.forEach((x,i)=>player.setConfig(x,old[i])); return ok })()|+100:quit")
check "recording, casting and stream-encoding values round-trip through VLC" "$out" "recordingRoundTrip=true"
if [ -s "$WORK/settings-recording.png" ]; then echo "PASS  recording preferences screenshot written"; pass=$((pass + 1))
else echo "FAIL  recording preferences screenshot missing"; fail=$((fail + 1)); fi
out=$(run "900:'rendererDiscoverySupported=' + player.rendererDiscoverySupported|+100:'rendererDiscoveryStarted=' + player.discoverRenderers(true)|+250:'rendererDeviceModel=' + (player.rendererDevices !== undefined && typeof player.rendererDevices.length === 'number')|+100:'rendererDiscoveryStopped=' + player.discoverRenderers(false)|+100:'rendererDevicesCleared=' + (player.rendererDevices.length===0)|+100:'rendererCapabilityHandled=' + (player.rendererDiscoverySupported ? player.discoverRenderers(true) : !player.discoverRenderers(true))|+100:player.discoverRenderers(false)|+100:quit")
check "renderer discovery succeeds when supported and degrades cleanly otherwise" "$out" "rendererCapabilityHandled=true"
check "discovered renderers are exposed to QML and cleared after stopping" "$out" "rendererDeviceModel=true"
check "stopping renderer discovery leaves no stale devices" "$out" "rendererDevicesCleared=true"
out=$(run "200:onboarding.close(); castDialog.open()|+150:'castDiscoveryLease=' + rendererDiscoveryClients.join('/')|+100:settingsDialog.open()|+200:'overlappingDiscoveryLeases=' + rendererDiscoveryClients.join('/')|+100:castDialog.close()|+150:'settingsKeepsDiscovery=' + (rendererDiscoveryClients.length===1 && rendererDiscoveryClients[0]==='settings-dialog')|+100:settingsDialog.close()|+150:'discoveryStopsAfterLastDialog=' + (rendererDiscoveryClients.length===0)|+100:quit")
check "Cast and Settings dialogs acquire independent renderer-discovery leases" "$out" "overlappingDiscoveryLeases=cast-dialog/settings-dialog"
check "closing the Cast dialog keeps discovery active for Settings" "$out" "settingsKeepsDiscovery=true"
check "renderer discovery stops after its final dialog closes" "$out" "discoveryStopsAfterLastDialog=true"
out=$(run "200:'castRendererReadyStates=' + [castDialog.rendererReadyForPlayback({selected:true,status:'Connected'}),castDialog.rendererReadyForPlayback({selected:true,status:'Playing'}),castDialog.rendererReadyForPlayback({selected:true,status:'Paused'}),castDialog.rendererReadyForPlayback({selected:true,status:'Connecting'}),castDialog.rendererReadyForPlayback({selected:true,status:'Stopped'}),castDialog.rendererReadyForPlayback({selected:false,status:'Connected'})].join('/')|+100:quit")
check "the cast dialog accepts VLC's connected Chromecast state and active DLNA states" "$out" "castRendererReadyStates=true/true/true/false/false/false"
echo "== VLC records the playing audio and video"
mkdir -p "$WORK/recordings"
out=$(run "6000:player.setConfig('input-record-path','$WORK/recordings'); player.toggleRecord()|+5000:'recordingActive=' + player.recording + '/' + (player.time > 7000)|+100:player.toggleRecord()|+2500:'recordingStopped=' + !player.recording|+100:quit" --avcodec-hw=none "$WORK/recording-test.mkv")
check "the Record action remains active while VLC advances the media" "$out" "recordingActive=true/true"
check "the Record action stops on a second toggle" "$out" "recordingStopped=true"
recordedFile=$(find "$WORK/recordings" -maxdepth 1 -type f -name 'vlc-record-*' -print -quit)
if [ -n "$recordedFile" ]; then
    recordedDuration=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$recordedFile" 2>/dev/null || true)
    recordedVideo=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "$recordedFile" 2>/dev/null || true)
    recordedAudio=$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of csv=p=0 "$recordedFile" 2>/dev/null || true)
else
    recordedDuration=""
    recordedVideo=""
    recordedAudio=""
fi
if [ -n "$recordedDuration" ] && awk -v duration="$recordedDuration" 'BEGIN { exit !(duration >= 3.5) }' \
        && [ "$recordedVideo" = "h264" ] && [ "$recordedAudio" = "aac" ]; then
    echo "PASS  VLC produced a multi-second H.264/AAC recording"; pass=$((pass + 1))
else
    echo "FAIL  recording output is too short or lacks expected streams (duration=$recordedDuration video=$recordedVideo audio=$recordedAudio)"; fail=$((fail + 1))
fi
mkdir -p "$WORK/recordings-with-subtitles"
out=$(run "6000:player.setConfig('input-record-path','$WORK/recordings-with-subtitles'); player.selectTrack('spu',2)|+100:'recordingSubtitleSelected=' + player.tracks('spu').some(track => track.id === 2 && track.selected)|+100:player.toggleRecord()|+4000:'recordingWithSubtitleActive=' + player.recording + '/' + (player.time > 9000)|+100:player.toggleRecord()|+2000:'recordingWithSubtitleStopped=' + !player.recording|+100:quit" "$WORK/recording-subtitle.mkv")
check "VLC can select a subtitle track before recording" "$out" "recordingSubtitleSelected=true"
check "Record captures audio and video while a subtitle track is selected" "$out" "recordingWithSubtitleActive=true/true"
check "Record stops cleanly with a subtitle track selected" "$out" "recordingWithSubtitleStopped=true"
subtitleRecording=$(find "$WORK/recordings-with-subtitles" -maxdepth 1 -type f -name 'vlc-record-*' -print -quit)
if [ -n "$subtitleRecording" ] \
        && [ "$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "$subtitleRecording" 2>/dev/null)" = "h264" ] \
        && [ "$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of csv=p=0 "$subtitleRecording" 2>/dev/null)" = "aac" ]; then
    echo "PASS  recording with a selected subtitle track contains playable H.264/AAC media"; pass=$((pass + 1))
else
    echo "FAIL  recording with a selected subtitle track lacks playable H.264/AAC media"; fail=$((fail + 1))
fi
echo "== controls preferences follow installed VLC options"
out=$(run "1000:win.width=1048; win.height=865; Theme.store.mode='dark'; Theme.store.accent='#D37918'; settingsDialog.open(); settingsDialog.page='controls'|+150:'controlsTitle=' + settingsDialog.pageTitle|+100:'controlsOptions=' + ['hotkeys-y-wheel-mode','hotkeys-x-wheel-mode','extrashort-jump-size','short-jump-size','medium-jump-size','long-jump-size','extraintf','http-port','http-password'].every(x => player.config(x) !== undefined)|+100:'controlsFieldWidth=' + ['extrashort-jump-size','short-jump-size','medium-jump-size','long-jump-size','hotkeys-y-wheel-mode','hotkeys-x-wheel-mode','http-port'].every(x => settingsDialog.preferenceControlWidth('vlc-option-' + x) === 320)|+100:'controlsSkipUnit=' + settingsDialog.preferenceControlDisplayValue('vlc-option-extrashort-jump-size').endsWith(' s')|+100:'configuredJumpAmounts=' + (win.jumpStep(false,true)===Number(player.config('extrashort-jump-size'))*1000 && win.jumpStep(true,false)===Number(player.config('long-jump-size'))*1000)|+100:'controlsConfigRoundTrip=' + (() => { const names=['hotkeys-y-wheel-mode','hotkeys-x-wheel-mode','extrashort-jump-size','short-jump-size','medium-jump-size','long-jump-size','extraintf','http-port']; const old=names.map(x=>player.config(x)); const click=Theme.store.clickToPause, dbl=Theme.store.doubleClickFullscreen; player.setConfig(names[0],2); player.setConfig(names[1],3); settingsDialog.setScrollDirectionReverse(false); const normalModes=player.config(names[0])===2 && player.config(names[1])===2; settingsDialog.setScrollDirectionReverse(true); const reverseModes=player.config(names[0])===3 && player.config(names[1])===3; const yWheel=settingsDialog.preferenceControl('vlc-option-hotkeys-y-wheel-mode'), xWheel=settingsDialog.preferenceControl('vlc-option-hotkeys-x-wheel-mode'); yWheel.save(2); xWheel.save(2); const normalDirectionSync=!settingsDialog.reverseScrollDirection; xWheel.save(3); const reverseDirectionSync=settingsDialog.reverseScrollDirection; player.setConfig(names[0],0); player.setConfig(names[1],-1); settingsDialog.syncScrollDirection(); const idleReverseDisabled=!settingsDialog.preferenceControl('reverse-scroll-direction').enabled && !settingsDialog.reverseScrollDirection; player.setConfig(names[2],4); player.setConfig(names[3],12); player.setConfig(names[4],65); player.setConfig(names[5],305); player.setConfig(names[6],'http'); player.setConfig(names[7],8181); Theme.store.clickToPause=false; Theme.store.doubleClickFullscreen=false; const ok=normalModes && reverseModes && normalDirectionSync && reverseDirectionSync && idleReverseDisabled && player.config(names[2])===4 && player.config(names[3])===12 && player.config(names[4])===65 && player.config(names[5])===305 && String(player.config(names[6])).includes('http') && player.config(names[7])===8181 && !Theme.store.clickToPause && !Theme.store.doubleClickFullscreen; names.forEach((x,i)=>player.setConfig(x,old[i])); settingsDialog.syncScrollDirection(); Theme.store.clickToPause=click; Theme.store.doubleClickFullscreen=dbl; return ok })()|+100:grab:$WORK/settings-controls.png|+100:settingsDialog.close()|+100:quit" "$E1")
check "controls use the exact Figma page title" "$out" "controlsTitle=Mouse, Keyboard & Remote Controls"
check "mouse, skip and remote controls use installed VLC options" "$out" "controlsOptions=true"
check "control settings fields match the Figma 320 px width" "$out" "controlsFieldWidth=true"
check "skip amounts display seconds units" "$out" "controlsSkipUnit=true"
check "keyboard seek amounts read the configured VLC jump sizes" "$out" "configuredJumpAmounts=true"
check "mouse modes, skip amounts, reverse-scroll sync and web remote config round-trip" "$out" "controlsConfigRoundTrip=true"
if [ -s "$WORK/settings-controls.png" ]; then echo "PASS  controls preferences screenshot written"; pass=$((pass + 1))
else echo "FAIL  controls preferences screenshot missing"; fail=$((fail + 1)); fi
echo "== keyboard shortcuts can be reassigned, persisted and reset"
out=$(run "1000:'shortcutInventory=' + (() => { const ids=Object.keys(Theme.defaultShortcuts); return ids.length === shortcutsDialog.shortcuts.length && ids.every(id => shortcutsDialog.shortcuts.some(item => item.id === id) && Theme.shortcutKeys(id).every(chord => Theme.shortcutAction(chord) === id)) })()|+100:quit")
check "every default shortcut is listed and all aliases resolve to its action" "$out" "shortcutInventory=true"
out=$(run "1000:shortcutsDialog.open()|+250:grab:$WORK/shortcut-editor.png|+100:shortcutsDialog.beginRecording('playPause')|+150:key:Ctrl+Space|+150:'shortcutCaptured=' + (shortcutsDialog.neoShortcutText('playPause')==='Ctrl+Space' && Theme.shortcutText('playPause')==='Space')|+100:shortcutsDialog.saveChanges(); 'shortcutSaved=' + (Theme.shortcutText('playPause')==='Ctrl+Space')|+100:shortcutsDialog.open()|+150:shortcutsDialog.beginRecording('mute')|+150:key:Ctrl+M|+100:click-item:shortcut-cancel|+100:'shortcutCancel=' + (Theme.shortcutText('mute')==='M')|+100:win.focusKeys(); player.togglePause()|+300:'pausedBeforeRemappedKey=' + (player.state===3)|+100:key:Space|+100:'oldShortcutSuppressed=' + (player.state===3)|+100:key:Ctrl+Space|+150:'remappedShortcutPlays=' + (player.state===2)|+100:shortcutsDialog.open()|+250:shortcutsDialog.beginRecording('mute')|+100:key:Ctrl+Space|+100:'shortcutConflict=' + (shortcutsDialog.captureError.length>0 && Theme.shortcutText('mute')==='M')|+100:quit" "$E1")
check "the shortcut editor stages key combinations until Save" "$out" "shortcutCaptured=true"
check "Save commits the customized Neo shortcut" "$out" "shortcutSaved=true"
check "Cancel discards a staged shortcut change" "$out" "shortcutCancel=true"
check "the previous default binding stops triggering after reassignment" "$out" "oldShortcutSuppressed=true"
check "the new key combination triggers the mapped playback action" "$out" "remappedShortcutPlays=true"
check "the shortcut editor rejects duplicate assignments" "$out" "shortcutConflict=true"
out=$(run "1000:'shortcutPersists=' + (Theme.shortcutText('playPause')==='Ctrl+Space' && Theme.shortcutAction('Ctrl+Space')==='playPause')|+100:shortcutsDialog.open()|+300:click-item:shortcut-reset-all|+100:'shortcutResetStaged=' + (shortcutsDialog.neoShortcutText('playPause')==='Space' && Theme.shortcutText('playPause')==='Ctrl+Space')|+100:shortcutsDialog.saveChanges(); 'shortcutReset=' + (Theme.shortcutText('playPause')==='Space' && Theme.shortcutText('mute')==='M')|+100:quit" "$E1")
check "custom shortcuts persist across VLC launches" "$out" "shortcutPersists=true"
check "Reset stages the default shortcut map until Save" "$out" "shortcutResetStaged=true"
check "Reset and Save restore the default shortcut map" "$out" "shortcutReset=true"
out=$(run "900:win.focusKeys()|+100:key:N|+500:'nextHotkey=' + player.mediaUrl.toString().endsWith('My.Show.S01E02.1080p.mkv')|+100:win.focusKeys()|+100:key:P|+500:'previousHotkey=' + player.mediaUrl.toString().endsWith('My.Show.S01E01.1080p.mkv')|+100:player.jumpTo(10000)|+100:win.focusKeys()|+100:key:Right|+500:'seekForwardHotkey=' + (player.time >= 18000)|+100:player.jumpTo(20000)|+100:win.focusKeys()|+100:key:Shift+Left|+500:'shortSeekHotkey=' + (player.time < 19000)|+100:player.jumpTo(30000)|+100:win.focusKeys()|+100:key:Ctrl+Left|+500:'longSeekHotkey=' + (player.time < 5000)|+100:player.setRate(1.5); win.focusKeys()|+100:key:-|+200:'speedDownHotkey=' + (player.rate < 1.5)|+100:player.setRate(1.5); win.focusKeys()|+100:key:]|+200:'speedUpHotkey=' + (player.rate > 1.5)|+100:player.setRate(1.5); win.focusKeys()|+100:key:=|+200:'speedNormalHotkey=' + (Math.abs(player.rate - 1) < 0.01)|+100:win.focusKeys()|+100:key:Ctrl+B|+150:'bookmarkHotkey=' + (player.bookmarks().length > 0)|+100:quit" "$E1" "$E2")
check "the Next shortcut advances to the next VLC queue item" "$out" "nextHotkey=true"
check "the Previous shortcut returns to the prior VLC queue item" "$out" "previousHotkey=true"
check "the normal seek shortcut changes the VLC playback position" "$out" "seekForwardHotkey=true"
check "the very-short seek shortcut uses the configured jump amount" "$out" "shortSeekHotkey=true"
check "the long seek shortcut uses the configured jump amount" "$out" "longSeekHotkey=true"
check "the speed-down shortcut changes the VLC playback rate" "$out" "speedDownHotkey=true"
check "the speed-up shortcut changes the VLC playback rate" "$out" "speedUpHotkey=true"
check "the normal-speed shortcut restores 1x playback" "$out" "speedNormalHotkey=true"
check "the bookmark shortcut adds a VLC Neo playback bookmark" "$out" "bookmarkHotkey=true"
out=$(run "1000:'figmaItemKeys=' + (Theme.shortcutChord(Qt.Key_Less, Qt.ShiftModifier, '<')==='<' && Theme.shortcutChord(Qt.Key_Greater, Qt.ShiftModifier, '>')==='>' && Theme.shortcutAction('<')==='previous' && Theme.shortcutAction('>')==='next')|+100:'figmaFrameKeys=' + (Theme.shortcutAction(',')==='previousFrame' && Theme.shortcutAction('.')==='nextFrame' && Theme.shortcutAction('E')==='nextFrame')|+100:player.togglePause(); player.jumpTo(10000); win.focusKeys()|+100:key:,|+500:'previousFrameHotkey=' + (player.time < 10000 && video.frameRate > 0)|+100:win.focusKeys()|+100:key:.|+200:'nextFrameHotkey=' + (toastItem.message==='Next frame')|+100:win.focusKeys()|+100:key:E|+200:'legacyNextFrameHotkey=' + (toastItem.message==='Next frame')|+100:quit" "$E1")
check "Figma item and frame keys resolve to their actions while legacy frame key remains" "$out" "figmaFrameKeys=true"
check "Figma comma key seeks backward by one frame" "$out" "previousFrameHotkey=true"
check "Figma period key invokes VLC next-frame stepping" "$out" "nextFrameHotkey=true"
check "legacy E key still invokes VLC next-frame stepping" "$out" "legacyNextFrameHotkey=true"
out=$(run "800:win.focusKeys()|+100:key:Q|+100:'queueHotkey=' + (win.rightPanel === 'queue')|+100:win.focusKeys()|+100:key:Ctrl+E|+100:'settingsPanelHotkey=' + (win.rightPanel === 'settings')|+100:win.focusKeys()|+100:key:Ctrl+E|+100:win.focusKeys()|+100:key:Ctrl+N|+150:'networkHotkey=' + networkDialog.visible|+100:networkDialog.close()|+200:win.focusKeys()|+100:key:Ctrl+O|+150:'fileHotkey=' + openFilesDialog.visible|+100:openFilesDialog.close()|+400:key:Ctrl+P|+150:'preferencesAfterFilePicker=' + settingsDialog.visible|+100:settingsDialog.close()|+200:win.focusKeys()|+100:key:?|+150:'shortcutsHotkey=' + shortcutsDialog.visible|+100:shortcutsDialog.close()|+200:win.focusKeys()|+100:key:L|+150:'libraryHotkey=' + win.libraryOpen|+100:win.focusKeys()|+100:key:L|+150:'libraryHotkeyTogglesBack=' + !win.libraryOpen|+100:quit")
check "the Queue shortcut opens its side panel" "$out" "queueHotkey=true"
check "the settings-panel shortcut opens its side panel" "$out" "settingsPanelHotkey=true"
check "the network shortcut opens the network dialog" "$out" "networkHotkey=true"
check "the file shortcut opens the native file picker" "$out" "fileHotkey=true"
check "closing the file picker restores keyboard focus" "$out" "preferencesAfterFilePicker=true"
check "the shortcuts shortcut opens the shortcut editor" "$out" "shortcutsHotkey=true"
check "the Library shortcut toggles the media browser" "$out" "libraryHotkey=true"
check "the Library shortcut returns to playback" "$out" "libraryHotkeyTogglesBack=true"
out=$(run "1000:player.openLocation('$WORK/multi-track.mkv', true)|+1300:'trackFixtureLoaded=' + player.isPlaying|+100:win.focusKeys()|+100:key:B|+300:'audioTrackHotkey=' + player.tracks('audio').some(x=>x.selected && x.name.indexOf('Spanish')>=0)|+100:win.focusKeys()|+100:key:V|+300:'subtitleTrackHotkey=' + player.tracks('spu').some(x=>x.selected && x.name.indexOf('Spanish')>=0)|+100:player.setAudioDelay(0); win.focusKeys()|+100:key:J|+250:'audioDelayEarlierHotkey=' + (player.audioDelay<0)|+100:win.focusKeys()|+100:key:K|+250:'audioDelayLaterHotkey=' + (player.audioDelay===0)|+100:player.setSubtitleDelay(0); win.focusKeys()|+100:key:G|+250:'subtitleDelayEarlierHotkey=' + (player.subtitleDelay<0)|+100:win.focusKeys()|+100:key:H|+250:'subtitleDelayLaterHotkey=' + (player.subtitleDelay===0)|+100:quit")
check "the audio-track shortcut switches tracks in VLC" "$out" "audioTrackHotkey=true"
check "the subtitle-track shortcut switches tracks in VLC" "$out" "subtitleTrackHotkey=true"
check "the audio-earlier shortcut changes VLC audio delay" "$out" "audioDelayEarlierHotkey=true"
check "the audio-later shortcut restores VLC audio delay" "$out" "audioDelayLaterHotkey=true"
check "the subtitle-earlier shortcut changes VLC subtitle delay" "$out" "subtitleDelayEarlierHotkey=true"
check "the subtitle-later shortcut restores VLC subtitle delay" "$out" "subtitleDelayLaterHotkey=true"
out=$(run "900:shortcutsDialog.open()|+100:'vlcShortcutCount=' + shortcutsDialog.vlcShortcuts.length|+100:'globalShortcutCount=' + shortcutsDialog.globalVlcShortcuts.length|+100:'shortcutSearch=' + (() => { shortcutsDialog.shortcutSearch='subdelay'; return shortcutsDialog.filteredShortcuts(shortcutsDialog.vlcShortcuts).some(x=>x.name==='key-subdelay-up') && shortcutsDialog.filteredShortcuts(shortcutsDialog.globalVlcShortcuts).some(x=>x.name==='global-key-subdelay-up') })()|+100:shortcutsDialog.shortcutSearch=''|+100:'vlcHotkeyOptions=' + (shortcutsDialog.vlcShortcuts.length===111 && shortcutsDialog.vlcShortcuts.every(x=>player.config(x.name)!==undefined))|+100:'globalHotkeyOptions=' + (shortcutsDialog.globalVlcShortcuts.length===111 && shortcutsDialog.globalVlcShortcuts.every(x=>player.config(x.name)!==undefined))|+100:'vlcHotkeyConflict=' + !shortcutsDialog.saveVlcShortcut('key-aspect-ratio','space')|+100:'vlcHotkeyEdit=' + (shortcutsDialog.saveVlcShortcut('key-aspect-ratio','Ctrl+Alt+9') && shortcutsDialog.vlcShortcutText('key-aspect-ratio')==='Ctrl+Alt+9')|+100:'vlcHotkeyStaged=' + (String(player.config('key-aspect-ratio'))!==shortcutsDialog.vlcShortcutText('key-aspect-ratio'))|+100:shortcutsDialog.saveChanges(); 'vlcHotkeySaved=' + (String(player.config('key-aspect-ratio'))==='Ctrl+Alt+9')|+100:shortcutsDialog.open()|+350:shortcutsDialog.resetVlcShortcuts(); 'vlcHotkeyResetStaged=' + (shortcutsDialog.vlcShortcutText('key-aspect-ratio')===shortcutsDialog.vlcShortcutValues()['key-aspect-ratio'] && String(player.config('key-aspect-ratio'))==='Ctrl+Alt+9')|+100:shortcutsDialog.saveChanges(); 'vlcHotkeyReset=' + (String(player.config('key-aspect-ratio'))===shortcutsDialog.vlcShortcutValues()['key-aspect-ratio'])|+100:shortcutsDialog.open(); 'globalHotkeyEdit=' + (shortcutsDialog.saveVlcShortcut('global-key-aspect-ratio','Ctrl+Alt+8') && shortcutsDialog.vlcShortcutText('global-key-aspect-ratio')==='Ctrl+Alt+8')|+100:'globalHotkeyRestartNotice=' + shortcutsDialog.captureNotice.startsWith('Restart VLC')|+100:shortcutsDialog.close(); 'globalHotkeyCancel=true'|+100:quit" "$E1")
check "the editor discovers the VLC core hotkey options" "$out" "vlcHotkeyOptions=true"
check "all 111 VLC global hotkey options are available to edit" "$out" "globalHotkeyOptions=true"
check "the editor includes VLC global hotkey options" "$out" "globalShortcutCount=111"
check "shortcut search finds local and global VLC actions" "$out" "shortcutSearch=true"
check "VLC shortcuts reject conflicts with Neo bindings, regardless of case" "$out" "vlcHotkeyConflict=true"
check "VLC shortcut edits remain staged until Save" "$out" "vlcHotkeyStaged=true"
check "VLC shortcuts can be edited and saved" "$out" "vlcHotkeyEdit=true"
check "Save commits VLC core hotkey changes" "$out" "vlcHotkeySaved=true"
check "VLC reset stages the captured initial value" "$out" "vlcHotkeyResetStaged=true"
check "VLC shortcut reset saves the captured initial value" "$out" "vlcHotkeyReset=true"
check "VLC global shortcuts can be edited and saved" "$out" "globalHotkeyEdit=true"
check "Cancel discards the staged global shortcut change" "$out" "globalHotkeyCancel=true"
check "global shortcut edits explain the restart requirement" "$out" "globalHotkeyRestartNotice=true"
globalShortcutSandbox="$WORK/global-shortcut-sandbox"
mkdir -p "$globalShortcutSandbox/config/vlc-neo"
printf '[appearance]\nonboarded=true\n' > "$globalShortcutSandbox/config/vlc-neo/neo.conf"
NEO_SANDBOX="$globalShortcutSandbox" out=$(run "900:shortcutsDialog.open(); 'globalHotkeyEdit=' + shortcutsDialog.saveVlcShortcut('global-key-aspect-ratio','Ctrl+Alt+8')|+100:shortcutsDialog.saveChanges(); 'globalHotkeySaved=' + (String(player.config('global-key-aspect-ratio'))==='Ctrl+Alt+8')|+100:quit")
check "Save commits the global VLC hotkey" "$out" "globalHotkeySaved=true"
NEO_SANDBOX="$globalShortcutSandbox" out=$(run "900:'globalHotkeyPersistsAcrossLaunch=' + (String(player.config('global-key-aspect-ratio'))==='Ctrl+Alt+8')|+100:player.setConfig('global-key-aspect-ratio',shortcutsDialog.globalVlcShortcutValues()['global-key-aspect-ratio'])|+100:quit")
check "saved global shortcut persists across VLC launches" "$out" "globalHotkeyPersistsAcrossLaunch=true"
shortcutsFrameSandbox="$WORK/shortcuts-frame-sandbox"
mkdir -p "$shortcutsFrameSandbox/config/vlc-neo"
printf '[appearance]\nonboarded=true\n' > "$shortcutsFrameSandbox/config/vlc-neo/neo.conf"
NEO_SANDBOX="$shortcutsFrameSandbox" out=$(run "500:win.width=1048; win.height=800; shortcutsDialog.open()|+200:'shortcutsFrameGeometry=' + [shortcutsDialog.width,shortcutsDialog.height,shortcutsDialog.x,shortcutsDialog.y].join('/')|+100:grab:$WORK/shortcuts-frame.png|+100:quit")
check "shortcuts dialog fills the exact Figma 1048×800 frame" "$out" "shortcutsFrameGeometry=1048/800/0/0"
if [ -s "$WORK/shortcuts-frame.png" ]; then echo 'PASS  Figma-sized shortcuts screenshot written'; pass=$((pass + 1))
else echo 'FAIL  Figma-sized shortcuts screenshot missing'; fail=$((fail + 1)); fi
if [ -s "$WORK/shortcut-editor.png" ]; then echo "PASS  shortcut editor screenshot written"; pass=$((pass + 1))
else echo "FAIL  shortcut editor screenshot missing"; fail=$((fail + 1)); fi
echo "== playback preferences map to VLC"
out=$(run "300:win.width=1048; win.height=865; settingsDialog.open(); settingsDialog.page='playback'|+120:'settingsFrameFull=' + (settingsDialog.x === 0 && settingsDialog.y === 0 && settingsDialog.width === win.width && settingsDialog.height === win.height)|+100:win.width=1120; win.height=900|+160:'settingsResizesWithWindow=' + (settingsDialog.x === 0 && settingsDialog.y === 0 && settingsDialog.width === win.width && settingsDialog.height === win.height)|+100:settingsDialog.close(); win.width=1120; win.height=680|+100:quit")
check "preferences fill the Figma frame edge to edge" "$out" "settingsFrameFull=true"
check "preferences continue filling the window when it resizes" "$out" "settingsResizesWithWindow=true"
out=$(run "1000:win.width=1048; win.height=865; Theme.store.advancedOptions=false; settingsDialog.open(); settingsDialog.page='playback'|+150:'playbackTitle=' + settingsDialog.pageTitle|+100:'playbackOptions=' + ['playlist-autostart','rate','playlist-cork','preferred-resolution','menu-language','audio-track','sub-track','loop','repeat','random','play-and-stop','play-and-exit','play-and-pause','input-fast-seek'].every(x => player.config(x) !== undefined)|+100:'playbackSimpleAdvanced=' + (!settingsDialog.optionVisible('start-paused') && !settingsDialog.optionVisible('input-repeat'))|+100:'playbackConfigRoundTrip=' + (() => { const old={rate:player.config('rate'),resolution:player.config('preferred-resolution'),language:player.config('menu-language'),audio:player.config('audio-track'),subtitle:player.config('sub-track'),cork:player.config('playlist-cork'),random:player.config('random'),stop:player.config('play-and-stop'),fast:player.config('input-fast-seek')}; settingsDialog.setDefaultPlaybackRate(1.25); player.setConfig('preferred-resolution',720); player.setConfig('menu-language','fr'); player.setConfig('audio-track',2); player.setConfig('sub-track',2); player.setConfig('playlist-cork',!old.cork); player.setConfig('random',!old.random); player.setConfig('play-and-stop',!old.stop); player.setConfig('input-fast-seek',!old.fast); const ok=Math.abs(Number(player.config('rate'))-1.25)<0.001 && player.config('preferred-resolution')===720 && player.config('menu-language')==='fr' && player.config('audio-track')===2 && player.config('sub-track')===2 && !!player.config('playlist-cork')===!old.cork && !!player.config('random')===!old.random && !!player.config('play-and-stop')===!old.stop && !!player.config('input-fast-seek')===!old.fast; settingsDialog.setDefaultPlaybackRate(old.rate); player.setConfig('preferred-resolution',old.resolution); player.setConfig('menu-language',old.language); player.setConfig('audio-track',old.audio); player.setConfig('sub-track',old.subtitle); player.setConfig('playlist-cork',old.cork); player.setConfig('random',old.random); player.setConfig('play-and-stop',old.stop); player.setConfig('input-fast-seek',old.fast); return ok })()|+100:'repeatAndFinishRoundTrip=' + (() => { const loop=!!player.config('loop'), repeat=!!player.config('repeat'), exit=!!player.config('play-and-exit'), pause=!!player.config('play-and-pause'); settingsDialog.setDefaultRepeatMode('one'); settingsDialog.setPlaybackEndAction('exit'); const ok=!!player.config('repeat') && !player.config('loop') && !!player.config('play-and-exit') && !player.config('play-and-pause'); settingsDialog.setDefaultRepeatMode(repeat?'one':loop?'all':'off'); settingsDialog.setPlaybackEndAction(exit?'exit':pause?'pause':'nothing'); return ok })()|+100:'precisionToggle=' + (typeof player.config('input-fast-seek') === 'boolean')|+100:'playbackWidths=' + ['vlc-option-preferred-resolution','vlc-option-menu-language','vlc-option-audio-track','vlc-option-sub-track','playback-resume-mode','playback-repeat-mode','playback-end-action'].every(name => settingsDialog.preferenceControlWidth(name) === 320)|+100:grab:$WORK/settings-playback.png|+100:settingsDialog.close()|+100:quit" "$E1")
check "the playback preferences use the Figma title" "$out" "playbackTitle=Playback Preferences"
check "playback preferences map to installed VLC options" "$out" "playbackOptions=true"
check "advanced playback controls stay hidden in Simple mode" "$out" "playbackSimpleAdvanced=true"
check "quality, language, track and playback controls round-trip" "$out" "playbackConfigRoundTrip=true"
check "repeat and end-of-playback actions control VLC" "$out" "repeatAndFinishRoundTrip=true"
check "precise seeking has a VLC boolean setting" "$out" "precisionToggle=true"
check "playback preference fields use the Figma 320 px width" "$out" "playbackWidths=true"
if [ -s "$WORK/settings-playback.png" ]; then echo "PASS  playback preferences screenshot written"; pass=$((pass + 1))
else echo "FAIL  playback preferences screenshot missing"; fail=$((fail + 1)); fi
TRACK_PREF_SANDBOX="$WORK/track-preferences-sandbox"
out=$(NEO_SANDBOX="$TRACK_PREF_SANDBOX" run "500:player.setConfig('audio-track',1); player.setConfig('sub-track',1); 'trackPreferencesSaved=' + (player.config('audio-track') === 1) + '/' + (player.config('sub-track') === 1)|+100:quit")
check "track-number preferences save through VLC configuration" "$out" "trackPreferencesSaved=true/true"
out=$(NEO_SANDBOX="$TRACK_PREF_SANDBOX" run "1600:'trackPreferencesApplied=' + (player.tracks('audio').some(track => track.selected && track.name.indexOf('Spanish') >= 0)) + '/' + (player.tracks('spu').some(track => track.selected && track.name.indexOf('Spanish') >= 0))|+100:quit" "$WORK/multi-track.mkv")
check "saved track numbers select the requested audio and subtitle streams after relaunch" "$out" "trackPreferencesApplied=true/true"
TRACK_PREF_ALT_SANDBOX="$WORK/track-preferences-alt-sandbox"
out=$(NEO_SANDBOX="$TRACK_PREF_ALT_SANDBOX" run "500:player.setConfig('audio-track',2); player.setConfig('sub-track',1); 'altTrackPreferencesSaved=' + (player.config('audio-track')===2) + '/' + (player.config('sub-track')===1)|+100:quit")
check "alternate multi-track preferences save distinct VLC indices" "$out" "altTrackPreferencesSaved=true/true"
out=$(NEO_SANDBOX="$TRACK_PREF_ALT_SANDBOX" run "1600:'altTrackPreferencesApplied=' + (player.mediaUrl.toString().endsWith('multi-track-alt.mkv')) + '/' + player.tracks('audio').some(track => track.selected && track.name.indexOf('French') >= 0) + '/' + player.tracks('spu').some(track => track.selected && track.name.indexOf('French') >= 0)|+100:quit" "$WORK/multi-track-alt.mkv")
check "alternate multi-track file restores the saved French audio and subtitle after relaunch" "$out" "altTrackPreferencesApplied=true/true/true"
echo "== end-of-playlist actions persist and affect VLC playback"
endPauseSandbox="$WORK/end-pause-sandbox"
mkdir -p "$endPauseSandbox/config/vlc-neo"
printf '[appearance]\nonboarded=true\n' > "$endPauseSandbox/config/vlc-neo/neo.conf"
NEO_SANDBOX="$endPauseSandbox" out=$(run "500:player.setConfig('play-and-pause',true); player.setConfig('play-and-exit',false); 'endPauseSaved=' + (player.config('play-and-pause')===true)|+100:quit")
check "end-of-playlist Pause action saves through VLC" "$out" "endPauseSaved=true"
endExitSandbox="$WORK/end-exit-sandbox"
mkdir -p "$endExitSandbox/config/vlc-neo"
printf '[appearance]\nonboarded=true\n' > "$endExitSandbox/config/vlc-neo/neo.conf"
NEO_SANDBOX="$endExitSandbox" out=$(run "500:player.setConfig('play-and-pause',false); player.setConfig('play-and-exit',true); 'endExitSaved=' + (player.config('play-and-exit')===true && player.config('play-and-pause')===false)|+100:quit")
check "end-of-playlist Exit action saves through VLC" "$out" "endExitSaved=true"
pauseEndLog="$WORK/end-pause-playback.log"
exitEndLog="$WORK/end-exit-playback.log"
# These end-action runs have separate config/data/cache roots, so two VLC instances are safe here.
NEO_SANDBOX="$endPauseSandbox" run "4200:'endPauseRestored=' + (player.config('play-and-pause')===true)|+100:'playlistPausedAtEnd=' + (!player.playing && player.time >= player.length - 500 && player.state===3)|+100:quit" "$WORK/convert-video.mkv" >"$pauseEndLog" 2>&1 &
pauseEndPid=$!
NEO_SANDBOX="$endExitSandbox" runExpectedExit "500:player.openLocation('$WORK/convert-video.mkv',true)|+900:'endExitRestoredAndPlaying=' + (player.config('play-and-exit')===true && player.state===2)" >"$exitEndLog" 2>&1 &
exitEndPid=$!
wait "$pauseEndPid"
wait "$exitEndPid"
out=$(<"$pauseEndLog")
check "end-of-playlist Pause action persists across VLC restarts" "$out" "endPauseRestored=true"
check "VLC pauses at the end of the playlist after restart" "$out" "playlistPausedAtEnd=true"
out=$(<"$exitEndLog")
check "end-of-playlist Exit action persists and starts the media after restart" "$out" "endExitRestoredAndPlaying=true"
check "VLC exits naturally when the restarted playlist ends" "$out" "exited naturally after playlist completion"
endStopSandbox="$WORK/end-stop-sandbox"
mkdir -p "$endStopSandbox/config/vlc-neo"
printf '[appearance]\nonboarded=true\n' > "$endStopSandbox/config/vlc-neo/neo.conf"
NEO_SANDBOX="$endStopSandbox" out=$(run "500:player.setConfig('play-and-stop',true); 'endStopSaved=' + (player.config('play-and-stop')===true)|+100:quit")
check "end-of-item Stop action saves through VLC" "$out" "endStopSaved=true"
NEO_SANDBOX="$endStopSandbox" out=$(run "500:'endStopRestored=' + (player.config('play-and-stop')===true)|+100:player.openUrls([platform.fileUrl('$WORK/convert-video.mkv'),platform.fileUrl('$WORK/base.mkv')],true)|+1200:'endStopStartedFirstItem=' + (player.playing && player.mediaUrl.toString().endsWith('convert-video.mkv'))|+3500:'endStopHonored=' + (player.config('play-and-stop')===true && !player.playing && !player.mediaUrl.toString().endsWith('base.mkv'))|+100:quit" "$WORK/convert-video.mkv" "$WORK/base.mkv")
check "end-of-item Stop action persists after VLC restarts" "$out" "endStopRestored=true"
check "play-and-stop stops VLC after the first queued item" "$out" "endStopStartedFirstItem=true"
check "play-and-stop prevents VLC from advancing to the next queued item" "$out" "endStopHonored=true"
echo "== audio preferences map to VLC"
audioShotSandbox="$WORK/audio-screenshot-sandbox"
mkdir -p "$audioShotSandbox/config/vlc-neo" "$audioShotSandbox/config/vlc"
printf '[appearance]\nonboarded=true\n' > "$audioShotSandbox/config/vlc-neo/neo.conf"
printf 'volume-step=1\nnorm-max-level=1\n' > "$audioShotSandbox/config/vlc/vlcrc"
NEO_SANDBOX="$audioShotSandbox" out=$(run "1000:win.width=1048; win.height=865; settingsDialog.open(); settingsDialog.page='audio'|+300:grab:$WORK/settings-audio.png|+100:quit")
NEO_SANDBOX="$audioShotSandbox" audioEffectsOut=$(run "1000:win.width=1048; win.height=865; settingsDialog.open(); settingsDialog.page='audio'; settingsDialog.scrollToAudioEffects(); 'equalizerExpanded=' + settingsDialog.equalizerExpanded|+500:grab:$WORK/settings-audio-effects.png|+100:quit")
out=$(run "1000:win.width=1048; win.height=865; settingsDialog.open(); settingsDialog.page='audio'; settingsDialog.readAudioFilters()|+100:'figmaAudioControls=' + settingsDialog.normalizerTargetVisible|+100:click-item:startup-volume-fixed|+100:'fixedStartupVolume=' + (Theme.store.startupVolumeMode === 'fixed' && player.config('volume-save') === false)|+100:click-item:startup-volume-remember|+100:'rememberStartupVolume=' + (Theme.store.startupVolumeMode === 'remember' && player.config('volume-save') === true)|+100:player.setConfig('audio-filter','compressor'); settingsDialog.readAudioFilters(); settingsDialog.setAudioFilter('normvol',true); 'filtersPreserved=' + (settingsDialog.audioFilterEnabled('compressor') && settingsDialog.audioFilterEnabled('normvol'))|+100:settingsDialog.setAudioFilter('compressor',false); 'filterRemoved=' + (!settingsDialog.audioFilterEnabled('compressor') && settingsDialog.audioFilterEnabled('normvol'))|+100:settingsDialog.setAudioFilter('normvol',false); 'filtersClear=' + (player.config('audio-filter') === '')|+100:(() => { const out=player.config('aout'), mode=player.config('stereo-mode'); player.setConfig('aout','pulse'); player.setConfig('stereo-mode',1); const ok=player.config('aout')==='pulse' && player.config('stereo-mode')===1; player.setConfig('aout',out); player.setConfig('stereo-mode',mode); return 'outputRoundTrip=' + ok })()|+100:'audioOptions=' + ['audio','aout','stereo-mode','norm-max-level','compressor-threshold','audio-replay-gain-mode','audio-replay-gain-preamp'].every(x => player.config(x) !== undefined)|+100:'audioDecimalDisplay=' + (() => { const oldVolume=player.config('volume-step'), oldPreamp=player.config('audio-replay-gain-preamp'); settingsDialog.setOptionValue('volume-step',1); settingsDialog.setOptionValue('audio-replay-gain-preamp',0); const compact=settingsDialog.preferenceControlDisplayValue('vlc-option-volume-step')==='1' && settingsDialog.preferenceControlDisplayValue('vlc-option-audio-replay-gain-preamp')==='0.0'; settingsDialog.setOptionValue('volume-step',1.75); settingsDialog.setOptionValue('audio-replay-gain-preamp',1.25); const precise=settingsDialog.preferenceControlDisplayValue('vlc-option-volume-step')==='1.75' && settingsDialog.preferenceControlDisplayValue('vlc-option-audio-replay-gain-preamp')==='1.25'; settingsDialog.setOptionValue('volume-step',12.8); const floatClean=settingsDialog.preferenceControlDisplayValue('vlc-option-volume-step')==='12.8'; settingsDialog.setOptionValue('volume-step',oldVolume); settingsDialog.setOptionValue('audio-replay-gain-preamp',oldPreamp); return compact && precise && floatClean })()|+100:settingsDialog.close()|+100:quit")
check "the audio preferences keep Target level visible when normalization is off" "$out" "figmaAudioControls=true"
check "Always starts at mode updates VLC volume-save behavior" "$out" "fixedStartupVolume=true"
check "Remember last volume restores VLC volume-save behavior" "$out" "rememberStartupVolume=true"
check "normalizer and night-mode filters preserve one another" "$out" "filtersPreserved=true"
check "disabling night mode leaves normalization enabled" "$out" "filterRemoved=true"
check "audio filters can both be disabled cleanly" "$out" "filtersClear=true"
check "audio output and speaker settings round-trip" "$out" "outputRoundTrip=true"
check "the audio page uses installed VLC options" "$out" "audioOptions=true"
check "audio values match Figma decimal formatting without rounding" "$out" "audioDecimalDisplay=true"
if command -v pactl >/dev/null 2>&1 && pactl info >/dev/null 2>&1; then
    startupVolumeSink="neo-startup-volume-${BASHPID}"
    startupVolumeModule="$(pactl load-module module-null-sink "sink_name=$startupVolumeSink" 2>/dev/null || true)"
    if [[ -n "$startupVolumeModule" ]]; then
        startupVolumeSandbox="$WORK/startup-volume-sandbox"
        mkdir -p "$startupVolumeSandbox/config/vlc-neo" "$startupVolumeSandbox/config/vlc"
        printf '[appearance]\nonboarded=true\n' > "$startupVolumeSandbox/config/vlc-neo/neo.conf"
        NEO_SANDBOX="$startupVolumeSandbox" out=$(run "200:Theme.store.startupVolume=0.35; win.chooseStartupVolumeMode('fixed')|+100:'fixedStartupVolumePersist=' + (Theme.store.startupVolumeMode==='fixed' && Math.abs(Theme.store.startupVolume-0.35)<0.001)|+100:quit")
        check "fixed startup volume choice persists its selected value" "$out" "fixedStartupVolumePersist=true"
        out=$(NEO_SANDBOX="$startupVolumeSandbox" PULSE_SINK="$startupVolumeSink" NEO_TEST_AOUT=pulse run "300:player.openLocation('$WORK/audio-only.m4a',true)|+1800:'startupVolumeApplied=' + (player.state===2 && !win.startupVolumePending && Math.abs(player.volume-Theme.store.startupVolume)<0.03) + '/' + player.volume|+100:quit")
        check "fixed startup volume applies to the first media after relaunch" "$out" "startupVolumeApplied=true/0.35"
        pactl unload-module "$startupVolumeModule" >/dev/null 2>&1 || true
    else
        echo "SKIP  fixed startup-volume playback check (PulseAudio/PipeWire null sink unavailable)"
    fi
    out=$(NEO_SANDBOX="$WORK/audio-device-sandbox" NEO_TEST_AOUT=pulse run "100:onboarding.close(); player.setVolume(0); player.openLocation('$WORK/audio-only.m4a',true)|+1800:'audioDeviceTarget=' + (() => { const devices=player.audioDevices(); if(!devices.length) return 'none'; const current=devices.find(device=>device.selected); let target=devices.find(device=>!device.selected); if(!target) target=devices[0]; win.objectName=target.id; player.setAudioDevice(target.id); return (current ? current.id : 'none') + '->' + target.id })()|+2500:'audioDeviceResult=' + player.audioDevices().some(device=>device.id===win.objectName && device.selected) + '/' + (player.state===2) + '/' + player.volume|+100:quit" "$WORK/audio-only.m4a")
    check "VLC enumerates audio devices during playback and accepts a device change" "$out" "audioDeviceTarget="
    check "the selected VLC audio device updates while playback stays muted and active" "$out" "audioDeviceResult=true/true/0"
else
    echo "SKIP  live VLC audio-device selection (PulseAudio/PipeWire service unavailable)"
fi
if [ -s "$WORK/settings-audio.png" ]; then echo "PASS  audio preferences screenshot written"; pass=$((pass + 1))
else echo "FAIL  audio preferences screenshot missing"; fail=$((fail + 1)); fi
if [ -s "$WORK/settings-audio-effects.png" ]; then echo "PASS  expanded equalizer screenshot written"; pass=$((pass + 1))
else echo "FAIL  expanded equalizer screenshot missing"; fail=$((fail + 1)); fi
check "the settings capture helper opens and scrolls to the equalizer" "$audioEffectsOut" "equalizerExpanded=true"
echo "== video preferences map to VLC"
out=$(run "1000:settingsDialog.open(); settingsDialog.page='video'; settingsDialog.loadPictureValues()|+100:'videoTitle=' + settingsDialog.pageTitle + '/fullscreen=' + settingsDialog.optionVisible('fullscreen')|+100:'videoOptions=' + ['video','fullscreen','disable-screensaver','video-wallpaper','hue','brightness','contrast','saturation','gamma','deinterlace','deinterlace-mode','aspect-ratio','crop','video-filter'].every(x => player.config(x) !== undefined)|+100:'videoControls=' + ['hue','brightness','contrast','saturation','gamma'].every(x => settingsDialog.pictureValues[x] !== undefined)|+100:'videoSimpleOptions=' + (settingsDialog.optionVisible('deinterlace-mode') && !settingsDialog.optionVisible('vout'))|+100:'pictureReset=' + (() => { const old=player.config('video-filter'); player.setConfig('video-filter','transform'); settingsDialog.loadPictureValues(); const preview=settingsDialog.setPictureValue('brightness',1.25); const enabled=player.config('video-filter').split(',').includes('adjust'); settingsDialog.resetPicture(); const ok=preview && enabled && Math.abs(player.config('brightness')-1)<0.0001 && player.config('video-filter')==='transform'; player.setConfig('video-filter',old); settingsDialog.loadPictureValues(); return ok })()|+100:grab:$WORK/settings-video.png|+100:settingsDialog.close()|+100:quit" "$E1")
check "the video preferences use the Figma title" "$out" "videoTitle=Video Defaults"
check "start-in-fullscreen is grouped under Video like the Figma frame" "$out" "fullscreen=true"
check "video defaults map to installed VLC options" "$out" "videoOptions=true"
check "picture adjustment controls load their VLC values" "$out" "videoControls=true"
check "deinterlacing is simple while output module stays advanced" "$out" "videoSimpleOptions=true"
check "picture adjustment previews through the active VLC video output and Reset restores defaults" "$out" "pictureReset=true"
out=$(run "1000:settingsDialog.open(); settingsDialog.page='video'; 'neutralPictureRemovesAdjust=' + (() => { player.setConfig('video-filter','transform'); player.setVideoFilterChain('transform'); ['hue','brightness','contrast','saturation','gamma'].forEach((name,i) => player.setConfig(name,[0,1,1,1,1][i])); settingsDialog.loadPictureValues(); settingsDialog.setPictureValue('brightness',1.25); settingsDialog.setPictureValue('contrast',1.1); const enabled=player.config('video-filter').split(',').includes('adjust'); settingsDialog.setPictureValue('brightness',1); const kept=player.config('video-filter').split(',').includes('adjust') && player.config('video-filter').split(',').includes('transform'); settingsDialog.setPictureValue('contrast',1); return enabled && kept && player.config('video-filter')==='transform' })()|+100:quit" "$E1")
check "returning all picture controls to neutral removes only VLC's adjust filter" "$out" "neutralPictureRemovesAdjust=true"
videoPrefSandbox="$WORK/video-preferences-sandbox"
out=$(NEO_SANDBOX="$videoPrefSandbox" run "500:player.setConfig('brightness',1.25); player.setConfig('contrast',1.1); player.setConfig('video-filter','adjust'); 'videoPrefsSaved=' + (Math.abs(Number(player.config('brightness'))-1.25)<0.0001 && Math.abs(Number(player.config('contrast'))-1.1)<0.0001 && player.config('video-filter')==='adjust')|+100:quit")
check "video picture settings save through VLC configuration" "$out" "videoPrefsSaved=true"
out=$(NEO_SANDBOX="$videoPrefSandbox" run "500:settingsDialog.open(); settingsDialog.page='video'; settingsDialog.loadPictureValues(); 'videoPrefsPersist=' + (Math.abs(Number(player.config('brightness'))-1.25)<0.0001 && Math.abs(Number(player.config('contrast'))-1.1)<0.0001 && player.config('video-filter')==='adjust' && Math.abs(settingsDialog.pictureValues.brightness-1.25)<0.0001 && Math.abs(settingsDialog.pictureValues.contrast-1.1)<0.0001)|+100:quit")
check "video picture settings reload in VLC and the Figma controls after relaunch" "$out" "videoPrefsPersist=true"
voutClassicSandbox="$WORK/vout-classic-sandbox"
mkdir -p "$voutClassicSandbox/config/vlc" "$voutClassicSandbox/data" "$voutClassicSandbox/cache"
printf 'vout=none\n' > "$voutClassicSandbox/config/vlc/vlcrc"
if XDG_CONFIG_HOME="$voutClassicSandbox/config" XDG_DATA_HOME="$voutClassicSandbox/data" XDG_CACHE_HOME="$voutClassicSandbox/cache" \
    timeout 20s /usr/bin/vlc --no-plugins-cache --intf=dummy --no-audio --play-and-exit --stop-time=1 -vv "$WORK/base.mkv" > "$voutClassicSandbox/vout.log" 2>&1; then
    if grep -qF 'looking for vout display module matching "none"' "$voutClassicSandbox/vout.log" \
        && grep -qF 'no vout display modules matched' "$voutClassicSandbox/vout.log"; then
        echo "PASS  VLC's non-Neo interface honors the saved vout=none option"; pass=$((pass + 1))
    else
        echo "FAIL  VLC's non-Neo interface did not apply the saved vout=none option"; fail=$((fail + 1))
    fi
else
    echo "FAIL  VLC's isolated non-Neo vout check did not exit cleanly"; fail=$((fail + 1))
fi
out=$(run "800:win.width=1120; win.height=680; onboarding.close(); Theme.store.onboarded=true; win.rightPanel='settings'; sidePanel.tab='video'; player.openLocation('$E1',true)|+1300:sidePanel.scrollToVideoEffects()|+300:'videoEffects=' + (sidePanel.videoEffectTiles.map(effect => effect.value).join(',') === ',sepia,invert,posterize,oldmovie,gaussianblur,sharpen,vhs,grain' && sidePanel.visible && player.hasVideo)|+100:'videoEffectSource=' + sidePanel.videoEffectPreviewSource('sepia').includes('effect=preview-set')|+100:player.setConfig('video-filter','adjust')|+100:move:936,150|+100:click:936,150|+250:'sepiaFilterApplied=' + (player.config('video-filter')==='adjust,sepia' && sidePanel.activeVideoEffect==='sepia')|+100:sidePanel.scrollToVideoEffects()|+300:move:825,150|+100:click:825,150|+250:'originalFilterRestored=' + (player.config('video-filter')==='adjust' && sidePanel.activeVideoEffect==='')|+100:'gaussianBlurApplied=' + (sidePanel.setVideoEffect('gaussianblur') && player.config('video-filter')==='adjust,gaussianblur' && sidePanel.activeVideoEffect==='gaussianblur')|+500:'sharpenApplied=' + (sidePanel.setVideoEffect('sharpen') && player.config('video-filter')==='adjust,sharpen' && sidePanel.activeVideoEffect==='sharpen')|+500:'vhsApplied=' + (sidePanel.setVideoEffect('vhs') && player.config('video-filter')==='adjust,vhs' && sidePanel.activeVideoEffect==='vhs')|+500:'grainApplied=' + (sidePanel.setVideoEffect('grain') && player.config('video-filter')==='adjust,grain' && sidePanel.activeVideoEffect==='grain')|+100:sidePanel.setVideoEffect('')|+6200:'videoEffectPreviewsLoaded=' + ['', 'sepia','invert','posterize','oldmovie','gaussianblur','sharpen','vhs','grain'].every(effect => sidePanel.videoEffectPreviewLoaded(effect))|+100:(() => { player.setConfig('video-filter',''); player.setVideoFilterChain(''); sidePanel.syncVideoEffect(); return true })()|+100:quit" "$E1")
check "video effect previews offer the installed VLC effects" "$out" "videoEffects=true"
check "video effect tiles share a VLC-decoded preview frame" "$out" "videoEffectSource=true"
check "choosing Sepia applies the VLC filter and preserves picture adjustment" "$out" "sepiaFilterApplied=true"
check "Original clears the selected filter while preserving picture adjustment" "$out" "originalFilterRestored=true"
check "Gaussian blur applies through VLC and preserves picture adjustment" "$out" "gaussianBlurApplied=true"
check "Sharpen applies through VLC and preserves picture adjustment" "$out" "sharpenApplied=true"
check "VHS applies through VLC and preserves picture adjustment" "$out" "vhsApplied=true"
check "Grain applies through VLC and preserves picture adjustment" "$out" "grainApplied=true"
check "all video effect preview images load asynchronously" "$out" "videoEffectPreviewsLoaded=true"
if [ -s "$WORK/settings-video.png" ]; then echo "PASS  video preferences screenshot written"; pass=$((pass + 1))
else echo "FAIL  video preferences screenshot missing"; fail=$((fail + 1)); fi
out=$(run "1000:win.width=1048; win.height=865; Theme.store.mode='dark'; Theme.store.accent='#D37918'; Theme.store.subtitlePixelFontSize=37; player.setConfig('freetype-font','System, sans-serif'); player.setConfig('freetype-opacity',128); settingsDialog.page='subtitles'; settingsDialog.open()|+150:'subtitleTitle=' + settingsDialog.pageTitle + ' subtitleFrame=' + (win.width===1048 && win.height===865)|+100:'apiKeyFollowsAppearance=' + (() => { const api=settingsDialog.preferenceControl('opensubtitles-api-key-row'), font=settingsDialog.preferenceControl('vlc-option-freetype-font'); return !!api && !!font && api.mapToItem(win.contentItem,0,0).y > font.mapToItem(win.contentItem,0,0).y })()|+100:'apiKeyControlsFit=' + (() => { const f=settingsDialog.openSubtitlesApiKeyField, s=settingsDialog.openSubtitlesApiKeySaveAction, r=settingsDialog.openSubtitlesApiKeyRemoveAction; const row=settingsDialog.preferenceControl('opensubtitles-api-key-row'); const fp=f.mapToItem(win.contentItem,0,0), sp=s.mapToItem(win.contentItem,0,0), rp=r.mapToItem(win.contentItem,0,0); return !!row && row.labelTopAligned && f.visible && s.visible && r.visible && f.width>=310 && Math.abs(fp.x-716)<10 && sp.y>=fp.y+f.height+4 && Math.abs(sp.y-rp.y)<3 && rp.x>=sp.x+s.width && rp.x+r.width<=win.width-12 })()|+100:'subtitleReferenceValues=' + (player.config('freetype-font') === 'System, sans-serif' && player.config('freetype-opacity') === 128 && settingsDialog.subtitleSizeMode === 'relative')|+100:grab:$WORK/settings-subtitles.png|+100:'subtitleBasicOptions=' + ['subsdec-encoding','freetype-bold','freetype-color','freetype-opacity','freetype-outline-thickness','freetype-outline-color','freetype-shadow-opacity'].every(x => settingsDialog.optionVisible(x))|+100:'colorEditor=' + (settingsDialog.optionColorValue('freetype-color','#D37918') === 0xD37918 && settingsDialog.optionColorHex('freetype-color',0xD37918) === '#D37918')|+100:'sizeModeStartsRelative=' + (settingsDialog.subtitleSizeMode === 'relative')|+100:settingsDialog.setSubtitleSizeMode('pixels')|+100:'pixelMode=' + (player.config('freetype-fontsize') > 0 && settingsDialog.optionVisible('freetype-fontsize') && !settingsDialog.optionVisible('freetype-rel-fontsize'))|+100:settingsDialog.setSubtitleSizeMode('relative')|+100:'relativeMode=' + (player.config('freetype-fontsize') === 0 && settingsDialog.optionVisible('freetype-rel-fontsize') && !settingsDialog.optionVisible('freetype-fontsize'))|+100:settingsDialog.setSubtitleSizeMode('pixels')|+100:'pixelSizeRestored=' + (player.config('freetype-fontsize') === Theme.store.subtitlePixelFontSize)|+100:settingsDialog.setSubtitleSizeMode('relative')|+100:'subtitleConfigRoundTrip=' + (() => { const names=['subsdec-encoding','freetype-color','freetype-bold','freetype-opacity']; const old=names.map(x=>player.config(x)); player.setConfig(names[0],'UTF-8'); player.setConfig(names[1],0xD37918); player.setConfig(names[2],!old[2]); player.setConfig(names[3],128); const ok=player.config(names[0])==='UTF-8' && player.config(names[1])===0xD37918 && player.config(names[2])===!old[2] && player.config(names[3])===128; names.forEach((x,i)=>player.setConfig(x,old[i])); return ok })()|+100:'shadowToggleSetup=' + settingsDialog.setOptionValue('freetype-shadow-opacity',128)|+100:settingsDialog.scrollControlIntoView('subtitle-shadow-toggle')|+250:click-item:subtitle-shadow-toggle|+100:'shadowTurnsOff=' + (player.config('freetype-shadow-opacity')===0)|+100:click-item:subtitle-shadow-toggle|+100:'shadowRestoresOpacity=' + (player.config('freetype-shadow-opacity')===128)|+100:player.setConfig('freetype-shadow-opacity',255)|+100:win.width=720; win.height=560|+250:settingsDialog.scrollControlIntoView('opensubtitles-api-key-remove-compact')|+250:'apiKeyCompactFit=' + (() => { const f=settingsDialog.preferenceControl('opensubtitles-api-key-compact'), s=settingsDialog.preferenceControl('opensubtitles-api-key-save-compact'), r=settingsDialog.preferenceControl('opensubtitles-api-key-remove-compact'); const fp=f.mapToItem(win.contentItem,0,0), sp=s.mapToItem(win.contentItem,0,0), rp=r.mapToItem(win.contentItem,0,0); return win.width<800 && f.visible && s.visible && r.visible && f.width>0 && fp.x>=0 && fp.x+f.width<=win.width-12 && sp.y>=fp.y+f.height+2 && Math.abs(sp.y-rp.y)<3 && rp.x+r.width<=win.width-12 })()|+100:grab:$WORK/settings-subtitles-compact.png|+100:win.width=1048; win.height=865|+100:settingsDialog.close()|+100:quit" "$E1")
check "subtitle preferences use the Figma title" "$out" "subtitleTitle=Subtitle Defaults"
check "subtitle preferences render at the exact 1048×865 Figma frame size" "$out" "subtitleFrame=true"
check "OpenSubtitles API key field aligns with preference controls and actions sit below it" "$out" "apiKeyControlsFit=true"
check "OpenSubtitles key setup follows the Figma subtitle appearance controls" "$out" "apiKeyFollowsAppearance=true"
check "subtitle screenshot uses the Figma font, relative sizing and 50% opacity" "$out" "subtitleReferenceValues=true"
check "OpenSubtitles API key controls fit the compact settings window" "$out" "apiKeyCompactFit=true"
check "Figma subtitle defaults map to available VLC options" "$out" "subtitleBasicOptions=true"
check "VLC subtitle colors parse from and format as hex" "$out" "colorEditor=true"
check "subtitle size mode starts in relative values" "$out" "sizeModeStartsRelative=true"
check "pixel size mode uses the exact VLC pixel-size option" "$out" "pixelMode=true"
check "relative size mode restores VLC's automatic pixel size" "$out" "relativeMode=true"
check "switching size modes preserves the previous pixel size" "$out" "pixelSizeRestored=true"
check "subtitle encoding, color, bold and opacity save to VLC" "$out" "subtitleConfigRoundTrip=true"
check "the Figma shadow switch turns the VLC shadow off" "$out" "shadowTurnsOff=true"
check "turning the Figma shadow switch back on restores its opacity" "$out" "shadowRestoresOpacity=true"
if [ -s "$WORK/settings-subtitles.png" ]; then echo "PASS  subtitle preferences screenshot written"; pass=$((pass + 1))
else echo "FAIL  subtitle preferences screenshot missing"; fail=$((fail + 1)); fi
extensionShotSandbox="$WORK/extensions-screenshot-sandbox"
mkdir -p "$extensionShotSandbox/config/vlc-neo" "$extensionShotSandbox/config/vlc"
printf '[appearance]\nonboarded=true\n' > "$extensionShotSandbox/config/vlc-neo/neo.conf"
out=$(NEO_SANDBOX="$extensionShotSandbox" run "900:win.width=1048; win.height=865; Theme.store.mode='dark'; Theme.store.accent='#D37918'; settingsDialog.open(); settingsDialog.page='extensions'|+250:'extensionsTitle=' + settingsDialog.pageTitle + ' layout=' + settingsDialog.extensionCatalogLayoutMatches()|+100:'addonActionLifecycle=' + (() => { const id='smoke-addon-action'; settingsDialog.addonActionUuid=id; settingsDialog.addonAction='install'; settingsDialog.addonStatus='Installing add-on…'; settingsDialog.updateAddonAction({uuid:id,installing:true,removing:false,installed:false}); const pendingInstall=settingsDialog.addonActionUuid===id && settingsDialog.addonStatus==='Installing add-on…'; settingsDialog.updateAddonAction({uuid:id,installing:false,removing:false,installed:true}); const installed=settingsDialog.addonActionUuid==='' && settingsDialog.addonStatus==='Add-on installed.'; settingsDialog.addonActionUuid=id; settingsDialog.addonAction='remove'; settingsDialog.addonStatus='Removing add-on…'; settingsDialog.updateAddonAction({uuid:id,installing:false,removing:true,installed:true}); const pendingRemove=settingsDialog.addonActionUuid===id && settingsDialog.addonStatus==='Removing add-on…'; settingsDialog.updateAddonAction({uuid:id,installing:false,removing:false,installed:false}); const removed=settingsDialog.addonActionUuid==='' && settingsDialog.addonStatus==='Add-on removed.'; settingsDialog.addonActionUuid=id; settingsDialog.addonAction='install'; settingsDialog.addonStatus='Installing add-on…'; settingsDialog.updateAddonAction({uuid:id,installing:false,removing:false,installed:false}); const failed=settingsDialog.addonActionUuid==='' && settingsDialog.addonStatus==='VLC could not install this add-on.'; return pendingInstall && installed && pendingRemove && removed && failed })()|+100:'addonPackageStatusLifecycle=' + (() => { settingsDialog.addonPackageKnownUuids=['known']; settingsDialog.addonPackageImportPending=true; settingsDialog.finishAddonPackageImport(); return !settingsDialog.addonPackageImportPending && settingsDialog.addonPackageKnownUuids.length===0 && settingsDialog.addonStatus==='VLC could not read or find an installable add-on in the selected package.' })()|+200:grab:$WORK/settings-extensions.png|+100:quit")
check "the add-ons page uses the Figma title and catalog-before-search layout" "$out" "extensionsTitle=Add-ons & Scripts layout=true"
check "VLC add-on status follows asynchronous install and removal results" "$out" "addonActionLifecycle=true"
check "local add-on package reports read success and failure" "$out" "addonPackageStatusLifecycle=true"
out=$(NEO_SANDBOX="$extensionShotSandbox" run "100:player.setConfig('qt-autoload-extensions',true); settingsDialog.open(); settingsDialog.page='extensions'|+800:'extensionStartupType=' + player.configType('qt-autoload-extensions') + '/' + (settingsDialog.preferenceControl('vlc-option-qt-autoload-extensions').current === true)|+100:click-item:vlc-option-switch-qt-autoload-extensions|+200:'extensionStartupDisabled=' + (player.config('qt-autoload-extensions') === false && settingsDialog.preferenceControl('vlc-option-qt-autoload-extensions').current === false)|+100:quit")
check "the add-on startup control maps to VLC's boolean option" "$out" "extensionStartupType=bool/true"
check "turning off the add-on startup switch changes VLC's preference" "$out" "extensionStartupDisabled=true"
out=$(NEO_SANDBOX="$extensionShotSandbox" run "100:settingsDialog.open(); settingsDialog.page='extensions'|+700:'extensionStartupPersists=' + (player.config('qt-autoload-extensions') === false && settingsDialog.preferenceControl('vlc-option-qt-autoload-extensions').current === false)|+100:click-item:vlc-option-switch-qt-autoload-extensions|+200:'extensionStartupRestored=' + (player.config('qt-autoload-extensions') === true)|+100:quit")
check "the add-on startup preference persists in VLC across relaunch" "$out" "extensionStartupPersists=true"
check "the add-on startup switch can be turned back on" "$out" "extensionStartupRestored=true"
out=$(NEO_SANDBOX="$extensionShotSandbox" run "100:settingsDialog.open(); settingsDialog.page='extensions'|+300:settingsDialog.importAddonPackage('file://$HERE/tests/fixtures/neo-disposable-test.vlp')|+31500:'addonPackageImportSettled=' + (!settingsDialog.addonPackageImportPending && !settingsDialog.addonActionUuid && !player.addonsLoading && ((['VLC could not read or find an installable add-on in the selected package.','VLC found no installable add-on in this package.','Add-on already installed.','Add-on installed.','VLC could not install this add-on.'].indexOf(settingsDialog.addonStatus) >= 0) ? true : /^\\d+ add-ons available\\.$/.test(settingsDialog.addonStatus)))|+100:'addonPackageImportStatus=' + settingsDialog.addonStatus|+100:quit")
check "a local .vlp import reaches a terminal VLC package result" "$out" "addonPackageImportSettled=true"
out=$(NEO_SANDBOX="$extensionShotSandbox" run "100:settingsDialog.open(); settingsDialog.page='extensions'|+200:'packageCandidateSkipsKnownAndUninstallable=' + (() => { settingsDialog.addonPackageKnownUuids=['known']; const addon=settingsDialog.packageAddonCandidate([{uuid:'known',manageable:true,installed:false},{uuid:'plugin',manageable:false,installed:false},{uuid:'installed',manageable:true,installed:true},{uuid:'new',manageable:true,installed:false}]); return addon && addon.uuid==='new' })()|+100:'packageImportDispatchesInstallation=' + (() => { settingsDialog.addonPackageKnownUuids=['known']; settingsDialog.addonPackageImportPending=true; settingsDialog.handleAddonPackageEntries([{uuid:'new',manageable:true,installed:false}]); return !settingsDialog.addonPackageImportPending && settingsDialog.addonActionUuid==='' && settingsDialog.addonStatus==='VLC could not install this add-on.' })()|+100:quit")
check "local packages select only a newly discovered installable add-on" "$out" "packageCandidateSkipsKnownAndUninstallable=true"
check "a discovered local package is dispatched to VLC for installation" "$out" "packageImportDispatchesInstallation=true"
if [ -s "$WORK/settings-extensions.png" ]; then echo "PASS  add-ons preferences screenshot written"; pass=$((pass + 1))
else echo "FAIL  add-ons preferences screenshot missing"; fail=$((fail + 1)); fi
out=$(run "500:player.setConfig('subsdec-encoding','UTF-8'); player.setConfig('freetype-color',0xD37918); player.setConfig('freetype-bold',true); player.setConfig('freetype-opacity',117)|+100:quit")
check "subtitle preference setup exits cleanly" "$out" "subsdec-encoding"
out=$(run "500:'subtitlePrefsPersist=' + (player.config('subsdec-encoding')==='UTF-8' && player.config('freetype-color')===0xD37918 && player.config('freetype-bold')===true && player.config('freetype-opacity')===117)|+100:'subtitlePixelSizePersists=' + (Theme.store.subtitlePixelFontSize===37)|+100:quit")
check "subtitle VLC preferences persist after relaunch" "$out" "subtitlePrefsPersist=true"
check "custom pixel subtitle size persists after relaunch" "$out" "subtitlePixelSizePersists=true"

echo "== Figma interface preferences"
interfaceShotSandbox="$WORK/interface-screenshot-sandbox"
mkdir -p "$interfaceShotSandbox/config/vlc-neo" "$interfaceShotSandbox/config/vlc"
printf '[appearance]\nonboarded=true\n' > "$interfaceShotSandbox/config/vlc-neo/neo.conf"
# Match the Figma reference state while still launching this run through Neo.
printf 'intf=skins2\nqt-video-autoresize=0\nqt-name-in-title=1\nqt-fullscreen-screennumber=-1\nqt-system-tray=1\nqt-notification=1\n' > "$interfaceShotSandbox/config/vlc/vlcrc"
NEO_SANDBOX="$interfaceShotSandbox" out=$(run "1000:win.width=1048; win.height=865; Theme.store.mode='dark'; Theme.store.accent='#D37918'; Theme.store.hideDelay=500; Theme.store.autoHideMode='fullscreen'; Theme.store.showControlsFullscreen=true; Theme.store.compactAtStart=false; settingsDialog.page='interface'; settingsDialog.open()|+250:grab:$WORK/settings-interface.png|+100:quit")
out=$(run "700:settingsDialog.page='interface'; settingsDialog.open()|+100:'interfaceSkinOptions=' + (() => { const skin=settingsDialog.skinInterfaceAvailable ? (settingsDialog.optionVisible('intf') && settingsDialog.optionVisible('skins2-last')) : (!settingsDialog.optionVisible('intf') && !settingsDialog.optionVisible('skins2-last') && settingsDialog.skinUnavailableMessageVisible); const windowOptions=['embedded-video','video-deco']; return skin && windowOptions.every(x => player.config(x) !== undefined ? settingsDialog.optionVisible(x) : !settingsDialog.optionVisible(x)) })()|+100:'interfaceSkinRoundTrip=' + (() => { if (!settingsDialog.skinInterfaceAvailable) return !settingsDialog.optionVisible('intf') && !settingsDialog.optionVisible('skins2-last') && settingsDialog.skinUnavailableMessageVisible; const oldIntf=String(player.config('intf')); const oldSkin=String(player.config('skins2-last')); const enabled=settingsDialog.setSkinInterfaceEnabled(true) && player.config('intf')==='skins2'; const notice=settingsDialog.skinRestartNotice.includes('Restart VLC'); player.setConfig('skins2-last','/tmp/neo-test-skin.vlt'); const path=player.config('skins2-last')==='/tmp/neo-test-skin.vlt'; const names=['embedded-video','video-deco']; const values=names.map(x => !player.config(x)); const supported=names.map((name,i)=>({name,value:values[i],old:player.config(name)})).filter(option => option.old !== undefined); supported.forEach(option => player.setConfig(option.name,option.value)); const windowOptions=supported.every(option => player.config(option.name)===option.value); const disabled=settingsDialog.setSkinInterfaceEnabled(false) && player.config('intf')==='neo'; player.setConfig('skins2-last',oldSkin); supported.forEach(option => player.setConfig(option.name,option.old)); player.setConfig('intf',oldIntf); return [enabled,notice,path,windowOptions,disabled].every(Boolean) })()|+100:settingsDialog.scrollControlIntoView('skin-file-browse')|+200:click-item:skin-file-browse|+100:'skinPickerOpens=' + (!settingsDialog.skinInterfaceAvailable ? true : settingsDialog.skinFileDialogVisible)|+100:settingsDialog.closeSkinFilePicker()|+100:settingsDialog.close()|+100:quit")
check "skin options are usable when VLC exposes them and explained when absent" "$out" "interfaceSkinOptions=true"
check "skin preferences persist or are hidden with a VLC-build explanation" "$out" "interfaceSkinRoundTrip=true"
check "skin file Browse opens only when the VLC skin module is available" "$out" "skinPickerOpens=true"
out=$(run "1000:player.openLocation('$E1', true); Theme.store.mode='dark'; Theme.store.accent='#D37918'; settingsDialog.page='interface'; settingsDialog.open()|+900:'interfaceTitle=' + settingsDialog.pageTitle + '/' + !settingsDialog.optionVisible('fullscreen') + '/' + settingsDialog.optionVisible('qt-video-autoresize') + '/' + settingsDialog.optionVisible('qt-fullscreen-screennumber') + '/' + settingsDialog.optionVisible('qt-system-tray') + '/' + settingsDialog.optionVisible('qt-notification')|+150:click-item:auto-hide-delay|+100:'sliderMouse=' + Theme.store.hideDelay|+100:key:Right|+100:'sliderKeyboard=' + Theme.store.hideDelay|+100:Theme.store.autoHideMode='always'; 'alwaysHides=' + win.overlayMode|+100:Theme.store.autoHideMode='never'; 'neverShows=' + !win.overlayMode|+100:(() => { const old = player.config('video-on-top'); player.setConfig('video-on-top', true); win.refreshWindowFlags(); const on = !!(win.flags & Qt.WindowStaysOnTopHint); player.setConfig('video-on-top', false); win.refreshWindowFlags(); const off = !(win.flags & Qt.WindowStaysOnTopHint); player.setConfig('video-on-top', old); win.refreshWindowFlags(); return 'topFlags=' + on + '/' + off })()|+100:(() => { const title=player.title; win.refreshWindowTitle(false); const hidden=!win.showMediaTitle && topBar.titleLabel.text==='VLC Media Player'; win.refreshWindowTitle(true); const shown=title.length>0 && topBar.titleLabel.text===title; return 'titlePreference=' + shown + '/' + hidden })()|+100:win.refreshSystemTray(false)|+100:'trayOff=' + !systemTray.visible|+100:win.refreshSystemTray(true)|+100:'trayOn=' + (systemTray.available ? systemTray.visible : true)|+100:'notificationService=' + systemTray.notificationServiceAvailable|+100:(() => { const old = player.config('qt-fullscreen-screennumber'); const selected = platform.selectFullscreenScreen(win, 0); player.setConfig('qt-fullscreen-screennumber', 0); const roundTrip = Number(player.config('qt-fullscreen-screennumber')) === 0; player.setConfig('qt-fullscreen-screennumber', old); return 'screenChoice=' + selected + '/' + roundTrip })()|+100:(() => { const old = player.config('qt-video-autoresize'); player.setConfig('qt-video-autoresize', !old); const saved = player.config('qt-video-autoresize') === !old; player.setConfig('qt-video-autoresize', old); return 'videoAutoresize=' + saved })()|+100:quit")
check "interface preferences match the Figma category grouping for resize, display and notifications" "$out" "interfaceTitle=Interface Settings/true/true/true/true/true"
check "video resize preference writes through to VLC" "$out" "videoAutoresize=true"
check "the auto-hide slider responds to pointer input" "$out" "sliderMouse=5000"
check "the auto-hide slider responds to keyboard input" "$out" "sliderKeyboard=5100"
check "always auto-hide applies in a normal window" "$out" "alwaysHides=true"
check "never auto-hide keeps controls visible in a normal window" "$out" "neverShows=true"
check "keep-above preference updates the window flag and can be disabled" "$out" "topFlags=true/true"
check "the top bar shows the current media title and honors the VLC title preference" "$out" "titlePreference=true/true"
check "system-tray option removes and restores the desktop tray item" "$out" "trayOff=true"
check "system-tray option restores the icon when a watcher is available" "$out" "trayOn=true"
check "fullscreen monitor selection uses a detected Qt screen and persists in VLC" "$out" "screenChoice=true/true"
out=$(run "500:Theme.store.rememberWindowGeometry=false; settingsDialog.page='interface'; settingsDialog.open()|+150:click-item:remember-window-geometry-switch|+100:'switchClick=' + Theme.store.rememberWindowGeometry|+100:key:Space|+100:'switchSpace=' + !Theme.store.rememberWindowGeometry|+100:Theme.store.rememberWindowGeometry=true|+100:quit")
check "preference switches take focus on click and toggle with Space" "$out" "switchClick=true"
check "focused preference switches toggle with Space" "$out" "switchSpace=true"
out=$(run "500:Theme.store.autoHideMode='fullscreen'; settingsDialog.page='interface'; settingsDialog.open()|+150:click-item:auto-hide-mode|+100:click-item:auto-hide-mode|+150:'dropdownDismissed=' + (win.activeFocusItem && win.activeFocusItem.objectName === 'auto-hide-mode')|+100:key:Space|+100:key:Down|+100:key:Return|+150:'dropdownKeyboard=' + (Theme.store.autoHideMode === 'always')|+100:Theme.store.autoHideMode='fullscreen'|+100:quit")
check "clicking a dropdown trigger again closes its menu" "$out" "dropdownDismissed=true"
check "keyboard navigation selects an option in a focused dropdown" "$out" "dropdownKeyboard=true"
if [ -s "$WORK/settings-interface.png" ]; then echo "PASS  interface settings screenshot written"; pass=$((pass + 1))
else echo "FAIL  interface settings screenshot missing"; fail=$((fail + 1)); fi
out=$(run "200:Theme.store.compactAtStart=false; win.width=930; win.height=610; win.x=24; win.y=32; win.saveWindowGeometry(); 'geometrySaved=' + (Theme.store.hasWindowGeometry && Theme.store.windowWidth === 930 && Theme.store.windowHeight === 610 && Theme.store.windowX === 24 && Theme.store.windowY === 32)|+100:quit")
check "window size and position are saved" "$out" "geometrySaved=true"
out=$(run "250:'geometryRestored=' + (win.width === 930 && win.height === 610 && win.x === 24 && win.y === 32)|+100:win.width=1120; win.height=680; win.x=0; win.y=0; Theme.store.compactAtStart=true|+100:quit")
check "window size and position restore on the next launch" "$out" "geometryRestored=true"
out=$(run "150:player.setConfig('qt-fullscreen-screennumber', 0); player.setConfig('fullscreen', true); player.openUrls([platform.fileUrl('$E1')], true)|+1800:'startFullscreen=' + win.fullscreen + '/' + platform.fullscreenScreenIndex(win)|+100:win.setFullscreen(false); player.setConfig('fullscreen', false); player.setConfig('qt-fullscreen-screennumber', -1)|+100:quit")
check "fullscreen-on-open targets the selected display" "$out" "startFullscreen=true/0"
out=$(run "100:onboarding.close(); Theme.store.autoHideMode='never'; win.width=1120; win.height=680; win.x=40; win.y=50; player.openLocation('$E1', true)|+900:key:F11|+250:'fullscreenToggle=' + (win.fullscreen && !win.overlayMode && topBar.visible && controlBar.visible && controlBar.findControl('seek').visible && !navigationRail.visible)|+100:grab:$WORK/fullscreen-controls.png|+100:key:F11|+250:'fullscreenRestore=' + (!win.fullscreen && win.width === 1120 && win.height === 680 && win.x === 40 && win.y === 50)|+100:quit" "$E1")
check "F11 enters fullscreen with playback controls visible and no library rail" "$out" "fullscreenToggle=true"
check "F11 exits fullscreen and restores the previous window geometry" "$out" "fullscreenRestore=true"
if [ -s "$WORK/fullscreen-controls.png" ]; then echo "PASS  fullscreen controls screenshot written"; pass=$((pass + 1))
else echo "FAIL  fullscreen controls screenshot missing"; fail=$((fail + 1)); fi
out=$(run "200:move:560,340|+100:win.run('hideui'); 'hideCommand=' + win.uiHidden|+200:win.topHot=false; win.bottomHot=false; 'hideCommandToast=' + !toastItem.visible|+150:'emptyHidden=' + (!homeView.visible && !win.bottomShown && !navigationRail.visible)|+100:win.uiHidden=false|+100:quit")
check "Ctrl+H hides the empty-state controls when no media is loaded" "$out" "emptyHidden=true"
check "the Hide UI action suppresses its confirmation toast" "$out" "hideCommandToast=true"
out=$(run "1000:player.openUrls([platform.fileUrl('$E1')],true)|+1800:player.togglePause(); win.width=1920; win.height=1080; Theme.store.autoHideMode='always'; Theme.store.hideDelay=500|+100:move:960,540|+100:win.uiHidden=true; win.topHot=false; win.bottomHot=false|+150:'hiddenUI=' + (!win.chromeShown && !win.topShown && !win.bottomShown && !navigationRail.visible && !homeView.visible)|+100:move:960,20|+100:'edgeReveals=' + (win.topHot && win.chromeShown)|+100:move:960,540|+50:win.topHot=false; win.bottomHot=false|+100:move:960,1060|+100:'bottomEdgeReveals=' + (win.bottomHot && win.bottomShown && win.chromeShown)|+100:move:960,540|+50:win.topHot=false; win.bottomHot=false|+150:'centerHides=' + (!win.chromeShown && !win.topShown && !win.bottomShown)|+150:grab:$WORK/hidden-ui.png|+100:win.uiHidden=false; Theme.store.hideDelay=5100|+100:quit" --no-osd --no-video-title-show "$E1")
check "Ctrl+H hides player chrome and the empty-state view" "$out" "hiddenUI=true"
check "moving to the top edge reveals hidden controls" "$out" "edgeReveals=true"
check "moving to the bottom edge reveals hidden transport controls" "$out" "bottomEdgeReveals=true"
check "moving to the center hides the controls again" "$out" "centerHides=true"
if [ -s "$WORK/hidden-ui.png" ]; then echo "PASS  hidden UI screenshot written"; pass=$((pass + 1))
else echo "FAIL  hidden UI screenshot missing"; fail=$((fail + 1)); fi
out=$(run "1000:'interfacePreferencesPersist=' + (Theme.store.hideDelay === 5100 && Theme.store.autoHideMode === 'always' && Theme.store.showControlsFullscreen && Theme.store.compactAtStart)|+100:'compactStart=' + (win.width === 560 && win.height === 340)|+100:Theme.store.compactAtStart=false; Theme.store.showControlsFullscreen=false; Theme.store.autoHideMode='fullscreen'; win.width=1120; win.height=680|+100:quit")
check "interface preferences persist across launches" "$out" "interfacePreferencesPersist=true"
check "compact mode changes the next launch size" "$out" "compactStart=true"
out=$(run "800:win.width=1048; win.height=865; settingsDialog.page='interface'; settingsDialog.open()|+200:settingsDialog.scrollControlIntoView('show-onboarding')|+200:click-item:show-onboarding|+300:'onboardingAccess=' + onboarding.visible|+100:onboarding.close(); settingsDialog.close(); win.width=560; win.height=340; settingsDialog.page='interface'; settingsDialog.open()|+200:'compactSettings=' + (settingsDialog.compactCategories && Math.round(settingsDialog.width) === 560 && Math.round(settingsDialog.height) === 340 && settingsDialog.preferenceControlWidth('auto-hide-mode') === 320)|+100:move-item:settings-category-controls|+800:(() => { const item=settingsDialog.preferenceControl('settings-category-controls'); return 'compactCategoryTooltip=' + item.ToolTip.visible + '/' + item.ToolTip.text })()|+100:(() => { const item=settingsDialog.preferenceControl('settings-category-controls'); item.forceActiveFocus(); return 'compactCategoryFocus=' + item.activeFocus })()|+100:key:Space|+100:'compactCategoryKeyboard=' + (settingsDialog.page === 'controls')|+100:settingsDialog.close(); win.width=1120; win.height=680|+100:quit")
check "onboarding remains available from Interface settings" "$out" "onboardingAccess=true"
check "Interface settings stay usable at a compact 560×340 window size" "$out" "compactSettings=true"
check "compact settings category icons expose their label on hover" "$out" "compactCategoryTooltip=true/Controls"
check "compact settings categories accept keyboard focus and Space activation" "$out" "compactCategoryFocus=true"
check "Space opens the focused compact settings category" "$out" "compactCategoryKeyboard=true"

echo "== timeline focus and keyboard navigation"
out=$(run "1200:'focus=' + controlBar.focusControl('seek')|+150:key:Right|+400:'right=' + (player.time >= 5000)|+100:key:Left|+400:'left=' + (player.time < 5000)|+150:grab:$WORK/timeline-focus.png|+150:key:Home|+600:'home=' + (player.position < 0.02)|+150:key:End|+800:'endState=' + player.state|+150:quit" "$E1")
check "timeline accepts keyboard focus" "$out" "focus=true"
check "focused timeline seeks right" "$out" "right=true"
check "focused timeline seeks left" "$out" "left=true"
check "Home moves to the start" "$out" "home=true"
check "End plays to the end of the media" "$out" "endState=0"
check "focused timeline consumes Home and End" "$out" "key End delivered (1)"
if [ -s "$WORK/timeline-focus.png" ]; then echo "PASS  focused timeline screenshot written"; pass=$((pass + 1))
else echo "FAIL  focused timeline screenshot missing"; fail=$((fail + 1)); fi

echo "== asynchronous seek thumbnail"
out=$(run "1000:onboarding.close(); win.width=1120; win.height=680; win.navigationPage='player'; Theme.store.showSeekThumbnails=true|+500:'seekReadyToHover=' + controlBar.findControl('seek').visible + '/' + player.seekable|+100:move:500,650|+500:'thumbnailSourceFromHover=' + controlBar.findControl('seek').contentItem.pointerHovered + '/' + (controlBar.findControl('seek').contentItem.thumbnailSource.length > 0)|+5000:'thumbnailReady=' + controlBar.findControl('seek').contentItem.thumbnailReady|+100:quit" "$E1")
check "the Player timeline is visible and seekable before thumbnail hover" "$out" "seekReadyToHover=true/true"
check "hovering the timeline requests a local-video preview" "$out" "thumbnailSourceFromHover=true/true"
check "the hovered video frame decodes asynchronously" "$out" "thumbnailReady=true"
echo "== seek thumbnail updates coalesce rapid pointer movement"
out=$(run "1000:onboarding.close(); win.width=1120; win.height=680; win.navigationPage='player'; player.openLocation('$WORK/seek-scenes.mkv',true)|+1000:move:300,650|+60:move:380,650|+60:move:460,650|+60:move:540,650|+60:move:620,650|+60:move:660,650|+4500:'rapidHoverPreview=' + (() => { const c=controlBar.findControl('seek').contentItem; return c.pointerHovered + '/' + c.pendingThumbnailSecond + '/' + c.requestedThumbnailSecond + '/' + c.displayedThumbnailSecond + '/' + c.thumbnailReady })()|+100:quit" "$WORK/seek-scenes.mkv")
check "rapid timeline movement keeps the latest preview request and decodes it" "$out" "rapidHoverPreview=true/-1/7/7/true"
echo "== seek thumbnails use the requested playback time and recover after cancellation"
out=$(run "800:(() => { win.width=1120; win.height=680; const later=Qt.createQmlObject('import QtQuick; Image { objectName:\"seekProbeLater\"; width:480;height:270;z:9999;asynchronous:true;cache:false }',win.contentItem,'seekProbeLater'); later.x=540; later.y=40; later.source='image://thumbnail/frame?path='+encodeURIComponent('$WORK/seek-scenes.mkv')+'&t=0'; const wasInFlight=later.status===Image.Loading; later.source='image://thumbnail/frame?path='+encodeURIComponent('$WORK/seek-scenes.mkv')+'&t=4'; const earlier=Qt.createQmlObject('import QtQuick; Image { objectName:\"seekProbeEarlier\"; width:480;height:270;z:9999;asynchronous:true;cache:false }',win.contentItem,'seekProbeEarlier'); earlier.x=40; earlier.y=40; earlier.source='image://thumbnail/frame?path='+encodeURIComponent('$WORK/seek-scenes.mkv')+'&t=0'; return 'seekCancelledWhileLoading=' + wasInFlight + ';seekRequestsReplaced=' + (later.source.toString().indexOf('&t=4') >= 0 && earlier.source.toString().indexOf('&t=0') >= 0) })()|+4000:'seekProbeReady=' + (win.contentItem.children.filter(x=>x.objectName==='seekProbeEarlier')[0].status === Image.Ready) + '/' + (win.contentItem.children.filter(x=>x.objectName==='seekProbeLater')[0].status === Image.Ready)|+100:grab:$WORK/seek-frame-probes.png|+100:quit" "$WORK/seek-scenes.mkv")
check "the replaced video thumbnail request was still loading" "$out" "seekCancelledWhileLoading=true"
check "replacing an in-flight thumbnail request admits the new seek and a concurrent request" "$out" "seekRequestsReplaced=true"
check "thumbnails at zero and four seconds both finish after request cancellation" "$out" "seekProbeReady=true/true"
if [[ -s "$WORK/seek-frame-probes.png" ]]; then
    earlierPixel=$(convert "$WORK/seek-frame-probes.png" -crop 1x1+280+175 txt:- | awk -F '[(),]' 'END { print $3, $4, $5 }')
    laterPixel=$(convert "$WORK/seek-frame-probes.png" -crop 1x1+780+175 txt:- | awk -F '[(),]' 'END { print $3, $4, $5 }')
    read -r earlierR earlierG earlierB <<< "$earlierPixel"
    read -r laterR laterG laterB <<< "$laterPixel"
    if (( earlierR > 180 && earlierB < 80 && laterB > 180 && laterR < 80 )); then
        echo "PASS  seek at zero decodes the red frame and seek at four seconds decodes the blue frame"
        pass=$((pass + 1))
    else
        echo "FAIL  seek thumbnails do not match their requested times (zero=$earlierPixel later=$laterPixel)"
        fail=$((fail + 1))
    fi
else
    echo "FAIL  seek-frame comparison screenshot missing"
    fail=$((fail + 1))
fi
thumbnailSandbox="$WORK/thumbnail-cap-sandbox"
out=$(NEO_SANDBOX="$thumbnailSandbox" run "100:onboarding.close(); var state=''; for(var i=0;i<80;i++) state+='P'; win.objectName=state; for(var j=0;j<80;j++){var im=Qt.createQmlObject(\"import QtQuick 2.15; Image { property int probeIndex: -1; asynchronous: true; cache: false; onStatusChanged: { var s=win.objectName; if(probeIndex>=0) win.objectName=s.substring(0,probeIndex)+(status===Image.Ready?'R':status===Image.Error?'E':'L')+s.substring(probeIndex+1) } }\",win,'thumbnail-overflow'); im.probeIndex=j; im.source='image://thumbnail/frame?path='+encodeURIComponent('$WORK/base.mkv')+'&t=5';}|+22000:'thumbnailBurst=' + (win.objectName.split('R').length-1) + ' ready; ' + (win.objectName.split('E').length-1) + ' errors; ' + (win.objectName.split('P').length-1) + ' pending'|+100:win.objectName += 'P'; var retry=Qt.createQmlObject(\"import QtQuick 2.15; Image { property int probeIndex: 80; asynchronous: true; cache: false; onStatusChanged: { var s=win.objectName; win.objectName=s.substring(0,probeIndex)+(status===Image.Ready?'R':status===Image.Error?'E':'L')+s.substring(probeIndex+1) } }\",win,'thumbnail-after-drain'); retry.source='image://thumbnail/frame?path='+encodeURIComponent('$WORK/base.mkv')+'&t=5'|+1500:'thumbnailAfterDrain=' + win.objectName.charAt(80)|+100:quit")
check "the 64-response thumbnail cap admits exactly 64 of 80 concurrent requests" "$out" "thumbnailBurst=64 ready; 16 errors; 0 pending"
check "a thumbnail request is admitted and completes after burst capacity drains" "$out" "thumbnailAfterDrain=R"
out=$(run "2500:'waveformRequest=' + controlBar.findControl('seek').contentItem.requestWaveform()|+5000:'waveformReady=' + controlBar.findControl('seek').contentItem.waveformReady|+100:quit" "$E1")
check "the seek waveform request accepts a local media file" "$out" "waveformRequest=true"
check "local-video waveform decodes asynchronously" "$out" "waveformReady=true"
out=$(run "2500:'audioOnly=' + !player.hasVideo + ' waveformRequest=' + controlBar.findControl('seek').contentItem.requestWaveform()|+5000:'waveformReady=' + controlBar.findControl('seek').contentItem.waveformReady|+100:quit" "$WORK/audio-only.m4a")
check "the audio-only player requests a waveform" "$out" "audioOnly=true waveformRequest=true"
check "audio-only waveform decodes asynchronously" "$out" "waveformReady=true"
out=$(run "2500:controlBar.findControl('seek').contentItem.requestWaveform()|+15000:'longWaveformReady=' + controlBar.findControl('seek').contentItem.waveformReady|+100:grab:$WORK/waveform-one-hour.png|+100:quit" "$WORK/long-waveform.mp3")
check "a one-hour local audio file produces its waveform asynchronously" "$out" "longWaveformReady=true"
if [ -s "$WORK/waveform-one-hour.png" ]; then echo "PASS  one-hour waveform screenshot written"; pass=$((pass + 1))
else echo "FAIL  one-hour waveform screenshot missing"; fail=$((fail + 1)); fi
echo "== cancelled waveform requests release decode capacity"
out=$(run "1000:win.width=1120;win.height=680;(() => { const a=Qt.createQmlObject('import QtQuick; Image { objectName:\"waveCancelA\"; width:2;height:2;asynchronous:true;cache:false }',win.contentItem,'waveCancelA'); const b=Qt.createQmlObject('import QtQuick; Image { objectName:\"waveCancelB\"; width:2;height:2;asynchronous:true;cache:false }',win.contentItem,'waveCancelB'); a.source='image://thumbnail/wave?path='+encodeURIComponent('$WORK/long-waveform.mp3')+'&duration=3600'; b.source='image://thumbnail/wave?path='+encodeURIComponent('$WORK/long-waveform.mp3')+'&duration=3600'; return 'longWaveformRequestsStarted=' + (a.status === Image.Loading && b.status === Image.Loading) })()|+250:(() => { const a=win.contentItem.children.filter(x=>x.objectName==='waveCancelA')[0]; const b=win.contentItem.children.filter(x=>x.objectName==='waveCancelB')[0]; const active=a.status===Image.Loading && b.status===Image.Loading; a.source='image://thumbnail/wave?path='+encodeURIComponent('$WORK/audio-only.m4a')+'&duration=40'; b.source='image://thumbnail/wave?path='+encodeURIComponent('$WORK/audio-only.m4a')+'&duration=40'; return 'longWaveformsCancelledWhileLoading=' + active })()|+5000:'replacementWaveformsReady=' + (win.contentItem.children.filter(x=>x.objectName==='waveCancelA')[0].status === Image.Ready) + '/' + (win.contentItem.children.filter(x=>x.objectName==='waveCancelB')[0].status === Image.Ready)|+100:quit" "$WORK/audio-only.m4a")
check "long waveform jobs are canceled while both decode workers are active" "$out" "longWaveformsCancelledWhileLoading=true"
check "short waveform requests finish after both long jobs are canceled" "$out" "replacementWaveformsReady=true/true"

echo "== track popup dismissal"
out=$(run "1200:tracksPopup.openFor('spu', controlBar.findControl('subtitle'))|+100:'defaultAudioTrackSelected=' + player.tracks('audio').some(track => track.id >= 0 && track.selected)|+100:'tabFocus=' + tracksPopup.focusTab('audio')|+100:key:Space|+100:'tabKeyboard=' + (tracksPopup.tab === 'audio')|+100:tracksPopup.close()|+100:quit" "$E1")
check "the first available audio track is selected by default" "$out" "defaultAudioTrackSelected=true"
check "track popup tabs accept keyboard focus" "$out" "tabFocus=true"
check "Space activates the focused audio tab" "$out" "tabKeyboard=true"
out=$(run "1200:tracksPopup.openFor('spu', controlBar.findControl('subtitle'))|+150:keyCatcher.forceActiveFocus()|+100:key:Esc|+100:'escapeClosed=' + !tracksPopup.visible|+100:quit" "$E1")
check "Escape closes the track popup while the main window has focus" "$out" "escapeClosed=true"
check "Escape is consumed while closing the track popup" "$out" "key Esc delivered (1)"
out=$(run "1200:move:500,850|+250:click-item:control-subtitle|+100:'opened=' + tracksPopup.visible|+100:click:500,300|+100:'outsideClosed=' + !tracksPopup.visible|+100:click-item:control-subtitle|+100:click-item:control-subtitle|+100:'toggleClosed=' + !tracksPopup.visible|+100:click-item:control-subtitle|+100:click-item:control-audio|+100:'switched=' + (tracksPopup.visible && tracksPopup.tab === 'audio')|+100:win.libraryOpen=true; tracksPopup.openFor('audio', controlBar.findControl('audio'))|+100:click:500,500|+100:'videoDismissesTrackPopup=' + (!tracksPopup.visible && libraryOpen)|+100:tracksPopup.close()|+100:quit" "$E1")
check "track popup opens" "$out" "opened=true"
check "clicking the video outside the track popup closes it" "$out" "outsideClosed=true"
check "clicking the same track control closes its popup" "$out" "toggleClosed=true"
check "clicking another track control switches the popup" "$out" "switched=true"
check "clicking the video dismisses tracks while leaving the side pane open" "$out" "videoDismissesTrackPopup=true"
out=$(run "1200:tracksPopup.openFor('spu', controlBar.findControl('subtitle'))|+100:click:500,50|+100:'windowClickCloses=' + !tracksPopup.visible|+100:quit" "$E1")
check "clicking elsewhere in the window closes the track popup" "$out" "windowClickCloses=true"
out=$(run "1200:tracksPopup.openFor('spu', controlBar.findControl('subtitle')); win.width=560; win.height=340|+200:'popupFitsCompact=' + (() => { const p = tracksPopup.parent.mapToItem(keyCatcher, tracksPopup.x, tracksPopup.y); return p.x >= 0 && p.y >= 0 && p.x + tracksPopup.width <= keyCatcher.width && p.y + tracksPopup.height <= keyCatcher.height })()|+100:grab:$WORK/track-popup-compact.png|+100:win.width=1120; win.height=680; tracksPopup.close()|+100:quit" "$E1")
check "track popup repositions within compact window bounds" "$out" "popupFitsCompact=true"
if [ -s "$WORK/track-popup-compact.png" ]; then echo "PASS  compact track popup screenshot written"; pass=$((pass + 1))
else echo "FAIL  compact track popup screenshot missing"; fail=$((fail + 1)); fi
out=$(run "700:win.width=1920; win.height=1080; tracksPopup.openFor('audio',controlBar.findControl('audio'))|+200:'audioPopupInitiallyFits=' + (() => { const p=tracksPopup.parent.mapToItem(keyCatcher,tracksPopup.x,tracksPopup.y); return p.x>=0 && p.y>=0 && p.x+tracksPopup.width<=keyCatcher.width && p.y+tracksPopup.height<=keyCatcher.height })()|+100:win.width=560; win.height=340|+400:'audioPopupFitsAfterShrink=' + (() => { const p=tracksPopup.parent.mapToItem(keyCatcher,tracksPopup.x,tracksPopup.y); return tracksPopup.visible && tracksPopup.tab==='audio' && p.x>=0 && p.y>=0 && p.x+tracksPopup.width<=keyCatcher.width && p.y+tracksPopup.height<=keyCatcher.height })()|+100:win.width=1920; win.height=1080|+400:'audioPopupFitsAfterGrow=' + (() => { const p=tracksPopup.parent.mapToItem(keyCatcher,tracksPopup.x,tracksPopup.y); return tracksPopup.visible && p.x>=0 && p.y>=0 && p.x+tracksPopup.width<=keyCatcher.width && p.y+tracksPopup.height<=keyCatcher.height })()|+100:tracksPopup.openFor('spu',controlBar.findControl('subtitle'))|+200:win.width=560; win.height=340|+400:'subtitlePopupFitsAfterShrink=' + (() => { const p=tracksPopup.parent.mapToItem(keyCatcher,tracksPopup.x,tracksPopup.y); return tracksPopup.visible && tracksPopup.tab==='spu' && p.x>=0 && p.y>=0 && p.x+tracksPopup.width<=keyCatcher.width && p.y+tracksPopup.height<=keyCatcher.height })()|+100:quit" "$E1")
check "an open Audio popup stays inside the window while shrinking and growing" "$out" "audioPopupInitiallyFits=true"
check "an open Audio popup repositions inside compact bounds when the window shrinks" "$out" "audioPopupFitsAfterShrink=true"
check "an open Audio popup repositions inside bounds when the window grows back" "$out" "audioPopupFitsAfterGrow=true"
check "an open Subtitles popup repositions inside compact bounds when the window shrinks" "$out" "subtitlePopupFitsAfterShrink=true"

echo "== audio and subtitle popup bounds in fullscreen"
out=$(run "700:onboarding.close(); Theme.store.autoHideMode='fullscreen'; Theme.store.showControlsFullscreen=false; win.width=1920; win.height=1080; player.openLocation('$E1',true)|+900:win.setFullscreen(true); win.topHot=true; win.bottomHot=true|+250:tracksPopup.openFor('audio',controlBar.findControl('audio'))|+200:'fullscreenAudioPopupFits=' + (() => { const p=tracksPopup.parent.mapToItem(keyCatcher,tracksPopup.x,tracksPopup.y); return tracksPopup.visible && p.x >= 0 && p.y >= topBar.y + topBar.height - 1 && p.x + tracksPopup.width <= keyCatcher.width && p.y + tracksPopup.height <= keyCatcher.height })()|+100:tracksPopup.openFor('spu',controlBar.findControl('subtitle'))|+200:'fullscreenSubtitlePopupFits=' + (() => { const p=tracksPopup.parent.mapToItem(keyCatcher,tracksPopup.x,tracksPopup.y); return tracksPopup.visible && p.x >= 0 && p.y >= topBar.y + topBar.height - 1 && p.x + tracksPopup.width <= keyCatcher.width && p.y + tracksPopup.height <= keyCatcher.height })()|+100:quit" "$E1")
check "fullscreen audio track popup stays below the title bar and inside the window" "$out" "fullscreenAudioPopupFits=true"
check "fullscreen subtitle track popup stays below the title bar and inside the window" "$out" "fullscreenSubtitlePopupFits=true"

echo "== fullscreen right-side panel clears the floating title bar"
out=$(run "700:onboarding.close(); Theme.store.autoHideMode='fullscreen'; Theme.store.showControlsFullscreen=false; win.width=1920; win.height=1080; player.openLocation('$E1',true)|+800:win.setFullscreen(true); win.topHot=true; sidePanel.tab='audio'; win.rightPanel='settings'|+300:'fullscreenPanelBelowTopbar=' + (win.fullscreen && win.overlayMode && sidePanel.mapToItem(keyCatcher,0,0).y >= topBar.y + topBar.height - 1 && sidePanel.mapToItem(keyCatcher,0,0).y + sidePanel.height <= keyCatcher.height)|+100:tracksPopup.openFor('audio',controlBar.findControl('audio'))|+150:'fullscreenAudioMenuVisible=' + tracksPopup.visible|+100:tracksPopup.openFor('spu',controlBar.findControl('subtitle'))|+150:'fullscreenSubtitleMenuVisible=' + tracksPopup.visible|+100:tracksPopup.close()|+100:move:700,700|+100:win.topHot=false|+250:'fullscreenPanelReturnsToTop=' + (topBar.y + topBar.height <= 1 && sidePanel.mapToItem(keyCatcher,0,0).y <= 1)|+100:quit" "$E1")
check "fullscreen right sidebar starts below the visible floating title bar" "$out" "fullscreenPanelBelowTopbar=true"
check "fullscreen audio picker opens over the right sidebar" "$out" "fullscreenAudioMenuVisible=true"
check "fullscreen subtitle picker opens over the right sidebar" "$out" "fullscreenSubtitleMenuVisible=true"
check "fullscreen right sidebar fills the top edge after the title bar hides" "$out" "fullscreenPanelReturnsToTop=true"

echo "== side panel dismissal"
out=$(run "1200:win.rightPanel='settings'; sidePanel.tab='spu'|+100:'tabFocus=' + sidePanel.focusTab('audio')|+100:key:Space|+100:'tabKeyboard=' + (sidePanel.tab === 'audio')|+100:win.focusKeys()|+100:click-item:video-click-area|+100:'closed=' + (win.rightPanel === '')|+100:quit" "$E1")
check "settings panel tabs accept keyboard focus" "$out" "tabFocus=true"
check "Space activates the focused audio settings tab" "$out" "tabKeyboard=true"
check "clicking the video closes the audio/subtitle panel" "$out" "closed=true"

echo "== equalizer preset controls"
raw=$(NEO_TIMEOUT=40 "$HERE/scripts/run-offscreen.sh" "1500:player.setEqualizerPreset('rock'); 'selected=' + player.equalizerPreset()|+100:quit" "$WORK/audio-only.m4a" 2>&1)
out=$(grep "neo test" <<<"$raw")
check "the equalizer preset applies through the player" "$out" "selected=rock"
if grep -qF "No preset selected" <<<"$raw" || grep -qF 'cannot add user audio filter "equalizer"' <<<"$raw"; then
    echo "FAIL  VLC accepted the equalizer preset without filter errors"; fail=$((fail + 1))
else
    echo "PASS  VLC loads the selected equalizer without filter errors"; pass=$((pass + 1))
fi
out=$(run "1200:'restored=' + player.equalizerPreset()|+100:quit" "$WORK/audio-only.m4a")
check "the selected equalizer preset persists across VLC launches" "$out" "restored=rock"
out=$(run "1200:player.setEqualizerPreset('off'); 'disabled=' + player.equalizerPreset()|+100:quit" "$WORK/audio-only.m4a")
check "the Off preset disables the VLC equalizer" "$out" "disabled=off"
out=$(run "1200:settingsDialog.open(); settingsDialog.page='audio'; settingsDialog.syncEqualizerSettings(); 'audioFxUi=' + (settingsDialog.equalizerFrequencies.length === 10) + '/' + (settingsDialog.equalizerBandValues.length === 10) + '/' + (settingsDialog.equalizerPresetState === 'off') + '/' + (player.configType('equalizer-bands') === 'string' && player.configType('equalizer-preamp') === 'float' && player.configType('equalizer-2pass') === 'bool')|+100:'audioFxRoundTrip=' + (() => { const bands=player.config('equalizer-bands'), preamp=player.config('equalizer-preamp'), twoPass=player.config('equalizer-2pass'); player.setConfig('equalizer-bands','1.0 2.0 3.0 4.0 5.0 6.0 7.0 8.0 9.0 10.0'); player.setConfig('equalizer-preamp',7.5); player.setConfig('equalizer-2pass',true); const ok=String(player.config('equalizer-bands')).split(/\\s+/).length===10 && Math.abs(Number(player.config('equalizer-preamp'))-7.5)<0.01 && player.config('equalizer-2pass')===true; player.setConfig('equalizer-bands',bands); player.setConfig('equalizer-preamp',preamp); player.setConfig('equalizer-2pass',twoPass); return ok })()|+100:settingsDialog.close()|+100:quit" "$WORK/audio-only.m4a")
check "Audio preferences expose all equalizer bands and VLC config types" "$out" "audioFxUi=true/true/true/true"
check "equalizer bands, preamp and two-pass settings round-trip" "$out" "audioFxRoundTrip=true"
out=$(run "1200:'audioModuleOptionTypes=' + ['spatializer-roomsize','spatializer-width','spatializer-wet','spatializer-dry','spatializer-damp','stereowiden-delay','stereowiden-feedback','stereowiden-crossfeed','stereowiden-dry-mix'].every(x => player.configType(x) === 'float')|+100:'audioModuleRoundTrip=' + (() => { const width=player.config('spatializer-width'), delay=player.config('stereowiden-delay'); player.setConfig('spatializer-width',0.45); player.setConfig('stereowiden-delay',20.5); const ok=Math.abs(Number(player.config('spatializer-width'))-0.45)<0.01 && Math.abs(Number(player.config('stereowiden-delay'))-20.5)<0.01; player.setConfig('spatializer-width',width); player.setConfig('stereowiden-delay',delay); return ok })()|+100:quit" "$WORK/audio-only.m4a")
check "all spatial audio and stereo widening module options use VLC float types" "$out" "audioModuleOptionTypes=true"
check "spatializer and stereo widening advanced values round-trip with decimals" "$out" "audioModuleRoundTrip=true"
out=$(run "1200:settingsDialog.open(); settingsDialog.page='audio'; settingsDialog.readAudioFilters(); settingsDialog.otherVlcOptionMessage=settingsDialog.audioFiltersState; settingsDialog.setAudioFilter('spatializer',true); settingsDialog.setAudioFilter('stereo_widen',true); 'filtersEnabled=' + settingsDialog.audioFilterEnabled('spatializer') + '/' + settingsDialog.audioFilterEnabled('stereo_widen')|+100:settingsDialog.setAudioFilter('spatializer',false); settingsDialog.setAudioFilter('stereo_widen',false); 'filterRoundTrip=' + (!settingsDialog.audioFilterEnabled('spatializer') && !settingsDialog.audioFilterEnabled('stereo_widen') && settingsDialog.audioFiltersState === settingsDialog.otherVlcOptionMessage)|+100:player.setConfig('audio-filter',settingsDialog.otherVlcOptionMessage)|+100:quit" "$WORK/audio-only.m4a")
check "spatializer and stereo-widen audio filters both enable" "$out" "filtersEnabled=true/true"
check "spatializer and stereo-widen disable while preserving other filters" "$out" "filterRoundTrip=true"

echo "== VLC media conversion"
out=$(run "1200:convertDialog.open()|+150:convertDialog.format='mp3'; convertDialog.outputFile=platform.fileUrl('$WORK/converted.mp3')|+100:click-item:convert-start|+3500:'convertDone=' + (!vlcTasks.busy && vlcTasks.status.startsWith('Conversion complete'))|+100:quit" "$WORK/audio-only.m4a")
check "the Convert dialog starts an MP3 transcode in VLC" "$out" "convertDone=true"
if [ -s "$WORK/converted.mp3" ] && command -v ffprobe >/dev/null 2>&1 \
    && file "$WORK/converted.mp3" | grep -q "MPEG ADTS, layer III" \
    && [ "$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$WORK/converted.mp3" 2>/dev/null)" = "mp3" ]; then
    echo "PASS  VLC produced an MP3 audio stream"; pass=$((pass + 1))
else
    echo "FAIL  VLC conversion output is missing or invalid"; fail=$((fail + 1)); fi
out=$(run "500:player.setConfig('sout-transcode-vb',650); player.setConfig('sout-transcode-ab',96); player.openLocation('$WORK/convert-video.mkv',true)|+1000:convertDialog.open()|+150:'convertProfileRates=' + (convertDialog.quality === 'vlc-profile' && convertDialog.profileQualityAvailable && convertDialog.videoBitrateKbps === 650 && convertDialog.audioBitrateKbps === 96)|+100:convertDialog.format='mp4'; convertDialog.outputFile=platform.fileUrl('$WORK/profile-converted.mp4')|+100:click-item:convert-start|+6000:'profileConvertDone=' + (!vlcTasks.busy && vlcTasks.status.startsWith('Conversion complete'))|+100:player.openLocation('$WORK/convert-video.mkv',true)|+1000:convertDialog.outputFile=platform.fileUrl('$WORK/converted.mp4'); convertDialog.quality='high'; 'convertQualityPresets=' + (convertDialog.qualityPresets.compact.video === 800 && convertDialog.qualityPresets.compact.audio === 96 && convertDialog.qualityPresets.balanced.video === 2000 && convertDialog.qualityPresets.balanced.audio === 192 && convertDialog.videoBitrateKbps === 5000 && convertDialog.audioBitrateKbps === 320)|+100:click-item:convert-start|+6000:'convertDone=' + (!vlcTasks.busy && vlcTasks.status.startsWith('Conversion complete'))|+100:quit")
check "the conversion dialog selects the active VLC profile bitrate" "$out" "convertProfileRates=true"
check "conversions use the active VLC profile bitrate" "$out" "profileConvertDone=true"
check "conversion quality presets map to their configured VLC bitrates" "$out" "convertQualityPresets=true"
check "VLC transcodes video to H.264/AAC MP4" "$out" "convertDone=true"
if [ -s "$WORK/converted.mp4" ] && command -v ffprobe >/dev/null 2>&1 \
    && file "$WORK/converted.mp4" | grep -q "ISO Media" \
    && [ "$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$WORK/converted.mp4" 2>/dev/null)" = "h264" ] \
    && [ "$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$WORK/converted.mp4" 2>/dev/null)" = "aac" ]; then
    echo "PASS  VLC produced an H.264/AAC MP4"; pass=$((pass + 1))
else
    echo "FAIL  VLC MP4 output is missing or invalid"; fail=$((fail + 1)); fi
profileVideoBitrate="$(ffprobe -v error -select_streams v:0 -show_entries stream=bit_rate -of default=noprint_wrappers=1:nokey=1 "$WORK/profile-converted.mp4" 2>/dev/null || true)"
if [[ "$profileVideoBitrate" =~ ^[0-9]+$ ]] && (( profileVideoBitrate >= 300000 && profileVideoBitrate < 1000000 )); then
    echo "PASS  profile transcode bitrate produced ${profileVideoBitrate} b/s"; pass=$((pass + 1))
else
    echo "FAIL  profile transcode bitrate was ignored: ${profileVideoBitrate:-unavailable}"; fail=$((fail + 1)); fi
mp4VideoBitrate="$(ffprobe -v error -select_streams v:0 -show_entries stream=bit_rate -of default=noprint_wrappers=1:nokey=1 "$WORK/converted.mp4" 2>/dev/null || true)"
if [[ "$mp4VideoBitrate" =~ ^[0-9]+$ ]] && (( mp4VideoBitrate > 1900000 )); then
    echo "PASS  High quality preset increased the encoded video bitrate to ${mp4VideoBitrate} b/s"; pass=$((pass + 1))
else
    echo "FAIL  High quality preset produced an unexpected video bitrate: ${mp4VideoBitrate:-unavailable}"; fail=$((fail + 1)); fi
out=$(run "1200:'started=' + vlcTasks.convert(platform.fileUrl('$WORK/convert-video.mkv'), platform.fileUrl('$WORK/converted.webm'), 'webm')|+9000:'convertDone=' + (!vlcTasks.busy && vlcTasks.status.startsWith('Conversion complete'))|+100:quit" "$WORK/audio-only.m4a")
check "VLC transcodes video to VP8/Vorbis WebM" "$out" "convertDone=true"
if [ -s "$WORK/converted.webm" ] && command -v ffprobe >/dev/null 2>&1 \
    && file "$WORK/converted.webm" | grep -q "WebM" \
    && [ "$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$WORK/converted.webm" 2>/dev/null)" = "vp8" ] \
    && [ "$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$WORK/converted.webm" 2>/dev/null)" = "vorbis" ]; then
    echo "PASS  VLC produced a VP8/Vorbis WebM"; pass=$((pass + 1))
else
    echo "FAIL  VLC WebM output is missing or invalid"; fail=$((fail + 1)); fi
out=$(run "1200:'cancelStarted=' + vlcTasks.convert(platform.fileUrl('$WORK/base.mkv'), platform.fileUrl('$WORK/cancelled.mp4'), 'mp4')|+500:vlcTasks.stop()|+1200:'cancelled=' + (!vlcTasks.busy && vlcTasks.status === 'Operation stopped')|+100:quit" "$WORK/audio-only.m4a")
check "stopping a VLC conversion reports completion of cancellation" "$out" "cancelled=true"
if [[ ! -e "$WORK/cancelled.mp4" ]]; then echo "PASS  stopping a VLC conversion removes its partial output"; pass=$((pass + 1)); else echo "FAIL  stopped conversion left a partial output"; fail=$((fail + 1)); fi
out=$(run "1200:'retryStarted=' + vlcTasks.convert(platform.fileUrl('$WORK/convert-video.mkv'), platform.fileUrl('$WORK/cancelled.mp4'), 'mp4')|+9000:'retryDone=' + (!vlcTasks.busy && vlcTasks.status.startsWith('Conversion complete'))|+100:quit" "$WORK/audio-only.m4a")
check "a cancelled conversion can retry to the same destination" "$out" "retryDone=true"

echo "== stream dialog protocols and VLC network outputs"
out=$(run "500:player.setConfig('sout-transcode-vb',650); player.setConfig('sout-transcode-ab',96); streamDialog.open(); 'streamDefault=' + (streamDialog.protocol === 'udp' && streamDialog.host === '127.0.0.1') + ' profileRates=' + (streamDialog.videoBitrateKbps === 650 && streamDialog.audioBitrateKbps === 96)|+100:streamDialog.chooseProtocol('http'); 'httpMode=' + (streamDialog.protocol === 'http' && streamDialog.host === '0.0.0.0' && streamDialog.subtitle.indexOf('HTTP') >= 0)|+100:streamDialog.chooseProtocol('rtp'); 'rtpMode=' + (streamDialog.protocol === 'rtp' && streamDialog.host === '127.0.0.1')|+100:streamDialog.close()|+150:'streamClosed=' + !streamDialog.visible|+100:quit" "$E1")
check "stream dialog defaults to UDP with a local receiver address" "$out" "streamDefault=true"
check "stream dialog reads VLC profile transcode bitrates" "$out" "profileRates=true"
check "HTTP mode explains server binding and the pull URL" "$out" "httpMode=true"
check "RTP mode restores receiver addressing" "$out" "rtpMode=true"
check "stream dialog closes without launching VLC" "$out" "streamClosed=true"
if python3 - "$HERE" "$E1" "$WORK/recording-subtitle.srt" "$WORK/embedded/embedded-only.mkv" <<'PY'
import json
import os
import socket
import subprocess
import sys
import tempfile
import threading
import time
import urllib.request

root, media, subtitle_file, embedded_media = sys.argv[1:]


def check_protocol(protocol, subtitle_path="", media_source=media, embedded_subtitles=False):
    verify_subtitles = bool(subtitle_path) or embedded_subtitles
    tcp = protocol == "http"
    receiver = socket.socket(socket.AF_INET, socket.SOCK_STREAM if tcp else socket.SOCK_DGRAM)
    receiver.bind(("127.0.0.1", 0))
    port = receiver.getsockname()[1]
    if tcp:
        receiver.close()
    else:
        receiver.settimeout(0.4)
    deadline = time.monotonic() + 9
    result = {"bytes": 0, "rtp_version": None, "http_status": None, "error": "", "payload": bytearray()}

    def receive_udp():
        while time.monotonic() < deadline:
            try:
                packet, _ = receiver.recvfrom(65536)
                result["bytes"] += len(packet)
                if protocol == "rtp":
                    if result["rtp_version"] is None:
                        result["rtp_version"] = packet[0] >> 6
                    if len(packet) >= 12 and packet[0] >> 6 == 2:
                        header_size = 12 + (packet[0] & 0x0f) * 4
                        if packet[0] & 0x10 and len(packet) >= header_size + 4:
                            extension_words = int.from_bytes(packet[header_size + 2:header_size + 4], "big")
                            header_size += 4 + extension_words * 4
                        result["payload"].extend(packet[header_size:])
                else:
                    result["payload"].extend(packet)
            except socket.timeout:
                continue
            except OSError:
                return

    def receive_http():
        url = "http://127.0.0.1:%d/stream.ts" % port
        while time.monotonic() < deadline:
            try:
                with urllib.request.urlopen(url, timeout=1) as response:
                    result["http_status"] = response.status
                    try:
                        # This response stays open while VLC streams. A short
                        # socket timeout makes BufferedReader unusable after
                        # the first idle interval (the next read raises
                        # "cannot read from timed out object").
                        response.fp.raw._sock.settimeout(2.0)
                    except (AttributeError, OSError):
                        pass
                    while time.monotonic() < deadline:
                        try:
                            chunk = response.read1(65536)
                        except (TimeoutError, OSError) as error:
                            result["error"] = str(error)
                            break
                        if not chunk:
                            break
                        result["bytes"] += len(chunk)
                        result["payload"].extend(chunk)
                    return
            except Exception as error:
                result["error"] = str(error)
                time.sleep(0.15)

    listener = threading.Thread(target=receive_http if tcp else receive_udp, daemon=True)
    if not tcp:
        listener.start()
    environment = os.environ.copy()
    environment["NEO_TIMEOUT"] = "25"
    if subtitle_path:
        setup = "1000:player.addSubtitleFile(platform.fileUrl(" + json.dumps(subtitle_path) + "))|+800:'subtitleSelected=' + (player.tracks('spu').some(track => track.id >= 0 && track.selected) && player.activeSubtitleFile.toString().endsWith('recording-subtitle.srt'))|+100:"
    elif embedded_subtitles:
        setup = "1800:player.selectTrack('spu',2)|+800:'subtitleSelected=' + (player.activeSubtitleTrackId === 2 && player.activeSubtitleFile.toString() === '')|+100:"
    else:
        setup = "1000:"
    steps = (
        setup + "player.setConfig('sout-transcode-vb',650); player.setConfig('sout-transcode-ab',96); "
        + "streamDialog.open(); streamDialog.chooseProtocol(" + json.dumps(protocol) + "); "
        + "streamDialog.port=" + json.dumps(str(port)) + "|+100:click-item:stream-start"
        + "|+100:'started=' + vlcTasks.streaming + ' active=' + vlcTasks.streaming"
        + " + ' profileRates=' + streamDialog.videoBitrateKbps + '/' + streamDialog.audioBitrateKbps"
        + "|+4500:vlcTasks.stop()"
        + "|+1300:'stopped=' + (!vlcTasks.busy) + ' status=' + vlcTasks.status|+100:quit"
    )
    if tcp:
        listener.start()
    try:
        run = subprocess.run([os.path.join(root, "scripts/run-offscreen.sh"), steps, media_source],
                             cwd=root, env=environment, text=True, stdout=subprocess.PIPE,
                             stderr=subprocess.STDOUT, timeout=16)
    finally:
        deadline = time.monotonic()
        receiver.close()
    listener.join(timeout=1)
    valid_payload = result["bytes"] > 0
    if protocol == "rtp":
        valid_payload = valid_payload and result["rtp_version"] == 2
    if protocol == "http":
        valid_payload = valid_payload and result["http_status"] == 200
    decode_ok = False
    subtitle_ok = not verify_subtitles
    if result["payload"]:
        with tempfile.NamedTemporaryFile(prefix="neo-stream-subtitles-", suffix=".ts", delete=False) as output:
            output.write(result["payload"])
            stream_path = output.name
        probe = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "stream=codec_type,codec_name",
                                "-of", "json", stream_path], text=True, capture_output=True)
        try:
            streams = json.loads(probe.stdout).get("streams", [])
            decode_ok = probe.returncode == 0 and any(
                item.get("codec_type") == "video" and item.get("codec_name") == "h264"
                for item in streams) and any(
                item.get("codec_type") == "audio" and item.get("codec_name") == "aac"
                for item in streams)
            decoder = subprocess.run(
                ["ffmpeg", "-v", "error", "-threads", "1", "-i", stream_path,
                 "-map", "0:v:0", "-map", "0:a:0", "-t", "1", "-f", "null", "-"],
                text=True, capture_output=True)
            decode_ok = decode_ok and decoder.returncode == 0
            subtitle_ok = not verify_subtitles or (probe.returncode == 0 and any(
                item.get("codec_type") == "subtitle" and item.get("codec_name") == "dvb_subtitle"
                for item in streams))
        except (ValueError, AttributeError):
            decode_ok = False
            subtitle_ok = False
        os.unlink(stream_path)
    if verify_subtitles and not result["payload"]:
        subtitle_ok = False
    subtitle_selected = not verify_subtitles or "subtitleSelected=true" in run.stdout
    ok = (run.returncode == 0 and "started=true active=true" in run.stdout
          and "profileRates=650/96" in run.stdout
          and "stopped=true status=Operation stopped" in run.stdout
          and valid_payload and decode_ok and subtitle_ok and subtitle_selected)
    if not ok:
        print(run.stdout)
        print(protocol + "_receiver=" + str({
            key: value for key, value in result.items() if key != "payload"
        }) + " payload_bytes=" + str(len(result["payload"])))
        if result["payload"]:
            print(protocol + "_probe_exit=" + str(probe.returncode)
                  + " probe_error=" + probe.stderr[:1000])
            print(protocol + "_decode_exit=" + str(decoder.returncode)
                  + " decode_error=" + decoder.stderr[:1000])
        return False
    print("VLC %s delivered %d bytes%s" % (
        protocol.upper(), result["bytes"],
        " (RTP version %d)" % result["rtp_version"] if protocol == "rtp" else
        " (HTTP %d)" % result["http_status"] if protocol == "http" else ""))
    print("ffmpeg decoded H.264 video and AAC audio from the %s receiver payload" % protocol.upper())
    return True


for protocol in ("udp", "rtp", "http"):
    if not check_protocol(protocol):
        raise SystemExit(1)
if not check_protocol("udp", subtitle_file):
    raise SystemExit(1)
print("VLC UDP output contains a DVB subtitle stream from the selected local subtitle file")
if not check_protocol("udp", "", embedded_media, True):
    raise SystemExit(1)
print("VLC UDP output contains a DVB subtitle stream from the selected embedded subtitle track")
PY
then
    echo "PASS  VLC sends real MPEG-TS over UDP, RTP and HTTP"; pass=$((pass + 1))
else
    echo "FAIL  VLC network stream protocols did not deliver playable output"; fail=$((fail + 1)); fi

echo "== folder browser with no active video"
out=$(run "100:win.width=1920; win.height=1080; win.navigate('videos'); libraryPanel.folder=platform.fileUrl('$WORK/show')|+350:'idleFolder=' + (!player.hasVideo && win.libraryFullPage && !win.libraryOpen && libraryPanel.visible && !libraryPanel.miniPlayerItem.visible && libraryPanel.fileCount() === 2 && libraryPanel.folderViewMode === 'grid')|+150:grab:$WORK/folder-browser-no-video-1920.png|+100:quit")
check "the Figma folder-browser state omits the mini-player when no video is active" "$out" "idleFolder=true"
if [ -s "$WORK/folder-browser-no-video-1920.png" ]; then echo "PASS  folder-browser-no-video-1920.png written"; pass=$((pass + 1))
else echo "FAIL  folder-browser-no-video-1920.png missing"; fail=$((fail + 1)); fi

echo "== primary navigation"
out=$(run "1200:win.width=1920; win.height=1080; player.seek(0.25); win.run('library', topBar)|+150:'focusVideos=' + navigationRail.focusPage('videos')|+100:key:Space|+100:'videosRootArrowsDisabled=' + (!libraryPanel.canGoBackFromSidePanel() && !libraryPanel.canGoForwardFromSidePanel())|+100:click-item:sidepanel-back-generic|+100:'videosRootBackStays=' + (navigationPage === 'videos' && libraryOpen)|+100:libraryPanel.folder = platform.fileUrl('$WORK/navigation-history')|+250:libraryPanel.openFolder(platform.fileUrl('$WORK/navigation-history/Season 1'))|+250:'historyNested=' + (platform.localPath(libraryPanel.folder).endsWith('/navigation-history/Season 1'))|+100:click-item:sidepanel-back-generic|+250:'historyBack=' + (platform.localPath(libraryPanel.folder).endsWith('/navigation-history') && libraryPanel.canGoForwardFromSidePanel())|+100:click-item:sidepanel-forward-generic|+250:'historyForward=' + (platform.localPath(libraryPanel.folder).endsWith('/navigation-history/Season 1') && !libraryPanel.canGoForwardFromSidePanel())|+100:libraryPanel.sideFolderHistory = []; libraryPanel.sidePanelForwardHistory = []; libraryPanel.folder = platform.fileUrl(player.folderPath)|+350:'videosSide=' + (navigationPage === 'videos' && libraryOpen && libraryPanel.section === 'folder' && libraryPanel.mediaType === 'video' && !navigationRail.expanded && Math.abs(libraryPanel.width - 377) < 2 && videoArea.visible && video.parent === videoArea && Math.abs(controlBar.x) < 1 && Math.abs(controlBar.width - win.width) < 1) + ' label=' + navigationRail.labelForPage('playlist') + ' noBrowse=' + (navigationRail.labelForPage('folder') === '') + ' files=' + libraryPanel.fileCount() + ' list=' + (libraryPanel.folderViewMode === 'list') + ' controlBar=' + Math.round(controlBar.x) + '/' + Math.round(controlBar.width)|+100:click-item:library-sidepanel-folder-view-toggle|+100:'sideGrid=' + (libraryPanel.folderViewMode === 'grid')|+100:click-item:library-sidepanel-folder-view-toggle|+100:'sideList=' + (libraryPanel.folderViewMode === 'list')|+100:libraryPanel.searchText = 'S01E01'|+250:'searchMatches=' + libraryPanel.matchingFiles()|+2500:'videoThumbnail=' + libraryPanel.videoThumbnailState('My.Show.S01E01.1080p.mkv')|+150:grab:$WORK/navigation-videos.png|+100:click-item:sidepanel-open-full-page|+350:'fullPage=' + (libraryFullPage && !libraryOpen && navigationRail.expanded && libraryPanel.visible && !videoArea.visible && video.parent === libraryPanel.miniVideoHost && !win.bottomShown && platform.localPath(libraryPanel.folder) === player.folderPath && libraryPanel.folderViewMode === 'list' && libraryPanel.searchText === 'S01E01' && libraryPanel.matchingFiles() === 1) + ' files=' + libraryPanel.fileCount() + ' search=' + libraryPanel.searchText|+100:libraryPanel.searchText = ''; 'expandedSearchClear=' + (libraryPanel.searchText === '' && libraryPanel.fileCount() === 2)|+100:click-item:library-folder-view-toggle|+150:'wideGrid=' + (libraryPanel.folderViewMode === 'grid' && Math.round(libraryPanel.miniPlayerItem.width) === 391 && libraryPanel.miniPlayerItem.x > win.width / 2 && libraryPanel.videoProgress('My.Show.S01E01.1080p.mkv') > 0)|+100:grab:$WORK/folder-browser-grid-1920.png|+100:click-item:library-folder-view-toggle|+150:'wideList=' + (libraryPanel.folderViewMode === 'list' && Math.round(libraryPanel.miniPlayerItem.width) === 391 && libraryPanel.miniPlayerItem.x < win.width / 2)|+100:grab:$WORK/folder-browser-list-1920.png|+100:win.width=1120; win.height=680|+350:click-item:mini-player-expand|+150:'miniRestore=' + (!libraryFullPage && videoArea.visible && video.parent === videoArea)|+100:'focusRecent=' + navigationRail.focusPage('recent')|+100:key:Space|+100:'recent=' + (navigationPage === 'recent' && libraryOpen && libraryPanel.section === 'recent' && !navigationRail.expanded && videoArea.visible)|+100:quit" "$E1")
check "navigation buttons accept keyboard focus" "$out" "focusVideos=true"
check "Space opens Videos in the Figma side pane beside the player" "$out" "videosSide=true label=Playlists noBrowse=true files=2 list=true"
check "the player control bar spans the window under the Figma side pane" "$out" "controlBar=0/1920"
check "the Videos root keeps Back and Forward disabled" "$out" "videosRootArrowsDisabled=true"
check "Back does not exit the Videos side pane at its root" "$out" "videosRootBackStays=true"
check "the side-pane folder history opens a nested folder" "$out" "historyNested=true"
check "the side-pane Back button enables Forward for the previous folder" "$out" "historyBack=true"
check "the side-pane Forward button restores the nested folder" "$out" "historyForward=true"
check "the Videos side pane switches to grid layout" "$out" "sideGrid=true"
check "the Videos side pane restores its list layout" "$out" "sideList=true"
check "the Videos open button preserves its current folder, list and active search" "$out" "fullPage=true files=2 search=S01E01"
check "clearing search in the expanded folder restores all side-pane files" "$out" "expandedSearchClear=true"
check "grid and list views place the Figma mini-player in their matching corners" "$out" "wideGrid=true"
check "the full-page list keeps a compact mini-player in the lower left" "$out" "wideList=true"
check "library search filters filenames" "$out" "searchMatches=1"
check "video files load VLC-decoded folder thumbnails" "$out" "videoThumbnail=ready"
check "the mini-player restore control returns to full playback" "$out" "miniRestore=true"
check "recent navigation accepts keyboard focus" "$out" "focusRecent=true"
check "recent navigation opens a side pane with the rail collapsed" "$out" "recent=true"
echo "== mini-player end card and replay action"
out=$(run "900:onboarding.close(); win.width=1120; win.height=680; player.openLocation('$WORK/convert-video.mkv',true)|+4500:win.navigate('home')|+100:'miniPlayerEndCard=' + (player.ended && !player.hasMedia && !player.hasVideo && homeView.miniPlayerItem.visible && homeView.miniPlayerToggleButton.icon === 'replay' && homeView.miniPlayerTitle.text === player.title)|+100:move-item:home-mini-player-video-drag|+200:'miniPlayerReplayButton=' + (homeView.miniPlayerOverlay.visible && homeView.miniPlayerToggleButton.visible && homeView.miniPlayerToggleButton.tip === 'Replay')|+100:click-item:home-mini-player-toggle|+600:'miniPlayerReplayStarts=' + (!player.ended && player.hasMedia && player.hasVideo && player.playing)|+100:quit")
check "natural video completion keeps a replay card in Home with its title" "$out" "miniPlayerEndCard=true"
check "the replay button is visible and labelled in the end card" "$out" "miniPlayerReplayButton=true"
check "the end-card replay button restarts playback through VLC" "$out" "miniPlayerReplayStarts=true"
echo "== mini-player end card and replay in the full library and Queue"
out=$(run "900:onboarding.close(); win.width=1920; win.height=1080; player.openLocation('$WORK/convert-video.mkv',true)|+4500:win.navigate('videos'); win.libraryFullPage=true|+200:'libraryMiniPlayerEndCard=' + (player.ended && !player.hasMedia && libraryPanel.miniPlayerItem.visible && libraryPanel.miniPlayerToggleButton.icon === 'replay')|+100:move-item:mini-player-video-drag|+100:click-item:mini-player-queue|+250:'queueMiniPlayerEndCard=' + (player.ended && rightPanel === 'queue' && libraryPanel.miniPlayerItem.parent === queuePanel && libraryPanel.miniPlayerItem.visible)|+100:move-item:mini-player-video-drag|+150:'queueReplayButton=' + (libraryPanel.miniPlayerToggleButton.visible && libraryPanel.miniPlayerToggleButton.tip === 'Replay')|+100:click-item:mini-player-play|+650:'queueReplayStarts=' + (!player.ended && player.hasMedia && player.hasVideo && player.playing)|+100:quit")
check "natural video completion keeps a Replay card in the full library" "$out" "libraryMiniPlayerEndCard=true"
check "the full-library Replay card docks into the Queue panel" "$out" "queueMiniPlayerEndCard=true"
check "the docked Queue card replays its VLC item" "$out" "queueReplayStarts=true"
echo "== Videos side-pane rows support keyboard focus and activation"
out=$(run "1000:onboarding.close(); win.width=1920; win.height=1080; win.run('library',topBar)|+150:navigationRail.focusPage('videos')|+100:key:Space|+200:libraryPanel.folder=platform.fileUrl('$WORK/navigation-history')|+300:'folderRowFocusable=' + (() => { const item=libraryPanel.folderListingItem.itemAtIndex(0); if (!item) return false; item.forceActiveFocus(); return item.activeFocus && item.border.width === 1 && item.fileName === 'Season 1' })()|+100:key:Space|+300:'folderRowKeyboardOpen=' + platform.localPath(libraryPanel.folder).endsWith('/navigation-history/Season 1')|+250:'fileRowFocusable=' + (() => { const item=libraryPanel.folderListingItem.itemAtIndex(0); if (!item) return false; item.forceActiveFocus(); return item.activeFocus && item.border.width === 1 && item.fileName === 'History.Episode.mkv' })()|+100:key:Return|+400:'fileRowKeyboardPlay=' + platform.localPath(player.mediaUrl).endsWith('/History.Episode.mkv')|+100:quit" "$E1")
check "Videos folder rows expose visible keyboard focus" "$out" "folderRowFocusable=true"
check "Space opens the focused Videos folder row" "$out" "folderRowKeyboardOpen=true"
check "Videos file rows expose visible keyboard focus" "$out" "fileRowFocusable=true"
check "Enter plays the focused Videos file row" "$out" "fileRowKeyboardPlay=true"
echo "== mini-player bounds at the minimum window size"
out=$(run "1000:onboarding.close(); win.width=560; win.height=340; player.openLocation('$E1',true)|+1200:win.navigate('home')|+350:'homeMiniFits=' + (() => { const m=homeView.miniPlayerItem; const p=m.mapToItem(win.contentItem,0,0); return m.visible && p.x >= 0 && p.y >= 0 && p.x + m.width <= win.width && p.y + m.height <= win.height })()|+100:move-item:home-mini-player-video-drag|+150:'homeMiniButtonsFit=' + (() => { const m=homeView.miniPlayerItem, bs=[homeView.miniPlayerCloseButton,homeView.miniPlayerExpandButton,homeView.miniPlayerPreviousButton,homeView.miniPlayerToggleButton,homeView.miniPlayerNextButton,homeView.miniPlayerQueueButton]; return homeView.miniPlayerOverlay.visible && Math.abs(homeView.miniPlayerOverlay.radius-6*m.uiScale)<0.1 && bs.every(b=>{const p=b.mapToItem(m,0,0); return b.visible && p.x>=0 && p.y>=0 && p.x+b.width<=m.width && p.y+b.height<=m.height}) })()|+100:win.navigate('videos'); win.libraryFullPage=true; libraryPanel.folderViewMode='grid'|+500:'gridMiniFits=' + (() => { const m=libraryPanel.miniPlayerItem; const p=m.mapToItem(win.contentItem,0,0); return m.visible && p.x >= 0 && p.y >= 0 && p.x + m.width <= win.width && p.y + m.height <= win.height })()|+100:move-item:mini-player-video-drag|+150:'gridMiniButtonsFit=' + (() => { const m=libraryPanel.miniPlayerItem, bs=[libraryPanel.miniPlayerCloseButton,libraryPanel.miniPlayerExpandButton,libraryPanel.miniPlayerPreviousButton,libraryPanel.miniPlayerToggleButton,libraryPanel.miniPlayerNextButton,libraryPanel.miniPlayerQueueButton]; return libraryPanel.miniPlayerOverlay.visible && Math.abs(libraryPanel.miniPlayerOverlay.radius-6*m.uiScale)<0.1 && bs.every(b=>{const p=b.mapToItem(m,0,0); return b.visible && p.x>=0 && p.y>=0 && p.x+b.width<=m.width && p.y+b.height<=m.height}) })()|+100:libraryPanel.folderViewMode='list'|+300:'listMiniFits=' + (() => { const m=libraryPanel.miniPlayerItem; const p=m.mapToItem(win.contentItem,0,0); return m.visible && p.x >= 0 && p.y >= 0 && p.x + m.width <= win.width && p.y + m.height <= win.height })() + '/' + Math.round(libraryPanel.miniPlayerItem.width)|+100:move-item:mini-player-video-drag|+150:'listMiniButtonsFit=' + (() => { const m=libraryPanel.miniPlayerItem, bs=[libraryPanel.miniPlayerCloseButton,libraryPanel.miniPlayerExpandButton,libraryPanel.miniPlayerPreviousButton,libraryPanel.miniPlayerToggleButton,libraryPanel.miniPlayerNextButton,libraryPanel.miniPlayerQueueButton]; return libraryPanel.miniPlayerOverlay.visible && Math.abs(libraryPanel.miniPlayerOverlay.radius-6*m.uiScale)<0.1 && bs.every(b=>{const p=b.mapToItem(m,0,0); return b.visible && p.x>=0 && p.y>=0 && p.x+b.width<=m.width && p.y+b.height<=m.height}) })()|+100:quit" "$E1")
check "the Home mini-player stays inside the minimum-size window" "$out" "homeMiniFits=true"
check "the Home mini-player overlay corners and all six buttons scale with its 220 px card" "$out" "homeMiniButtonsFit=true"
check "the library grid mini-player stays inside the minimum-size window" "$out" "gridMiniFits=true"
check "the grid mini-player overlay corners and all six buttons scale with its 220 px card" "$out" "gridMiniButtonsFit=true"
check "the library list mini-player stays inside the minimum-size window at 220 px" "$out" "listMiniFits=true/220"
check "the list mini-player overlay corners and all six buttons scale with its 220 px card" "$out" "listMiniButtonsFit=true"
echo "== mini-player drag cursor affordance"
out=$(run "500:onboarding.close(); win.width=1920; win.height=1080; player.openLocation('$E1',true)|+1200:win.navigate('home')|+350:'homeMiniDragCursor=' + (homeView.miniPlayerDragTarget.cursorShape === Qt.OpenHandCursor)|+100:win.navigate('folder')|+350:'libraryMiniDragCursor=' + (libraryPanel.miniPlayerDragTarget.cursorShape === Qt.OpenHandCursor)|+100:quit" "$E1")
check "Home mini-player video advertises that it can be dragged" "$out" "homeMiniDragCursor=true"
check "full-library mini-player video advertises that it can be dragged" "$out" "libraryMiniDragCursor=true"
echo "== mini-player keyboard controls"
out=$(run "500:onboarding.close(); win.width=1920; win.height=1080; player.openLocation('$E1',true)|+1400:win.navigate('home')|+450:move:800,600|+100:focus-item:home-mini-player|+150:'homeMiniKeyboardReveal=' + (homeView.miniPlayerItem.activeFocus && homeView.miniPlayerOverlay.visible)|+100:key:Tab|+100:key:Tab|+100:key:Tab|+100:key:Tab|+150:'homeMiniPlayFocus=' + (win.activeFocusItem.objectName === 'home-mini-player-toggle' && homeView.miniPlayerOverlay.visible)|+100:key:Space|+150:'homeMiniKeyboardPause=' + !player.playing|+100:key:Tab|+100:key:Tab|+100:'homeMiniSeekFocus=' + (win.activeFocusItem.objectName === 'home-mini-player-seek')|+100:player.seek(0.2)|+100:key:Right|+150:'homeMiniKeyboardSeekRight=' + (player.position > 0.3)|+100:player.seek(0.1)|+100:click-item:home-mini-player-seek|+350:'homeMiniPointerSeek=' + (player.position > 0.4 && player.position < 0.6)|+100:win.navigate('folder')|+500:drag-item:mini-player-title:mini-player:90,70|+100:move-item:mini-player-video-drag|+50:'libraryMiniTitleDrag=' + (libraryPanel.miniPlayerItem.dragOffsetX < -50 && libraryPanel.miniPlayerItem.dragOffsetY < -50 && libraryPanel.miniPlayerOverlay.visible) + ' libraryMiniVisualControls=' + (libraryPanel.miniPlayerExpandButton.icon === 'open' && Math.round(libraryPanel.miniPlayerTransportControls.spacing / libraryPanel.miniPlayerItem.uiScale) === 42)|+100:focus-item:mini-player|+150:'libraryMiniKeyboardReveal=' + (libraryPanel.miniPlayerItem.activeFocus && libraryPanel.miniPlayerOverlay.visible)|+100:key:Tab|+100:key:Tab|+100:key:Tab|+100:key:Tab|+150:'libraryMiniPlayFocus=' + (win.activeFocusItem.objectName === 'mini-player-play' && libraryPanel.miniPlayerOverlay.visible)|+100:key:Space|+150:'libraryMiniKeyboardResume=' + player.playing|+100:key:Tab|+100:key:Tab|+150:'libraryMiniSeekFocus=' + (win.activeFocusItem.objectName === 'mini-player-seek')|+100:player.seek(0.8)|+100:key:Left|+150:'libraryMiniKeyboardSeekLeft=' + (player.position < 0.7)|+100:player.seek(0.1)|+100:click-item:mini-player-seek|+350:'libraryMiniPointerSeek=' + (player.position > 0.4 && player.position < 0.6)|+100:quit" "$E1")
check "Home mini-player reveals its controls when the card receives keyboard focus" "$out" "homeMiniKeyboardReveal=true"
check "Home mini-player transport buttons are reachable with Tab" "$out" "homeMiniPlayFocus=true"
check "Space activates Home mini-player pause" "$out" "homeMiniKeyboardPause=true"
check "Home mini-player seek control is reachable with Tab" "$out" "homeMiniSeekFocus=true"
check "Right seeks forward from the Home mini-player" "$out" "homeMiniKeyboardSeekRight=true"
check "clicking the Home mini-player timeline seeks to the clicked position" "$out" "homeMiniPointerSeek=true"
check "the full-library mini-player moves from its title and reveals controls over video" "$out" "libraryMiniTitleDrag=true"
check "the full-library mini-player uses Figma's open icon and transport spacing" "$out" "libraryMiniVisualControls=true"
check "full-library mini-player reveals its controls when keyboard-focused" "$out" "libraryMiniKeyboardReveal=true"
check "full-library mini-player transport buttons are reachable with Tab" "$out" "libraryMiniPlayFocus=true"
check "Space activates full-library mini-player play" "$out" "libraryMiniKeyboardResume=true"
check "full-library mini-player seek control is reachable with Tab" "$out" "libraryMiniSeekFocus=true"
check "Left seeks backward from the full-library mini-player" "$out" "libraryMiniKeyboardSeekLeft=true"
check "clicking the full-library mini-player timeline seeks to the clicked position" "$out" "libraryMiniPointerSeek=true"
echo "== mini-player Queue keyboard control"
out=$(run "500:onboarding.close(); win.width=1920; win.height=1080; player.openLocation('$E1',true)|+1200:win.navigate('home')|+350:focus-item:home-mini-player-queue|+100:'homeQueueKeyboardFocus=' + (homeView.miniPlayerQueueButton.activeFocus && homeView.miniPlayerQueueButton.color === Theme.hover)|+100:key:Space|+200:'homeQueueKeyboardOpen=' + (rightPanel === 'queue' && homeView.miniPlayerItem.parent === queuePanel)|+100:key:Space|+200:'homeQueueKeyboardClose=' + (rightPanel === '' && homeView.miniPlayerItem.parent === homeView)|+150:win.navigate('folder')|+400:focus-item:mini-player-queue|+100:'libraryQueueKeyboardFocus=' + (libraryPanel.miniPlayerQueueButton.activeFocus && libraryPanel.miniPlayerQueueButton.color === Theme.hover)|+100:key:Space|+200:'libraryQueueKeyboardOpen=' + (rightPanel === 'queue' && libraryPanel.miniPlayerItem.parent === queuePanel)|+100:key:Space|+200:'libraryQueueKeyboardClose=' + (rightPanel === '' && libraryPanel.miniPlayerItem.parent === win.contentItem)|+100:quit" "$E1")
check "Home mini-player Queue button receives visible keyboard focus" "$out" "homeQueueKeyboardFocus=true"
check "Space opens the Home mini-player Queue panel" "$out" "homeQueueKeyboardOpen=true"
check "Space closes the Home mini-player Queue panel" "$out" "homeQueueKeyboardClose=true"
check "full-library mini-player Queue button receives visible keyboard focus" "$out" "libraryQueueKeyboardFocus=true"
check "Space opens the full-library mini-player Queue panel" "$out" "libraryQueueKeyboardOpen=true"
check "Space closes the full-library mini-player Queue panel" "$out" "libraryQueueKeyboardClose=true"
echo "== mini-player hover state"
out=$(run "500:onboarding.close(); win.width=1920; win.height=1080; player.openLocation('$E1',true)|+1200:win.navigate('home')|+200:move:800,600|+80:'homeMiniOverlayInitiallyHidden=' + (!homeView.miniPlayerOverlay.visible && homeView.miniPlayerOverlay.opacity < 0.01 && homeView.miniPlayerQueueButton.iconColor === Theme.icon)|+100:move-item:home-mini-player-title|+60:'homeMiniOverlayHiddenOverTitle=' + (!homeView.miniPlayerHovered && !homeView.miniPlayerOverlay.visible && homeView.miniPlayerQueueButton.iconColor === Theme.icon)|+100:move-item:home-mini-player-video-drag|+60:'homeMiniButtonsShownImmediately=' + (homeView.miniPlayerHovered && homeView.miniPlayerOverlay.visible && homeView.miniPlayerOverlay.opacity > 0.99 && homeView.miniPlayerTransportControls.children.length === 3 && homeView.miniPlayerExpandButton.icon === 'open' && homeView.miniPlayerQueueButton.iconColor === Theme.icon)|+100:move:800,600|+60:'homeMiniButtonsHiddenImmediately=' + (!homeView.miniPlayerOverlay.visible && homeView.miniPlayerOverlay.opacity < 0.01 && homeView.miniPlayerQueueButton.iconColor === Theme.icon)|+100:quit" "$E1")
check "Home mini-player controls start hidden" "$out" "homeMiniOverlayInitiallyHidden=true"
check "Home mini-player hover stays hidden over the title row" "$out" "homeMiniOverlayHiddenOverTitle=true"
check "Home mini-player buttons appear immediately when the video is hovered" "$out" "homeMiniButtonsShownImmediately=true"
check "Home mini-player buttons disappear immediately when hover ends" "$out" "homeMiniButtonsHiddenImmediately=true"
echo "== full-library mini-player hover state"
out=$(run "500:onboarding.close(); win.width=1920; win.height=1080; player.openLocation('$E1',true)|+1200:win.navigate('folder')|+300:move:800,600|+80:'libraryMiniOverlayInitiallyHidden=' + (!libraryPanel.miniPlayerOverlay.visible && libraryPanel.miniPlayerOverlay.opacity < 0.01 && libraryPanel.miniPlayerQueueButton.iconColor === Theme.icon)|+100:move-item:mini-player-title|+60:'libraryMiniOverlayHiddenOverTitle=' + (!libraryPanel.miniPlayerHovered && !libraryPanel.miniPlayerOverlay.visible && libraryPanel.miniPlayerQueueButton.iconColor === Theme.icon)|+100:move-item:mini-player-video-drag|+60:'libraryMiniButtonsShownImmediately=' + (libraryPanel.miniPlayerHovered && libraryPanel.miniPlayerOverlay.visible && libraryPanel.miniPlayerOverlay.opacity > 0.99 && libraryPanel.miniPlayerTransportControls.children.length === 3 && libraryPanel.miniPlayerExpandButton.icon === 'open' && libraryPanel.miniPlayerQueueButton.iconColor === Theme.icon)|+100:move:800,600|+60:'libraryMiniButtonsHiddenImmediately=' + (!libraryPanel.miniPlayerOverlay.visible && libraryPanel.miniPlayerOverlay.opacity < 0.01 && libraryPanel.miniPlayerQueueButton.iconColor === Theme.icon)|+100:quit" "$E1")
check "full-library mini-player controls start hidden" "$out" "libraryMiniOverlayInitiallyHidden=true"
check "full-library mini-player hover stays hidden over the title row" "$out" "libraryMiniOverlayHiddenOverTitle=true"
check "full-library mini-player buttons appear immediately when the video is hovered" "$out" "libraryMiniButtonsShownImmediately=true"
check "full-library mini-player buttons disappear immediately when hover ends" "$out" "libraryMiniButtonsHiddenImmediately=true"
echo "== mini-player button hover response"
out=$(run "500:onboarding.close(); win.width=1920; win.height=1080; player.openLocation('$E1',true)|+1200:win.navigate('home')|+350:move-item:home-mini-player-video-drag|+50:move-item:home-mini-player-close|+30:'homeCloseHoverInstant=' + (() => { const b=homeView.miniPlayerCloseButton; return b.hovered && !b.colorAnimationEnabled && b.color === Theme.hover })()|+40:move-item:home-mini-player-expand|+30:'homeExpandHoverInstant=' + (() => { const b=homeView.miniPlayerExpandButton; return b.hovered && !b.colorAnimationEnabled && b.color === Theme.hover })()|+40:move-item:home-mini-player-previous|+30:'homePreviousHoverInstant=' + (() => { const b=homeView.miniPlayerPreviousButton; return b.hovered && !b.colorAnimationEnabled && b.color === Theme.hover })()|+40:move-item:home-mini-player-toggle|+30:'homeToggleHoverInstant=' + (() => { const b=homeView.miniPlayerToggleButton; return b.hovered && !b.colorAnimationEnabled && b.color === Theme.hover })()|+40:move-item:home-mini-player-next|+30:'homeNextHoverInstant=' + (() => { const b=homeView.miniPlayerNextButton; return b.hovered && !b.colorAnimationEnabled && b.color === Theme.hover })()|+100:win.navigate('folder')|+300:move-item:mini-player-video-drag|+50:move-item:mini-player-close|+30:'libraryCloseHoverInstant=' + (() => { const b=libraryPanel.miniPlayerCloseButton; return b.hovered && !b.colorAnimationEnabled && b.color === Theme.hover })()|+40:move-item:mini-player-expand|+30:'libraryExpandHoverInstant=' + (() => { const b=libraryPanel.miniPlayerExpandButton; return b.hovered && !b.colorAnimationEnabled && b.color === Theme.hover })()|+40:move-item:mini-player-previous|+30:'libraryPreviousHoverInstant=' + (() => { const b=libraryPanel.miniPlayerPreviousButton; return b.hovered && !b.colorAnimationEnabled && b.color === Theme.hover })()|+40:move-item:mini-player-play|+30:'libraryToggleHoverInstant=' + (() => { const b=libraryPanel.miniPlayerToggleButton; return b.hovered && !b.colorAnimationEnabled && b.color === Theme.hover })()|+40:move-item:mini-player-next|+30:'libraryNextHoverInstant=' + (() => { const b=libraryPanel.miniPlayerNextButton; return b.hovered && !b.colorAnimationEnabled && b.color === Theme.hover })()|+100:quit" "$E1")
check "the Home mini-player Close button responds to hover instantly" "$out" "homeCloseHoverInstant=true"
check "the Home mini-player Expand button responds to hover instantly" "$out" "homeExpandHoverInstant=true"
check "the Home mini-player Previous button responds to hover instantly" "$out" "homePreviousHoverInstant=true"
check "the Home mini-player Play/Pause button responds to hover instantly" "$out" "homeToggleHoverInstant=true"
check "the Home mini-player Next button responds to hover instantly" "$out" "homeNextHoverInstant=true"
check "the full-library mini-player Close button responds to hover instantly" "$out" "libraryCloseHoverInstant=true"
check "the full-library mini-player Expand button responds to hover instantly" "$out" "libraryExpandHoverInstant=true"
check "the full-library mini-player Previous button responds to hover instantly" "$out" "libraryPreviousHoverInstant=true"
check "the full-library mini-player Play/Pause button responds to hover instantly" "$out" "libraryToggleHoverInstant=true"
check "the full-library mini-player Next button responds to hover instantly" "$out" "libraryNextHoverInstant=true"
echo "== mini-player queue button hover"
out=$(run "500:onboarding.close(); win.width=1920; win.height=1080; Theme.store.mode='dark'; player.openLocation('$E1',true)|+1200:win.navigate('home')|+300:move-item:home-mini-player-queue|+60:'homeMiniQueueHover=' + (() => { const b=homeView.miniPlayerQueueButton; return b.hovered && !b.colorAnimationEnabled && b.color === Theme.hover && b.iconColor === Theme.text })()|+100:win.navigate('folder')|+300:move-item:mini-player-queue|+60:'libraryMiniQueueHover=' + (() => { const b=libraryPanel.miniPlayerQueueButton; return b.hovered && !b.colorAnimationEnabled && b.color === Theme.hover && b.iconColor === Theme.text })()|+100:quit" "$E1")
check "Home mini-player Queue button uses the instant Figma hover state" "$out" "homeMiniQueueHover=true"
check "full-library mini-player Queue button uses the instant Figma hover state" "$out" "libraryMiniQueueHover=true"
echo "== mini-player button focus response"
out=$(run "500:onboarding.close(); win.width=1920; win.height=1080; player.openLocation('$E1',true)|+1200:win.navigate('home')|+350:focus-item:home-mini-player-close|+50:'homeCloseFocus=' + (homeView.miniPlayerCloseButton.activeFocus && homeView.miniPlayerOverlay.visible && homeView.miniPlayerCloseButton.color === Theme.hover)|+50:focus-item:home-mini-player-expand|+50:'homeExpandFocus=' + (homeView.miniPlayerExpandButton.activeFocus && homeView.miniPlayerOverlay.visible && homeView.miniPlayerExpandButton.color === Theme.hover)|+50:focus-item:home-mini-player-previous|+50:'homePreviousFocus=' + (homeView.miniPlayerPreviousButton.activeFocus && homeView.miniPlayerOverlay.visible && homeView.miniPlayerPreviousButton.color === Theme.hover)|+50:focus-item:home-mini-player-toggle|+50:'homeToggleFocus=' + (homeView.miniPlayerToggleButton.activeFocus && homeView.miniPlayerOverlay.visible && homeView.miniPlayerToggleButton.color === Theme.hover)|+50:focus-item:home-mini-player-next|+50:'homeNextFocus=' + (homeView.miniPlayerNextButton.activeFocus && homeView.miniPlayerOverlay.visible && homeView.miniPlayerNextButton.color === Theme.hover)|+100:win.navigate('folder')|+300:focus-item:mini-player-close|+50:'libraryCloseFocus=' + (libraryPanel.miniPlayerCloseButton.activeFocus && libraryPanel.miniPlayerOverlay.visible && libraryPanel.miniPlayerCloseButton.color === Theme.hover)|+50:focus-item:mini-player-expand|+50:'libraryExpandFocus=' + (libraryPanel.miniPlayerExpandButton.activeFocus && libraryPanel.miniPlayerOverlay.visible && libraryPanel.miniPlayerExpandButton.color === Theme.hover)|+50:focus-item:mini-player-previous|+50:'libraryPreviousFocus=' + (libraryPanel.miniPlayerPreviousButton.activeFocus && libraryPanel.miniPlayerOverlay.visible && libraryPanel.miniPlayerPreviousButton.color === Theme.hover)|+50:focus-item:mini-player-play|+50:'libraryToggleFocus=' + (libraryPanel.miniPlayerToggleButton.activeFocus && libraryPanel.miniPlayerOverlay.visible && libraryPanel.miniPlayerToggleButton.color === Theme.hover)|+50:focus-item:mini-player-next|+50:'libraryNextFocus=' + (libraryPanel.miniPlayerNextButton.activeFocus && libraryPanel.miniPlayerOverlay.visible && libraryPanel.miniPlayerNextButton.color === Theme.hover)|+100:quit" "$E1")
check "Home mini-player Close button displays keyboard focus" "$out" "homeCloseFocus=true"
check "Home mini-player Expand button displays keyboard focus" "$out" "homeExpandFocus=true"
check "Home mini-player Previous button displays keyboard focus" "$out" "homePreviousFocus=true"
check "Home mini-player Play/Pause button displays keyboard focus" "$out" "homeToggleFocus=true"
check "Home mini-player Next button displays keyboard focus" "$out" "homeNextFocus=true"
check "full-library mini-player Close button displays keyboard focus" "$out" "libraryCloseFocus=true"
check "full-library mini-player Expand button displays keyboard focus" "$out" "libraryExpandFocus=true"
check "full-library mini-player Previous button displays keyboard focus" "$out" "libraryPreviousFocus=true"
check "full-library mini-player Play/Pause button displays keyboard focus" "$out" "libraryToggleFocus=true"
check "full-library mini-player Next button displays keyboard focus" "$out" "libraryNextFocus=true"
echo "== mini-player hover buttons"
out=$(run "500:onboarding.close(); win.width=1920; win.height=1080; player.openUrls([platform.fileUrl('$E1'),platform.fileUrl('$E2')],true)|+1400:win.navigate('home')|+400:drag-item:home-mini-player-title:home-mini-player:90,70|+100:move-item:home-mini-player-video-drag|+50:'homeMiniTitleDrag=' + (homeView.miniPlayerItem.dragOffsetX < -50 && homeView.miniPlayerItem.dragOffsetY < -50 && homeView.miniPlayerOverlay.visible) + ' homeMiniVisualControls=' + (homeView.miniPlayerExpandButton.icon === 'open' && Math.round(homeView.miniPlayerTransportControls.spacing / homeView.miniPlayerItem.uiScale) === 42)|+100:move-item:home-mini-player-video-drag|+180:'homeMiniHoverButtons=' + (homeView.miniPlayerHovered && homeView.miniPlayerOverlay.visible)|+100:move-item:home-mini-player-toggle|+50:click-item:home-mini-player-toggle|+150:'homeMiniButtonPause=' + !player.playing|+100:move-item:home-mini-player-toggle|+50:click-item:home-mini-player-toggle|+150:'homeMiniButtonResume=' + player.playing|+100:move-item:home-mini-player-next|+50:click-item:home-mini-player-next|+700:'homeMiniButtonNext=' + player.mediaUrl.toString().endsWith('My.Show.S01E02.1080p.mkv') + '/' + (navigationPage === 'home')|+100:player.seek(0.5)|+250:move-item:home-mini-player-previous|+50:click-item:home-mini-player-previous|+700:'homeMiniButtonPrevious=' + player.mediaUrl.toString().endsWith('My.Show.S01E01.1080p.mkv') + '/' + (navigationPage === 'home')|+100:move-item:home-mini-player-expand|+50:click-item:home-mini-player-expand|+250:'homeMiniButtonExpand=' + (navigationPage === 'player' && !homeView.visible && controlBar.visible)|+100:win.navigate('home')|+300:move-item:home-mini-player-video-drag|+150:move-item:home-mini-player-close|+50:click-item:home-mini-player-close|+350:'homeMiniButtonClose=' + !player.hasVideo|+100:quit" "$E1" "$E2")
check "the Home mini-player moves from its title and reveals controls over video" "$out" "homeMiniTitleDrag=true"
check "the Home mini-player uses Figma's open icon and transport spacing" "$out" "homeMiniVisualControls=true"
check "Home mini-player playback buttons appear in the hover animation" "$out" "homeMiniHoverButtons=true"
check "the Home mini-player pause button pauses VLC" "$out" "homeMiniButtonPause=true"
check "the Home mini-player play button resumes VLC" "$out" "homeMiniButtonResume=true"
check "the Home mini-player next button advances the VLC queue without leaving Home" "$out" "homeMiniButtonNext=true/true"
check "the Home mini-player previous button returns to the prior VLC queue item without leaving Home" "$out" "homeMiniButtonPrevious=true/true"
check "the Home mini-player expand button opens the player" "$out" "homeMiniButtonExpand=true"
check "the Home mini-player close button stops playback" "$out" "homeMiniButtonClose=true"
echo "== full-library mini-player buttons after moving the card"
out=$(run "500:onboarding.close(); win.width=1920; win.height=1080; player.openUrls([platform.fileUrl('$E1'),platform.fileUrl('$E2')],true)|+1400:win.navigate('folder')|+400:drag-item:mini-player-title:mini-player:90,70|+100:move-item:mini-player-video-drag|+50:'libraryMiniMovedWithOverlay=' + (libraryPanel.miniPlayerItem.dragOffsetX < -50 && libraryPanel.miniPlayerItem.dragOffsetY < -50 && libraryPanel.miniPlayerOverlay.visible)|+100:move-item:mini-player-play|+50:click-item:mini-player-play|+150:'libraryMiniButtonPause=' + !player.playing|+100:move-item:mini-player-play|+50:click-item:mini-player-play|+150:'libraryMiniButtonResume=' + player.playing|+100:move-item:mini-player-next|+50:click-item:mini-player-next|+700:'libraryMiniButtonNext=' + player.mediaUrl.toString().endsWith('My.Show.S01E02.1080p.mkv')|+100:player.seek(0.5)|+200:move-item:mini-player-previous|+50:click-item:mini-player-previous|+700:'libraryMiniButtonPrevious=' + player.mediaUrl.toString().endsWith('My.Show.S01E01.1080p.mkv')|+100:move-item:mini-player-expand|+50:click-item:mini-player-expand|+250:'libraryMiniButtonExpand=' + (navigationPage === 'player')|+100:win.navigate('folder')|+300:move-item:mini-player-video-drag|+150:move-item:mini-player-close|+50:click-item:mini-player-close|+350:'libraryMiniButtonClose=' + !player.hasVideo|+100:quit" "$E1" "$E2")
check "the full-library mini-player moves from its title and reveals its controls over video" "$out" "libraryMiniMovedWithOverlay=true"
check "the full-library mini-player pause button pauses VLC after dragging" "$out" "libraryMiniButtonPause=true"
check "the full-library mini-player play button resumes VLC after dragging" "$out" "libraryMiniButtonResume=true"
check "the full-library mini-player next button advances the VLC queue after dragging" "$out" "libraryMiniButtonNext=true"
check "the full-library mini-player previous button returns to the prior VLC queue item after dragging" "$out" "libraryMiniButtonPrevious=true"
check "the full-library mini-player expand button opens the player after dragging" "$out" "libraryMiniButtonExpand=true"
check "the full-library mini-player close button stops playback after dragging" "$out" "libraryMiniButtonClose=true"
echo "== mini-player button placement after dragging"
out=$(run "500:onboarding.close(); win.width=1920; win.height=1080; player.openLocation('$E1',true)|+1200:win.navigate('home')|+300:drag-item:home-mini-player-title:home-mini-player:90,70|+100:'homeMiniButtonLayout=' + (() => { const m=homeView.miniPlayerItem, s=m.uiScale; const p=b=>b.mapToItem(m,0,0); const c=p(homeView.miniPlayerCloseButton), e=p(homeView.miniPlayerExpandButton), prev=p(homeView.miniPlayerPreviousButton), toggle=p(homeView.miniPlayerToggleButton), next=p(homeView.miniPlayerNextButton), qb=homeView.miniPlayerQueueButton, q=p(qb); const near=(a,b)=>Math.abs(a-b)<1; const rowX=(m.width-180*s)/2, rowY=8*s+(m.width-16*s)*9/32-18*s; return near(c.x,20*s) && near(c.y,20*s) && near(e.x,m.width-50*s) && near(e.y,20*s) && near(prev.x,rowX) && near(prev.y,rowY) && near(toggle.x,rowX+72*s) && near(toggle.y,rowY) && near(next.x,rowX+150*s) && near(next.y,rowY) && near(q.x,m.width-46*s) && near(q.y,m.height-44*s) && near(qb.height,32*s) })()|+100:win.navigate('folder')|+300:drag-item:mini-player-title:mini-player:90,70|+100:'libraryMiniButtonLayout=' + (() => { const m=libraryPanel.miniPlayerItem, s=m.uiScale; const p=b=>b.mapToItem(m,0,0); const c=p(libraryPanel.miniPlayerCloseButton), e=p(libraryPanel.miniPlayerExpandButton), prev=p(libraryPanel.miniPlayerPreviousButton), toggle=p(libraryPanel.miniPlayerToggleButton), next=p(libraryPanel.miniPlayerNextButton), qb=libraryPanel.miniPlayerQueueButton, q=p(qb); const near=(a,b)=>Math.abs(a-b)<1; const rowX=(m.width-180*s)/2, rowY=8*s+(m.width-16*s)*9/32-18*s; return near(c.x,20*s) && near(c.y,20*s) && near(e.x,m.width-50*s) && near(e.y,20*s) && near(prev.x,rowX) && near(prev.y,rowY) && near(toggle.x,rowX+72*s) && near(toggle.y,rowY) && near(next.x,rowX+150*s) && near(next.y,rowY) && near(q.x,m.width-46*s) && near(q.y,m.height-44*s) && near(qb.height,32*s) })()|+100:quit" "$E1")
check "Home mini-player buttons keep their Figma positions relative to the moved card" "$out" "homeMiniButtonLayout=true"
check "full-library mini-player buttons keep their Figma positions relative to the moved card" "$out" "libraryMiniButtonLayout=true"
check "the Home mini-player moves with all six buttons at each drag step" "$out" "neo test: Home mini-player card moved with all six controls (6/6 steps)"
check "the full-library mini-player moves with all six buttons at each drag step" "$out" "neo test: Library mini-player card moved with all six controls (6/6 steps)"
echo "== queue buttons on moved mini-players"
out=$(run "500:onboarding.close(); win.width=1920; win.height=1080; player.openLocation('$E1',true)|+1400:win.navigate('home')|+350:drag-item:home-mini-player-title:home-mini-player:90,70|+100:'homeQueueButtonInstantHover=' + !homeView.miniPlayerQueueButton.colorAnimationEnabled|+150:click-item:home-mini-player-queue|+150:'homeQueueOpened=' + (rightPanel === 'queue' && homeView.miniPlayerQueueButton.iconColor === Theme.accent && homeView.miniPlayerItem.visible && homeView.miniPlayerItem.parent === queuePanel && Math.round(homeView.miniPlayerItem.width) === 391 && Math.round(homeView.miniPlayerItem.y) === Math.round(queuePanel.height - homeView.miniPlayerItem.height - 16) && queuePanel.reservedBottomHeight > 350)|+100:click-item:home-mini-player-queue|+150:move:800,600|+50:'homeQueueToggleClosed=' + (rightPanel === '' && homeView.miniPlayerQueueButton.iconColor !== Theme.accent && homeView.miniPlayerItem.parent === homeView && homeView.miniPlayerItem.dragOffsetX < -50 && homeView.miniPlayerItem.dragOffsetY < -50)|+150:win.navigate('folder')|+350:drag-item:mini-player-title:mini-player:90,70|+100:'libraryQueueButtonInstantHover=' + !libraryPanel.miniPlayerQueueButton.colorAnimationEnabled|+150:click-item:mini-player-queue|+150:'libraryQueueOpened=' + (rightPanel === 'queue' && libraryPanel.miniPlayerQueueButton.iconColor === Theme.accent && libraryPanel.miniPlayerItem.visible && libraryPanel.miniPlayerItem.parent === queuePanel && Math.round(libraryPanel.miniPlayerItem.width) === 391 && Math.round(libraryPanel.miniPlayerItem.y) === Math.round(queuePanel.height - libraryPanel.miniPlayerItem.height - 16) && queuePanel.reservedBottomHeight > 350)|+100:click-item:mini-player-queue|+150:move:800,600|+50:'libraryQueueToggleClosed=' + (rightPanel === '' && libraryPanel.miniPlayerQueueButton.iconColor !== Theme.accent && libraryPanel.miniPlayerItem.parent === win.contentItem && libraryPanel.miniPlayerItem.dragOffsetX < -50 && libraryPanel.miniPlayerItem.dragOffsetY < -50)|+100:quit" "$E1")
check "the Home mini-player Queue button disables its delayed color transition" "$out" "homeQueueButtonInstantHover=true"
check "the Home mini-player docks into the Queue column when its queue button opens it after a drag" "$out" "homeQueueOpened=true"
check "the Home mini-player returns to Home when its queue button closes the panel after a drag" "$out" "homeQueueToggleClosed=true"
check "the full-library mini-player Queue button disables its delayed color transition" "$out" "libraryQueueButtonInstantHover=true"
check "the full-library mini-player docks into the Queue column after its queue button is clicked" "$out" "libraryQueueOpened=true"
check "the full-library mini-player returns to the window when the Queue panel closes" "$out" "libraryQueueToggleClosed=true"
echo "== buttons remain inside the mini-player after Queue docking"
out=$(run "500:onboarding.close(); win.width=1920; win.height=1080; player.openLocation('$E1',true)|+1300:win.navigate('home')|+350:drag-item:home-mini-player-title:home-mini-player:90,70|+100:click-item:home-mini-player-queue|+150:move-item:home-mini-player-video-drag|+150:'homeQueueDockButtonLayout=' + (() => { const m=homeView.miniPlayerItem, s=m.uiScale, bs=[homeView.miniPlayerCloseButton,homeView.miniPlayerExpandButton,homeView.miniPlayerPreviousButton,homeView.miniPlayerToggleButton,homeView.miniPlayerNextButton,homeView.miniPlayerQueueButton], p=b=>b.mapToItem(m,0,0); const c=p(bs[0]), e=p(bs[1]), prev=p(bs[2]), toggle=p(bs[3]), next=p(bs[4]), q=p(bs[5]), near=(a,b)=>Math.abs(a-b)<1, rowX=(m.width-180*s)/2, rowY=8*s+(m.width-16*s)*9/32-18*s; return m.parent===queuePanel && homeView.miniPlayerOverlay.visible && bs.every(b=>b.visible) && near(c.x,20*s) && near(c.y,20*s) && near(e.x,m.width-50*s) && near(e.y,20*s) && near(prev.x,rowX) && near(prev.y,rowY) && near(toggle.x,rowX+72*s) && near(toggle.y,rowY) && near(next.x,rowX+150*s) && near(next.y,rowY) && near(q.x,m.width-46*s) && near(q.y,m.height-44*s) && near(bs[5].height,32*s) })()|+100:click-item:home-mini-player-queue|+150:win.navigate('folder')|+350:drag-item:mini-player-title:mini-player:90,70|+100:click-item:mini-player-queue|+150:move-item:mini-player-video-drag|+150:'libraryQueueDockButtonLayout=' + (() => { const m=libraryPanel.miniPlayerItem, s=m.uiScale, bs=[libraryPanel.miniPlayerCloseButton,libraryPanel.miniPlayerExpandButton,libraryPanel.miniPlayerPreviousButton,libraryPanel.miniPlayerToggleButton,libraryPanel.miniPlayerNextButton,libraryPanel.miniPlayerQueueButton], p=b=>b.mapToItem(m,0,0); const c=p(bs[0]), e=p(bs[1]), prev=p(bs[2]), toggle=p(bs[3]), next=p(bs[4]), q=p(bs[5]), near=(a,b)=>Math.abs(a-b)<1, rowX=(m.width-180*s)/2, rowY=8*s+(m.width-16*s)*9/32-18*s; return m.parent===queuePanel && libraryPanel.miniPlayerOverlay.visible && bs.every(b=>b.visible) && near(c.x,20*s) && near(c.y,20*s) && near(e.x,m.width-50*s) && near(e.y,20*s) && near(prev.x,rowX) && near(prev.y,rowY) && near(toggle.x,rowX+72*s) && near(toggle.y,rowY) && near(next.x,rowX+150*s) && near(next.y,rowY) && near(q.x,m.width-46*s) && near(q.y,m.height-44*s) && near(bs[5].height,32*s) })()|+100:quit" "$E1")
check "all six Home mini-player buttons keep Figma positions and visibility after Queue docking" "$out" "homeQueueDockButtonLayout=true"
check "all six full-library mini-player buttons keep Figma positions and visibility after Queue docking" "$out" "libraryQueueDockButtonLayout=true"
for screenshot in navigation-videos.png folder-browser-grid-1920.png folder-browser-list-1920.png; do
    if [ -s "$WORK/$screenshot" ]; then echo "PASS  $screenshot written"; pass=$((pass + 1))
    else echo "FAIL  $screenshot missing"; fail=$((fail + 1)); fi
done
echo "== network sidebar"
out=$(run "1000:onboarding.close(); Theme.store.mode='dark'; win.width=1920; win.height=1080; win.navigateFromRail('network')|+300:'networkSide=' + [win.navigationPage,win.libraryOpen,libraryPanel.section,libraryPanel.figmaSidePanel,navigationRail.currentPage,libraryPanel.width,libraryPanel.visibleNetworkCategories().map(x=>x.label).join(',')].join('/')|+100:'networkRootArrowsDisabled=' + (!libraryPanel.canGoBackFromSidePanel() && !libraryPanel.canGoForwardFromSidePanel())|+100:click-item:sidepanel-back-network|+100:'networkRootBackStays=' + (win.navigationPage === 'network' && win.libraryOpen)|+100:grab:$WORK/network-sidebar.png|+100:focus-item:network-sidepanel-add|+100:key:Return|+150:'networkAdd=' + [networkDialog.visible,networkDialog.sourceCategory,networkDialog.title].join('/')|+100:networkDialog.close()|+450:focus-item:network-sidepanel-category-podcast|+100:key:Return|+150:'networkPodcast=' + [networkDialog.visible,networkDialog.sourceCategory,networkDialog.title].join('/')|+100:networkDialog.close()|+450:click-item:network-sidepanel-category-radio|+150:'networkRadio=' + [networkDialog.visible,networkDialog.sourceCategory,networkDialog.title].join('/')|+100:networkDialog.close()|+100:win.closeSidePanel()|+300:'networkClosed=' + (!win.libraryOpen && navigationRail.width === 0 && !navigationRail.visible)|+100:quit" "$E1")
check "the Network rail opens its Figma side pane beside the player" "$out" "networkSide=network/true/network/true/network/377/Podcasts,Radio"
check "the Network root keeps Back and Forward disabled" "$out" "networkRootArrowsDisabled=true"
check "Back does not exit the Network side pane at its root" "$out" "networkRootBackStays=true"
check "Add Network Stream is keyboard-activatable and opens VLC's real stream dialog" "$out" "networkAdd=true//Open Network Stream"
check "Podcasts opens VLC's stream dialog with a podcast feed prompt" "$out" "networkPodcast=true/podcast/Open Podcast Feed"
check "Radio opens VLC's stream dialog with a radio stream prompt" "$out" "networkRadio=true/radio/Open Radio Stream"
check "closing the Network pane removes the entire side rail" "$out" "networkClosed=true"
if [ -s "$WORK/network-sidebar.png" ]; then echo "PASS  network sidebar screenshot written"; pass=$((pass + 1))
else echo "FAIL  network sidebar screenshot missing"; fail=$((fail + 1)); fi
out=$(run "500:onboarding.close(); win.openSidePanel('music')|+250:click-item:music-sidepanel-category-albums|+150:'musicSideAlbum=' + (libraryPanel.musicSidePage === 'albums')|+100:click-item:sidepanel-back-generic|+150:'musicSideBack=' + (libraryPanel.musicSidePage === 'categories' && libraryPanel.canGoForwardFromSidePanel())|+100:click-item:sidepanel-forward-music|+150:'musicSideForward=' + (libraryPanel.musicSidePage === 'albums' && !libraryPanel.canGoForwardFromSidePanel())|+100:quit" "$E1")
check "Music side-pane category navigation records an album page" "$out" "musicSideAlbum=true"
check "Music side-pane Back enables Forward to the album page" "$out" "musicSideBack=true"
check "Music side-pane Forward restores the album page" "$out" "musicSideForward=true"
out=$(run "500:onboarding.close(); win.width=1920; win.height=1080; player.openLocation('$WORK/audio-only.m4a',true)|+1200:win.navigateFromRail('network')|+200:click-item:sidepanel-more-button-network|+150:'sideMenu=' + [sidePanelActionsMenu.visible,sidePanelActionsMenu.count].join('/')|+100:focus-item:sidepanel-action-add-file|+100:key:Return|+150:'sideAddFile=' + openFilesDialog.visible|+100:openFilesDialog.close()|+200:click-item:sidepanel-more-button-network|+100:focus-item:sidepanel-action-add-folder|+100:key:Return|+150:'sideAddFolder=' + openFolderDialog.visible|+100:openFolderDialog.close()|+200:click-item:sidepanel-more-button-network|+100:focus-item:sidepanel-action-edit-subtitles|+100:key:Return|+150:'sideSubtitles=' + [tracksPopup.visible,tracksPopup.tab].join('/')|+100:tracksPopup.close()|+200:click-item:sidepanel-more-button-network|+100:focus-item:sidepanel-action-edit-audio|+100:key:Return|+150:'sideAudio=' + [tracksPopup.visible,tracksPopup.tab].join('/')|+100:tracksPopup.close()|+200:player.setAudioDelay(350); player.setSubtitleDelay(-250)|+200:click-item:sidepanel-more-button-network|+100:focus-item:sidepanel-action-resync|+100:key:Return|+200:'sideResync=' + [player.audioDelay,player.subtitleDelay].join('/')|+100:click-item:sidepanel-more-button-network|+100:focus-item:sidepanel-action-info|+100:key:Return|+150:'sideInfo=' + mediaPropertiesDialog.visible|+100:mediaPropertiesDialog.close()|+100:quit" "$WORK/audio-only.m4a")
check "the side-pane More button opens Figma's six-action menu" "$out" "sideMenu=true/6"
check "the side-pane Add File action opens VLC's file picker" "$out" "sideAddFile=true"
check "the side-pane Add Folder action opens VLC's folder picker" "$out" "sideAddFolder=true"
check "Edit Subtitle Tracks opens the VLC subtitle picker" "$out" "sideSubtitles=true/spu"
check "Edit Audio Tracks opens the VLC audio picker" "$out" "sideAudio=true/audio"
check "Resync resets real VLC audio and subtitle delays" "$out" "sideResync=0/0"
check "Info opens VLC Neo's media properties dialog" "$out" "sideInfo=true"
out=$(run "500:onboarding.close(); win.width=1920; win.height=1080; win.openSidePanel('home')|+200:'homeRootArrowsDisabled=' + (!libraryPanel.canGoBackFromSidePanel() && !libraryPanel.canGoForwardFromSidePanel())|+100:click-item:home-sidepanel-back|+100:'homeRootBackStays=' + (navigationPage === 'home' && libraryOpen)|+100:click-item:home-sidepanel-more-button|+100:'homeMore=' + sidePanelActionsMenu.visible|+100:sidePanelActionsMenu.close()|+200:win.navigateFromRail('playlist')|+200:'playlistRootArrowsDisabled=' + (!libraryPanel.canGoBackFromSidePanel() && !libraryPanel.canGoForwardFromSidePanel())|+100:click-item:playlist-sidepanel-back|+100:'playlistRootBackStays=' + (navigationPage === 'playlist' && libraryOpen)|+100:click-item:playlist-sidepanel-more-button|+100:'playlistMore=' + sidePanelActionsMenu.visible|+100:sidePanelActionsMenu.close()|+200:win.navigateFromRail('music')|+200:'musicRootArrowsDisabled=' + (!libraryPanel.canGoBackFromSidePanel() && !libraryPanel.canGoForwardFromSidePanel())|+100:click-item:sidepanel-back-music|+100:'musicRootBackStays=' + (navigationPage === 'music' && libraryPanel.musicSidePage === 'categories')|+100:click-item:sidepanel-more-button-music|+100:'musicMore=' + sidePanelActionsMenu.visible|+100:sidePanelActionsMenu.close()|+200:win.navigateFromRail('videos')|+200:'videosRootArrowsDisabled=' + (!libraryPanel.canGoBackFromSidePanel() && !libraryPanel.canGoForwardFromSidePanel())|+100:click-item:sidepanel-back-generic|+100:'videosRootBackStays=' + (navigationPage === 'videos' && libraryOpen)|+100:click-item:sidepanel-more-button-generic|+100:'videosMore=' + sidePanelActionsMenu.visible|+100:quit")
check "Home's side-pane More button opens the shared VLC actions menu" "$out" "homeMore=true"
check "Home's root arrows stay disabled and Back keeps the side pane open" "$out" "homeRootArrowsDisabled=true"
check "Back does not leave Home's side pane when its history is empty" "$out" "homeRootBackStays=true"
check "Playlists' side-pane More button opens the shared VLC actions menu" "$out" "playlistMore=true"
check "Playlists' root arrows stay disabled and Back keeps the side pane open" "$out" "playlistRootArrowsDisabled=true"
check "Back does not leave Playlists when its history is empty" "$out" "playlistRootBackStays=true"
check "Music's side-pane More button opens the shared VLC actions menu" "$out" "musicMore=true"
check "Music's root arrows stay disabled and Back keeps its categories open" "$out" "musicRootArrowsDisabled=true"
check "Back does not leave the Music side pane when its history is empty" "$out" "musicRootBackStays=true"
check "Videos' side-pane More button opens the shared VLC actions menu" "$out" "videosMore=true"
check "Videos' root arrows stay disabled and Back keeps the side pane open" "$out" "videosRootArrowsDisabled=true"
check "Back does not leave Videos when its history is empty" "$out" "videosRootBackStays=true"
out=$(NEO_SANDBOX="$WORK/home-navigation-sandbox" run "500:onboarding.close(); win.width=1920; win.height=1080; win.openSidePanel('home'); sideHomeView.folderItems=[{path:'$WORK/navigation-history',title:'Shows'}]|+250:click-item:home-side-folder-0|+0:'homeFolderRoute=' + (navigationPage === 'folder' && win.libraryOpen && libraryPanel.canGoBackFromSidePanel())|+100:libraryPanel.openFolder(platform.fileUrl('$WORK/navigation-history/Season 1')); 'homeFolderNested=' + libraryPanel.canGoBackFromSidePanel()|+100:click-item:sidepanel-back-generic|+200:'homeFolderRootBack=' + (platform.localPath(libraryPanel.folder) === '$WORK/navigation-history' && libraryPanel.canGoBackFromSidePanel())|+100:keyCatcher.forceActiveFocus(); 'escapeReady=' + keyCatcher.activeFocus|+100:key:Esc|+200:'homeFolderBack=' + (navigationPage === 'home' && win.libraryOpen && sideHomeView.visible && libraryPanel.canGoForwardFromSidePanel())|+100:focus-item:home-sidepanel-forward|+100:key:Return|+200:'homeFolderForward=' + (navigationPage === 'folder' && win.libraryOpen && platform.localPath(libraryPanel.folder) === '$WORK/navigation-history' && libraryPanel.canGoForwardFromSidePanel())|+100:click-item:sidepanel-forward-generic|+200:'homeFolderNestedForward=' + (platform.localPath(libraryPanel.folder) === '$WORK/navigation-history/Season 1')|+100:quit")
check "opening a Home folder enables Back to the Home side pane" "$out" "homeFolderRoute=true"
check "Home folder Back visits its nested parent before Home" "$out" "homeFolderRootBack=true"
check "Escape follows Home side-pane history before closing the panel" "$out" "homeFolderBack=true"
check "Home's Forward restores the folder root and its nested forward history" "$out" "homeFolderForward=true"
check "the folder Forward restores the nested directory after returning from Home" "$out" "homeFolderNestedForward=true"
out=$(run "500:onboarding.close(); win.width=1920; win.height=1080; win.openSidePanel('home')|+250:sideHomeView.musicItems=[{title:'Recent song',artist:'Recent Artist',path:'/tmp/recent.m4a',artwork:''},{title:'Frequent song 1',artist:'Frequent Artist',path:'/tmp/frequent-1.m4a',artwork:''},{title:'Frequent song 2',artist:'Frequent Artist',path:'/tmp/frequent-2.m4a',artwork:''}]; sideHomeView.recordArtistListen('Recent Artist','file:///tmp/recent.m4a'); sideHomeView.recordArtistListen('Frequent Artist','file:///tmp/frequent-1.m4a'); sideHomeView.recordArtistListen('Frequent Artist','file:///tmp/frequent-2.m4a'); sideHomeView.refreshArtistItems(); 'homeArtistShelf=' + (sideHomeView.artistItems.length === 2 && sideHomeView.artistItems[0].artist === 'Frequent Artist')|+100:click-item:home-side-artist-0|+350:'homeArtistRoute=' + (navigationPage === 'music' && libraryFullPage && mediaLibrary.model.view === 'artists' && mediaLibrary.model.search === 'Frequent Artist')|+100:quit")
check "Home shows the most frequently played indexed artists first" "$out" "homeArtistShelf=true"
check "selecting a Home artist opens its filtered Artists view" "$out" "homeArtistRoute=true"
out=$(NEO_SANDBOX="$WORK/home-artist-playback-sandbox" run "500:onboarding.close(); win.width=1120; win.height=700; mediaLibrary.addFolder(platform.fileUrl('$WORK/music')); win.openSidePanel('home')|+1000:player.openLocation('$WORK/music/Neon Track 01.m4a',true)|+2600:'homeArtistPlayback=' + (player.playing && !player.hasVideo && player.artist === 'Demo Artist' && JSON.parse(Theme.store.homeArtistListenCountsJson)['Demo Artist'].count === 1)|+100:quit")
check "starting an audio-only track records its artist once while Home is hidden" "$out" "homeArtistPlayback=true"
out=$(NEO_SANDBOX="$WORK/home-artist-playback-sandbox" run "500:onboarding.close(); win.width=1120; win.height=700; player.openLocation('$WORK/music/Neon Track 01.m4a',true)|+2600:'homeArtistPlaybackRestart=' + (player.playing && JSON.parse(Theme.store.homeArtistListenCountsJson)['Demo Artist'].count === 2)|+100:quit")
check "Home artist play counts persist and count a new session after relaunch" "$out" "homeArtistPlaybackRestart=true"
out=$(run "500:onboarding.close(); win.width=1920; win.height=1080; player.openLocation('$E1',true)|+1200:win.openSidePanel('home')|+200:click-item:home-sidepanel-open-full-page|+350:'homeExpand=' + (navigationPage === 'folder' && libraryFullPage && !libraryOpen && libraryPanel.section === 'folder' && platform.localPath(libraryPanel.folder) === player.folderPath && !videoArea.visible && video.parent === libraryPanel.miniVideoHost)|+100:quit")
check "Home's open button follows Figma to the current folder browser with a mini-player" "$out" "homeExpand=true"
out=$(run "500:onboarding.close(); win.width=1920; win.height=1080; player.openLocation('$E1',true)|+1200:win.openSidePanel('playlist')|+200:click-item:playlist-expand|+300:'playlistExpand=' + (navigationPage === 'folder' && libraryFullPage && !libraryOpen && libraryPanel.section === 'folder' && platform.localPath(libraryPanel.folder) === player.folderPath && !videoArea.visible && video.parent === libraryPanel.miniVideoHost)|+100:quit")
check "Playlists' open button follows Figma to the current folder's full-page view" "$out" "playlistExpand=true"

out=$(run "500:onboarding.close(); win.width=1120; win.height=680; 'emptyFolderChip=' + topBar.folderLabel|+100:player.openLocation('$WORK/audio-only.m4a',true)|+1200:'audioFolderChip=' + topBar.folderLabel|+100:player.openLocation('$E1',true)|+1200:'videoFolderChip=' + topBar.folderLabel|+100:quit")
check "the empty player header defaults to the Videos folder" "$out" "emptyFolderChip=Videos"
check "audio playback keeps the My Songs header label" "$out" "audioFolderChip=My Songs"
check "video playback shows its containing folder in the header" "$out" "videoFolderChip=show"
echo "== asynchronous indexed media library"
out=$(run "1200:'musicFocus=' + navigationRail.focusPage('music')|+100:key:Space|+100:'musicPage=' + (navigationPage === 'music' && win.libraryOpen && libraryPanel.section === 'music')|+100:mediaLibrary.model.view='tracks'; 'indexRequested=' + mediaLibrary.addFolder(platform.fileUrl('$WORK/music')) + ' busy=' + mediaLibrary.scanning|+1600:'indexComplete=' + (!mediaLibrary.scanning) + ' count=' + mediaLibrary.indexedCount + ' roots=' + mediaLibrary.roots.length + ' tracks=' + mediaLibrary.model.itemCount() + ' title=' + mediaLibrary.model.itemAt(0).title + ' art=' + (mediaLibrary.model.itemAt(0).artwork.length > 0)|+100:grab:$WORK/music-library.png|+100:focus-item:music-sidepanel-category-albums|+100:key:Space|+100:'keyboardAlbum=' + mediaLibrary.model.view + '/' + libraryPanel.musicSidePage|+100:click-item:sidepanel-back-generic|+100:click-item:music-sidepanel-category-songs|+100:click-item:music-sidepanel-root-music|+150:mediaLibrary.model.search='ELECTRONIC'|+250:'search=' + libraryPanel.musicSideTracks().length|+100:mediaLibrary.model.search='neon'|+250:'trackSearch=' + libraryPanel.musicSideTracks().length|+100:mediaLibrary.model.search='Untitled Track'|+250:'untaggedFallback=' + libraryPanel.musicSideTracks()[0].title|+100:mediaLibrary.model.search=''|+150:click-item:sidepanel-back-music|+100:click-item:sidepanel-back-music|+100:click-item:music-sidepanel-category-albums|+250:'album=' + mediaLibrary.model.itemAt(0).title + '/' + mediaLibrary.model.itemAt(0).count + ' art=' + libraryPanel.musicArtworkReady(0)|+100:click-item:music-library-group-0|+150:'albumTracks=' + mediaLibrary.model.grouped + '/' + mediaLibrary.model.itemCount()|+100:click-item:sidepanel-back-generic|+100:click-item:sidepanel-back-generic|+100:click-item:music-sidepanel-category-artists|+250:'artist=' + mediaLibrary.model.itemAt(0).title|+100:click-item:sidepanel-back-generic|+100:click-item:music-sidepanel-category-genres|+250:'genre=' + mediaLibrary.model.itemAt(0).title|+100:click-item:sidepanel-back-generic|+100:win.expandLibrarySidePanel(); mediaLibrary.model.view='videos'|+250:'video=' + mediaLibrary.model.itemAt(0).title + '/' + mediaLibrary.model.itemCount()|+100:quit" "$E1")
check "the Music rail opens the indexed Music library page" "$out" "musicPage=true"
check "adding a local folder starts indexing without blocking the UI" "$out" "indexRequested=true busy=true"
check "the asynchronous index reads tags, cover art and persists its root" "$out" "indexComplete=true count=4 roots=1 tracks=3 title=Neon Track art=true"
check "Music category rows accept keyboard focus" "$out" "focused music-sidepanel-category-albums (1)"
check "Space opens the visible Albums category" "$out" "keyboardAlbum=albums/albums"
check "library search finds album tags and track titles" "$out" "search=2"
check "search is case-insensitive for track metadata" "$out" "trackSearch=2"
check "missing tags fall back to the media filename" "$out" "untaggedFallback=Untitled Track"
check "album groups expose their tracks" "$out" "album=Demo Album/2"
check "album artwork loads from the cached file URL in the Figma sidebar" "$out" "album=Demo Album/2 art=true"
check "opening an album shows its two tracks" "$out" "albumTracks=true/2"
check "artist and genre sections are populated from media tags" "$out" "artist=Demo Artist"
check "genre section contains the tagged genre" "$out" "genre=Electronic"
check "video files are indexed and searchable separately from tracks" "$out" "video=Sample Video/1"
out=$(run "100:onboarding.close(); Theme.store.mode='dark'; mediaLibrary.model.search=''; player.openLocation('$E1', true)|+1200:player.jumpTo(20000)|+900:win.navigate('home')|+300:'homeFigma=' + (homeView.visible && !win.libraryOpen && navigationRail.visible && navigationRail.expanded && navigationRail.width > 0 && !controlBar.visible && videoArea.visible && homeView.videoItems.length > 0 && homeView.musicItems.length > 0 && homeView.folderItems.length > 0)|+100:'resumeProgress=' + homeView.videoItems.some(item => item.point > 0 && item.duration > item.point && item.progress > 0)|+100:homeView.searchText='Untitled'; homeView.refreshContent(); 'homeSearch=' + homeView.videoItems.length + '/' + homeView.musicItems.length|+100:homeView.searchText=''; homeView.refreshContent(); 'homeSearchReset=' + homeView.musicItems.length|+100:click:770,56|+100:'homeSort=' + homeView.sortByName|+100:click:812,56|+100:'homeCompact=' + homeView.compactCards|+100:homeView.compactCards=false|+100:win.width=1920; win.height=1080; player.stop()|+150:homeView.videoItems=[{url:platform.fileUrl('$E1'),path:'$E1',title:'My.Show.S01E01.1080p.mkv',point:20000,duration:40000,progress:0.5},{url:platform.fileUrl('$E2'),path:'$E2',title:'My.Show.S01E02.1080p.mkv',point:18000,duration:40000,progress:0.45},{url:platform.fileUrl('$WORK/seek-scenes.mkv'),path:'$WORK/seek-scenes.mkv',title:'Seek scenes.mkv',point:4000,duration:8000,progress:0.5},{url:platform.fileUrl('$WORK/recording-test.mkv'),path:'$WORK/recording-test.mkv',title:'Recording test.mkv',point:10000,duration:20000,progress:0.5}]; homeView.folderItems=[{path:'$WORK/music',title:'music'},{path:'$WORK/show',title:'show'},{path:'$WORK/Videos',title:'Videos'},{path:'$WORK/recursive-root',title:'recursive-root'}]; 'homeFigmaCardCounts=' + homeView.videoItems.length + '/' + homeView.musicItems.length + '/' + homeView.folderItems.length|+10000:'homeWide=' + (homeView.width > 1600 && navigationRail.width >= 200) + '/' + homeView.videoThumbnailReady(0)|+100:'homeSearchWidth=' + Math.round(homeView.fullPageSearchField.width)|+100:move:1910,1070|+100:grab:$WORK/home-library.png|+100:win.width=1120; win.height=680|+200:'homeSearchResponsive=' + (homeView.fullPageSearchField.width > 100 && homeView.fullPageSearchField.width < 324)|+100:player.stop()|+100:click-item:home-video-card-play-0|+800:'homeCardPlayback=' + (player.hasVideo && player.mediaUrl.toString().length > 0) + '/' + (win.navigationPage === 'player' && !homeView.visible && controlBar.visible)|+100:quit" "$E1")
check "Home matches the Figma shelves with recent video, indexed music and folders" "$out" "homeFigma=true"
check "Continue Watching cards retain a real resume position and duration" "$out" "resumeProgress=true"
check "Home review capture uses the four video and four folder cards shown in Figma" "$out" "homeFigmaCardCounts=4/3/4"
check "Home search filters matching music and video shelves" "$out" "homeSearch=0/1"
check "clearing Home search restores its shelves" "$out" "homeSearchReset=3"
check "Home sort control changes the shelf ordering" "$out" "homeSort=true"
check "Home view control switches to compact cards" "$out" "homeCompact=true"
check "Home reflows at 1920 px and asynchronously shows VLC video artwork" "$out" "homeWide=true/true"
check "Home search matches the 324 px Figma field at 1920 px" "$out" "homeSearchWidth=324"
check "Home search resizes for a standard 1120 px window" "$out" "homeSearchResponsive=true"
check "selecting a Continue Watching card opens video playback and restores player controls" "$out" "homeCardPlayback=true/true"
if [ -s "$WORK/home-library.png" ]; then echo "PASS  Figma Home screenshot written"; pass=$((pass + 1))
else echo "FAIL  Figma Home screenshot missing"; fail=$((fail + 1)); fi
out=$(NEO_SANDBOX="$WORK/home-route-history" run "500:onboarding.close(); win.width=1920; win.height=1080; win.navigate('videos'); win.navigate('home'); 'homeRouteReady=' + (navigationPage === 'home' && homeView.visible && win.canGoBack && !win.canGoForward)|+150:focus-item:home-fullpage-back|+100:key:Space|+150:'homeRouteBack=' + (navigationPage === 'videos' && libraryFullPage && win.canGoForward)|+100:focus-item:library-global-forward|+100:key:Space|+150:'homeRouteForward=' + (navigationPage === 'home' && !libraryFullPage && win.canGoBack && !win.canGoForward)|+100:quit")
check "Home full-page Back follows route history to Videos" "$out" "homeRouteBack=true"
check "Videos full-page Forward restores Home from route history" "$out" "homeRouteForward=true"
if [ -s "$WORK/music-library.png" ]; then echo "PASS  indexed music library screenshot written"; pass=$((pass + 1))
else echo "FAIL  indexed music library screenshot missing"; fail=$((fail + 1)); fi
out=$(run "100:onboarding.close(); Theme.store.mode='dark'; Theme.setLayout(Theme.defaultLayout.slice()); win.width=1920; win.height=1080; player.openLocation('$WORK/music/Neon Track 01.m4a', true)|+1200:toastItem.opacity=0; 'musicControls=' + controlBar.renderedItems.slice(0,5).join(',') + ';icons=' + Theme.controls.back15.icon + '/' + Theme.controls.fwd15.icon|+100:Theme.setLayout(Theme.defaultLayout.concat(['back15','fwd15']))|+100:'customMusicSkipDeduplicated=' + (controlBar.renderedItems.filter(id => id === 'back15').length === 1 && controlBar.renderedItems.filter(id => id === 'fwd15').length === 1)|+100:Theme.setLayout(Theme.defaultLayout.slice())|+100:'musicLayout=' + Math.round(musicView.artworkItem.width) + '/' + musicView.titleGap + '/' + musicView.infoLabel.font.pixelSize + '/' + musicView.infoLabel.color|+4500:'musicWaveformReady=' + controlBar.findControl('seek').contentItem.waveformReady|+100:grab:$WORK/music-player.png|+100:win.width=560; win.height=340|+400:'musicCompact=' + Math.round(musicView.artworkItem.width) + '/' + (musicView.artworkItem.width < 220)|+100:quit" "$WORK/music/Neon Track 01.m4a")
check "audio player artwork, title spacing and typography match Figma" "$out" "musicLayout=740/72/22/#8f8f8f"
check "music playback places Figma 15-second seek controls around Play" "$out" "musicControls=prev,back15,play,fwd15,next;icons=backward-15-sec/forward-15-sec"
check "saved audio layouts do not duplicate Figma 15-second seek controls" "$out" "customMusicSkipDeduplicated=true"
check "music player waits for its asynchronous waveform before capture" "$out" "musicWaveformReady=true"
check "audio player artwork reflows to a compact window" "$out" "musicCompact=189/true"
out=$(run "300:onboarding.close(); Theme.setLayout(Theme.defaultLayout.slice()); player.openLocation('$WORK/music/Neon Track 01.m4a', true)|+1200:'audioSeekStart=' + player.time|+100:win.run('fwd15')|+300:'audioSeekForward=' + (player.time >= 15000 && player.time < 20000) + '/' + Math.round(player.time)|+100:win.run('back15')|+300:'audioSeekBackward=' + (player.time < 5000) + '/' + Math.round(player.time)|+100:player.openLocation('$E1',true)|+900:'videoSkipControls=' + controlBar.renderedItems.includes('back15') + '/' + controlBar.renderedItems.includes('fwd15')|+100:quit" "$WORK/music/Neon Track 01.m4a")
check "Figma music forward-skip control seeks 15 seconds in VLC" "$out" "audioSeekForward=true/"
check "Figma music backward-skip control returns near the starting position" "$out" "audioSeekBackward=true/"
check "audio-only skip controls are not added to video playback" "$out" "videoSkipControls=false/false"
if [ -s "$WORK/music-player.png" ]; then echo "PASS  Figma audio-player screenshot written"; pass=$((pass + 1))
else echo "FAIL  Figma audio-player screenshot missing"; fail=$((fail + 1)); fi
out=$(run "500:win.width=1920; win.height=1080; Theme.store.mode='dark'; Theme.store.resumeMode='never'; player.setResumeEnabled(false); player.clearPlaybackHistory(); resumePill.offer(32000)|+200:'resumePromptBeforeChange=' + resumePill.visible|+100:player.openLocation('$WORK/music/Neon Track 01.m4a', true)|+400:win.run('music-library', topBar)|+250:'musicSidebar=' + (win.musicSidebarOpen && libraryPanel.visible && videoArea.visible && libraryPanel.compactMusicSidebar) + ' countLabel=' + libraryPanel.musicItemCountText + ' trackCount=' + mediaLibrary.model.itemCount() + ' sidebarWidth=' + Math.round(libraryPanel.width) + ' resumePromptHidden=' + !resumePill.visible|+100:move:1800,700|+250:grab:$WORK/music-sidebar.png|+100:win.run('music-library', topBar); 'musicSidebarClosed=' + (!win.musicSidebarOpen && videoArea.visible)|+100:Theme.store.resumeMode='ask'; player.setResumeEnabled(true)|+100:quit" "$E1")
check "a resume prompt is visible before changing media" "$out" "resumePromptBeforeChange=true"
check "the My Songs control opens the 377 px Figma music sidebar beside playback without a resume prompt" "$out" "musicSidebar=true countLabel=3 items trackCount=3 sidebarWidth=377 resumePromptHidden=true"
check "the My Songs control closes its sidebar on the second click" "$out" "musicSidebarClosed=true"
if [ -s "$WORK/music-sidebar.png" ]; then echo "PASS  music sidebar screenshot written"; pass=$((pass + 1))
else echo "FAIL  music sidebar screenshot missing"; fail=$((fail + 1)); fi
out=$(run "100:onboarding.close(); Theme.store.mode='light'; Theme.store.autoHideMode='never'; win.width=1920; win.height=1080|+100:player.openLocation('$E1', true)|+700:click-item:folder-chip|+200:'folderSidebar=' + (win.folderSidebarOpen && !win.libraryOpen && libraryPanel.visible && libraryPanel.section === 'folder' && libraryPanel.mediaType === 'video' && player.hasVideo && video.parent === videoArea) + '/' + libraryPanel.fileCount() + ' panelAlpha=' + libraryPanel.color.a.toFixed(2) + ' searchCollapsed=' + (!libraryPanel.folderSearchOpen && libraryPanel.folderSearchButton.visible) + ' compactToolbar=' + libraryPanel.compactFolderToolbar.visible + ' folderActionsHidden=' + (!libraryPanel.folderActionsRow.visible) + ' rowGeometry=' + Math.round(libraryPanel.compactFolderToolbar.y) + '/' + Math.round(libraryPanel.folderListing.y)|+150:'folderSidebarWidth=' + (Math.abs(libraryPanel.width - Math.max(220, Math.min(500, Math.ceil(win.width * 0.19635)))) < 2)|+100:'folderSidebar1920=' + Math.round(libraryPanel.width)|+100:win.width=1333|+300:'folderSidebar1333=' + Math.round(libraryPanel.width)|+100:win.width=1920|+300:'folderSidebarRestored=' + Math.round(libraryPanel.width)|+100:click-item:library-folder-search-open|+100:'folderSearchOpened=' + libraryPanel.folderSearchOpen|+100:libraryPanel.searchText='S01E02'|+200:'folderSearchMatches=' + libraryPanel.matchingFiles()|+100:click-item:library-folder-search-close|+100:'folderSearchClosed=' + (!libraryPanel.folderSearchOpen && libraryPanel.searchText === '')|+2500:'sidebarThumbnail=' + libraryPanel.videoThumbnailState('My.Show.S01E01.1080p.mkv')|+100:move:1090,670|+100:grab:$WORK/folder-sidebar.png|+100:click-item:folder-chip|+300:'folderSidebarClosed=' + (!win.folderSidebarOpen && videoArea.visible && player.hasVideo && !libraryPanel.visible && !navigationRail.visible && navigationRail.width < 1)|+100:win.width=560; win.height=340|+100:click-item:folder-chip|+250:'compactFolderSidebar=' + (win.folderSidebarOpen && libraryPanel.visible && Math.abs(libraryPanel.width - 220) <= 3 && videoArea.width >= 300 && libraryPanel.compactFolderToolbar.visible && libraryPanel.folderSearchButton.visible && !libraryPanel.folderActionsRow.visible && libraryPanel.fileCount() === 2)|+100:grab:$WORK/folder-sidebar-compact.png|+100:click-item:library-folder-search-open|+150:'compactSearchOpened=' + (libraryPanel.folderSearchOpen && !libraryPanel.folderSearchButton.visible && libraryPanel.matchingFiles() === 2)|+100:click-item:library-folder-search-close|+150:'compactSearchClosed=' + (!libraryPanel.folderSearchOpen && libraryPanel.folderSearchButton.visible)|+100:click-item:folder-chip|+100:win.run('library', topBar); 'homeSideLibrary=' + (win.libraryOpen && sideHomeView.visible && videoArea.visible && !win.libraryFullPage)|+300:win.run('library', topBar)|+350:'librarySideFullyClosed=' + (!win.libraryOpen && !win.folderSidebarOpen && !win.musicSidebarOpen && !win.libraryFullPage && !sideHomeView.visible && !libraryPanel.visible && videoArea.visible && !navigationRail.visible && navigationRail.width < 1)|+100:quit" "$E1")
check "the folder chip opens a light folder sidebar with the Figma compact toolbar and aligned rows" "$out" "folderSidebar=true/2 panelAlpha=0.80 searchCollapsed=true compactToolbar=true folderActionsHidden=true rowGeometry=63/125"
check "folder-sidebar search starts collapsed to match Figma" "$out" "searchCollapsed=true"
check "the Figma folder sidebar scales to the player width" "$out" "folderSidebarWidth=true"
check "the video sidebar uses the 377 px Figma width at 1920 px" "$out" "folderSidebar1920=377"
check "the video sidebar tracks window resizing proportionally" "$out" "folderSidebar1333=262"
check "the video sidebar restores its Figma width after window resize" "$out" "folderSidebarRestored=377"
check "the Figma folder sidebar loads VLC-decoded video thumbnails" "$out" "sidebarThumbnail=ready"
check "the folder search icon opens a search field" "$out" "folderSearchOpened=true"
check "the folder search filters matching video names" "$out" "folderSearchMatches=1"
check "closing folder search clears and collapses it" "$out" "folderSearchClosed=true"
check "closing the folder sidebar also removes the navigation rail" "$out" "folderSidebarClosed=true"
check "the folder sidebar preserves a usable video area at compact window size" "$out" "compactFolderSidebar=true"
check "the compact Figma sidebar keeps its toolbar, folder items and search usable" "$out" "compactFolderSidebar=true"
check "compact folder search opens without hiding the sidebar" "$out" "compactSearchOpened=true"
check "compact folder search closes without hiding the sidebar" "$out" "compactSearchClosed=true"
check "the Library button opens the Home side pane while preserving the player" "$out" "homeSideLibrary=true"
check "closing the Home side pane removes the pane and its navigation rail" "$out" "librarySideFullyClosed=true"
if [ -s "$WORK/folder-sidebar.png" ]; then echo "PASS  folder sidebar screenshot written"; pass=$((pass + 1))
else echo "FAIL  folder sidebar screenshot missing"; fail=$((fail + 1)); fi
if [ -s "$WORK/folder-sidebar-compact.png" ]; then echo "PASS  compact folder sidebar screenshot written"; pass=$((pass + 1))
else echo "FAIL  compact folder sidebar screenshot missing"; fail=$((fail + 1)); fi
out=$(run "100:onboarding.close(); Theme.store.mode='dark'; Theme.store.accent='#D37918'; win.width=1920; win.height=1080; Theme.setLayout(['hideui','pip','foldername','filename','favorite','spacer','prev','play','next','spacer','volume','visualizer','subtitle','settings','queue','fullscreen']); player.openLocation('$E1', true)|+900:win.run('folder-sidebar')|+1400:'customizedFolderState=' + (win.folderSidebarOpen && videoArea.visible && player.hasVideo && Math.round(libraryPanel.width) === 377)|+100:grab:$WORK/customize-folder-browser.png|+100:quit" "$E1")
check "the customized Figma folder-browser layout keeps the playlist sidebar beside live video" "$out" "customizedFolderState=true"
if [ -s "$WORK/customize-folder-browser.png" ]; then echo "PASS  customized folder-browser screenshot written"; pass=$((pass + 1))
else echo "FAIL  customized folder-browser screenshot missing"; fail=$((fail + 1)); fi
out=$(run "100:Theme.setLayout(Theme.defaultLayout.concat(['visualizer']))|+50:player.openLocation('$WORK/music/Neon Track 01.m4a', true)|+1000:'audioOnly=' + player.hasMedia + '/' + !player.hasVideo + ' visualizerButton=' + controlBar.findControl('visualizer').visible|+100:win.run('visualizer', controlBar.findControl('visualizer')); 'visualizerPopup=' + audioVisualizerPopup.visible + '/' + audioVisualizerPopup.height|+200:grab:$WORK/audio-visualizer.png|+100:audioVisualizerPopup.selectMode('spectrometer'); 'spectrometerMode=' + player.config('audio-visual') + '/' + player.config('effect-list')|+100:audioVisualizerPopup.selectMode('scope'); 'scopeMode=' + player.config('audio-visual') + '/' + player.config('effect-list')|+100:audioVisualizerPopup.selectMode('spectrum'); 'spectrumMode=' + player.config('audio-visual') + '/' + player.config('effect-list')|+100:audioVisualizerPopup.selectMode('waveform'); 'waveformMode=' + player.config('audio-visual') + '/' + player.config('effect-list')|+100:audioVisualizerPopup.selectMode('disabled'); 'disabledMode=' + player.config('audio-visual')|+100:win.run('visualizer', controlBar.findControl('visualizer')); 'visualizerReopen=' + audioVisualizerPopup.visible|+100:click-item:video-click-area|+100:'visualizerOutsideClose=' + !audioVisualizerPopup.visible|+100:quit" "$E1")
check "audio-only playback reveals the Figma audio visualizer control" "$out" "audioOnly=true/true visualizerButton=true"
check "the visualizer menu opens at the Figma menu size" "$out" "visualizerPopup=true/260"
check "Spectrometer uses VLC's visual effect" "$out" "spectrometerMode=visual/spectrometer"
check "Scope uses VLC's scope effect" "$out" "scopeMode=visual/scope"
check "Spectrum uses VLC's spectrum effect" "$out" "spectrumMode=visual/spectrum"
check "Waveform uses VLC's VU meter effect" "$out" "waveformMode=visual/vuMeter"
check "Disabled turns VLC audio visualization off" "$out" "disabledMode=none"
check "clicking the video surface dismisses the audio visualizer menu" "$out" "visualizerOutsideClose=true"
if [ -s "$WORK/audio-visualizer.png" ]; then echo "PASS  Figma audio visualizer menu screenshot written"; pass=$((pass + 1))
else echo "FAIL  Figma audio visualizer menu screenshot missing"; fail=$((fail + 1)); fi
out=$(run --timeout 70 "1200:'focusPlaylist=' + navigationRail.focusPage('playlist')|+100:key:Space|+350:'playlistScreen=' + (navigationPage === 'playlist' && playlistsPanel.visible && libraryOpen && !libraryFullPage && rightPanel === '') + ' widthMatches=' + (Math.abs(playlistsPanel.width - libraryPaneLayoutWidth) < 2) + ' titleBarAnchor=' + (topBar.parent === keyCatcher && Math.round(topBar.x) === 0)|+100:'savePlaylist=' + player.saveQueueAs(platform.fileUrl(platform.playlistLibraryDirectory() + '/Cool Songs.m3u8'))|+100:'savePlaylistTwo=' + player.saveQueueAs(platform.fileUrl(platform.playlistLibraryDirectory() + '/Anime to Watch.m3u8'))|+600:'savedPlaylistCount=' + playlistsPanel.fileCount()|+2500:grab:$WORK/playlists.png|+100:click-item:playlist-search|+100:'searchOpened=' + playlistsPanel.searchOpen|+100:playlistsPanel.searchText='cool'; 'playlistSearch=' + playlistsPanel.fileCount()|+100:click-item:playlist-search-close|+100:click-item:playlist-sort|+100:click-item:playlist-view|+100:click-item:playlist-expand|+100:'playlistControls=' + (navigationPage === 'folder' && libraryFullPage && libraryPanel.section === 'folder' && libraryPanel.visible && !videoArea.visible && playlistsPanel.compactRows && !playlistsPanel.reverseSort && !playlistsPanel.searchOpen && playlistsPanel.fileCount() === 2)|+100:win.navigateFromRail('playlist')|+150:win.width=1920|+150:'responsivePlaylistWidth=' + ((navigationRail.width + playlistsPanel.width) / win.width > 0.21 && (navigationRail.width + playlistsPanel.width) / win.width < 0.235)|+100:win.width=1120|+150:'defaultPlaylistWidth=' + ((navigationRail.width + playlistsPanel.width) / win.width > 0.21 && (navigationRail.width + playlistsPanel.width) / win.width < 0.235)|+100:click-item:create-playlist|+250:'newPlaylistDialogVisible=' + newPlaylistDialog.visible|+100:'newPlaylistDialogFrame=' + Math.round(newPlaylistDialog.width) + 'x' + Math.round(newPlaylistDialog.height) + ' drop=' + Math.round(newPlaylistDialog.mediaDropZone.height)|+100:grab:$WORK/new-playlist.png|+100:click-item:playlist-media-drop-area|+100:'mediaDropClickOpensPicker=' + newPlaylistDialog.mediaFilesDialog.visible|+100:newPlaylistDialog.mediaFilesDialog.close()|+100:drop-urls:playlist-media-drop-area:file://$E1;file://$E2|+100:'playlistDrop=' + newPlaylistDialog.mediaFiles.length|+100:newPlaylistDialog.mediaFiles=[]; newPlaylistDialog.nameInput.text='Dialog playlist'; newPlaylistDialog.mediaFiles=[platform.fileUrl('$E1')]; newPlaylistDialog.addFiles([platform.fileUrl('$WORK/audio-only.m4a')]); newPlaylistDialog.coverUrl=platform.fileUrl('$WORK/cover.png')|+50:'newPlaylistMixedIcons=' + (newPlaylistDialog.iconForMedia(platform.fileUrl('$E1')) === 'video-file' && newPlaylistDialog.iconForMedia(platform.fileUrl('$WORK/audio-only.m4a')) === 'music') + '/' + (libraryPanel.audioFilters.includes('*.mpc') && libraryPanel.audioFilters.includes('*.wv') && libraryPanel.mediaFilters.includes('*.mpc') && libraryPanel.mediaFilters.includes('*.wv')) + '/' + (newPlaylistDialog.iconForMedia(Qt.resolvedUrl('https://example.test/audio.m4a?token=abc')) === 'music' && newPlaylistDialog.displayMediaName(Qt.resolvedUrl('https://example.test/audio.m4a?token=abc')) === 'audio.m4a')|+250:'newPlaylistSelection=' + (newPlaylistDialog.mediaFiles.length === 2 && newPlaylistDialog.coverPreview.status === Image.Ready) + '/' + newPlaylistDialog.coverPreview.status|+100:grab:$WORK/new-playlist-selected.png|+100:'newPlaylistSaved=' + newPlaylistDialog.save() + ' cover=' + (platform.playlistCoverUrl(platform.fileUrl(platform.playlistLibraryDirectory() + '/Dialog playlist.m3u8')).toString().length > 0)|+500:'createdPlaylistCount=' + playlistsPanel.fileCount()|+100:grab:$WORK/playlists-with-cover.png|+100:click-item:create-playlist|+250:newPlaylistDialog.nameInput.text='Dialog playlist'; newPlaylistDialog.mediaFiles=[platform.fileUrl('$E1'), platform.fileUrl('$WORK/audio-only.m4a')]; newPlaylistDialog.coverUrl=platform.fileUrl('$WORK/cover-replacement.jpg'); 'replacementCoverLoaded=' + (newPlaylistDialog.coverPreview.status === Image.Ready)|+200:'replacementCoverSaved=' + newPlaylistDialog.save() + '/' + platform.playlistCoverUrl(platform.fileUrl(platform.playlistLibraryDirectory() + '/Dialog playlist.m3u8')).toString().endsWith('.cover.jpg')|+300:player.clearQueue(); player.openUrls([platform.fileUrl(platform.playlistLibraryDirectory() + '/Dialog playlist.m3u8')], true)|+1200:'playlistContentsLoad=' + player.queue.count + '/' + player.playlistName|+100:quit" "$E1" "$E2")
check "keyboard navigation opens the saved-playlists side pane at its Figma width" "$out" "playlistScreen=true widthMatches=true titleBarAnchor=true"
check "the queue saves into the persistent playlist library" "$out" "savePlaylist=true"
check "a second named playlist saves from the same queue" "$out" "savePlaylistTwo=true"
check "the playlist library discovers both saved M3U8 files" "$out" "savedPlaylistCount=2"
check "the search toolbar opens and filters saved playlist names" "$out" "searchOpened=true"
check "playlist search matches the Figma playlist name" "$out" "playlistSearch=1"
check "playlist sorting, density and the dedicated full-page action work" "$out" "playlistControls=true"
check "the Playlists pane scales with the Figma player width" "$out" "responsivePlaylistWidth=true"
check "the Playlists pane keeps its layout at the default window width" "$out" "defaultPlaylistWidth=true"
check "create-playlist opens the Figma details and file-selection dialog" "$out" "newPlaylistDialogVisible=true"
check "new playlist dialog matches the 713x589 Figma frame and its 188 px file area" "$out" "newPlaylistDialogFrame=713x589 drop=188"
check "clicking the Figma file-drop area opens the native file picker" "$out" "mediaDropClickOpensPicker=true"
check "dropping media URLs onto the playlist drop area adds both files" "$out" "playlistDrop=2"
check "local and remote audio URLs show music icons, clean names and extended audio filters" "$out" "newPlaylistMixedIcons=true/true/true"
check "two selected files and the playlist cover render in the dialog" "$out" "newPlaylistSelection=true/1"
check "the named playlist saves selected files and a validated cover image" "$out" "newPlaylistSaved=true cover=true"
check "the replacement cover loads and is saved over the playlist cover" "$out" "replacementCoverLoaded=true"
check "the replacement cover URL uses the new image format" "$out" "replacementCoverSaved=true/true"
cover_path=$(find "$WORK" -type f -path "*/Playlists/Dialog playlist.cover.jpg" -print -quit)
if [ -n "$cover_path" ] && cmp -s "$WORK/cover-replacement.jpg" "$cover_path" && [ ! -e "${cover_path%.jpg}.png" ]; then echo "PASS  replacement cover bytes persist and the previous cover is removed"; pass=$((pass + 1)); else echo "FAIL  replacement cover bytes persist and the previous cover is removed"; fail=$((fail + 1)); fi
if [ -s "$WORK/new-playlist-selected.png" ]; then echo "PASS  selected playlist files and cover screenshot written"; pass=$((pass + 1))
else echo "FAIL  selected playlist files and cover screenshot missing"; fail=$((fail + 1)); fi
check "the created playlist appears in the persistent playlist panel" "$out" "createdPlaylistCount=3"
check "VLC opens the new M3U8, loads both files and exposes its playlist name" "$out" "playlistContentsLoad=2/Dialog playlist"
if [ -s "$WORK/playlists.png" ]; then echo "PASS  saved playlists screenshot written"; pass=$((pass + 1))
else echo "FAIL  saved playlists screenshot missing"; fail=$((fail + 1)); fi
if [ -s "$WORK/new-playlist.png" ]; then echo "PASS  new playlist dialog screenshot written"; pass=$((pass + 1))
else echo "FAIL  new playlist dialog screenshot missing"; fail=$((fail + 1)); fi
if [ -s "$WORK/playlists-with-cover.png" ]; then echo "PASS  playlist cover list screenshot written"; pass=$((pass + 1))
else echo "FAIL  playlist cover list screenshot missing"; fail=$((fail + 1)); fi
out=$(run "1000:'persistedPlaylistCount=' + playlistsPanel.fileCount()|+100:quit" "$E1")
check "all three saved playlists persist across VLC launches" "$out" "persistedPlaylistCount=3"
networkOut=$(run "500:win.width=1080; win.height=680; networkDialog.open()|+250:'networkDialogFigmaFrame=' + (networkDialog.width === 1048 && networkDialog.height === 632 && (() => { const header=networkDialog.contentItem.children[0]; const close=header.children[1]; return header.width > 1000 && close.x >= header.width - 32 })())|+100:'emptyNetworkActionsHidden=' + (!networkDialog.contentItem.children[2].children[2].visible && !networkDialog.contentItem.children[2].children[3].visible)|+100:networkDialog.sourceText='https://example.com/live.m3u'; 'validNetworkActionsVisible=' + (networkDialog.contentItem.children[2].children[2].visible && networkDialog.contentItem.children[2].children[3].visible)|+100:quit" "$E1")
check "network dialog matches the Figma frame and right-aligned close button" "$networkOut" "networkDialogFigmaFrame=true"
check "empty network dialog hides queue and playback actions" "$networkOut" "emptyNetworkActionsHidden=true"
check "network queue and playback actions appear for a valid URL" "$networkOut" "validNetworkActionsVisible=true"
out=$(run "1000:networkDialog.open(); 'opened=' + networkDialog.visible|+250:networkDialog.sourceText='not a URL'; 'invalidRejected=' + !networkDialog.urlsValid|+100:networkDialog.sourceText='https://example.com/live-one.m3u' + String.fromCharCode(10) + '# optional comment' + String.fromCharCode(10) + 'https://example.net/live-two.m3u'; networkDialog.playlistTitle='Network Streams'; 'validMultiUrl=' + networkDialog.urlsValid + ' urls=' + networkDialog.networkUrls.length|+200:grab:$WORK/network-stream.png|+200:'networkPlaylistSaved=' + networkDialog.saveNamedPlaylist()|+500:'networkPlaylistCount=' + playlistsPanel.fileCount()|+100:quit" "$E1")
check "network stream dialog rejects malformed URLs" "$out" "invalidRejected=true"
check "network stream dialog accepts multiple URLs and ignores comments" "$out" "validMultiUrl=true urls=2"
check "network stream dialog saves a named M3U8 playlist" "$out" "networkPlaylistSaved=true"
check "saved network playlist appears in the playlist library" "$out" "networkPlaylistCount=4"
if grep -qF "https://example.com/live-one.m3u" "$NEO_SANDBOX/data/vlc-neo/neo/Playlists/Network Streams.m3u8" && grep -qF "https://example.net/live-two.m3u" "$NEO_SANDBOX/data/vlc-neo/neo/Playlists/Network Streams.m3u8"; then
    echo "PASS  network playlist stores each URL"; pass=$((pass + 1))
else
    echo "FAIL  network playlist stores each URL"; fail=$((fail + 1))
fi
if [ -s "$WORK/network-stream.png" ]; then echo "PASS  network stream screenshot written"; pass=$((pass + 1))
else echo "FAIL  network stream screenshot missing"; fail=$((fail + 1)); fi
echo "== network URL playback through VLC"
python3 - "$WORK" >"$WORK/http-input-server.log" 2>&1 <<'PY' &
import functools
import http.server
import pathlib
import sys

directory = pathlib.Path(sys.argv[1])
class HttpInputHandler(http.server.SimpleHTTPRequestHandler):
    def guess_type(self, path):
        if path.lower().endswith(".m3u"):
            return "audio/x-mpegurl"
        return super().guess_type(path)

server = http.server.ThreadingHTTPServer(
    ("127.0.0.1", 0),
    functools.partial(HttpInputHandler, directory=str(directory)),
)
(directory / "http-input-port").write_text(str(server.server_address[1]))
server.serve_forever()
PY
httpInputServerPid=$!
for _ in {1..40}; do
    [ -s "$WORK/http-input-port" ] && break
    sleep 0.1
done
if [ -s "$WORK/http-input-port" ]; then
    httpInputPort=$(cat "$WORK/http-input-port")
    httpInputUrl="http://127.0.0.1:$httpInputPort/base.mkv"
    out=$(run "700:networkDialog.open()|+200:networkDialog.sourceText='$httpInputUrl'; 'networkDialogUrlValid=' + networkDialog.urlsValid|+200:networkDialog.go(true)|+2000:'httpInputPlayback=' + (player.hasMedia && player.hasVideo && player.length > 0 && player.state === 2 && player.mediaUrl.toString() === '$httpInputUrl')|+200:quit")
    check "the Open Network Stream dialog accepts the reachable HTTP URL" "$out" "networkDialogUrlValid=true"
    check "the Open Network Stream Play action starts the HTTP video in VLC" "$out" "httpInputPlayback=true"
    httpInputPlaylistUrl="http://127.0.0.1:$httpInputPort/http-input-live.m3u"
    cp "$WORK/base.mkv" "$WORK/http-input-playlist-media.mkv"
    httpInputPlaylistMediaUrl="http://127.0.0.1:$httpInputPort/http-input-playlist-media.mkv"
    printf '#EXTM3U\n#EXTINF:-1,HTTP input fixture\n%s\n' "$httpInputPlaylistMediaUrl" > "$WORK/http-input-live.m3u"
    cp "$WORK/base.mkv" "$WORK/http-input-queued-media.mkv"
    httpInputQueuedMediaUrl="http://127.0.0.1:$httpInputPort/http-input-queued-media.mkv"
    out=$(run "700:player.clearQueue(); networkDialog.open()|+250:networkDialog.sourceText='$httpInputPlaylistUrl'; 'networkM3uUrlValid=' + networkDialog.urlsValid|+200:networkDialog.go(true)|+10000:'networkM3uPlayback=' + (player.state === 2 && player.hasVideo && player.mediaUrl.toString() === '$httpInputPlaylistMediaUrl')|+100:'networkM3uState=' + player.state + '/' + player.hasVideo + '/' + player.mediaUrl.toString() + '/' + player.queue.count|+100:networkDialog.open()|+250:networkDialog.sourceText='$httpInputUrl' + String.fromCharCode(10) + '$httpInputQueuedMediaUrl'; 'networkQueueUrlsValid=' + (networkDialog.urlsValid && networkDialog.networkUrls.length === 2)|+200:networkDialog.go(false)|+500:'networkQueueAppend=' + (player.queue.count === 3 && player.mediaUrl.toString() === '$httpInputPlaylistMediaUrl')|+100:quit")
    kill "$httpInputServerPid" 2>/dev/null || true
    wait "$httpInputServerPid" 2>/dev/null || true
    check "the Open Network Stream dialog accepts a reachable HTTP M3U playlist" "$out" "networkM3uUrlValid=true"
    check "VLC plays the media from the remote HTTP M3U playlist" "$out" "networkM3uPlayback=true"
    if grep -qF 'GET /http-input-live.m3u ' "$WORK/http-input-server.log"; then
        echo "PASS  VLC retrieves the HTTP M3U playlist"; pass=$((pass + 1))
    else
        echo "FAIL  VLC retrieves the HTTP M3U playlist"; fail=$((fail + 1))
    fi
    if grep -qF 'GET /http-input-playlist-media.mkv ' "$WORK/http-input-server.log"; then
        echo "PASS  VLC resolves the HTTP M3U entry to its media URL"; pass=$((pass + 1))
    else
        echo "FAIL  VLC resolves the HTTP M3U entry to its media URL"; fail=$((fail + 1))
    fi
    sed -n '/GET /p' "$WORK/http-input-server.log"
    check "the network dialog validates both queued HTTP URLs" "$out" "networkQueueUrlsValid=true"
    check "adding live HTTP URLs to the queue preserves M3U playback" "$out" "networkQueueAppend=true"
else
    kill "$httpInputServerPid" 2>/dev/null || true
    wait "$httpInputServerPid" 2>/dev/null || true
    echo "FAIL  local HTTP input server did not start"; fail=$((fail + 1))
fi
echo "== custom HTTP proxy preference"
python3 - "$WORK" >"$WORK/http-proxy-server.log" 2>&1 <<'PY' &
import http.server
import pathlib
import sys

directory = pathlib.Path(sys.argv[1])
media = (directory / "converted.mp4").read_bytes()
requests = directory / "http-proxy-requests.txt"

class Proxy(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        with requests.open("a") as output:
            output.write(str(self.server.server_port) + " " + self.path + "\n")
        self.send_response(200)
        self.send_header("Content-Type", "video/mp4")
        self.send_header("Content-Length", str(len(media)))
        self.end_headers()
        self.wfile.write(media)

    def log_message(self, *args):
        pass

servers = [http.server.ThreadingHTTPServer(("127.0.0.1", 0), Proxy) for _ in range(2)]
(directory / "http-proxy-port-a").write_text(str(servers[0].server_address[1]))
(directory / "http-proxy-port-b").write_text(str(servers[1].server_address[1]))
import threading
for server in servers:
    threading.Thread(target=server.serve_forever, daemon=True).start()
threading.Event().wait()
PY
httpProxyServerPid=$!
for _ in {1..40}; do
    [ -s "$WORK/http-proxy-port-a" ] && [ -s "$WORK/http-proxy-port-b" ] && break
    sleep 0.1
done
if [ -s "$WORK/http-proxy-port-a" ] && [ -s "$WORK/http-proxy-port-b" ]; then
    httpProxySystemUrl="http://127.0.0.1:$(cat "$WORK/http-proxy-port-a")"
    httpProxyCustomUrl="http://127.0.0.1:$(cat "$WORK/http-proxy-port-b")"
    httpProxyMediaUrl="http://neo-proxy.invalid/custom.mp4"
    httpProxyInheritedMediaUrl="http://neo-proxy.invalid/inherited.mp4"
    out=$(http_proxy="$httpProxySystemUrl" https_proxy="$httpProxySystemUrl" run "100:player.setConfig('http-proxy','$httpProxyCustomUrl'); player.setConfig('http-proxy-pwd',''); player.openLocation('$httpProxyMediaUrl', true)|+2000:'customProxyPlayback=' + (player.state === 2 && player.hasVideo && player.length > 0)|+100:player.setConfig('http-proxy',''); player.openLocation('$httpProxyInheritedMediaUrl', true)|+2000:'inheritedProxyPlayback=' + (player.state === 2 && player.hasVideo && player.length > 0)|+100:quit")
    kill "$httpProxyServerPid" 2>/dev/null || true
    wait "$httpProxyServerPid" 2>/dev/null || true
    check "the saved HTTP proxy carries VLC playback through the configured server" "$out" "customProxyPlayback=true"
    check "clearing a custom HTTP proxy restores playback through the inherited system proxy" "$out" "inheritedProxyPlayback=true"
    if grep -qF "$(cat "$WORK/http-proxy-port-b") $httpProxyMediaUrl" "$WORK/http-proxy-requests.txt"; then
        echo "PASS  VLC sent the configured media URL through the custom HTTP proxy"; pass=$((pass + 1))
    else
        echo "FAIL  VLC sent the configured media URL through the custom HTTP proxy"; fail=$((fail + 1))
    fi
    if grep -qF "$(cat "$WORK/http-proxy-port-a") $httpProxyInheritedMediaUrl" "$WORK/http-proxy-requests.txt"; then
        echo "PASS  clearing the preference restored the inherited proxy URL"; pass=$((pass + 1))
    else
        echo "FAIL  clearing the preference restored the inherited proxy URL"; fail=$((fail + 1))
    fi
else
    kill "$httpProxyServerPid" 2>/dev/null || true
    wait "$httpProxyServerPid" 2>/dev/null || true
    echo "FAIL  local HTTP proxy server did not start"; fail=$((fail + 1))
fi
echo "== TLS certificate trust preference"
tlsDir="$WORK/tls"
mkdir -p "$tlsDir/trust"
if command -v openssl >/dev/null 2>&1 \
    && openssl req -x509 -newkey rsa:2048 -nodes -keyout "$tlsDir/ca.key" -out "$tlsDir/ca.pem" -days 1 -subj "/CN=VLC Neo Smoke CA" -addext "basicConstraints=critical,CA:TRUE" -addext "keyUsage=critical,keyCertSign,cRLSign" >/dev/null 2>&1 \
    && openssl req -new -newkey rsa:2048 -nodes -keyout "$tlsDir/server.key" -out "$tlsDir/server.csr" -subj "/CN=127.0.0.1" >/dev/null 2>&1; then
    cat >"$tlsDir/server.ext" <<'EOF'
subjectAltName=IP:127.0.0.1
extendedKeyUsage=serverAuth
EOF
    if openssl x509 -req -in "$tlsDir/server.csr" -CA "$tlsDir/ca.pem" -CAkey "$tlsDir/ca.key" -CAcreateserial -out "$tlsDir/server.pem" -days 1 -sha256 -extfile "$tlsDir/server.ext" >/dev/null 2>&1; then
        tlsCertHash=$(openssl x509 -in "$tlsDir/ca.pem" -hash -noout)
        ln -sf "$tlsDir/ca.pem" "$tlsDir/trust/$tlsCertHash.0"
        python3 - "$WORK" "$tlsDir" >"$WORK/tls-server.log" 2>&1 <<'PY' &
import http.server
import pathlib
import ssl
import sys

directory = pathlib.Path(sys.argv[1])
tls = pathlib.Path(sys.argv[2])
media = (directory / "converted.mp4").read_bytes()
requests = directory / "tls-requests.txt"

class TlsServer(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        with requests.open("a") as output:
            output.write(self.path + "\n")
        start, end = 0, len(media) - 1
        requested_range = self.headers.get("Range")
        if requested_range and requested_range.startswith("bytes="):
            first, last = requested_range[6:].split("-", 1)
            start = int(first or 0)
            end = int(last) if last else end
            self.send_response(206)
            self.send_header("Content-Range", f"bytes {start}-{end}/{len(media)}")
        else:
            self.send_response(200)
        body = media[start:end + 1]
        self.send_header("Content-Type", "video/mp4")
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass

server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), TlsServer)
context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.minimum_version = context.maximum_version = ssl.TLSVersion.TLSv1_2
context.set_ciphers("ECDHE-RSA-AES128-GCM-SHA256")
context.load_cert_chain(tls / "server.pem", tls / "server.key")
server.socket = context.wrap_socket(server.socket, server_side=True)
(directory / "tls-port").write_text(str(server.server_address[1]))
server.serve_forever()
PY
        tlsServerPid=$!
        for _ in {1..40}; do
            [ -s "$WORK/tls-port" ] && break
            sleep 0.1
        done
        if [ -s "$WORK/tls-port" ]; then
            tlsUrl="https://127.0.0.1:$(cat "$WORK/tls-port")/media.mp4"
            tlsMissingTrust="$tlsDir/missing-trust"
            out=$(run "100:player.setConfig('gnutls-system-trust',false); player.setConfig('gnutls-dir-trust','$tlsMissingTrust'); player.setConfig('gnutls-priorities','SECURE128'); player.openLocation('$tlsUrl',true)|+900:'untrustedTlsRejected=' + (!player.hasVideo && player.length === 0)|+100:player.stop(); player.setConfig('gnutls-dir-trust','$tlsDir/trust'); player.setConfig('gnutls-priorities','SECURE256'); player.openLocation('$tlsUrl',true)|+900:'tlsCipherPolicyRejected=' + (!player.hasVideo && player.length === 0)|+100:player.stop(); player.setConfig('gnutls-priorities','SECURE128'); player.openLocation('$tlsUrl',true)|+1800:'configuredTlsTrustPlayback=' + (player.state === 2 && player.hasVideo && player.length > 0)|+100:quit")
            kill "$tlsServerPid" 2>/dev/null || true
            wait "$tlsServerPid" 2>/dev/null || true
            check "TLS rejects a server certificate outside the configured trust store" "$out" "untrustedTlsRejected=true"
            check "the VLC cipher priority rejects TLS suites below its configured strength" "$out" "tlsCipherPolicyRejected=true"
            check "the VLC Neo certificate trust directory enables HTTPS playback" "$out" "configuredTlsTrustPlayback=true"
            if grep -qF "/media.mp4" "$WORK/tls-requests.txt"; then
                echo "PASS  the trusted TLS fixture received the media request"; pass=$((pass + 1))
            else
                echo "FAIL  the trusted TLS fixture received the media request"; fail=$((fail + 1))
            fi
        else
            kill "$tlsServerPid" 2>/dev/null || true
            wait "$tlsServerPid" 2>/dev/null || true
            echo "FAIL  local TLS input server did not start"; fail=$((fail + 1))
        fi
    else
        echo "FAIL  local TLS server certificate could not be signed"; fail=$((fail + 1))
    fi
else
    echo "FAIL  OpenSSL could not create a local TLS certificate authority"; fail=$((fail + 1))
fi
out=$(run "1800:'persistedLibrary=' + mediaLibrary.roots.length + '/' + mediaLibrary.indexedCount + '/' + mediaLibrary.model.itemCount()|+100:'removeCall=' + mediaLibrary.removeFolder(platform.fileUrl('$WORK/music'))|+250:'removeIndexedRoot=' + (mediaLibrary.roots.length === 0) + ' empty=' + (mediaLibrary.roots.length === 0 && mediaLibrary.indexedCount === 0 && !mediaLibrary.model.loading && mediaLibrary.model.itemCount() === 0)|+100:'clearLibrary=' + mediaLibrary.clearLibrary() + ' empty=' + (mediaLibrary.roots.length === 0 && mediaLibrary.indexedCount === 0 && mediaLibrary.model.itemCount() === 0)|+100:quit")
check "indexed roots and tagged entries persist after relaunch" "$out" "persistedLibrary=1/4/3"
check "removing one indexed folder deletes its rows and unreferenced artwork" "$out" "removeIndexedRoot=true empty=true"
check "clear library removes the persisted index and its artwork" "$out" "clearLibrary=true empty=true"
if [ -n "$(find "$NEO_SANDBOX/data/vlc-neo/neo/LibraryArt" -type f -print -quit 2>/dev/null)" ]; then
    echo "FAIL  library clear left artwork files"; fail=$((fail + 1))
else echo "PASS  library clear removed all cached artwork"; pass=$((pass + 1)); fi

echo
echo "passed $pass, failed $fail"
[ "$fail" -eq 0 ]
