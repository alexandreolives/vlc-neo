#!/usr/bin/env bash
# Audit every VLC option declared by SettingsDialog against the installed VLC.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
NEO_BUILD_DIR="${NEO_BUILD_DIR:-$HERE/build}"
export NEO_BUILD_DIR
NEO_SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/neo-preference-mapping.XXXXXX")"
export NEO_SANDBOX
trap 'python3 -c "import shutil,sys; shutil.rmtree(sys.argv[1], ignore_errors=True)" "$NEO_SANDBOX"' EXIT

python3 - "$HERE" "$NEO_SANDBOX/audit.py" "$NEO_SANDBOX/unavailable-options.json" <<'PY'
import json
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
names = sorted(set(re.findall(r'\boption:\s*"([^"]+)"',
                              (root / "qml/SettingsDialog.qml").read_text())))
Path(sys.argv[2]).write_text(json.dumps(names))
print(f"Auditing {len(names)} unique declared VLC options")
PY

output="$(python3 - "$HERE" "$NEO_SANDBOX/audit.py" "$NEO_SANDBOX/unavailable-options.json" <<'PY'
import json
import os
import subprocess
import sys
from pathlib import Path

root = Path(sys.argv[1])
names = json.loads(Path(sys.argv[2]).read_text())
steps = ["500:settingsDialog.open()"]
for name in names:
    quoted = json.dumps(name)
    control_name = json.dumps("vlc-option-" + name)
    control = "settingsDialog.preferenceControl(" + control_name + ")"
    steps.append(
        "+1:'audit-" + name + "=' + player.configType(" + quoted + ") + '/' + "
        + "(" + control + " ? " + control + ".kind : 'missing') + '/' + "
        + "(!!" + control + " && String(" + control + ".effectiveInfo).trim().length>0) + '/' + "
        + "(!!" + control + " && String(" + control + ".current)===String(player.config(" + quoted + "))) + '/' + "
        + "(!!" + control + " && " + control + ".visible)"
    )
steps.append("+100:quit")
environment = os.environ.copy()
environment["NEO_TIMEOUT"] = "60"
result = subprocess.run(
    [str(root / "scripts/run-offscreen.sh"), "|".join(steps)],
    cwd=root, env=environment, text=True, stdout=subprocess.PIPE,
    stderr=subprocess.STDOUT, timeout=70, check=False,
)
print(result.stdout, end="")
if result.returncode:
    raise SystemExit(result.returncode)
PY
)"

python3 - "$HERE" "$output" "$NEO_SANDBOX/unavailable-options.json" <<'PY'
import collections
import json
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
output = sys.argv[2]
unavailable_path = Path(sys.argv[3])
names = sorted(set(re.findall(r'\boption:\s*"([^"]+)"',
                              (root / "qml/SettingsDialog.qml").read_text())))
results = {}
for line in output.splitlines():
    match = re.search(r"neo test: .*?=> audit-([^=]+)=([^\s]+)$", line)
    if match:
        results[match.group(1)] = match.group(2).split("/")

failures = []
if len(results) != len(names):
    failures.append(f"received {len(results)} results for {len(names)} options")
unavailable = []
for name, result in results.items():
    if result[0] == "":
        unavailable.append(name)
        if len(result) != 5 or result[4] != "false":
            failures.append(f"{name}: VLC does not expose this option but its control is not hidden")

available_names = [name for name in names if name not in unavailable]
unavailable_path.write_text(json.dumps(unavailable))
compatible = {
    "bool": {"bool", "choice"},
    "integer": {"number", "slider", "choice", "color"},
    "float": {"number", "slider", "choice"},
    "string": {"text", "choice"},
}
types = collections.Counter()
for name in available_names:
    result = results.get(name)
    if not result:
        failures.append(f"{name}: no runtime audit result")
        continue
    if len(result) != 5:
        failures.append(f"{name}: malformed runtime audit result")
        continue
    value_type, kind, has_help, control_matches, _visible = result
    types[value_type] += 1
    if value_type not in compatible:
        failures.append(f"{name}: missing/unknown VLC type {value_type!r}")
    elif kind not in compatible[value_type]:
        failures.append(f"{name}: VLC type {value_type} uses incompatible {kind} control")
    if has_help != "true":
        failures.append(f"{name}: no effective help text")
    if control_matches != "true":
        failures.append(f"{name}: control value differs from VLC config")

