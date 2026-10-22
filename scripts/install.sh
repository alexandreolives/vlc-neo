#!/usr/bin/env bash
# Build and install the Neo interface for the current user. System VLC is untouched.
#
#   scripts/install.sh                 install; use it with `vlc-neo`
#   scripts/install.sh --default       also make Neo the interface of plain `vlc`
#   scripts/install.sh --default --yes  install missing dependencies without prompting
#   scripts/install.sh --uninstall     remove VLC Neo
#   scripts/install.sh --help          show installer options
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
PLUGIN_ROOT="$HOME/.local/lib/vlc-neo/plugins"
BIN="$HOME/.local/bin"
APPS="$HOME/.local/share/applications"
SYSTEM_VLC="${SYSTEM_VLC:-/usr/bin/vlc}"
QT_ROOT="${QT_ROOT:-}"
SYSTEM_DESKTOP="${SYSTEM_DESKTOP:-/usr/share/applications/vlc.desktop}"
BUILD_DIR="${BUILD_DIR:-$HERE/build}"
MARK="# vlc-neo-managed"

mode="install"
assume_yes=0
OS_RELEASE_FILE="${OS_RELEASE_FILE:-/etc/os-release}"
for arg in "$@"; do
    case "$arg" in
        --default) mode="--default" ;;
        --uninstall) mode="--uninstall" ;;
        --yes) assume_yes=1 ;;
        --help)
            echo "Usage: scripts/install.sh [--default] [--yes] [--uninstall]"
            echo "  --default  Make Neo the default interface for VLC."
            echo "  --yes      Install missing packages and Qt without prompting."
            echo "  --uninstall Remove VLC Neo."
            echo "Environment: QT_ROOT, VLC_NEO_QT_VERSION, VLC_NEO_QT_MIRROR, BUILD_DIR."
            exit 0
            ;;
        *) echo "Unknown option: $arg" >&2; exit 2 ;;
    esac
done

die() {
    echo "VLC Neo installer: $*" >&2
    exit 1
}

confirm() {
    local prompt="$1" answer="" tty_fd
    if [ "$assume_yes" -eq 1 ]; then
        return 0
    fi
    if ! { exec {tty_fd}<>/dev/tty; } 2>/dev/null; then
        die "$prompt Run this installer in a terminal, or pass --yes."
    fi
    if ! read -r -p "$prompt [Y/n] " answer <&"$tty_fd"; then
        exec {tty_fd}>&-
        die "$prompt Run this installer in a terminal, or pass --yes."
    fi
    exec {tty_fd}>&-
    case "$answer" in
        [nN]|[nN][oO]) return 1 ;;
        *) return 0 ;;
    esac
}

version_at_least() {
    local actual="$1" required="$2"
    [ "$(printf '%s\n%s\n' "$required" "$actual" | sort -V | head -n 1)" = "$required" ]
}

package_is_installed() {
    case "$PACKAGE_MANAGER" in
        apt) dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'install ok installed' ;;
        pacman) pacman -Qq "$1" >/dev/null 2>&1 ;;
        dnf) rpm -q "$1" >/dev/null 2>&1 ;;
    esac
}

