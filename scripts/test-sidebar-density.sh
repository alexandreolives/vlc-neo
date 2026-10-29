#!/usr/bin/env bash
# Focused real-VLC check for the Figma folder sidebar with a 15-item season.
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${NEO_BUILD_DIR:-$HERE/build}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/neo-sidebar-density.XXXXXX")"
trap 'python3 -c "import shutil,sys; shutil.rmtree(sys.argv[1], ignore_errors=True)" "$WORK"' EXIT
MEDIA="$WORK/The Wand/S01"
CAPTURE="${NEO_SIDEBAR_CAPTURE:-$WORK/sidebar.png}"
CUSTOMIZE_CAPTURE="${NEO_CUSTOMIZE_CAPTURE:-$WORK/customize-folder-browser.png}"
mkdir -p "$MEDIA"

for number in $(seq 1 15); do
    printf -v episode '%02d' "$number"
    still="$HERE/tests/fixtures/figma-player-sidebar/s01e$episode.png"
    video_filter="scale=180:180:flags=neighbor,pad=320:180:(ow-iw)/2:0,format=yuv420p"
    if [[ "$episode" == 04 ]]; then
        still="$HERE/tests/fixtures/figma-player-sidebar/s01e04-source.png"
        video_filter="scale=320:180,format=yuv420p"
    fi
    ffmpeg -hide_banner -loglevel error -y -loop 1 -framerate 12 \
        -i "$still" -t 40 \
        -vf "$video_filter" -an \
        -c:v libx264 -preset ultrafast -pix_fmt yuv420p -movflags +faststart \
        "$MEDIA/The_Wand_S01E$episode.mp4"
done

timestamp=1760000000
for episode in 05 06 07 08 09 10 11 12 13 14 15 04 03 02 01; do
    touch -d "@$timestamp" "$MEDIA/The_Wand_S01E$episode.mp4"
    ((timestamp += 1))
done

