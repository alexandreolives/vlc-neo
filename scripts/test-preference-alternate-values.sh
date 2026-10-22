#!/usr/bin/env bash
# Exercise alternate UI-supported VLC preference values and verify relaunch persistence.
set -euo pipefail

if [[ "${NEO_PREFERENCE_ALTERNATE_VALUES_PRIVATE_DBUS:-}" != "1" ]]; then
    if ! command -v dbus-run-session >/dev/null 2>&1; then
        echo "dbus-run-session is required to isolate VLC single-instance preference tests." >&2
        exit 2
    fi
    export NEO_PREFERENCE_ALTERNATE_VALUES_PRIVATE_DBUS=1
    exec dbus-run-session -- "$0" "$@"
fi

HERE="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${NEO_BUILD_DIR:-$HERE/build}"
SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/neo-preference-alternates.XXXXXX")"
trap 'python3 -c "import shutil,sys; shutil.rmtree(sys.argv[1], ignore_errors=True)" "$SANDBOX"' EXIT

python3 - "$HERE" "$BUILD_DIR" "$SANDBOX" <<'PY'
import json
import os
import re
import subprocess
import sys
from pathlib import Path

root, build, sandbox = map(Path, sys.argv[1:])
settings = (root / "qml/SettingsDialog.qml").read_text()
names = sorted(set(re.findall(r'\boption:\s*"([^"]+)"', settings)))
runner = root / "scripts/run-offscreen.sh"
env = os.environ.copy()
env.update(NEO_BUILD_DIR=str(build), NEO_TIMEOUT="90")

def launch(run_sandbox, steps):
    run_env = env | {"NEO_SANDBOX": str(run_sandbox)}
    result = subprocess.run([str(runner), "|".join(steps)], cwd=root, env=run_env,
                            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            timeout=100, check=False)
    if result.returncode:
        raise SystemExit(f"VLC Neo exited with {result.returncode}")
    return result.stdout

meta_steps = ["500:settingsDialog.open()"]
for name in names:
    qname = json.dumps(name)
    control = json.dumps("vlc-option-" + name)
    meta_steps.append(
        f"+1:'meta-{name}=' + JSON.stringify({{type:player.configType({qname}),"
        f"kind:settingsDialog.preferenceControl({control}).kind,"
        f"choices:settingsDialog.preferenceControl({control}).choices,"
        f"bounds:player.configRange({qname}),current:player.config({qname})}})"
    )
meta_output = launch(sandbox / "meta", meta_steps + ["+100:quit"])
metadata = {}
for line in meta_output.splitlines():
    match = re.search(r"=> meta-([^=]+)=(\{.*\})$", line)
    if match:
        metadata[match.group(1)] = json.loads(match.group(2))
if set(metadata) != set(names):
    raise SystemExit(f"FAIL: got metadata for {len(metadata)}/{len(names)} declared options")

# Text options have no enumerable domain, so use documented, non-networking values.
text_values = {
    "audio-language": "fr,en", "avcodec-options": "{threads=1}",
    "codec": "avcodec", "encoder": "x264", "extraintf": "dummy",
    "freetype-font": "DejaVu Sans", "gnutls-dir-trust": "/etc/ssl/certs",
    "http-password": "neo-audit-password", "http-proxy": "http://127.0.0.1:18987",
    "http-proxy-pwd": "neo-audit-password", "ignore-filetypes": "m3u,txt",
    "lastfm-password": "neo-audit-password", "lastfm-username": "neo-audit-user",
    "postproc-name": "deblock", "qt-recentplay-filter": "neo",
    "scrobbler-url": "audioscrobbler.invalid", "snapshot-path": "/tmp",
    "socks": "127.0.0.1:1080", "socks-pwd": "neo-audit-password",
    "socks-user": "neo-audit-user", "sout-chromecast-ip": "127.0.0.1",
    "sout-transcode-acodec": "mp4a", "sout-transcode-fps": "25",
    "sout-transcode-vcodec": "h264", "sub-language": "fr,en",
}

def candidate(name, item):
    kind, value_type = item["kind"], item["type"]
    current = item["current"]
    if kind == "bool":
        return not bool(current)
    if kind == "choice":
        for choice in item["choices"]:
            if value_type == "bool":
                differs = bool(choice["value"]) != bool(current)
            else:
                differs = str(choice["value"]) != str(current)
            if differs:
                return choice["value"]
        return None
    if kind == "color":
        return 1 if int(current) == 0 else 0
    if kind in {"number", "slider"}:
        bounds = item.get("bounds", {})
        minimum, maximum = bounds.get("minimum"), bounds.get("maximum")
        step = 0.01 if value_type == "float" else 1
        next_value = float(current) + step
        if maximum is not None and next_value > float(maximum):
            next_value = float(current) - step
        if minimum is not None and next_value < float(minimum):
            next_value = float(current) + step
        return next_value if value_type == "float" else int(next_value)
    if kind == "text":
        return text_values.get(name)
    return None

