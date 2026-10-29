#!/usr/bin/env bash
# Exercise per-user install/default/uninstall behavior in a disposable HOME.
# Package manager, Qt metadata, compiler output, and VLC are stubbed: this is
# an installer lifecycle test, not a build or playback test.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/vlc-neo-installer.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

TEST_HOME="$WORK/home"
FAKE_BIN="$WORK/bin"
FAKE_QT="$WORK/Qt/6.8.3/gcc_64"
BUILD_DIR="$WORK/build"
SYSTEM_DESKTOP="$WORK/system-applications/vlc.desktop"
SYSTEM_VLC="$WORK/system-bin/vlc"
mkdir -p "$TEST_HOME" "$FAKE_BIN" "$FAKE_QT/lib/cmake/Qt6" "$FAKE_QT/lib/pkgconfig" \
    "$(dirname "$SYSTEM_DESKTOP")" "$(dirname "$SYSTEM_VLC")"
touch "$FAKE_QT/lib/cmake/Qt6/Qt6Config.cmake"
for module in QtCore QtQuick QtQuick/Controls/Basic QtQuick/Dialogs QtQuick/Effects \
    QtQuick/Layouts QtQuick/Shapes QtQuick/Window Qt/labs/folderlistmodel; do
    mkdir -p "$FAKE_QT/qml/$module"
    touch "$FAKE_QT/qml/$module/qmldir"
done
cat > "$SYSTEM_DESKTOP" <<DESKTOP
[Desktop Entry]
Type=Application
Name=VLC
Exec=$SYSTEM_VLC --started-from-file %U
TryExec=$SYSTEM_VLC
DESKTOP
cp "$SYSTEM_DESKTOP" "$WORK/system-desktop.before"

cat > "$SYSTEM_VLC" <<'VLC'
#!/usr/bin/env bash
if [[ "${1:-}" == "-I" && "${2:-}" == "qt" ]]; then
    : > "$VLC_CLASSIC_CALLED"
fi
printf '%s\n' "$*" >> "$VLC_ARGS_LOG"
echo "VLC version 3.0.20 installer-test"
VLC
chmod +x "$SYSTEM_VLC"

cat > "$FAKE_BIN/dpkg-query" <<'STUB'
#!/usr/bin/env bash
if [[ "${PACKAGE_MISSING:-0}" == "1" ]]; then exit 1; fi
echo 'install ok installed'
STUB
cat > "$FAKE_BIN/pacman" <<'STUB'
#!/usr/bin/env bash
if [[ "${1:-}" == "-Qq" ]]; then
    [[ "${PACKAGE_MISSING:-0}" == "0" ]]
    exit
fi
printf '%s\n' "$*" >> "$PACKAGE_LOG"
STUB
cat > "$FAKE_BIN/rpm" <<'STUB'
#!/usr/bin/env bash
[[ "${PACKAGE_MISSING:-0}" == "0" ]]
STUB
cat > "$FAKE_BIN/apt-cache" <<'STUB'
#!/usr/bin/env bash
if [[ "$*" == *qml6-module-qtquick-effects* ]]; then exit 100; fi
exit 0
STUB
cat > "$FAKE_BIN/apt-get" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$PACKAGE_LOG"
STUB
cat > "$FAKE_BIN/dnf" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$PACKAGE_LOG"
STUB
cat > "$FAKE_BIN/sudo" <<'STUB'
#!/usr/bin/env bash
exec "$@"
STUB
cat > "$FAKE_BIN/pkg-config" <<'STUB'
#!/usr/bin/env bash
if [[ "${PKG_CONFIG_MISSING:-}" != "" && "$*" == *"${PKG_CONFIG_MISSING}"* ]]; then
    exit 1
fi
if [[ "${1:-}" == "--atleast-version=6.6" && "${SYSTEM_QT_TOO_OLD:-0}" == "1" \
    && "${PKG_CONFIG_PATH:-}" != *"$HOME/Qt/"* ]]; then
    exit 1
fi
if [[ "${1:-}" == "--modversion" && "${2:-}" == "vlc-plugin" ]]; then
    echo "${VLC_PLUGIN_VERSION:-3.0.20}"
    exit 0
fi
exit 0
STUB
cat > "$FAKE_BIN/ninja" <<'STUB'
#!/usr/bin/env bash
echo '1.11.1'
STUB
cat > "$FAKE_BIN/cmake" <<'STUB'
#!/usr/bin/env bash
if [[ "${1:-}" == "--version" ]]; then
    echo 'cmake version 3.28.3'
    exit 0
