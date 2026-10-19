<h1 align="center">VLC Neo</h1>

<p align="center">
  <strong>A modern interface for VLC media player, packaged as a real VLC plugin.</strong><br>
  Based on the community <em>VLC Redesign</em> by Juxtopposed. VLC itself stays untouched and keeps updating normally.
</p>

<p align="center">
  <a href="LICENSE"><img alt="License: GPL v3+" src="https://img.shields.io/badge/license-GPL--3.0--or--later-blue"></a>
  <img alt="VLC 3.0" src="https://img.shields.io/badge/VLC-3.0.x-orange">
  <img alt="Qt 6" src="https://img.shields.io/badge/Qt-6.6%2B-41cd52">
  <img alt="Linux" src="https://img.shields.io/badge/platform-Linux%20(Wayland%20%26%20X11)-lightgrey">
  <a href="../../actions/workflows/ci.yml"><img alt="CI" src="../../actions/workflows/ci.yml/badge.svg"></a>
</p>

<p align="center">
  <img src="docs/screenshots/player.webp" alt="VLC Neo: the redesigned VLC media player interface playing a video with subtitles" width="100%">
</p>

VLC Neo replaces the classic VLC interface with a clean, modern one. It is not a
skin and not a fork. It is an **interface plugin** that VLC 3 loads like any of
its own modules. Playback, codecs, hardware decoding, hotkeys and every setting
in `vlcrc` are still handled by VLC itself.

- **Your VLC stays your VLC.** Updates from your package manager keep working.
  Nothing in `/usr` is changed.
