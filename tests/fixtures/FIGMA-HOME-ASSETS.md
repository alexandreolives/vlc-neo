# Figma Home media artwork

The `figma-home/` images were exported from the media artwork embedded in the
Home screen (node `6261:15078`) of Juxtopposed's free [VLC Redesign Community
file](https://www.figma.com/design/5UEUReDQz2dQjwoQDHY5z9/VLC-Redesign--Community-).
Figma states that free Community files are published under
[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). The original creator
is credited here; the image files have been renamed for their matching media
items.

- `the-wand-s01e05.png`, `the-wand-s01e06.png`, `the-wand-s01e07.png`: the
  three corresponding episode poster images.
- `untangle.jpg`: the `untangle` music artwork.
- `moonlight.png`: the matching green music-note artwork shown for both
  `moonlight` and `black bird` in the Figma Home screen.

The 110-item library probe encodes the three episode stills as short, silent
video fixtures and crops them to 16:9 to exercise VLC's real thumbnail path.
The fourth Home card in the Figma reference is black, so its fixture remains a
black frame. No source video or audio recording is included.

## Player folder-sidebar thumbnail fixtures

`figma-player-sidebar/s01e01.png` through `s01e15.png` are 33 × 33 pixel crops
of the fifteen episode thumbnails shown in the light Player folder-sidebar
frame (Figma node `2425:13624`) in the same Juxtopposed Community file. They
are screenshot-derived visual fixtures, not original-resolution episode
artwork or episode media. `s01e04-source.png` is the full-resolution 480 × 270
Figma image export used for the E04 playback frame. `scripts/test-sidebar-density.sh`
wraps these stills in silent 40-second videos so the real VLC thumbnail decoder
and sidebar layout are exercised with the imagery visible in that Figma
reference. The reference crops replace the previous synthetic color bars. The
original creator is credited above; the Community file's stated CC BY 4.0 terms
apply.