if failures:
    print("FAIL preference mapping audit")
    print("\n".join(f"  {failure}" for failure in failures))
    raise SystemExit(1)
print(f"PASS {len(available_names)}/{len(names)} available VLC preferences: controls, types, help and current-value mapping")
if unavailable:
    print(f"HIDDEN {len(unavailable)} options absent from this VLC build: " + ", ".join(unavailable))
print("VLC types: " + ", ".join(f"{key}={types[key]}" for key in sorted(types)))
PY

# Write each control through VLC (toggle ordinary booleans, retain other current
# values), then compare persisted values and mapped controls after relaunch.
python3 - "$HERE" "$NEO_SANDBOX/audit.py" "$NEO_SANDBOX/unavailable-options.json" <<'PY'
import json
import os
import re
import subprocess
import sys
from pathlib import Path

root = Path(sys.argv[1])
names = json.loads(Path(sys.argv[2]).read_text())
unavailable = set(json.loads(Path(sys.argv[3]).read_text()))
names = [name for name in names if name not in unavailable]
runner = str(root / "scripts/run-offscreen.sh")
environment = os.environ.copy()
environment["NEO_TIMEOUT"] = "90"

def launch(steps):
    result = subprocess.run(
        [runner, "|".join(steps)], cwd=root, env=environment,
        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        timeout=100, check=False,
    )
    if result.returncode:
        print(result.stdout, end="")
        raise SystemExit(result.returncode)
    return result.stdout

write_steps = ["500:settingsDialog.open()"]
for name in names:
    quoted = json.dumps(name)
    write_steps.append(
        "+1:player.setConfig(" + quoted + ",player.configType(" + quoted + ")==='bool' && " + quoted + "!=='one-instance' && " + quoted + "!=='one-instance-when-started-from-file' ? !player.config(" + quoted + ") : player.config(" + quoted + ")); 'saved-" + name
        + "=' + Qt.md5(encodeURIComponent(String(player.config(" + quoted + "))))"
    )
write_output = launch(write_steps + ["+100:quit"])
saved = {}
for line in write_output.splitlines():
    match = re.search(r"neo test: .*?=> saved-([^=]+)=([0-9a-f]{32})$", line)
    if match:
        saved[match.group(1)] = match.group(2)
if len(saved) != len(names):
    raise SystemExit(f"FAIL preference persistence: captured {len(saved)}/{len(names)} values before relaunch")

reload_steps = ["500:settingsDialog.open()"]
for name in names:
    quoted = json.dumps(name)
    control = json.dumps("vlc-option-" + name)
    digest = json.dumps(saved[name])
    reload_steps.append(
        "+1:'reloaded-" + name + "=' + "
        "(Qt.md5(encodeURIComponent(String(player.config(" + quoted + "))))===" + digest + ") + '/' + "
        "(String(settingsDialog.preferenceControl(" + control + ").current)===String(player.config(" + quoted + ")))"
    )
reload_output = launch(reload_steps + ["+100:quit"])
results = {}
for line in reload_output.splitlines():
    match = re.search(r"neo test: .*?=> reloaded-([^=]+)=(true|false)/(true|false)$", line)
    if match:
        results[match.group(1)] = match.groups()[1:]
if len(results) != len(names):
    print(reload_output, end="")
    raise SystemExit(f"FAIL preference persistence: received {len(results)}/{len(names)} results after relaunch")
failures = [name for name in names if results[name] != ("true", "true")]
if failures:
    raise SystemExit("FAIL preference persistence after VLC relaunch: " + ", ".join(failures))
print(f"PASS {len(names)} available VLC preferences: saved values and controls survive a VLC relaunch")
PY
