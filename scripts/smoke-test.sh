#!/usr/bin/env bash
# End-to-end checks of the Neo interface against the real VLC 3 core (headless).
# Generates its own media, runs VLC with -I neo offscreen, asserts on the results.
set -uo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${NEO_SMOKE_DIR:-${TMPDIR:-/tmp}/neo-smoke}"
rm -rf "$WORK" && mkdir -p "$WORK/show" "$WORK/subs"
export NEO_SANDBOX="$WORK/sandbox"
pass=0; fail=0

check() { # name, haystack, needle
    if grep -qF -- "$3" <<<"$2"; then echo "PASS  $1"; pass=$((pass + 1))
    else echo "FAIL  $1  (expected: $3; got: $2)"; fail=$((fail + 1)); fi
}
run() { NEO_TIMEOUT=40 "$HERE/scripts/run-offscreen.sh" "$@" 2>&1 | grep "neo test" ; }

echo "== preparing media"
ffmpeg -loglevel error -y -f lavfi -i "testsrc2=size=640x360:rate=25" -f lavfi -i "sine=frequency=440" \
    -t 40 -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest "$WORK/base.mkv"
for i in 01 02; do
    cp "$WORK/base.mkv" "$WORK/show/My.Show.S01E$i.1080p.mkv"
    printf '1\n00:00:00,500 --> 00:00:30,000\nEpisode %s\n' "$i" > "$WORK/subs/myshow_1x${i}_ar.srt"
done
mkdir -p "$NEO_SANDBOX/config/vlc-neo"
printf '[appearance]\nonboarded=true\n' > "$NEO_SANDBOX/config/vlc-neo/neo.conf"
E1="$WORK/show/My.Show.S01E01.1080p.mkv"; E2="$WORK/show/My.Show.S01E02.1080p.mkv"

echo "== playback, video output, queue"
out=$(run "2500:'state=' + player.state + ' video=' + player.hasVideo + ' queue=' + player.queue.count + ' len=' + player.length|2700:quit" "$E1" "$E2")
check "plays (state 2)" "$out" "state=2"
check "frames reach the QML video item" "$out" "video=true"
check "queue has both episodes" "$out" "queue=2"
check "duration known" "$out" "len=40"
out=$(run "1000:'noSubtitleCues=' + (player.subtitleCues.length === 0)|+100:quit" "$E1")
check "media without subtitles produces an empty timeline" "$out" "noSubtitleCues=true"
out=$(run "1500:player.next()|2600:'next=' + player.mediaUrl.toString().endsWith('My.Show.S01E02.1080p.mkv')|2800:quit" "$E1" "$E2")
check "next advances to the following queue item" "$out" "next=true"

echo "== transport controls"
out=$(run "1500:player.togglePause()|2300:'paused=' + player.state|2400:player.togglePause()|3300:'resumed=' + player.state|3500:quit" "$E1")
check "pause control pauses playback" "$out" "paused=3"
check "play control resumes playback" "$out" "resumed=2"

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
if [ -s "$WORK/subtitle-timeline.png" ]; then echo "PASS  subtitle timeline screenshot written"; pass=$((pass + 1))
else echo "FAIL  subtitle timeline screenshot missing"; fail=$((fail + 1)); fi

echo "== resume"
run "1500:player.jumpTo(20000)|2500:win.close()" "$E1" >/dev/null
out=$(run "1800:'resume=' + (resumePill.visible ? Math.round(resumePill.point / 1000) : 0)|2000:quit" "$E1")
check "resume offered at ~20 s" "$out" "resume=2"

echo "== hotkeys, bookmarks, rate"
out=$(run "1500:win.handleKey({key: Qt.Key_Right, modifiers: 0, text: ''})|2200:'t=' + Math.round(player.time / 1000)|2300:player.addBookmark()|2500:'marks=' + player.bookmarks().length|2600:player.setRate(1.5)|3000:'rate=' + player.rate|3100:quit" "$E1")
check "→ seeks forward 10 s" "$out" "t=1"
check "bookmark stored" "$out" "marks=1"
check "speed applied" "$out" "rate=1.5"

echo "== VLC core config round trip"
out=$(run "1000:player.setConfig('network-caching', 1500)|1200:'cache=' + player.config('network-caching')|1300:quit")
check "vlcrc option written and read back" "$out" "cache=1500"
out=$(run "1000:'cache=' + player.config('network-caching')|1200:quit")
check "vlcrc preference persists across VLC launches" "$out" "cache=1500"

