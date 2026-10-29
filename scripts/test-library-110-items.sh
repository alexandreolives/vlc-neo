#!/usr/bin/env bash
# Exercise asynchronous indexing and the folder grid at the 110-item Figma scale.
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${NEO_BUILD_DIR:-$HERE/build}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/neo-library-110.XXXXXX")"
ARTIFACTS="${NEO_LIBRARY_OUTPUT_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/neo-library-artifacts.XXXXXX")}"
mkdir -p "$WORK/show" "$ARTIFACTS"
trap 'python3 -c "import shutil,sys; shutil.rmtree(sys.argv[1], ignore_errors=True)" "$WORK"' EXIT

ffmpeg -loglevel error -y -f lavfi -i "testsrc2=size=320x180:rate=12" \
    -t 40 -an -c:v libx264 -preset ultrafast -pix_fmt yuv420p "$WORK/episode.mp4"
mkdir -p "$WORK/music" "$WORK/Films" "$WORK/Anime" "$WORK/Downloads"
ffmpeg -loglevel error -y -f lavfi -i 'sine=frequency=660:sample_rate=48000' -t 3 -c:a aac "$WORK/home-track.m4a"
for number in $(seq 1 110); do
    printf -v episode '%02d' "$number"
    ln "$WORK/episode.mp4" "$WORK/show/The_Wand_S01E$episode.mp4"
done

