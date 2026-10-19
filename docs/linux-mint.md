# Linux Mint build and install notes

VLC Neo targets Linux Mint 22.x on x86-64. Mint 22.x uses the Ubuntu 24.04 package base. Its repository Qt 6 packages may be older than VLC Neo's Qt 6.6 minimum, so `scripts/install.sh` checks the version and installs a separate Qt under `~/Qt` when needed. It does not replace the system Qt packages.

## Build

The installer checks system build dependencies and VLC 3 development headers. It asks before installing missing apt packages. When system Qt is too old, it uses `aqtinstall` to provision Qt 6.8.3 in the user's home directory and tries the configured Qt mirrors in sequence.

```bash
scripts/install.sh
```

To select a different Qt installation or version:

```bash
QT_ROOT="$HOME/Qt/6.8.3/gcc_64" scripts/install.sh
VLC_NEO_QT_VERSION=6.8.3 scripts/install.sh
```

The system Qt remains available to other applications. The Neo launchers add the selected Qt library and QML paths only when launching VLC Neo.

For a manual build with an already installed user Qt:

```bash
export QT_ROOT="$HOME/Qt/6.8.3/gcc_64"
export PKG_CONFIG_PATH="$QT_ROOT/lib/pkgconfig:$QT_ROOT/lib64/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
export CMAKE_PREFIX_PATH="$QT_ROOT${CMAKE_PREFIX_PATH:+:$CMAKE_PREFIX_PATH}"
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DQt6_DIR="$QT_ROOT/lib/cmake/Qt6"
cmake --build build
```

## Verify default install and classic restore

Run the isolated installer lifecycle check first:

```bash
scripts/test-installer.sh
```

This creates a disposable home directory and stubs the package manager, Qt metadata, build output and VLC executable. It checks the default launcher, explicit classic-interface passthrough, removal of user launchers and preservation of the system desktop entry. It does not compile the plugin or test real playback.

For an end-to-end run after a successful build, record the system Qt package version, install with `scripts/install.sh --default`, launch a file through the new `vlc` command, and then run `scripts/install.sh --uninstall`. Confirm that `~/.local/bin/vlc` and the user override at `~/.local/share/applications/vlc.desktop` are removed, while `/usr/bin/vlc` and `/usr/share/applications/vlc.desktop` remain intact. Compare the system Qt package version before and after; Qt under `~/Qt` is a per-user install and is retained by uninstall.

## Known verification boundary

On the current Linux Mint 22.3 workstation, the Qt 6.8.3 installation under `~/Qt` reports all six required Qt pkg-config modules at 6.8.3. The Mint/Ubuntu package candidate for `qt6-base-dev` is 6.4.2, below the project minimum, and that system package is not installed. The isolated `scripts/test-installer.sh` lifecycle check passes.

A full compile was attempted but could not configure on this workstation: `ninja-build` and `libvlccore-dev` are not installed, and `pkg-config` cannot find `vlc-plugin`. No system packages were installed as part of this check. The installer should offer to install missing apt packages, but its real package-install path and a clean end-to-end Mint install remain unverified. Report the exact Mint release, Qt version, and whether the check used a clean or existing installation when filing a compatibility issue. Do not claim a release is verified based only on its Ubuntu base or a successful build on another distribution.