echo "== appearance, window sizes and persistent settings"
out=$(run "1000:Theme.store.mode='dark'; Theme.store.accent='#D9822B'|+350:grab:$WORK/dark.png|+200:Theme.store.mode='light'; Theme.store.accent='#2F5FC4'|+350:grab:$WORK/light.png|+200:win.width=560; win.height=340|+350:grab:$WORK/compact.png|+200:quit" "$E1")
check "dark theme captured at standard size" "$out" "window 1120x680"
check "light theme captured at standard size" "$out" "window 1120x680"
check "compact window size captured" "$out" "window 560x340"
for image in dark light compact; do
    if [ -s "$WORK/$image.png" ]; then echo "PASS  $image screenshot written"; pass=$((pass + 1))
    else echo "FAIL  $image screenshot missing"; fail=$((fail + 1)); fi
done
out=$(run "1000:'mode=' + Theme.store.mode + ' accent=' + Theme.store.accent|1200:quit" "$E1")
check "theme and accent persist across VLC launches" "$out" "mode=light accent=#2F5FC4"

echo "== preferences global screen"
out=$(run "1000:Theme.store.mode='dark'; Theme.store.accent='#D37918'; settingsDialog.open()|+150:'settings=' + settingsDialog.visible + ' page=' + settingsDialog.page|+150:settingsDialog.categorySearch='audio'|+100:'search=' + settingsDialog.pagesInGroup(settingsDialog.categoryGroups[1].ids).length|+100:settingsDialog.categorySearch=''|+100:grab:$WORK/settings-global.png|+100:settingsDialog.close(); Theme.store.mode='light'; Theme.store.accent='#2F5FC4'|+150:settingsDialog.open()|+100:'searchReset=' + (settingsDialog.categorySearch.length === 0)|+100:settingsDialog.close()|+100:'logTypes=' + typeof player.config('file-logging') + '/' + typeof player.config('logfile') + '/' + typeof player.config('log-verbose') + '/' + typeof player.config('verbose')|+100:quit" "$E1")
check "global settings opens on the General page" "$out" "settings=true page=general"
check "settings search filters the category list" "$out" "search=1"
check "settings search resets when reopened" "$out" "searchReset=true"
check "diagnostic fields map to VLC config options" "$out" "logTypes=boolean/string/number/number"
if [ -s "$WORK/settings-global.png" ]; then echo "PASS  global settings screenshot written"; pass=$((pass + 1))
else echo "FAIL  global settings screenshot missing"; fail=$((fail + 1)); fi
out=$(run "1000:settingsDialog.open(); settingsDialog.page='audio'|+150:'simpleHidesAdvanced=' + !settingsDialog.optionVisible('volume-step')|+150:click-item:preferences-detail-level|+150:'buttonEnablesAdvanced=' + (Theme.store.advancedOptions && settingsDialog.optionVisible('volume-step'))|+150:click-item:preferences-detail-level|+150:'buttonReturnsToSimple=' + (!Theme.store.advancedOptions && !settingsDialog.optionVisible('volume-step'))|+150:Theme.store.advancedOptions=true|+150:'advancedShowsOption=' + settingsDialog.optionVisible('volume-step')|+150:'advancedValueRead=' + (player.config('volume-step') !== undefined)|+150:'fractionalInput=' + settingsDialog.optionNumberValue('volume-step', '0.75')|+150:'integerInput=' + settingsDialog.optionNumberValue('network-caching', '1500')|+150:'floatRoundTrip=' + (() => { const previous = player.config('volume-step'); player.setConfig('volume-step', 1.75); const ok = Math.abs(player.config('volume-step') - 1.75) < 0.001; player.setConfig('volume-step', previous); return ok })()|+150:Theme.store.advancedOptions=false|+150:'simpleKeepsValue=' + (player.config('volume-step') !== undefined && !settingsDialog.optionVisible('volume-step'))|+150:Theme.store.advancedOptions=true|+100:settingsDialog.close()|+100:quit" "$E1")
check "simple preferences hide advanced VLC options" "$out" "simpleHidesAdvanced=true"
check "the detail-level button enables advanced mode" "$out" "buttonEnablesAdvanced=true"
check "the detail-level button switches back to simple mode" "$out" "buttonReturnsToSimple=true"
check "advanced preferences reveal the mapped VLC option" "$out" "advancedShowsOption=true"
check "advanced option values remain readable" "$out" "advancedValueRead=true"
check "switching back to simple preserves the option value" "$out" "simpleKeepsValue=true"
check "float VLC settings round-trip without losing fractional precision" "$out" "floatRoundTrip=true"
check "decimal VLC options parse fractional values" "$out" "fractionalInput=0.75"
check "integer VLC options keep whole-number input" "$out" "integerInput=1500"
out=$(run "1000:'advancedModePersists=' + Theme.store.advancedOptions|+100:Theme.store.advancedOptions=false|+100:quit")
check "the preference detail level persists across launches" "$out" "advancedModePersists=true"