SANDBOX="$WORK/sandbox"
mkdir -p "$SANDBOX/config/vlc-neo"
printf '[appearance]\nonboarded=true\n' > "$SANDBOX/config/vlc-neo/neo.conf"
output="$(NEO_BUILD_DIR="$BUILD_DIR" NEO_SANDBOX="$SANDBOX" NEO_TIMEOUT=60 \
    "$HERE/scripts/run-offscreen.sh" \
    "500:onboarding.close(); win.width=1920; win.height=1080; mediaLibrary.addFolder(platform.fileUrl('$WORK/show'))|+7000:'index=' + mediaLibrary.indexedCount + '/' + mediaLibrary.scanning|+100:mediaLibrary.model.view='videos'|+700:'videoView=' + mediaLibrary.model.itemCount() + '/' + mediaLibrary.model.loading|+100:player.openLocation('$WORK/show/The_Wand_S01E01.mp4',true)|+1200:win.navigate('videos'); libraryPanel.folder=platform.fileUrl('$WORK/show')|+350:'folderCount=' + libraryPanel.fileCount() + ' grid=' + libraryPanel.folderViewMode + ' mini=' + libraryPanel.miniPlayerItem.visible + ' rail=' + navigationRail.expandedRowCenters()|+100:libraryPanel.searchText='The_Wand_S01E110.mp4'|+200:'lastEpisodeSearch=' + libraryPanel.matchingFiles()|+100:libraryPanel.searchText=''|+500:'resetCount=' + libraryPanel.fileCount()|+6000:'visibleThumbnailReadyCount=' + (() => { let ready=0; for(let i=1;i<=15;i++){ const n='The_Wand_S01E'+String(i).padStart(2,'0')+'.mp4'; if(libraryPanel.videoThumbnailState(n)==='ready') ready++ } return ready })()|+100:'gridGeometry=' + libraryPanel.folderGridGeometry()|+100:'folderSearchGeometry=' + libraryPanel.folderToolbarSearchGeometry()|+100:'folderToolbarGeometry=' + libraryPanel.folderToolbarGeometry()|+100:click-item:library-folder-more-options|+100:'folderMoreMenu=' + sidePanelActionsMenu.visible + '/' + sidePanelActionsMenu.count|+100:sidePanelActionsMenu.close()|+150:grab:$ARTIFACTS/folder-browser-110-grid-1920.png|+100:libraryPanel.folderViewMode='list'|+500:'listCount=' + libraryPanel.fileCount() + ' mode=' + libraryPanel.folderViewMode|+6000:'listThumbnailReadyCount=' + (() => { let ready=0; for(let i=1;i<=15;i++){ const n='The_Wand_S01E'+String(i).padStart(2,'0')+'.mp4'; if(libraryPanel.videoThumbnailState(n)==='ready') ready++ } return ready })()|+100:'listThumbnailSummary=' + libraryPanel.visibleVideoThumbnailSummary()|+18000:'listThumbnailFinalSummary=' + libraryPanel.visibleVideoThumbnailSummary() + ' geometry=' + libraryPanel.folderListGeometry()|+150:grab:$ARTIFACTS/folder-browser-110-list-1920.png|+100:player.stop()|+200:win.navigate('home')|+200:homeView.videoItems=[{url:platform.fileUrl('$WORK/show/The_Wand_S01E05.mp4'),path:'$WORK/show/The_Wand_S01E05.mp4',title:'The_Wand_S01E05.mp4',point:20000,duration:40000,progress:0.5},{url:platform.fileUrl('$WORK/show/The_Wand_S01E06.mp4'),path:'$WORK/show/The_Wand_S01E06.mp4',title:'The_Wand_S01E06.mp4',point:20000,duration:40000,progress:0.5},{url:platform.fileUrl('$WORK/show/The_Wand_S01E07.mp4'),path:'$WORK/show/The_Wand_S01E07.mp4',title:'The_Wand_S01E07.mp4',point:20000,duration:40000,progress:0.5},{url:platform.fileUrl('$WORK/show/The_Wand_S01E08.mp4'),path:'$WORK/show/The_Wand_S01E08.mp4',title:\"DON'T BLINK\",point:20000,duration:40000,progress:0.5}]; homeView.musicItems=[{title:'untangle',artist:'juxtopposed',path:'$WORK/home-track.m4a',artwork:'$HERE/tests/fixtures/music-cover.png'},{title:'moonlight',artist:'juxtopposed',path:'$WORK/home-track.m4a',artwork:'$HERE/tests/fixtures/music-cover.png'},{title:'black bird',artist:'juxtopposed',path:'$WORK/home-track.m4a',artwork:'$HERE/tests/fixtures/music-cover.png'}]; homeView.folderItems=[{path:'$WORK/show',title:'Shows'},{path:'$WORK/Films',title:'Films'},{path:'$WORK/Anime',title:'Anime'},{path:'$WORK/Downloads',title:'Downloads'}]; 'homeReview=' + mediaLibrary.indexedCount + '/' + homeView.videoItems.length + '/' + homeView.musicItems.length + '/' + homeView.folderItems.length|+10000:'homeThumbnailReady=' + [0,1,2,3].map(i => homeView.videoThumbnailReady(i)).join(',')|+100:move:1910,1070|+150:grab:$ARTIFACTS/home-full-layout-review.png|+100:Qt.quit()" 2>&1)"
printf '%s\n' "$output" | grep -E 'neo test(:| step failed)' || true
python3 - "$SANDBOX/data" <<'PY'
import sqlite3
import sys
from pathlib import Path

databases = list(Path(sys.argv[1]).rglob("library.sqlite"))
if databases:
    with sqlite3.connect(databases[0]) as database:
        print("Indexed kinds:", database.execute("SELECT kind,count(*) FROM media GROUP BY kind").fetchall())
PY
if ! grep -qF 'homeReview=110/4/3/4' <<<"$output"; then
    echo "FAIL Home review capture did not preserve Figma's 110-item count and 4/3/4 shelves" >&2
    exit 1
fi
if ! grep -qF 'homeThumbnailReady=true,true,true,true' <<<"$output"; then
    echo "FAIL Home review capture is missing one or more decoded episode thumbnails" >&2
    exit 1
fi
if [[ ! -s "$ARTIFACTS/home-full-layout-review.png" ]]; then
    echo "FAIL Home review screenshot was not written" >&2
    exit 1
fi
for expected in 'index=110/false' 'videoView=110/false' 'folderCount=110 grid=grid mini=true' \
                'gridGeometry=237/131/316/178/388/257' \
                'folderSearchGeometry=1494/324' \
                'folderMoreMenu=true/6' \
                'lastEpisodeSearch=1' 'resetCount=110' 'listCount=110 mode=list'; do
    if ! grep -qF "$expected" <<<"$output"; then
        echo "FAIL expected library result: $expected" >&2
        exit 1
    fi
done
if ! grep -Eq 'folderToolbarGeometry=132[5-9]/1398/1446/1494/1836/1868' <<<"$output"; then
    echo "FAIL folder toolbar geometry drifted from the Figma 1920x1080 frame" >&2
    exit 1
fi
if ! grep -qF 'rail=76/122/168/214/260/306/352' <<<"$output"; then
    echo "FAIL expanded navigation row centers drifted from the Figma 1920x1080 frame" >&2
    exit 1
fi
if ! grep -Eq 'visibleThumbnailReadyCount=[1-9][0-9]*' <<<"$output"; then
    echo "FAIL no video thumbnail became ready in the initial viewport" >&2
    exit 1
fi
if ! grep -Eq 'visibleThumbnailReadyCount=(1[2-5]|[2-9])([^0-9]|$)' <<<"$output"; then
    echo "FAIL fewer than twelve initial-grid thumbnails became ready within six seconds" >&2
    exit 1
fi
if ! grep -Eq 'listThumbnailReadyCount=(1[2-5]|[2-9])([^0-9]|$)' <<<"$output"; then
    echo "FAIL fewer than twelve initial-list thumbnails became ready within six seconds" >&2
    exit 1
fi
if ! grep -Eq 'listThumbnailFinalSummary=([0-9]+)/\1/0/0 geometry=' <<<"$output"; then
    echo "FAIL visible list thumbnails did not all finish loading within twenty-four seconds" >&2
    exit 1
fi
if ! grep -qF 'geometry=135/237/140/32/32/6/735/391/339/true' <<<"$output"; then
    echo "FAIL full-list or mini-player geometry drifted from the Figma 1920x1080 frame" >&2
    exit 1
fi
if [[ ! -s "$ARTIFACTS/folder-browser-110-grid-1920.png" ]]; then
    echo "FAIL 110-item grid screenshot was not written" >&2
    exit 1
fi
if [[ ! -s "$ARTIFACTS/folder-browser-110-list-1920.png" ]]; then
    echo "FAIL  110-item compact-list screenshot was not written" >&2
    exit 1
fi
echo "PASS 110-item asynchronous indexing, folder grid/list, exact search, and mini-player"
echo "Grid screenshot: $ARTIFACTS/folder-browser-110-grid-1920.png"
echo "Compact-list screenshot: $ARTIFACTS/folder-browser-110-list-1920.png"
echo "Home review screenshot: $ARTIFACTS/home-full-layout-review.png"