fi
if [[ "${1:-}" == "-S" ]]; then
    while (($#)); do
        if [[ "$1" == "-B" ]]; then
            mkdir -p "$2"
            : > "$2/libneo_plugin.so"
            exit 0
        fi
        shift
    done
fi
if [[ "${1:-}" == "--build" ]]; then exit 0; fi
echo "Unexpected cmake invocation: $*" >&2
exit 1
STUB
cat > "$FAKE_BIN/update-desktop-database" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
cat > "$FAKE_BIN/aqt" <<'STUB'
#!/usr/bin/env bash
base=""
while (($#)); do
    if [[ "$1" == "--base" ]]; then base="$2"; shift 2; else shift; fi
done
printf '%s\n' "$base" >> "$AQT_LOG"
if [[ "$base" == *berkeley* ]]; then exit 1; fi
qt_root="$HOME/Qt/6.8.3/gcc_64"
mkdir -p "$qt_root/lib/cmake/Qt6" "$qt_root/lib/pkgconfig"
touch "$qt_root/lib/cmake/Qt6/Qt6Config.cmake"
for module in QtCore QtQuick QtQuick/Controls/Basic QtQuick/Dialogs QtQuick/Effects \
    QtQuick/Layouts QtQuick/Shapes QtQuick/Window Qt/labs/folderlistmodel; do
    mkdir -p "$qt_root/qml/$module"
    touch "$qt_root/qml/$module/qmldir"
done
exit 0
STUB
chmod +x "$FAKE_BIN"/*

export PATH="$FAKE_BIN:/usr/bin:/bin"
export HOME="$TEST_HOME"
export QT_ROOT="$FAKE_QT"
export BUILD_DIR SYSTEM_DESKTOP SYSTEM_VLC
export VLC_CLASSIC_CALLED="$WORK/classic-called"
export VLC_ARGS_LOG="$WORK/vlc-args.log"
export PACKAGE_LOG="$WORK/package-manager.log"
export AQT_LOG="$WORK/aqt-mirrors.log"
cat > "$WORK/os-release-id-only" <<'OS_RELEASE'
ID=debian
OS_RELEASE

"$HERE/scripts/install.sh" --default --yes
test -x "$HOME/.local/bin/vlc-neo"
test -x "$HOME/.local/bin/vlc"
test -f "$HOME/.local/lib/vlc-neo/plugins/gui/libneo_plugin.so"
grep -q 'vlc-neo-managed' "$HOME/.local/bin/vlc"
grep -q "Exec=$HOME/.local/bin/vlc --started-from-file %U" "$HOME/.local/share/applications/vlc.desktop"
grep -q 'Exec=.*-I qt' "$HOME/.local/share/applications/vlc-classic.desktop"

"$HOME/.local/bin/vlc" --version | grep -q 'VLC version 3.0.20'
"$HOME/.local/bin/vlc" -I qt --version | grep -q 'VLC version 3.0.20'
test -f "$VLC_CLASSIC_CALLED"
"$HOME/.local/bin/vlc" "$WORK/default.mp4" >/dev/null
grep -q -- '-I neo ' "$VLC_ARGS_LOG"
mkdir -p "$HOME/.config/vlc"
printf 'intf=skins2\n' > "$HOME/.config/vlc/vlcrc"
"$HOME/.local/bin/vlc" "$WORK/skin.mp4" >/dev/null
test "$(tail -n 1 "$VLC_ARGS_LOG")" = "$WORK/skin.mp4"
"$HOME/.local/bin/vlc-neo" "$WORK/neo.mp4" >/dev/null
test "$(tail -n 1 "$VLC_ARGS_LOG")" = "-I neo $WORK/neo.mp4"

echo 'PASS  default install, classic passthrough, uninstall, and system launcher restore'

"$HERE/scripts/install.sh" --uninstall
test ! -e "$HOME/.local/bin/vlc-neo"
test ! -e "$HOME/.local/bin/vlc"
test ! -e "$HOME/.local/share/applications/vlc.desktop"
test ! -e "$HOME/.local/share/applications/vlc-classic.desktop"
test ! -e "$HOME/.local/share/applications/vlc-neo.desktop"
cmp "$WORK/system-desktop.before" "$SYSTEM_DESKTOP"
test -x "$SYSTEM_VLC"
echo 'PASS  uninstall removes the user override without changing the system launcher'

PACKAGE_MISSING=1 "$HERE/scripts/install.sh" --default --yes
if [[ "$(. /etc/os-release; echo "$ID $ID_LIKE")" == *debian* || "$(. /etc/os-release; echo "$ID $ID_LIKE")" == *ubuntu* ]]; then
    grep -qx 'update' "$PACKAGE_LOG"
    grep -q '^install -y .*ninja-build.*libvlccore-dev.*libtag1-dev.*libsqlite3-dev' "$PACKAGE_LOG"
    ! grep -Eq 'qml6-module-qtquick|qml6-module-qtcore' "$PACKAGE_LOG"
elif [[ "$(. /etc/os-release; echo "$ID $ID_LIKE")" == *arch* ]]; then
    grep -q '^-S --needed .*ninja.*libvlc.*taglib.*sqlite' "$PACKAGE_LOG"
elif [[ "$(. /etc/os-release; echo "$ID $ID_LIKE")" == *fedora* || "$(. /etc/os-release; echo "$ID $ID_LIKE")" == *rhel* ]]; then
    grep -q '^install -y .*ninja-build.*vlc-devel.*taglib-devel.*sqlite-devel' "$PACKAGE_LOG"
else
    echo 'Unsupported host for installer dependency test' >&2
    exit 1
fi
echo 'PASS  missing dependencies are sent to the detected package manager with --yes'

cat > "$WORK/os-release-debian" <<'OS_RELEASE'
ID=debian
OS_RELEASE
cat > "$WORK/os-release-arch" <<'OS_RELEASE'
ID=arch
OS_RELEASE
cat > "$WORK/os-release-fedora" <<'OS_RELEASE'
ID=fedora
OS_RELEASE

: > "$PACKAGE_LOG"
OS_RELEASE_FILE="$WORK/os-release-debian" PACKAGE_MISSING=1 \
    "$HERE/scripts/install.sh" --yes >/dev/null
grep -qx 'update' "$PACKAGE_LOG"
grep -q '^install -y .*ninja-build.*libvlccore-dev.*libtag1-dev.*libsqlite3-dev' "$PACKAGE_LOG"
test "$(wc -l < "$PACKAGE_LOG")" -eq 2
echo 'PASS  Debian OS_RELEASE selects apt and installs Debian dependency names'
"$HERE/scripts/install.sh" --uninstall

: > "$PACKAGE_LOG"
OS_RELEASE_FILE="$WORK/os-release-arch" PACKAGE_MISSING=1 \
    "$HERE/scripts/install.sh" --yes >/dev/null
grep -q '^-S --needed .*ninja.*libvlc.*taglib.*sqlite' "$PACKAGE_LOG"
test "$(wc -l < "$PACKAGE_LOG")" -eq 1
echo 'PASS  Arch OS_RELEASE selects pacman and installs Arch dependency names'
"$HERE/scripts/install.sh" --uninstall

: > "$PACKAGE_LOG"
OS_RELEASE_FILE="$WORK/os-release-fedora" PACKAGE_MISSING=1 \
    "$HERE/scripts/install.sh" --yes >/dev/null
grep -q '^install -y .*ninja-build.*vlc-devel.*taglib-devel.*sqlite-devel' "$PACKAGE_LOG"
test "$(wc -l < "$PACKAGE_LOG")" -eq 1
echo 'PASS  Fedora OS_RELEASE selects dnf and installs Fedora dependency names'
"$HERE/scripts/install.sh" --uninstall

OS_RELEASE_FILE="$WORK/os-release-id-only" "$HERE/scripts/install.sh" --yes >/dev/null
echo 'PASS  distro detection works when optional ID_LIKE is absent'

if PKG_CONFIG_MISSING=Qt6Concurrent "$HERE/scripts/install.sh" --yes >"$WORK/missing-qt.log" 2>&1; then
    echo 'Installer accepted missing Qt6Concurrent.' >&2
    exit 1
fi
grep -q 'Qt 6.6+ development modules' "$WORK/missing-qt.log"
echo 'PASS  preflight rejects a missing required Qt component'

rm "$FAKE_QT/qml/QtQuick/Effects/qmldir"
if "$HERE/scripts/install.sh" --yes >"$WORK/missing-qml.log" 2>&1; then
    echo 'Installer accepted a missing QtQuick.Effects QML module.' >&2
    exit 1
fi
grep -q "requires the Qt QML module 'QtQuick/Effects'" "$WORK/missing-qml.log"
touch "$FAKE_QT/qml/QtQuick/Effects/qmldir"
echo 'PASS  preflight diagnoses missing Qt QML runtime imports'

if VLC_PLUGIN_VERSION=4.0.0 "$HERE/scripts/install.sh" --yes >"$WORK/vlc4-sdk.log" 2>&1; then
    echo 'Installer accepted VLC 4 plugin headers with a VLC 3 runtime.' >&2
    exit 1
fi
grep -q 'VLC 3 plugin headers are required' "$WORK/vlc4-sdk.log"
echo 'PASS  preflight rejects mismatched VLC 4 plugin headers'

"$HERE/scripts/install.sh" --uninstall
unset QT_ROOT
SYSTEM_QT_TOO_OLD=1 "$HERE/scripts/install.sh" --default --yes
grep -q 'mirrors.ocf.berkeley.edu/qt/' "$AQT_LOG"
grep -q 'ftp.fau.de/qtproject/' "$AQT_LOG"
test "$(wc -l < "$AQT_LOG")" -eq 2
grep -Fq "export NEO_QT_ROOT=\"$TEST_HOME/Qt/6.8.3/gcc_64\"" "$HOME/.local/bin/vlc-neo"
echo 'PASS  an unavailable Qt mirror falls back to the next mirror and installs Qt per user'

"$HERE/scripts/install.sh" --uninstall