echo "== Figma interface preferences"
out=$(run "1000:Theme.store.mode='dark'; Theme.store.accent='#D37918'; settingsDialog.page='interface'; settingsDialog.open()|+200:'interfaceTitle=' + settingsDialog.pageTitle|+150:click-item:auto-hide-delay|+100:'sliderMouse=' + Theme.store.hideDelay|+100:key:Right|+100:'sliderKeyboard=' + Theme.store.hideDelay|+100:Theme.store.autoHideMode='always'; 'alwaysHides=' + win.overlayMode|+100:Theme.store.autoHideMode='never'; 'neverShows=' + !win.overlayMode|+100:Theme.store.autoHideMode='always'; Theme.store.showControlsFullscreen=true; Theme.store.compactAtStart=true|+150:grab:$WORK/settings-interface.png|+100:quit")
check "interface preferences use the Figma page title" "$out" "interfaceTitle=Interface Settings"
check "the auto-hide slider responds to pointer input" "$out" "sliderMouse=5000"
check "the auto-hide slider responds to keyboard input" "$out" "sliderKeyboard=5100"
check "always auto-hide applies in a normal window" "$out" "alwaysHides=true"
check "never auto-hide keeps controls visible in a normal window" "$out" "neverShows=true"
if [ -s "$WORK/settings-interface.png" ]; then echo "PASS  interface settings screenshot written"; pass=$((pass + 1))
else echo "FAIL  interface settings screenshot missing"; fail=$((fail + 1)); fi
out=$(run "1000:Theme.store.autoHideMode='always'; Theme.store.hideDelay=500; win.uiHidden=true; win.topHot=false; win.bottomHot=false|+100:move:560,20|+100:'edgeReveals=' + (win.topHot && win.chromeShown)|+100:move:560,340|+50:win.topHot=false; win.bottomHot=false|+100:'centerHides=' + !win.chromeShown|+100:win.uiHidden=false; Theme.store.hideDelay=5100|+100:quit")
check "moving to the top edge reveals hidden controls" "$out" "edgeReveals=true"
check "moving to the center hides the controls again" "$out" "centerHides=true"
out=$(run "1000:'interfacePreferencesPersist=' + (Theme.store.hideDelay === 5100 && Theme.store.autoHideMode === 'always' && Theme.store.showControlsFullscreen && Theme.store.compactAtStart)|+100:'compactStart=' + (win.width === 560 && win.height === 340)|+100:Theme.store.compactAtStart=false; Theme.store.showControlsFullscreen=false; Theme.store.autoHideMode='fullscreen'; win.width=1120; win.height=680|+100:quit")
check "interface preferences persist across launches" "$out" "interfacePreferencesPersist=true"
check "compact mode changes the next launch size" "$out" "compactStart=true"

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

