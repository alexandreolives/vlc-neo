#!/usr/bin/env bash
# Verify VLC's equalizer changes real decoded audio, not only saved settings.
set -euo pipefail

if [[ "${NEO_EQUALIZER_TEST_PRIVATE_DBUS:-}" != "1" ]]; then
    if ! command -v dbus-run-session >/dev/null 2>&1; then
        echo "dbus-run-session is required to isolate the VLC audio output test." >&2
        exit 2
    fi
    export NEO_EQUALIZER_TEST_PRIVATE_DBUS=1
    exec dbus-run-session -- "$0" "$@"
fi

HERE="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${NEO_BUILD_DIR:-$HERE/build}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/neo-audio-equalizer.XXXXXX")"
trap 'python3 -c "import shutil,sys; shutil.rmtree(sys.argv[1], ignore_errors=True)" "$WORK"' EXIT

for tool in ffmpeg python3; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "FAIL required tool not found: $tool" >&2
        exit 2
    fi
done

ffmpeg -loglevel error -y -f lavfi \
    -i "sine=frequency=1000:duration=5:sample_rate=48000" \
    -ac 2 -c:a pcm_s16le "$WORK/tone.wav"

run_capture() {
    local preamp="$1"
    local output_file="$2"
    local sandbox="$3"
    local output
    output="$(NEO_BUILD_DIR="$BUILD_DIR" NEO_SANDBOX="$sandbox" \
        NEO_TEST_AOUT=afile NEO_TIMEOUT=15 \
        "$HERE/scripts/run-offscreen.sh" \
        "700:player.setConfig('audiofile-file','$output_file'); player.setConfig('audiofile-format','s16'); player.setEqualizerPreset('flat'); player.setConfig('equalizer-preamp',$preamp); player.openLocation('$WORK/tone.wav',true)|+1000:'equalizerCapture=' + player.equalizerPreset() + '/' + player.config('equalizer-preamp') + '/' + (player.state===2)|+1400:quit" 2>&1)"
    printf '%s\n' "$output" | grep 'neo test:' || true
    if ! grep -qF "equalizerCapture=flat/$preamp/true" <<<"$output"; then
        echo "FAIL VLC did not start the requested equalizer capture" >&2
        return 1
    fi
    if [ ! -s "$output_file" ]; then
        echo "FAIL VLC did not write PCM audio to $output_file" >&2
        return 1
    fi
}

run_capture 0 "$WORK/flat-0.pcm" "$WORK/sandbox-0"
run_capture 12 "$WORK/flat-12.pcm" "$WORK/sandbox-12"

python3 - "$WORK/flat-0.pcm" "$WORK/flat-12.pcm" <<'PY'
import array
import math
import pathlib
import sys


def rms(path: str) -> float:
    data = pathlib.Path(path).read_bytes()
    if len(data) < 96000 or len(data) % 2:
        raise SystemExit(f"FAIL insufficient or malformed PCM capture: {path} ({len(data)} bytes)")
    samples = array.array("h")
    samples.frombytes(data)
    start, end = len(samples) // 4, 3 * len(samples) // 4
    middle = samples[start:end]
    return math.sqrt(sum(sample * sample for sample in middle) / len(middle))


quiet = rms(sys.argv[1])
boosted = rms(sys.argv[2])
ratio = boosted / quiet if quiet else 0
print(f"equalizerRms={quiet:.1f}->{boosted:.1f}; ratio={ratio:.2f}")
if ratio < 2.0:
    raise SystemExit("FAIL VLC equalizer preamp did not measurably change decoded PCM")
print("PASS VLC equalizer changed captured audio output")
PY