install_system_dependencies() {
    local package missing=()
    case " ${ID:-} ${ID_LIKE:-} " in
        *debian*|*ubuntu*)
            PACKAGE_MANAGER="apt"
            SYSTEM_PACKAGES=(build-essential cmake ninja-build pkg-config python3-venv libgl1-mesa-dev vlc libvlccore-dev libtag1-dev libsqlite3-dev)
            # QML modules are split into packages on Debian-family systems.
            for package in qml6-module-qtquick qml6-module-qtquick-controls \
                qml6-module-qtquick-dialogs qml6-module-qtquick-layouts \
                qml6-module-qtquick-window qml6-module-qt-labs-folderlistmodel \
                qml6-module-qtcore qml6-module-qtquick-shapes qml6-module-qtquick-effects; do
                if apt-cache show "$package" >/dev/null 2>&1; then
                    SYSTEM_PACKAGES+=("$package")
                fi
            done
            ;;
        *arch*)
            PACKAGE_MANAGER="pacman"
            SYSTEM_PACKAGES=(base-devel cmake ninja pkgconf python mesa vlc libvlc taglib sqlite)
            ;;
        *fedora*|*rhel*)
            PACKAGE_MANAGER="dnf"
            SYSTEM_PACKAGES=(gcc-c++ cmake ninja-build pkgconf-pkg-config python3 mesa-libGL-devel vlc vlc-devel taglib-devel sqlite-devel)
            ;;
        *)
            die "Unsupported package manager for $ID. Install a C++17 compiler, CMake 3.21+, Ninja, pkg-config, Python venv, VLC 3 and VLC plugin headers manually."
            ;;
    esac

    for package in "${SYSTEM_PACKAGES[@]}"; do
        package_is_installed "$package" || missing+=("$package")
    done
    if [ "${#missing[@]}" -eq 0 ]; then
        return
    fi

    echo "Missing system dependencies: ${missing[*]}"
    confirm "Install these packages using $PACKAGE_MANAGER?" || die "Dependency installation cancelled."

    if [ "$(id -u)" -eq 0 ]; then
        ROOT_CMD=()
    else
        command -v sudo >/dev/null 2>&1 || die "sudo is required to install system packages."
        ROOT_CMD=(sudo)
    fi
    case "$PACKAGE_MANAGER" in
        apt)
            "${ROOT_CMD[@]}" apt-get update
            "${ROOT_CMD[@]}" apt-get install -y "${missing[@]}"
            ;;
        pacman) "${ROOT_CMD[@]}" pacman -S --needed "${missing[@]}" ;;
        dnf) "${ROOT_CMD[@]}" dnf install -y "${missing[@]}" ;;
    esac
}

qt_pkgconfig_ok() {
    local pkg_path="$1" module
    local modules=(Qt6Concurrent Qt6Core Qt6DBus Qt6Gui Qt6Network Qt6Qml Qt6Quick Qt6QuickControls2 Qt6Svg)
    for module in "${modules[@]}"; do
        PKG_CONFIG_PATH="$pkg_path" pkg-config --exists "$module" || return 1
    done
    PKG_CONFIG_PATH="$pkg_path" pkg-config --atleast-version=6.6 Qt6Core
}

qt_qml_imports_ok() {
    local qt_root="$1" import module_dir root prefix paths
    local imports=(QtCore QtQuick QtQuick/Controls/Basic QtQuick/Dialogs QtQuick/Effects \
        QtQuick/Layouts QtQuick/Shapes QtQuick/Window Qt/labs/folderlistmodel)
    local roots=() extra_roots=()
    if [ -n "$qt_root" ]; then
        # A private Qt installation must provide its own import plugins; the
        # system Qt tree may have a different version and ABI.
        roots+=("$qt_root/qml")
    else
        prefix="$(pkg-config --variable=prefix Qt6Core 2>/dev/null || true)"
        [ -z "$prefix" ] || roots+=("$prefix/qml" "$prefix/lib/qt6/qml" "$prefix/lib64/qt6/qml")
        roots+=(/usr/lib/qt6/qml /usr/lib64/qt6/qml /usr/local/lib/qt6/qml)
        if command -v gcc >/dev/null 2>&1; then
            roots+=("/usr/lib/$(gcc -dumpmachine 2>/dev/null)/qt6/qml")
        fi
    fi
    for paths in "${QT_QML_IMPORT_PATH:-}" "${QML2_IMPORT_PATH:-}" "${QML_IMPORT_PATH:-}"; do
        IFS=: read -r -a extra_roots <<< "$paths"
        roots+=("${extra_roots[@]}")
    done
    for import in "${imports[@]}"; do
        module_dir=""
        for root in "${roots[@]}"; do
            [ -n "$root" ] && [ -f "$root/$import/qmldir" ] && module_dir="$root/$import" && break
        done
        if [ -z "$module_dir" ]; then
            echo "VLC Neo requires the Qt QML module '$import'; install the matching Qt 6 QML runtime package." >&2
            return 1
        fi
    done
}

