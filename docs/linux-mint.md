# Linux Mint build and install notes

VLC Neo targets Linux Mint 22.x on x86-64. Mint 22.x uses the Ubuntu 24.04 package base. Its repository Qt 6 packages may be older than VLC Neo's Qt 6.6 minimum, so `scripts/install.sh` checks the version and installs a separate Qt under `~/Qt` when needed. It does not replace the system Qt packages.

## Build

The installer checks system build dependencies, VLC 3 development headers, TagLib and SQLite. It asks before installing missing apt packages. When system Qt is too old, it uses `aqtinstall` to provision Qt 6.8.3 in the user's home directory and tries the configured Qt mirrors in sequence. If that per-user Qt already contains every required QML import, the installer does not also propose the split system `qml6-module-*` packages.

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

The headless test wrapper also accepts `NEO_QT_ROOT` (or `QT_ROOT`) so it can
load a plugin linked to the separate Qt without changing the system library
path globally:

```bash
NEO_QT_ROOT="$HOME/Qt/6.8.3/gcc_64" scripts/smoke-test.sh
```

## Verify default install and classic restore

Run the isolated installer lifecycle check first:

```bash
scripts/test-installer.sh
```

This creates a disposable home directory and stubs the package manager, Qt metadata, build output and VLC executable. It checks the default launcher, explicit classic-interface passthrough, removal of user launchers and preservation of the system desktop entry. It does not compile the plugin or test real playback.

For an end-to-end run after a successful build, record the system Qt package version, install with `scripts/install.sh --default`, launch a file through the new `vlc` command, and then run `scripts/install.sh --uninstall`. Confirm that `~/.local/bin/vlc` and the user override at `~/.local/share/applications/vlc.desktop` are removed, while `/usr/bin/vlc` and `/usr/share/applications/vlc.desktop` remain intact. Compare the system Qt package version before and after; Qt under `~/Qt` is a per-user install and is retained by uninstall.

## CI coverage and known verification boundary

The `mint-22-package-base` job in [CI](../.github/workflows/ci.yml) runs on a
hosted Ubuntu 24.04 runner, the package base used by Linux Mint 22. It installs
the distribution Qt 6 packages first, then exercises the installer, separate
Qt provisioning, build, playback smoke test and uninstall. It confirms the
distribution Qt package version is unchanged. This is package-base coverage;
it does not replace a check on a clean Linux Mint installation. The latest
cross-distro run passed the Mint and Arch jobs with 14/14 CTests and 880/880
smoke assertions on each, including Mint install/uninstall checks that preserve
system Qt and the VLC desktop entry: [workflow run 40945069510](https://github.com/alexandreolives/vlc-neo/actions/runs/40945069510).

On the Linux Mint 22.3 workstation, all nine required Qt pkg-config modules report 6.8.3 when `~/Qt/6.8.3/gcc_64/lib/pkgconfig` is selected, and all required QML imports are present. The isolated `scripts/test-installer.sh` check passes, including simulated dependency installation for Debian, Arch and Fedora, Qt preflight checks and fallback from the Berkeley mirror to FAU. The installed Neo plugin hash matches the current build artifact. The existing build's CMake cache points to this checkout.

A fresh compile and full system-dependency install have not been run on this workstation. The installer still needs `ninja-build`, `libgl1-mesa-dev`, `libvlccore-dev` and `libtag1-dev`; the `vlc-plugin` pkg-config module is consequently unavailable. Installing those packages requires interactive `sudo` authentication, which was not available during this check. No system packages were installed. CI and the isolated installer test pass, but a clean end-to-end install on Mint itself remains unverified. Report the exact Mint release, Qt version, and whether the check used a clean or existing installation when filing a compatibility issue. Do not claim a release is verified based only on its Ubuntu base or a successful build on another distribution.
