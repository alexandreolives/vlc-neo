#!/usr/bin/env bash
# Smoke the asynchronous seek waveform with one-minute CC0 track excerpts from three genres.
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${NEO_BUILD_DIR:-$HERE/build}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/neo-waveform-variety.XXXXXX")"
ARTIFACTS="${NEO_WAVEFORM_OUTPUT_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/neo-waveform-artifacts.XXXXXX")}"
mkdir -p "$ARTIFACTS"
trap 'python3 -c "import shutil,sys; shutil.rmtree(sys.argv[1], ignore_errors=True)" "$WORK"' EXIT
declare -A waveform_hashes

run_sample() {
    local genre="$1" file="$2" sandbox="$WORK/$1-sandbox"
    local long_file="$WORK/$genre-60s.ogg"
    mkdir -p "$sandbox"
    ffmpeg -hide_banner -loglevel error -stream_loop -1 -i "$file" -t 60 \
        -ac 1 -ar 48000 -c:a libvorbis -q:a 3 "$long_file"
    local duration
    duration="$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$long_file")"
    if ! awk -v d="$duration" 'BEGIN { exit !(d >= 59.5) }'; then
        echo "FAIL $genre waveform sample is only ${duration}s; expected a one-minute real-audio exercise" >&2
        return 1
    fi
    local output
    output="$(NEO_BUILD_DIR="$BUILD_DIR" NEO_SANDBOX="$sandbox" NEO_TIMEOUT=20 \
        "$HERE/scripts/run-offscreen.sh" \
        "500:onboarding.close(); win.width=1120; win.height=680; player.openLocation('$long_file',true)|+1200:'waveformRequest=' + controlBar.findControl('seek').contentItem.requestWaveform()|+4500:'waveformReady=' + controlBar.findControl('seek').contentItem.waveformReady|+150:grab:$ARTIFACTS/$genre.png|+100:Qt.quit()" 2>&1)"
    printf '%s\n' "$output" | grep 'neo test:' || true
    if ! grep -q 'waveformRequest=true' <<<"$output" || ! grep -q 'waveformReady=true' <<<"$output"; then
        echo "FAIL $genre waveform did not become ready" >&2
        return 1
    fi
    if [[ ! -s "$ARTIFACTS/$genre.png" ]]; then
        echo "FAIL $genre screenshot was not written" >&2
        return 1
    fi
    waveform_hashes["$genre"]="$(ffmpeg -loglevel error -i "$ARTIFACTS/$genre.png" \
        -vf 'crop=612:28:231:640,format=gray' -frames:v 1 -f rawvideo - | sha256sum | cut -d' ' -f1)"
    echo "PASS $genre one-minute waveform ready (${duration}s); screenshot: $ARTIFACTS/$genre.png"
}

run_sample jazz "$HERE/tests/fixtures/waveform-jazz.ogg"
run_sample classical "$HERE/tests/fixtures/waveform-classical.ogg"
run_sample electronic "$HERE/tests/fixtures/waveform-electronic.ogg"

if [[ "${waveform_hashes[jazz]}" == "${waveform_hashes[classical]}" || \
      "${waveform_hashes[jazz]}" == "${waveform_hashes[electronic]}" || \
      "${waveform_hashes[classical]}" == "${waveform_hashes[electronic]}" ]]; then
    echo "FAIL expected distinct rendered waveform shapes for jazz, classical, and electronic audio" >&2
    exit 1
fi
echo "PASS jazz, classical, and electronic tracks produce three distinct waveform renders"