use_qt_root() {
    local root="$1" pkg_path
    [ -f "$root/lib/cmake/Qt6/Qt6Config.cmake" ] || return 1
    pkg_path="$root/lib/pkgconfig:$root/lib64/pkgconfig:${PKG_CONFIG_PATH:-}"
    qt_pkgconfig_ok "$pkg_path" || return 1
    qt_qml_imports_ok "$root" || return 1
    QT_ROOT="$root"
    export QT_ROOT
    export PKG_CONFIG_PATH="$pkg_path"
    export CMAKE_PREFIX_PATH="$QT_ROOT${CMAKE_PREFIX_PATH:+:$CMAKE_PREFIX_PATH}"
    export LD_LIBRARY_PATH="$QT_ROOT/lib:$QT_ROOT/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
}

bootstrap_aqt() {
    if command -v aqt >/dev/null 2>&1; then
        AQT_BIN="$(command -v aqt)"
        return
    fi
    local venv="$HOME/.local/share/vlc-neo/aqt-venv"
    if [ ! -x "$venv/bin/aqt" ]; then
        echo "Installing aqtinstall in $venv to provide Qt 6.8.3."
        mkdir -p "$(dirname "$venv")"
        python3 -m venv "$venv" || die "Could not create the aqtinstall environment; install python3-venv and retry."
        "$venv/bin/pip" install --disable-pip-version-check aqtinstall || die "Could not install aqtinstall; check your Python package index/network."
    fi
    AQT_BIN="$venv/bin/aqt"
}

install_qt_from_mirror() {
    local mirror
    bootstrap_aqt
    local mirrors=()
    [ -z "${VLC_NEO_QT_MIRROR:-}" ] || mirrors+=("$VLC_NEO_QT_MIRROR")
    mirrors+=(
        "https://mirrors.ocf.berkeley.edu/qt/"
        "https://ftp.fau.de/qtproject/"
        "https://mirrors.dotsrc.org/qtproject"
        "https://download.qt.io/"
    )
    echo "Qt 6.6 or newer was not found. VLC Neo will install Qt ${VLC_NEO_QT_VERSION:-6.8.3} in ~/Qt."
    confirm "Download the Qt development files?" || die "Qt installation cancelled."
    for mirror in "${mirrors[@]}"; do
        echo "Trying Qt mirror: $mirror"
        if "$AQT_BIN" install-qt linux desktop "${VLC_NEO_QT_VERSION:-6.8.3}" linux_gcc_64 \
            --outputdir "$HOME/Qt" --timeout 30 --base "$mirror" \
            --archives qtbase qtdeclarative qtsvg icu; then
            QT_ROOT="$HOME/Qt/${VLC_NEO_QT_VERSION:-6.8.3}/gcc_64"
            use_qt_root "$QT_ROOT" || die "Qt installed, but a required development module or QML runtime import is missing."
            return
        fi
        echo "Mirror failed; trying the next mirror." >&2
    done
    die "Could not download Qt from any configured mirror. Set VLC_NEO_QT_MIRROR to a working Qt mirror and retry."
}

remove_default() {
    for f in "$BIN/vlc" "$APPS/vlc.desktop"; do
        if [ -f "$f" ] && grep -q "$MARK" "$f"; then rm -f "$f"; fi
    done
    rm -f "$APPS/vlc-classic.desktop"
}

if [ "$mode" = "--uninstall" ]; then
    remove_default
    rm -f "$BIN/vlc-neo" "$APPS/vlc-neo.desktop" "$PLUGIN_ROOT/gui/libneo_plugin.so"
    update-desktop-database "$APPS" 2>/dev/null || true
    echo "Removed. Settings stay in ~/.config/vlc-neo (delete it if you like)."
    exit 0
fi

