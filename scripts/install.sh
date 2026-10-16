#!/usr/bin/env bash
# Build and install the Neo interface for the current user. System VLC is untouched.
#
#   scripts/install.sh            install; use it with `vlc-neo`
#   scripts/install.sh --default  also make Neo the interface of plain `vlc`
#                                 (terminal, launcher, file manager "Open with VLC")
#   scripts/install.sh --uninstall
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
PLUGIN_ROOT="$HOME/.local/lib/vlc-neo/plugins"
BIN="$HOME/.local/bin"
APPS="$HOME/.local/share/applications"
SYSTEM_VLC="${SYSTEM_VLC:-/usr/bin/vlc}"
SYSTEM_DESKTOP="/usr/share/applications/vlc.desktop"
MARK="# vlc-neo-managed"

mode="${1:-install}"

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

cmake -S "$HERE" -B "$HERE/build" -G Ninja -DCMAKE_BUILD_TYPE=Release >/dev/null
cmake --build "$HERE/build"
install -Dm755 "$HERE/build/libneo_plugin.so" "$PLUGIN_ROOT/gui/libneo_plugin.so"

# `vlc-neo`: always the Neo interface.
install -Dm755 /dev/stdin "$BIN/vlc-neo" <<SH
#!/usr/bin/env bash
$MARK
# VLC with the Neo interface. Plugins and settings are shared with normal VLC.
export VLC_PLUGIN_PATH="$PLUGIN_ROOT\${VLC_PLUGIN_PATH:+:\$VLC_PLUGIN_PATH}"
exec "$SYSTEM_VLC" -I neo "\$@"
SH

if [ "$mode" = "--default" ]; then
    # `vlc` in ~/.local/bin (ahead of /usr/bin in PATH): Neo unless an interface is
    # requested explicitly (`vlc -I qt`, `vlc --intf dummy`, --help, ...).
    install -Dm755 /dev/stdin "$BIN/vlc" <<SH
#!/usr/bin/env bash
$MARK
export VLC_PLUGIN_PATH="$PLUGIN_ROOT\${VLC_PLUGIN_PATH:+:\$VLC_PLUGIN_PATH}"
for arg in "\$@"; do
    case "\$arg" in
        -I|-I*|--intf|--intf=*|-H|--help|--version|--list*) exec "$SYSTEM_VLC" "\$@" ;;
    esac
done
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
    echo "Installed as the default VLC interface. Classic UI: 'vlc -I qt' or 'VLC (Classic interface)'."
else
    echo "Installed. Run: vlc-neo <file>   (normal 'vlc' still opens the classic UI)"
fi