- **Built from a real design.** It follows the Figma file and video by
  [Juxtopposed](https://www.youtube.com/@juxtopposed), "I Redesigned VLC After 25 Years".
- **Fixes the things people complain about.** It makes subtitles, presets,
  resume, the settings maze and the hidden features easier to reach.

## Contents

- [Design credits](#design-credits)
- [Features](#features)
- [Screenshots](#screenshots)
- [Install](#install)
- [Linux Mint compatibility](docs/linux-mint.md)
- [Figma parity matrix](docs/figma-parity.md)
- [Contributing](CONTRIBUTING.md)
- [Usage and shortcuts](#usage-and-shortcuts)
- [How it works](#how-it-works)
- [Updating VLC](#updating-vlc)
- [Development and tests](#development-and-tests)
- [Roadmap](#roadmap)
- [License and trademarks](#license-and-trademarks)

## Design credits

The interface is an implementation of the **VLC Redesign** by
**Juxtopposed**:

- **Video:** [I Redesigned VLC After 25 Years](https://www.youtube.com/watch?v=ERFeOgqk324)
- **Figma file:** [VLC Redesign (Community)](https://www.figma.com/design/5UEUReDQz2dQjwoQDHY5z9/VLC-Redesign--Community-)
- **Designer:** [Juxtopposed on YouTube](https://www.youtube.com/@juxtopposed)

<p align="center">
  <a href="https://www.youtube.com/watch?v=ERFeOgqk324">
    <img src="https://img.youtube.com/vi/ERFeOgqk324/maxresdefault.jpg" alt="I Redesigned VLC After 25 Years, by Juxtopposed (YouTube)" width="640">
  </a>
</p>

The colours, layout, control bar, sidebar, settings structure, onboarding and
customization screen come from that work. In the video, the designer said the
redesign would be open source and free to use, and asked viewers to support the
VLC project. This repository follows that spirit. It is an independent community
project, not made by Juxtopposed or VideoLAN.

If you like VLC, consider [donating to VideoLAN](https://www.videolan.org/contribute.html#money).

## Features

### Player
- The look from the Figma file: neutral greys, VLC orange, slightly rounded
  rectangles, and two-tone icons.
- The play button stays on the left. It is larger, and previous/next sit around it.
- A **thick seek bar** with a hover time preview and bookmark ticks.
- A **cone-shaped volume slider** that runs from green to orange.
- Fullscreen, **picture-in-picture** and window buttons are in the top bar. The
  media title stays reachable in fullscreen.
- In fullscreen and in **Hide UI** mode (Ctrl+H), the top and bottom bars appear
  only when the pointer is near them, and disappear as soon as it leaves.
- **Subtitle and audio buttons** sit on the bottom right. Each opens a quick
  track list. The audio list also switches the output device (headphones or
  speakers) without leaving VLC.
- **One clean right-click menu** instead of duplicated menus.
- **Every hotkey shows the key that was pressed** ("F · Fullscreen"), so an
  accidental key press is easy to undo.
- A **"Continue from 00:12:30?"** prompt appears right above the controls, where
  you can see it.

### Sidebar (replaces "Adjustments and Effects")
Everything here applies live while the video keeps playing.
- **Subtitles:**
  - track and add file
  - delay slider plus ±50 ms / ±0.5 s buttons
  - size as named steps or a precise percentage
  - position, font, colour, outline and background box
  - default subtitle language
- **Audio:** track, output device, delay, equalizer presets and default audio language.
- **Video:** aspect ratio, fit or fill/crop, rotate and flip, deinterlace, snapshot.
- **Playback:** speed, repeat one or all, shuffle, sleep timer, frame by frame and media info.
- **Marks:** bookmarks (Ctrl+B) and chapters.
- **Show presets:** save the subtitle delay, audio delay, subtitle size and
  chosen tracks for a folder. Every episode in that folder then gets them
  automatically. Binge watching without redoing settings every episode.

### Subtitles for a whole season
Point it at a folder of subtitles, for example an extracted zip. Each episode
gets the right file **by episode number** (`S01E05`, `1x05`, `- 05 -`), even
when the file names do not match the videos. It is remembered for future
episodes. A shortcut to search OpenSubtitles for the current title is included.

### Library and queue
- A **compact library next to the video** (L). It has places, pinned folders,
  recent files, a clickable address bar, sorting, play or queue a whole folder,
  and drag-and-drop to the queue.
- **Queue** (Q): see what plays next. It shows the current item, and lets you
  remove items, clear the queue, toggle repeat and shuffle, save the queue as
  `.m3u8`, and drop files onto it.
- A **home screen** with "Continue" items instead of a blank traffic cone.
- **Network streams:** paste a URL or an online `.m3u`. Playlists, such as
  public IPTV lists, become a queue automatically.
- A **music view** with large cover art for audio files.

### Settings, onboarding and customization
- **Preferences regrouped into 13 human categories:**
  - General, Interface, Privacy, Controls
  - Playback, Video, Audio, Subtitles
  - Library, Network, Performance, Recording, Extensions

  Basic options come first and advanced ones further down the same page. Each
  has an **info icon** that explains it.
- Every option writes to the real `vlcrc`. Numeric codes become words. For
  example, the subtitle auto-detection "fuzzy" level is shown as plain choices.
- **Dark, light or system theme**, plus an **accent colour** picker that replaces the orange.
- **First-run onboarding:** welcome screen, theme and colour, basic shortcuts.
- **Customize Player:** drag buttons onto the control bar, reorder them, or drag
  them out to remove them.

## Screenshots

> Screenshots use the [Sintel](https://durian.blender.org/) trailer,
> © Blender Foundation, licensed CC BY 3.0. They are regenerated by
> `scripts/screenshots.sh`.

**Live sidebar: subtitles and video**
<p>
  <img src="docs/screenshots/sidebar-subtitles.webp" alt="VLC Neo subtitle sidebar with delay slider, size and style options" width="49%">
  <img src="docs/screenshots/sidebar-video.webp" alt="VLC Neo video sidebar with aspect ratio, rotate and deinterlace" width="49%">
</p>

**Track picker and library with the queue**
<p>
  <img src="docs/screenshots/tracks-popup.webp" alt="Subtitle and audio track picker opened from the VLC Neo control bar" width="49%">
  <img src="docs/screenshots/library-queue.webp" alt="Compact media library next to the video and the play queue" width="49%">
</p>

**Right-click menu and main menu**
<p>
  <img src="docs/screenshots/context-menu.webp" alt="Clean VLC Neo right-click menu" width="49%">
  <img src="docs/screenshots/main-menu.webp" alt="VLC Neo main menu with open file, network stream and recent media" width="49%">
</p>

**Preferences**
<p>
  <img src="docs/screenshots/settings.webp" alt="VLC Neo preferences, subtitles category" width="49%">
  <img src="docs/screenshots/settings-performance.webp" alt="VLC Neo preferences, performance and hardware decoding" width="49%">
</p>

**Customize the control bar and add subtitles to a whole folder**
<p>
  <img src="docs/screenshots/customize.webp" alt="Drag and drop control bar customization in VLC Neo" width="49%">
  <img src="docs/screenshots/add-subtitles.webp" alt="Add subtitles to a single file or to every episode in a folder" width="49%">
</p>

**Hide UI mode and light theme with a custom accent**
<p>
  <img src="docs/screenshots/hidden-ui.webp" alt="Hide UI mode: only the video, controls appear near the edges" width="49%">
  <img src="docs/screenshots/light-theme.webp" alt="VLC Neo light theme with a blue accent colour" width="49%">
</p>

**Music view and home screen**
<p>
  <img src="docs/screenshots/music.webp" alt="Music playback view with large cover art" width="49%">
  <img src="docs/screenshots/home.webp" alt="Home screen with continue watching" width="49%">
</p>

**Onboarding**
<p>
  <img src="docs/screenshots/onboarding-welcome.webp" alt="VLC Neo onboarding welcome screen" width="32%">
  <img src="docs/screenshots/onboarding-theme.webp" alt="Onboarding: choose theme and accent colour" width="32%">
  <img src="docs/screenshots/onboarding-shortcuts.webp" alt="Onboarding: basic keyboard shortcuts" width="32%">
</p>

**Playback sidebar and all keyboard shortcuts**
<p>
  <img src="docs/screenshots/sidebar-playback.webp" alt="Playback sidebar: speed, repeat, sleep timer, media info" width="49%">
  <img src="docs/screenshots/shortcuts.webp" alt="All VLC Neo keyboard shortcuts" width="49%">
</p>

## Install

### Requirements

- **VLC 3.0.x** with its plugin headers.
- **Qt 6.6 or newer:** Base, Declarative (Qt Quick), Svg.
- **Build tools:** CMake 3.21+, Ninja, a C++17 compiler, pkg-config.

The installer checks for the required packages and asks before installing any
that are missing. It supports apt-based Debian/Ubuntu/Mint, Arch, and Fedora.
It also checks Qt's version. If the system Qt is older than 6.6, it installs
Qt 6.8.3 in `~/Qt` and tries the Berkeley, FAU, and dotsrc mirrors in turn.
Override the Qt version or the first mirror with `VLC_NEO_QT_VERSION` and
`VLC_NEO_QT_MIRROR`.

See [Linux Mint build and install notes](docs/linux-mint.md) for a reproducible
Qt setup and checks for default install, uninstall, and classic VLC restore.

### Build and install

```bash
git clone https://github.com/AlexandreOlives/vlc-neo.git
cd vlc-neo
scripts/install.sh            # adds `vlc-neo` and a "VLC (Neo)" launcher entry
# or
scripts/install.sh --default  # make Neo the interface of plain `vlc` everywhere
# or, for an unattended package install
scripts/install.sh --default --yes
```

System packages are installed with the system package manager and may require
`sudo`. Qt is installed per user. The build and VLC plugin remain in the user
account.

`--default` makes every way of opening VLC use Neo: the `vlc` command, the app
launcher, "Open with VLC" in the file manager, and existing file associations.
The classic interface stays one step away:
`vlc -I qt`, or the **"VLC (Classic interface)"** launcher entry.

The script installs these files:
- `~/.local/lib/vlc-neo/plugins/gui/libneo_plugin.so`: the plugin
- `~/.local/bin/vlc-neo`, plus `~/.local/bin/vlc` with `--default`: small launchers
  that add the plugin path
- `~/.local/share/applications/*.desktop`: launcher entries

Uninstall with `scripts/install.sh --uninstall`.

## Usage and shortcuts

```bash
vlc-neo movie.mkv                 # play a file
vlc-neo ~/Videos/Show/            # play a folder as a queue
vlc-neo https://example.com/list.m3u
```

| Action | Key |
|---|---|
| Play / pause | Space |
| Seek 10 s / 3 s / 1 min | ← → / Shift + ← → / Ctrl + ← → |
| Volume | ↑ ↓, mouse wheel on the video |
| Fullscreen | F, double-click |
| Hide the whole UI | Ctrl+H |
| Queue / library / playback settings | Q / L / Ctrl+E |
| Cycle subtitle / audio track | V / B |
| Subtitle earlier / later | G / H |
| Audio earlier / later | J / K |
| Speed down / up / normal | [ ] = |
| Bookmark / snapshot / record | Ctrl+B / Shift+S / Shift+R |
| Open file / network / clipboard | Ctrl+O / Ctrl+N / Ctrl+V |
| Preferences / all shortcuts | Ctrl+P / ? |

Any other key goes to VLC's own hotkey engine. Your custom `vlcrc` hotkeys keep
working.

## How it works

```
VLC 3 core (system package, unchanged)
 ├─ interface "neo"        Qt Quick UI thread (QML)
 │                          └─ Player facade ◄─ PlayerBackend ◄─ Vlc3PlayerBackend
 │                             (adapter is injected by the interface bootstrap)
 └─ vout display "neo_vout" RGB32 frames with subtitles and OSD already blended by VLC
                            └─ FrameStore ─► VideoOutput (Qt scene-graph texture)
```

| File | Role |
|---|---|
| `src/module.cpp` | Module descriptor; routes the playlist's video to `neo_vout` |
| `src/vout_display.cpp` | Receives decoded pictures from the VLC core |
| `src/video_item.cpp` | Draws them in QML (fit or fill) |
| `src/player.cpp` | Backend-independent QML-facing player facade, UI state, preferences and conversion to QML values |
| `src/player_backend.hpp` | VLC-independent backend interface for generic state, events and transport, playlist, track, chapter, audio and video operations |
| `src/vlc3_player_backend.cpp` | VLC 3 adapter that owns input references, registers VLC callbacks and implements the generic backend operations |
| `src/ui.cpp` | Interface bootstrap that injects the VLC 3 backend into the player facade |
| `src/queue_model.cpp` | QML-facing playlist model, separate from the adapter |
| `qml/` | The interface. Design tokens live in `qml/singletons/NeoTheme.qml` |

Video is composited by Qt, so the interface runs as a native **Wayland** window
(and on X11) without window reparenting. VLC still decodes, including hardware
decoding, and converts to RGB. Qt uploads each frame as a texture.

## Updating VLC

- **VLC 3.0.x updates** (for example via pacman or apt) need nothing. The plugin
  interface is stable within 3.0.
- If a distribution rebuild ever breaks loading, run `scripts/install.sh` again.
  The build takes about a minute.
- **VLC 4.0** changes the internal player API. The C++ bridge will need a port
  then, and the QML interface carries over as is.

## Development and tests

```bash
scripts/smoke-test.sh     # end-to-end checks against the real VLC core, headless
ctest --test-dir build --output-on-failure  # focused C++ logic tests
scripts/screenshots.sh ~/Videos   # regenerate docs/screenshots (needs the Sintel demo folder)
scripts/test-installer.sh # default install/uninstall lifecycle in a disposable HOME
```

The smoke test runs `vlc -I neo` on Qt's offscreen platform and generates its
own media. It checks:
- playback and frame delivery to QML
- queue contents and next-item playback
- pause/resume controls
- folder subtitle matching
- show presets carried across episodes
- resume
- hotkeys, bookmarks and speed
- `vlcrc` writes and persistence across launches
- dark/light and compact-window screenshots

CTest covers subtitle filename matching and the backend-injected player facade,
including volume clamping, mute/unmute state and audio restoration after mute.
- theme and accent persistence across launches

CI uploads the dark, light and compact-window captures as workflow artifacts so
they can be inspected after each run.

`NEO_TEST_STEPS` drives any launch with timed QML expressions and window grabs.
It is ignored when the variable is unset:

```bash
NEO_TEST_STEPS="1500:player.togglePause()|+800:grab:/tmp/shot.png|+200:quit" vlc-neo movie.mkv
```

Contributions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) and the
[Figma parity matrix](docs/figma-parity.md) before changing the interface. The
design tokens and every screen are plain QML files under `qml/`.

## Roadmap

These parts of the redesign are not implemented yet:
- **Waveform seek bar and seek thumbnails.** VLC 3 has no API for them. They
  need a second decoder per file.
- **Subtitle timeline** (see when lines appear while syncing).
- **Filter previews** for the audio and video presets.
- **Music library sections** (albums, artists, genres). VLC 3 has no
  media-library database. Music folders play from the library panel today.
- **Profiles:** save layouts and settings per profile.
- **Stream to another device and Convert dialogs.** These are still available
  in the classic interface (`vlc -I qt`).
- Translations, plus Windows and macOS builds.

## License and trademarks

- **Code:** [GPL-3.0-or-later](LICENSE).
- **Icons:** Figma exports from Juxtopposed's VLC Redesign (CC BY 4.0) and
  [Lucide](https://lucide.dev) (ISC); see [`assets/ATTRIBUTION.md`](assets/ATTRIBUTION.md).
- **Design:** VLC Redesign by [Juxtopposed](https://www.youtube.com/@juxtopposed),
  shared through Figma Community under CC BY 4.0.
- **Trademarks:** VLC and the VLC cone are trademarks of VideoLAN. This project
  is not affiliated with or endorsed by VideoLAN.