states="'thumbnailStates=' + (() => { const states=[]; for(let i=1;i<=15;i++) states.push(libraryPanel.videoThumbnailState('The_Wand_S01E'+String(i).padStart(2,'0')+'.mp4')); return states.join('/') })() + ' ready=' + (() => { const states=[]; for(let i=1;i<=15;i++) states.push(libraryPanel.videoThumbnailState('The_Wand_S01E'+String(i).padStart(2,'0')+'.mp4')); return states.filter(state=>state==='ready').length })()"
steps="1000:onboarding.close(); Theme.store.onboarded=true; Theme.store.mode='light'; win.width=1920; win.height=1080; player.openLocation('$MEDIA/The_Wand_S01E04.mp4',true)|+1200:click-item:folder-chip|+1000:libraryPanel.sortBy='date'; 'sidebarLayout=' + libraryPanel.fileCount() + '/' + Math.round(libraryPanel.width) + '/' + win.folderSidebarOpen + ' rowGeometry=' + Math.round(libraryPanel.compactFolderToolbar.y) + '/' + Math.round(libraryPanel.folderListing.y) + ' breadcrumb=' + libraryPanel.crumbs().map(c=>c.name).join('  ›  ') + ' figmaHeader=' + libraryPanel.figmaFolderHeaderControlsMatch + ' viewMode=' + libraryPanel.folderViewMode + ' displayTitle=' + win.displayMediaTitle + ' topBarTitle=' + topBar.titleLabel.text + ' titleVisible=' + topBar.titleLabel.visible|+22000:$states|+100:grab:$CAPTURE|+100:Theme.setLayout(['hideui','pip','foldername','filename','favorite','spacer','prev','play','next','spacer','volume','visualizer','subtitle','settings','queue','fullscreen']); 'customizeSidebarLayout=' + Theme.layoutList().join(',') + '/' + libraryPanel.fileCount() + '/' + win.folderSidebarOpen + '/titleVisible=' + topBar.titleLabel.visible|+900:grab:$CUSTOMIZE_CAPTURE|+100:click-item:sidepanel-back-generic|+250:'folderParentBack=' + (platform.localPath(libraryPanel.folder).endsWith('/The Wand') && libraryPanel.canGoForwardFromSidePanel())|+100:click-item:sidepanel-forward-generic|+250:'folderParentForward=' + platform.localPath(libraryPanel.folder).endsWith('/The Wand/S01')|+100:libraryPanel.folder=platform.fileUrl('$WORK/The Wand'); libraryPanel.sideFolderHistory=[]; libraryPanel.sidePanelForwardHistory=[]|+300:click-item:library-folder-item-S01|+300:'folderHistoryNavigated=' + (platform.localPath(libraryPanel.folder).endsWith('/The Wand/S01') && libraryPanel.canGoBackFromSidePanel())|+100:click-item:sidepanel-back-generic|+250:'folderHistoryBack=' + (platform.localPath(libraryPanel.folder).endsWith('/The Wand') && libraryPanel.canGoForwardFromSidePanel())|+100:click-item:sidepanel-forward-generic|+250:'folderHistoryForward=' + (platform.localPath(libraryPanel.folder).endsWith('/The Wand/S01') && !libraryPanel.canGoForwardFromSidePanel())|+100:click-item:sidepanel-more-button-generic|+100:'folderMore=' + sidePanelActionsMenu.visible|+100:sidePanelActionsMenu.close()|+100:click-item:sidepanel-open-full-page|+350:'folderExpand=' + (win.libraryFullPage && !win.libraryOpen && !win.folderSidebarOpen && libraryPanel.visible && !videoArea.visible && libraryPanel.section === 'folder' && platform.localPath(libraryPanel.folder).endsWith('/The Wand/S01'))|+100:quit"
output=$(NEO_BUILD_DIR="$BUILD_DIR" NEO_SANDBOX="$WORK/sandbox" NEO_TIMEOUT=35 QT_QPA_PLATFORM=offscreen \
    "$HERE/scripts/run-offscreen.sh" "$steps" 2>&1) || {
    printf '%s\n' "$output" >&2
    exit 1
}
printf '%s\n' "$output"
grep -Fq "sidebarLayout=15/377/true" <<<"$output" || {
    echo "FAIL: expected 15 folder entries and a 377 px sidebar at 1920 px" >&2
    exit 1
}
grep -Fq "customizeSidebarLayout=hideui,pip,foldername,filename,favorite,spacer,prev,play,next,spacer,volume,visualizer,subtitle,settings,queue,fullscreen/15/true/titleVisible=false" <<<"$output" || {
    echo "FAIL: expected the Figma custom layout and no duplicate centered filename" >&2
    exit 1
}
grep -Fq "rowGeometry=52/120" <<<"$output" || {
    echo "FAIL: expected Figma-aligned compact toolbar and folder rows at 1920 px" >&2
    exit 1
}
grep -Fq "breadcrumb=…  ›  The Wand  ›  S01" <<<"$output" || {
    echo "FAIL: expected the Figma-collapsed The Wand / S01 breadcrumb" >&2
    exit 1
}
grep -Fq "displayTitle=The Wand S01E04 topBarTitle=The Wand S01E04 titleVisible=true" <<<"$output" || {
    echo "FAIL: expected the Figma-style media title without filename punctuation" >&2
    exit 1
}
grep -Fq "figmaHeader=true" <<<"$output" || {
    echo "FAIL: expected the Figma folder header controls without Pin or Close" >&2
    exit 1
}
grep -Fq "viewMode=list" <<<"$output" || {
    echo "FAIL: expected the Figma list-view control in the folder sidebar" >&2
    exit 1
}
grep -Fq " ready=15" <<<"$output" || {
    echo "FAIL: expected all 15 visible video thumbnails to decode" >&2
    exit 1
}
[[ -s "$CUSTOMIZE_CAPTURE" ]] || {
    echo "FAIL: customized folder-browser screenshot missing" >&2
    exit 1
}
for assertion in folderParentBack=true folderParentForward=true folderHistoryNavigated=true folderHistoryBack=true folderHistoryForward=true folderMore=true folderExpand=true; do
    grep -Fq "$assertion" <<<"$output" || {
        echo "FAIL: expected the Figma folder sidebar action $assertion" >&2
        exit 1
    }
done
echo "PASS: 15 entries and 15 decoded thumbnails in the light and customized folder sidebars"
