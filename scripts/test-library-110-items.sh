#!/usr/bin/env bash
# Exercise asynchronous indexing and the folder grid at the 110-item Figma scale.
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${NEO_BUILD_DIR:-$HERE/build}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/neo-library-110.XXXXXX")"
ARTIFACTS="${NEO_LIBRARY_OUTPUT_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/neo-library-artifacts.XXXXXX")}"
HOME_SIDEBAR_CAPTURE="${NEO_HOME_SIDEBAR_CAPTURE:-$ARTIFACTS/home-sidebar-review.png}"
mkdir -p "$WORK/show" "$ARTIFACTS"
trap 'python3 -c "import shutil,sys; shutil.rmtree(sys.argv[1], ignore_errors=True)" "$WORK"' EXIT

FIGMA_GRID="$HERE/tests/fixtures/figma-player-grid"
(cd "$FIGMA_GRID" && sha256sum --check --quiet SHA256SUMS)
mkdir -p "$WORK/posters" "$WORK/music" "$WORK/Films" "$WORK/Anime" "$WORK/Downloads"
for episode in $(seq -w 1 15); do
    ffmpeg -loglevel error -y -loop 1 -framerate 12 \
        -i "$FIGMA_GRID/s01e$episode.png" -t 40 \
        -vf "format=yuv420p" \
        -an -c:v libx264 -preset ultrafast -tune stillimage \
        "$WORK/posters/The_Wand_S01E$episode.mp4"
done
ffmpeg -loglevel error -y -f lavfi -i 'sine=frequency=660:sample_rate=48000' -t 3 -c:a aac "$WORK/home-track.m4a"
visible_order=(05 06 07 08 09 10 11 12 13 14 15 01 02 03 04)
for number in $(seq 16 110); do
    printf -v episode '%02d' "$number"
    visible_order+=("$episode")
