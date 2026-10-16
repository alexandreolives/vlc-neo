#!/usr/bin/env bash
# End-to-end checks of the Neo interface against the real VLC 3 core (headless).
# Generates its own media, runs VLC with -I neo offscreen, asserts on the results.
set -uo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${TMPDIR:-/tmp}/neo-smoke"
rm -rf "$WORK" && mkdir -p "$WORK/show" "$WORK/subs"
export NEO_SANDBOX="$WORK/sandbox"
pass=0; fail=0

check() { # name, haystack, needle
    if grep -qF -- "$3" <<<"$2"; then echo "PASS  $1"; pass=$((pass + 1))
    else echo "FAIL  $1  (expected: $3)"; fail=$((fail + 1)); fi
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

echo "== folder subtitles + show preset"
out=$(run "1500:'matched=' + player.linkSubtitleFolder(platform.fileUrl('$WORK/subs'))|2500:player.setSubtitleDelay(-400); player.setSubtitleScale(160)|2800:player.savePresetForFolder()|3000:quit" "$E1" "$E2")
check "folder link matches both episodes" "$out" "matched=2"
out=$(run "3000:'spu=' + player.tracks('spu').filter(t => t.selected).map(t => t.name).join() + ' delay=' + player.subtitleDelay + ' scale=' + player.subtitleScale()|3200:quit" "$E2")
check "episode 2 gets its own subtitle" "$out" "myshow_1x02_ar"
check "preset restores subtitle delay" "$out" "delay=-400"
check "preset restores subtitle size" "$out" "scale=160"

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

echo
echo "passed $pass, failed $fail"
[ "$fail" -eq 0 ]