source "$OS_RELEASE_FILE"
install_system_dependencies

if ! command -v cmake >/dev/null 2>&1; then die "CMake was not installed."; fi
cmake_version="$(cmake --version | sed -n '1s/[^0-9]*//p')"
version_at_least "$cmake_version" 3.21 || die "CMake 3.21 or newer is required; found $cmake_version."
command -v pkg-config >/dev/null 2>&1 || die "pkg-config was not installed."
command -v g++ >/dev/null 2>&1 || command -v c++ >/dev/null 2>&1 || die "A C++17 compiler was not installed."

NINJA_BIN=""
for candidate in "$(command -v ninja 2>/dev/null || true)" /usr/bin/ninja /usr/local/bin/ninja; do
    if [ -n "$candidate" ] && [ -x "$candidate" ] && "$candidate" --version >/dev/null 2>&1; then
        NINJA_BIN="$candidate"
        break
    fi
done
[ -n "$NINJA_BIN" ] || die "Ninja was not installed or cannot run."

if [ -n "$QT_ROOT" ]; then
    use_qt_root "$QT_ROOT" || die "QT_ROOT=$QT_ROOT is missing Qt 6.6+ development modules."
elif ! qt_pkgconfig_ok "${PKG_CONFIG_PATH:-}"; then
    qt_found=0
    if [ -d "$HOME/Qt" ]; then
        while IFS= read -r candidate; do
            if use_qt_root "$candidate"; then qt_found=1; break; fi
        done < <(printf '%s\n' "$HOME"/Qt/*/gcc_64 | sort -rV)
    fi
    if [ "$qt_found" -eq 0 ]; then
        install_qt_from_mirror
    fi
elif ! qt_qml_imports_ok "$QT_ROOT"; then
    install_qt_from_mirror
fi

SYSTEM_VLC="${SYSTEM_VLC:-/usr/bin/vlc}"
[ -x "$SYSTEM_VLC" ] || die "VLC was not found at $SYSTEM_VLC."
vlc_version="$("$SYSTEM_VLC" --version | sed -n '1p')"
[[ "$vlc_version" =~ VLC\ version\ 3\.0\. ]] || die "VLC 3.0.x is required; found: $vlc_version"
pkg-config --exists 'vlc-plugin >= 3.0.0' || die "VLC plugin headers are unavailable. Install the matching VLC development package."
vlc_plugin_version="$(pkg-config --modversion vlc-plugin)"
[[ "$vlc_plugin_version" =~ ^3\. ]] || die "VLC 3 plugin headers are required to match the VLC runtime; found $vlc_plugin_version."

QT_CMAKE_ARGS=(-DQt6_DIR=)
if [ -n "$QT_ROOT" ]; then
    QT_CMAKE_ARGS=(-DQt6_DIR="$QT_ROOT/lib/cmake/Qt6")
fi
cmake -S "$HERE" -B "$BUILD_DIR" -G Ninja -DCMAKE_MAKE_PROGRAM="$NINJA_BIN" \
    -DCMAKE_BUILD_TYPE=Release "${QT_CMAKE_ARGS[@]}" >/dev/null
cmake --build "$BUILD_DIR"
install -Dm755 "$BUILD_DIR/libneo_plugin.so" "$PLUGIN_ROOT/gui/libneo_plugin.so"

# `vlc-neo`: always the Neo interface.
install -Dm755 /dev/stdin "$BIN/vlc-neo" <<SH
#!/usr/bin/env bash
$MARK
# VLC with the Neo interface. Plugins and settings are shared with normal VLC.
export VLC_PLUGIN_PATH="$PLUGIN_ROOT\${VLC_PLUGIN_PATH:+:\$VLC_PLUGIN_PATH}"
export NEO_QT_ROOT="$QT_ROOT"
if [ -n "\$NEO_QT_ROOT" ]; then
    export LD_LIBRARY_PATH="\$NEO_QT_ROOT/lib\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
    export QML_IMPORT_PATH="\$NEO_QT_ROOT/qml\${QML_IMPORT_PATH:+:\$QML_IMPORT_PATH}"
fi
exec "$SYSTEM_VLC" -I neo "\$@"
SH

if [ "$mode" = "--default" ]; then
    mkdir -p "$APPS"
    # `vlc` in ~/.local/bin (ahead of /usr/bin in PATH): Neo unless an interface is
    # requested explicitly, or the saved skins2 preference enables VLC skins.
    install -Dm755 /dev/stdin "$BIN/vlc" <<SH
#!/usr/bin/env bash
$MARK
export VLC_PLUGIN_PATH="$PLUGIN_ROOT\${VLC_PLUGIN_PATH:+:\$VLC_PLUGIN_PATH}"
export NEO_QT_ROOT="$QT_ROOT"
if [ -n "\$NEO_QT_ROOT" ]; then
    export LD_LIBRARY_PATH="\$NEO_QT_ROOT/lib\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
    export QML_IMPORT_PATH="\$NEO_QT_ROOT/qml\${QML_IMPORT_PATH:+:\$QML_IMPORT_PATH}"
fi
for arg in "\$@"; do
    case "\$arg" in
        -I|-I*|--intf|--intf=*|-H|--help|--version|--list*) exec "$SYSTEM_VLC" "\$@" ;;
    esac
done
vlc_config="\${XDG_CONFIG_HOME:-\$HOME/.config}/vlc/vlcrc"
if [ -r "\$vlc_config" ] && grep -Eq '^[[:space:]]*intf=skins2([[:space:]]|$)' "\$vlc_config"; then
    exec "$SYSTEM_VLC" "\$@"
fi
exec "$SYSTEM_VLC" -I neo "\$@"
SH
    # Same id as the system entry, so launchers, "Open with" and existing
    # file associations to vlc.desktop now open Neo.
    if [ -f "$SYSTEM_DESKTOP" ]; then
        { echo "$MARK"; sed -e "s#^Exec=.*#Exec=$BIN/vlc --started-from-file %U#" \
                            -e "s#^TryExec=.*#TryExec=$BIN/vlc#" "$SYSTEM_DESKTOP"; } > "$APPS/vlc.desktop"
    fi
    install -Dm644 /dev/stdin "$APPS/vlc-classic.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=VLC (Classic interface)
Comment=VLC media player with its original Qt interface
Exec=$SYSTEM_VLC -I qt --started-from-file %U
Icon=vlc
Terminal=false
Categories=AudioVideo;Player;
MimeType=video/mp4;video/x-matroska;video/webm;audio/mpeg;
DESKTOP
    rm -f "$APPS/vlc-neo.desktop"   # vlc.desktop is Neo now; avoid a duplicate entry
else
    remove_default
    install -Dm644 /dev/stdin "$APPS/vlc-neo.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=VLC (Neo)
GenericName=Media Player
Comment=VLC media player with the redesigned Neo interface
Exec=$BIN/vlc-neo --started-from-file %U
TryExec=$BIN/vlc-neo
Icon=vlc
Terminal=false
Categories=AudioVideo;Player;Recorder;
MimeType=video/mp4;video/x-matroska;video/webm;video/x-msvideo;video/quicktime;video/mpeg;video/x-flv;video/ogg;audio/mpeg;audio/flac;audio/ogg;audio/x-wav;audio/mp4;audio/x-mpegurl;application/x-mpegurl;
Keywords=Player;Capture;DVD;Audio;Video;Server;Broadcast;
StartupWMClass=vlc-neo
DESKTOP
fi
update-desktop-database "$APPS" 2>/dev/null || true

if [ "$mode" = "--default" ]; then
    echo "Installed as the default VLC interface. Classic Qt UI: 'vlc -I qt' or 'VLC (Classic interface)'. Enable a custom skin in Neo Preferences to use skins2 from 'vlc'."
else
    echo "Installed. Run: vlc-neo <file>   (normal 'vlc' still opens the classic UI)"
fi