done
mtime_base="$(date +%s)"
for index in "${!visible_order[@]}"; do
    episode="${visible_order[$index]}"
    number=$((10#$episode))
    poster_number=$(((number - 1) % 15 + 1))
    printf -v poster '%02d' "$poster_number"
    cp "$WORK/posters/The_Wand_S01E$poster.mp4" "$WORK/show/The_Wand_S01E$episode.mp4"
    touch -m -d "@$((mtime_base + index))" "$WORK/show/The_Wand_S01E$episode.mp4"
done

SANDBOX="$WORK/sandbox"
mkdir -p "$SANDBOX/config/vlc-neo"
printf '[appearance]\nonboarded=true\n' > "$SANDBOX/config/vlc-neo/neo.conf"
output="$(NEO_BUILD_DIR="$BUILD_DIR" NEO_SANDBOX="$SANDBOX" NEO_TIMEOUT=60 \
    "$HERE/scripts/run-offscreen.sh" \
    "500:onboarding.close(); win.width=1920; win.height=1080; mediaLibrary.addFolder(platform.fileUrl('$WORK/show'))|+7000:'index=' + mediaLibrary.indexedCount + '/' + mediaLibrary.scanning|+100:mediaLibrary.model.view='videos'|+700:'videoView=' + mediaLibrary.model.itemCount() + '/' + mediaLibrary.model.loading|+100:player.openLocation('$WORK/show/The_Wand_S01E04.mp4',true)|+1200:win.navigate('videos'); libraryPanel.folder=platform.fileUrl('$WORK/show'); libraryPanel.sortBy='date'|+350:'folderCount=' + libraryPanel.fileCount() + ' grid=' + libraryPanel.folderViewMode + ' mini=' + libraryPanel.miniPlayerItem.visible + ' rail=' + navigationRail.expandedRowCenters()|+100:'folderVisualOrder=' + Array.from({length:15},(_,i)=>libraryPanel.folderListing.model.get(i,'fileName')).join(',')|+100:libraryPanel.searchText='The_Wand_S01E110.mp4'|+200:'lastEpisodeSearch=' + libraryPanel.matchingFiles()|+100:libraryPanel.searchText=''|+500:'resetCount=' + libraryPanel.fileCount()|+6000:'visibleThumbnailReadyCount=' + (() => { let ready=0; for(let i=1;i<=15;i++){ const n='The_Wand_S01E'+String(i).padStart(2,'0')+'.mp4'; if(libraryPanel.videoThumbnailState(n)==='ready') ready++ } return ready })()|+100:'gridGeometry=' + libraryPanel.folderGridGeometry()|+100:'gridMiniPlayerGeometry=' + (() => { const m=libraryPanel.miniPlayerItem; const p=m.mapToItem(win.contentItem,0,0); return Math.round(p.x)+'/'+Math.round(p.y)+'/'+Math.round(m.width)+'/'+Math.round(m.height) })()|+100:'gridMiniPlayerRadius=' + Math.round(libraryPanel.miniPlayerBackground.radius)|+100:'folderSearchGeometry=' + libraryPanel.folderToolbarSearchGeometry()|+100:'folderToolbarGeometry=' + libraryPanel.folderToolbarGeometry()|+100:click-item:library-folder-more-options|+100:'folderMoreMenu=' + sidePanelActionsMenu.visible + '/' + sidePanelActionsMenu.count|+100:sidePanelActionsMenu.close()|+150:grab:$ARTIFACTS/folder-browser-110-grid-1920.png|+100:libraryPanel.folderViewMode='list'|+500:'listCount=' + libraryPanel.fileCount() + ' mode=' + libraryPanel.folderViewMode|+6000:'listThumbnailReadyCount=' + (() => { let ready=0; for(let i=1;i<=15;i++){ const n='The_Wand_S01E'+String(i).padStart(2,'0')+'.mp4'; if(libraryPanel.videoThumbnailState(n)==='ready') ready++ } return ready })()|+100:'listThumbnailSummary=' + libraryPanel.visibleVideoThumbnailSummary()|+18000:'listThumbnailFinalSummary=' + libraryPanel.visibleVideoThumbnailSummary() + ' geometry=' + libraryPanel.folderListGeometry()|+100:'visibleListThumbnailErrors=' + libraryPanel.visibleVideoThumbnailErrors()|+100:'listMiniPlayerGeometry=' + (() => { const m=libraryPanel.miniPlayerItem; const p=m.mapToItem(win.contentItem,0,0); return Math.round(p.x)+'/'+Math.round(p.y)+'/'+Math.round(m.width)+'/'+Math.round(m.height) })()|+100:'listMiniPlayerRadius=' + Math.round(libraryPanel.miniPlayerBackground.radius)|+150:grab:$ARTIFACTS/folder-browser-110-list-1920.png|+100:player.stop()|+200:win.navigate('home')|+200:homeView.videoItems=[{url:platform.fileUrl('$WORK/show/The_Wand_S01E05.mp4'),path:'$WORK/show/The_Wand_S01E05.mp4',title:'The_Wand_S01E05.mp4',point:2600,duration:40000,progress:0.065},{url:platform.fileUrl('$WORK/show/The_Wand_S01E06.mp4'),path:'$WORK/show/The_Wand_S01E06.mp4',title:'The_Wand_S01E06.mp4',point:200,duration:40000,progress:0.005},{url:platform.fileUrl('$WORK/show/The_Wand_S01E07.mp4'),path:'$WORK/show/The_Wand_S01E07.mp4',title:'The_Wand_S01E07.mp4',point:19400,duration:40000,progress:0.485},{url:platform.fileUrl('$WORK/show/The_Wand_S01E08.mp4'),path:'$WORK/show/The_Wand_S01E08.mp4',title:\"DON'T BLINK\",point:1000,duration:40000,progress:0.025}]; homeView.musicItems=[{title:'untangle',artist:'juxtopposed',path:'$WORK/home-track.m4a',artwork:'$HERE/tests/fixtures/figma-home/untangle.jpg'},{title:'moonlight',artist:'juxtopposed',path:'$WORK/home-track.m4a',artwork:'$HERE/tests/fixtures/figma-home/moonlight.png'},{title:'black bird',artist:'juxtopposed',path:'$WORK/home-track.m4a',artwork:'$HERE/tests/fixtures/figma-home/moonlight.png'}]; homeView.folderItems=[{path:'$WORK/show',title:'Shows'},{path:'$WORK/Films',title:'Films'},{path:'$WORK/Anime',title:'Anime'},{path:'$WORK/Downloads',title:'Downloads'}]; 'homeReview=' + mediaLibrary.indexedCount + '/' + homeView.videoItems.length + '/' + homeView.musicItems.length + '/' + homeView.folderItems.length|+100:'homeMiniPlayerRadius=' + Math.round(homeView.miniPlayerBackground.radius)|+10000:'homeThumbnailReady=' + [0,1,2,3].map(i => homeView.videoThumbnailReady(i)).join(',')|+100:move:1910,1070|+150:grab:$ARTIFACTS/home-full-layout-review.png|+100:win.openSidePanel('home')|+350:sideHomeView.videoItems=homeView.videoItems; sideHomeView.musicItems=homeView.musicItems; sideHomeView.folderItems=homeView.folderItems.slice(0,3); sideHomeView.playlistItems=[{fileName:'Fav Episodes.m3u8',filePath:'$WORK/Fav Episodes.m3u8'},{fileName:'Coolest Songs.m3u8',filePath:'$WORK/Coolest Songs.m3u8'},{fileName:'Anime Playlist.m3u8',filePath:'$WORK/Anime Playlist.m3u8'}]; sideHomeView.artistItems=[{artist:'juxtopposed',path:homeView.musicItems[0].path,artwork:homeView.musicItems[0].artwork}]|+1000:'homeSidebarReview=' + sideHomeView.videoItems.length + '/' + sideHomeView.musicItems.length + '/' + sideHomeView.folderItems.length + '/' + sideHomeView.playlistItems.length + '/' + sideHomeView.artistItems.length|+100:'homeSidebarAssets=' + [0,1,2].map(i => sideHomeView.videoThumbnailReady(i)).join(',') + '/' + [0,1,2].map(i => sideHomeView.musicArtworkReady(i)).join(',')|+100:move:200,1060|+150:grab:$HOME_SIDEBAR_CAPTURE|+100:Qt.quit()" 2>&1)"
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
if [[ ! -s "$HOME_SIDEBAR_CAPTURE" ]] || ! grep -qF "homeSidebarReview=4/3/3/3/1" <<<"$output"; then
    echo "FAIL Home side-pane review did not preserve Figma shelf counts or capture" >&2
    exit 1
fi
if ! grep -qF "homeSidebarAssets=true,true,true/true,true,true" <<<"$output"; then
    echo "FAIL Home side-pane did not decode all three Figma video thumbnails and music covers" >&2
    exit 1
fi
for expected in 'index=110/false' 'videoView=110/false' 'folderCount=110 grid=grid mini=true' \
                'folderVisualOrder=The_Wand_S01E05.mp4,The_Wand_S01E06.mp4,The_Wand_S01E07.mp4,The_Wand_S01E08.mp4,The_Wand_S01E09.mp4,The_Wand_S01E10.mp4,The_Wand_S01E11.mp4,The_Wand_S01E12.mp4,The_Wand_S01E13.mp4,The_Wand_S01E14.mp4,The_Wand_S01E15.mp4,The_Wand_S01E01.mp4,The_Wand_S01E02.mp4,The_Wand_S01E03.mp4,The_Wand_S01E04.mp4' \
                'gridGeometry=237/131/316/178/388/257' \
                'gridMiniPlayerGeometry=1523/735/391/339' \
                'gridMiniPlayerRadius=14' 'listMiniPlayerRadius=14' 'homeMiniPlayerRadius=14' \
                'listMiniPlayerGeometry=6/735/391/339' \
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
    grep -F "visibleListThumbnailErrors=" <<<"$output" >&2 || true
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
echo "Home sidebar review screenshot: $HOME_SIDEBAR_CAPTURE"
