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

CUSTOM_VIDEO="$WORK/custom/S01/The_Wand_S01E11.mp4"
mkdir -p "$(dirname "$CUSTOM_VIDEO")"
ffmpeg -hide_banner -loglevel error -y -loop 1 -framerate 12 \
    -i "$HERE/tests/fixtures/figma-playlists/player-video-surface.png" -t 40 \
    -vf "pad=1494:984:0:0,format=yuv420p" -an \
    -c:v libx264 -preset ultrafast -pix_fmt yuv420p -movflags +faststart \
    "$CUSTOM_VIDEO"

timestamp=1760000000
for episode in 05 06 07 08 09 10 11 12 13 14 15 01 02 03 04; do
    touch -d "@$timestamp" "$MEDIA/The_Wand_S01E$episode.mp4"
    ((timestamp += 1))
done

states="'videoFrame=' + video.hasFrame + '/' + video.frameSize.width + 'x' + video.frameSize.height + ' thumbnailStates=' + (() => { const states=[]; for(let i=1;i<=15;i++) states.push(libraryPanel.videoThumbnailState('The_Wand_S01E'+String(i).padStart(2,'0')+'.mp4')); return states.join('/') })() + ' ready=' + (() => { const states=[]; for(let i=1;i<=15;i++) states.push(libraryPanel.videoThumbnailState('The_Wand_S01E'+String(i).padStart(2,'0')+'.mp4')); return states.filter(state=>state==='ready').length })()"
steps="1000:onboarding.close(); Theme.store.onboarded=true; Theme.store.mode='light'; win.width=1920; win.height=1080; player.openLocation('$MEDIA/The_Wand_S01E04.mp4',true)|+1200:click-item:folder-chip|+1000:libraryPanel.sortBy='date'|+600:'sidebarLayout=' + libraryPanel.fileCount() + '/' + Math.round(libraryPanel.width) + '/' + win.folderSidebarOpen + ' rowGeometry=' + Math.round(libraryPanel.compactFolderToolbar.y) + '/' + Math.round(libraryPanel.folderListing.y) + ' breadcrumb=' + libraryPanel.crumbs().map(c=>c.name).join('  ›  ') + ' figmaHeader=' + libraryPanel.figmaFolderHeaderControlsMatch + ' viewMode=' + libraryPanel.folderViewMode + ' displayTitle=' + win.displayMediaTitle + ' topBarTitle=' + topBar.titleLabel.text + ' titleVisible=' + topBar.titleLabel.visible + ' fileOrder=' + Array.from({length:libraryPanel.fileCount()},(_,i)=>libraryPanel.fileNameAt(i)).join(',')|+22000:$states|+100:grab:$CAPTURE|+100:Theme.setLayout(['hideui','pip','foldername','filename','spacer','prev','play','next','spacer','volume','visualizer','subtitle','settings','queue','fullscreen']); Theme.store.mode='dark'; player.openLocation('$CUSTOM_VIDEO',true)|+4000:libraryPanel.folder=platform.fileUrl('$MEDIA')|+500:'customizeSidebarLayout=' + Theme.layoutList().join(',') + '/' + libraryPanel.fileCount() + '/' + win.folderSidebarOpen + '/mode=' + Theme.store.mode + '/media=' + win.displayMediaTitle + '/filename=' + controlBar.findControl('filename').contentItem.text + '/titleVisible=' + topBar.titleLabel.visible + '/splitTimeline=' + controlBar.splitTimeline + '/' + (Math.abs(splitTimeline.x - 20) < 1 && Math.abs(splitTimeline.width - win.width + 40) < 1) + '/' + (Math.abs(splitTimeline.y + splitTimeline.height - controlBar.y) < 1) + '/transportCenter=' + Math.round((controlBar.findControl('prev').x + controlBar.findControl('next').x + controlBar.findControl('next').width) / 2 - controlBar.width / 2) + '/frame=' + video.frameSize.width + 'x' + video.frameSize.height|+900:grab:$CUSTOMIZE_CAPTURE|+100:click-item:sidepanel-back-generic|+250:'folderParentBack=' + (platform.localPath(libraryPanel.folder).endsWith('/The Wand') && libraryPanel.canGoForwardFromSidePanel())|+100:click-item:sidepanel-forward-generic|+250:'folderParentForward=' + platform.localPath(libraryPanel.folder).endsWith('/The Wand/S01')|+100:libraryPanel.folder=platform.fileUrl('$WORK/The Wand'); libraryPanel.sideFolderHistory=[]; libraryPanel.sidePanelForwardHistory=[]|+300:click-item:library-folder-item-S01|+300:'folderHistoryNavigated=' + (platform.localPath(libraryPanel.folder).endsWith('/The Wand/S01') && libraryPanel.canGoBackFromSidePanel())|+100:click-item:sidepanel-back-generic|+250:'folderHistoryBack=' + (platform.localPath(libraryPanel.folder).endsWith('/The Wand') && libraryPanel.canGoForwardFromSidePanel())|+100:click-item:sidepanel-forward-generic|+250:'folderHistoryForward=' + (platform.localPath(libraryPanel.folder).endsWith('/The Wand/S01') && !libraryPanel.canGoForwardFromSidePanel())|+100:click-item:sidepanel-more-button-generic|+100:'folderMore=' + sidePanelActionsMenu.visible|+100:sidePanelActionsMenu.close()|+100:click-item:sidepanel-open-full-page|+350:'folderExpand=' + (win.libraryFullPage && !win.libraryOpen && !win.folderSidebarOpen && libraryPanel.visible && !videoArea.visible && libraryPanel.section === 'folder' && platform.localPath(libraryPanel.folder).endsWith('/The Wand/S01'))|+100:quit"
output=$(NEO_BUILD_DIR="$BUILD_DIR" NEO_SANDBOX="$WORK/sandbox" NEO_TIMEOUT=60 QT_QPA_PLATFORM=offscreen \
    "$HERE/scripts/run-offscreen.sh" "$steps" 2>&1) || {
    printf '%s\n' "$output" >&2
    exit 1
}
printf '%s\n' "$output"
grep -Fq "sidebarLayout=15/377/true" <<<"$output" || {
    echo "FAIL: expected 15 folder entries and a 377 px sidebar at 1920 px" >&2
    exit 1
}
grep -Fq "fileOrder=The_Wand_S01E05.mp4,The_Wand_S01E06.mp4,The_Wand_S01E07.mp4,The_Wand_S01E08.mp4,The_Wand_S01E09.mp4,The_Wand_S01E10.mp4,The_Wand_S01E11.mp4,The_Wand_S01E12.mp4,The_Wand_S01E13.mp4,The_Wand_S01E14.mp4,The_Wand_S01E15.mp4,The_Wand_S01E01.mp4,The_Wand_S01E02.mp4,The_Wand_S01E03.mp4,The_Wand_S01E04.mp4" <<<"$output" || {
    echo "FAIL: expected the Figma Player-Light episode order" >&2
    exit 1
}
grep -Fq "customizeSidebarLayout=hideui,pip,foldername,filename,spacer,prev,play,next,spacer,volume,visualizer,subtitle,settings,queue,fullscreen/15/true/mode=dark/media=The Wand S01E11/filename=The Wand S01E11/titleVisible=false/splitTimeline=true/true/true/transportCenter=0/frame=1494x984" <<<"$output" || {
    echo "FAIL: expected Figma's dark custom layout, full-width split timeline, centered transport and active E11 title" >&2
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
grep -Fq "videoFrame=true/320x180" <<<"$output" || {
    echo "FAIL: VLC did not deliver a decoded frame to the main Neo video surface" >&2
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
