# Contributing to VLC Neo

Thanks for helping improve VLC Neo. The project is an independent VLC 3 interface plugin. Its interface is implemented in Qt Quick/QML, and its C++ bridge talks to the VLC player.

## Before you start

- Read the [README](README.md) for supported platforms, build requirements, installation, current limitations and design credits.
- Check [open issues](https://github.com/AlexandreOlives/vlc-neo/issues) and pull requests to avoid duplicating work.
- For a substantial change, open an issue first to discuss the behavior and scope.
- UI work should follow the [Figma parity matrix](docs/figma-parity.md) and credit the original VLC Redesign by Juxtopposed. This is a community project and is not affiliated with Juxtopposed or VideoLAN.

## Build locally

The supported build requires VLC 3.0.x, Qt 6.6 or newer, CMake 3.21 or newer, Ninja, pkg-config and a C++17 compiler. The installer checks and offers to install missing system packages. If a suitable Qt is not available, it can install a separate Qt under `~/Qt`; it does not replace the system Qt.

```bash
git clone https://github.com/AlexandreOlives/vlc-neo.git
cd vlc-neo
scripts/install.sh
```

For an explicit local build, use the same CMake configuration as the installer:

```bash
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build
```

If Qt is installed outside the system prefix, set `CMAKE_PREFIX_PATH` (and `PKG_CONFIG_PATH` if needed) to that Qt installation before configuring. Do not replace or remove the distribution's Qt packages to build VLC Neo.

## Validate changes

Run the checks relevant to your change before opening a pull request:

```bash
scripts/smoke-test.sh
ctest --test-dir build --output-on-failure
scripts/screenshots.sh /path/to/media
```

The smoke test uses the installed VLC 3 core with Qt's offscreen platform and generates test media itself. It covers playback, queue state, subtitle behavior, hotkeys, VLC configuration, dark/light appearance, two window sizes, screenshot creation and theme persistence across launches. To use a per-user Qt installation, set `NEO_QT_ROOT="$HOME/Qt/6.8.3/gcc_64"` for the test command. Screenshot generation expects the Sintel media folder described in the script and writes images under `docs/screenshots/`. When UI output changes, inspect the generated images and include updated screenshots when they clarify the change.

CTest covers subtitle filename matching, persistent player state, and the QML-facing player facade through an injected fake backend. `PlayerStateStore` owns recents, resume points, bookmarks, folder presets, equalizer preference and linked subtitle folders; its test runs without VLC. The facade test also runs without VLC, so it can verify UI-facing state and command bounds without starting the VLC core.

For packaging or installer changes, also review the installer help and document any new supported package manager, environment variable or install behavior in the README. Do not run package installation or uninstall commands against a system you do not control.

## Pull requests

- Keep each pull request focused and describe the user-visible problem and the change.
- Include steps to reproduce or verify the behavior, plus screenshots for visual changes.
- Update the README or parity matrix when user-facing behavior, requirements or design coverage changes.
- Mention platform-specific behavior and any checks you could not run.
- Keep changes consistent with the existing GPL-3.0-or-later project license. Preserve attribution and third-party license notices when modifying bundled assets.

## Design and project identity

VLC Neo implements the community VLC redesign by Juxtopposed. Credit the design when presenting or distributing UI work. VLC and the VLC cone are VideoLAN trademarks; this project is independent and is not endorsed by VideoLAN. See the README for the full design and trademark notes.