echo "== track popup dismissal"
out=$(run "1200:tracksPopup.openFor('spu', controlBar.findControl('subtitle'))|+100:'tabFocus=' + tracksPopup.focusTab('audio')|+100:key:Space|+100:'tabKeyboard=' + (tracksPopup.tab === 'audio')|+100:tracksPopup.close()|+100:quit" "$E1")
check "track popup tabs accept keyboard focus" "$out" "tabFocus=true"
check "Space activates the focused audio tab" "$out" "tabKeyboard=true"
out=$(run "1200:tracksPopup.openFor('spu', controlBar.findControl('subtitle'))|+150:'mainEscapeHandled=' + win.handleKey({key:Qt.Key_Escape, modifiers:Qt.NoModifier})|+100:'escapeClosed=' + !tracksPopup.visible|+100:quit" "$E1")
check "Escape closes the track popup through the main window handler" "$out" "escapeClosed=true"
check "the main window consumes Escape while closing the track popup" "$out" "mainEscapeHandled=true"
out=$(run "1200:tracksPopup.openFor('spu', controlBar.findControl('subtitle'))|+100:'opened=' + tracksPopup.visible|+100:click:900,300|+100:'outsideClosed=' + !tracksPopup.visible|+100:tracksPopup.openFor('spu', controlBar.findControl('subtitle'))|+100:tracksPopup.openFor('spu', controlBar.findControl('subtitle'))|+100:'toggleClosed=' + !tracksPopup.visible|+100:tracksPopup.openFor('audio', controlBar.findControl('audio'))|+100:'switched=' + (tracksPopup.visible && tracksPopup.tab === 'audio')|+100:win.libraryOpen=true; tracksPopup.openFor('audio', controlBar.findControl('audio'))|+100:click:900,500|+100:'miniCloses=' + (!tracksPopup.visible && !libraryOpen)|+100:tracksPopup.close()|+100:quit" "$E1")
check "track popup opens" "$out" "opened=true"
check "clicking the video outside the track popup closes it" "$out" "outsideClosed=true"
check "clicking the same track control closes its popup" "$out" "toggleClosed=true"
check "clicking another track control switches the popup" "$out" "switched=true"
check "clicking the mini-player video dismisses tracks and restores playback" "$out" "miniCloses=true"
out=$(run "1200:tracksPopup.openFor('spu', controlBar.findControl('subtitle')); win.width=560; win.height=340|+200:'popupFitsCompact=' + (tracksPopup.x >= 0 && tracksPopup.y >= 0 && tracksPopup.x + tracksPopup.width <= keyCatcher.width && tracksPopup.y + tracksPopup.height <= keyCatcher.height)|+100:grab:$WORK/track-popup-compact.png|+100:win.width=1120; win.height=680; tracksPopup.close()|+100:quit" "$E1")
check "track popup repositions within compact window bounds" "$out" "popupFitsCompact=true"
if [ -s "$WORK/track-popup-compact.png" ]; then echo "PASS  compact track popup screenshot written"; pass=$((pass + 1))
else echo "FAIL  compact track popup screenshot missing"; fail=$((fail + 1)); fi

echo "== side panel dismissal"
out=$(run "1200:win.rightPanel='settings'; sidePanel.tab='spu'|+100:'tabFocus=' + sidePanel.focusTab('audio')|+100:key:Space|+100:'tabKeyboard=' + (sidePanel.tab === 'audio')|+100:win.focusKeys()|+100:click-item:video-click-area|+100:'closed=' + (win.rightPanel === '')|+100:quit" "$E1")
check "settings panel tabs accept keyboard focus" "$out" "tabFocus=true"
check "Space activates the focused audio settings tab" "$out" "tabKeyboard=true"
check "clicking the video closes the audio/subtitle panel" "$out" "closed=true"

echo "== primary navigation"
out=$(run "1200:'focusVideos=' + navigationRail.focusPage('videos')|+100:key:Space|+100:libraryPanel.folder = platform.fileUrl(player.folderPath)|+350:'videos=' + (navigationPage === 'videos' && libraryOpen && libraryPanel.section === 'folder' && libraryPanel.mediaType === 'video') + ' expanded=' + (navigationRail.expanded && navigationRail.width === 112) + ' label=' + navigationRail.labelForPage('folder') + ' wide=' + (libraryPanel.visible && libraryPanel.width > win.width * 0.7 && !videoArea.visible) + ' mini=' + (video.parent === libraryPanel.miniVideoHost) + ' files=' + libraryPanel.fileCount()|+100:libraryPanel.searchText = 'S01E02'|+250:'searchMatches=' + libraryPanel.matchingFiles()|+100:libraryPanel.searchText = ''|+150:grab:$WORK/navigation-videos.png|+100:click:1092,596|+150:'miniRestore=' + (!libraryOpen && videoArea.visible && video.parent === videoArea)|+100:'focusRecent=' + navigationRail.focusPage('recent')|+100:key:Space|+100:'recent=' + (navigationPage === 'recent' && libraryPanel.section === 'recent' && navigationRail.expanded)|+100:quit" "$E1")
check "navigation buttons accept keyboard focus" "$out" "focusVideos=true"
check "Space opens the video library and expands the labeled navigation rail" "$out" "videos=true expanded=true label=Browse"
check "the library replaces the video area and keeps a live mini-player" "$out" "wide=true mini=true"
check "the full library lists the current folder media" "$out" "files=2"
check "library search filters filenames" "$out" "searchMatches=1"
check "the mini-player restore control returns to full playback" "$out" "miniRestore=true"
check "recent navigation accepts keyboard focus" "$out" "focusRecent=true"
check "recent navigation opens the recent-media view with the expanded rail" "$out" "recent=true"
if [ -s "$WORK/navigation-videos.png" ]; then echo "PASS  expanded navigation screenshot written"; pass=$((pass + 1))
else echo "FAIL  expanded navigation screenshot missing"; fail=$((fail + 1)); fi

echo
echo "passed $pass, failed $fail"
[ "$fail" -eq 0 ]