values = {}
missing = []
for name in names:
    value = candidate(name, metadata[name])
    if value is None:
        missing.append(name)
    else:
        values[name] = value
if missing:
    raise SystemExit("No alternate test value for: " + ", ".join(missing))

write_steps = ["500:settingsDialog.open()"]
for name, value in values.items():
    qname, qvalue = json.dumps(name), json.dumps(value)
    control = json.dumps("vlc-option-" + name)
    if metadata[name]["kind"] == "number":
        validate = f"settingsDialog.optionNumberValue({qname},String({qvalue}))!==undefined"
    elif metadata[name]["kind"] == "color":
        validate = f"settingsDialog.optionColorValue({qname},settingsDialog.optionColorHex({qname},{qvalue}))!==undefined"
    else:
        validate = "true"
    write_steps.append(
        f"+1:(() => {{ const ok={validate}; if(ok) settingsDialog.setOptionValue({qname},{qvalue}); "
        f"const shown=settingsDialog.preferenceControl({control}).current; const actual=player.config({qname}); "
        f"const actualType=player.configType({qname}); const same=actualType==='bool' ? Boolean(shown)===Boolean(actual) : "
        f"(['integer','float'].includes(actualType) ? Math.abs(Number(shown)-Number(actual))<0.00001 : String(shown)===String(actual)); "
        f"return 'saved-{name}=' + ok + '/' + same + '/' + Qt.md5(encodeURIComponent(String(actual))) }})()"
    )
write_output = launch(sandbox / "config", write_steps + ["+100:quit"])
saved = {}
for line in write_output.splitlines():
    match = re.search(r"=> saved-([^=]+)=(true|false)/(true|false)/([0-9a-f]{32})$", line)
    if match:
        saved[match.group(1)] = (match.group(2), match.group(3), match.group(4))
if len(saved) != len(values):
    absent = sorted(set(values) - set(saved))
    raise SystemExit(f"FAIL: saved {len(saved)}/{len(values)} alternate values; no result for: {', '.join(absent)}")
bad = [name for name, (valid, mapped, _) in saved.items() if valid != "true" or mapped != "true"]
if bad:
    details = ", ".join(f"{name}={saved[name][0]}/{saved[name][1]}" for name in bad)
    raise SystemExit("FAIL: invalid alternate value or UI/backend mismatch (value-valid/control-matches): " + details)

reload_steps = ["500:settingsDialog.open()"]
for name in values:
    qname, control = json.dumps(name), json.dumps("vlc-option-" + name)
    expected_hash = json.dumps(saved[name][2])
    reload_steps.append(
        f"+1:'restored-{name}=' + (Qt.md5(encodeURIComponent(String(player.config({qname}))))==={expected_hash}) + '/' + "
        f"(String(settingsDialog.preferenceControl({control}).current)===String(player.config({qname})))"
    )
reload_output = launch(sandbox / "config", reload_steps + ["+100:quit"])
restored = {}
for line in reload_output.splitlines():
    match = re.search(r"=> restored-([^=]+)=(true|false)/(true|false)$", line)
    if match:
        restored[match.group(1)] = match.groups()[1:]
if len(restored) != len(values):
    syntax_errors = len(re.findall(r"SyntaxError|test step failed", reload_output))
    observed = re.findall(r"neo test: .*?=> ([a-z]+-[a-z0-9-]+)=", reload_output)
    raise SystemExit(f"FAIL: restored {len(restored)}/{len(values)} preference values; QML step errors={syntax_errors}; markers={len(observed)}")
bad = [name for name, result in restored.items() if result != ("true", "true")]
if bad:
    raise SystemExit("FAIL: alternate values did not survive VLC relaunch: " + ", ".join(bad))

counts = {"bool": 0, "choice": 0, "numeric": 0, "color": 0, "text": 0}
for name in values:
    kind = metadata[name]["kind"]
    counts["numeric" if kind in {"number", "slider"} else kind] += 1
print(f"PASS {len(values)}/{len(names)} alternate VLC preference values, mapped controls, and relaunch persistence")
print("Coverage: " + ", ".join(f"{key}={value}" for key, value in counts.items()))
print("VLC relaunches ran in a private D-Bus session to isolate single-instance IPC from desktop VLC processes.")
print("Secret text values are tested in an isolated VLC config and never printed.")
PY
