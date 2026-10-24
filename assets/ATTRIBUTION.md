# Design asset attribution

The SVG exports and paint-style tokens in this directory are based on the free
“VLC Redesign (Community)” Figma file by Juxtopposed. Figma publishes free
Community files under the [Creative Commons Attribution 4.0 International
license (CC BY 4.0)](https://creativecommons.org/licenses/by/4.0/), which allows
sharing and adapting the material when the creator is credited. See Figma's
[Community copyright and licensing guide](https://help.figma.com/hc/en-us/articles/360042296374-Figma-Community-copyright-and-licensing).

- **Creator:** Juxtopposed
- **Design:** [VLC Redesign (Community)](https://www.figma.com/design/5UEUReDQz2dQjwoQDHY5z9/VLC-Redesign--Community-)
- **Export collection:** [Olmo Gutierrez's Figma SVGs and palette](https://github.com/Olmo-Gutierrez/VLC-juxtopposed/tree/2c4b704edc49e01b6375de034ff8c85aa592918f/design)
- **License:** [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)
- **Changes:** selected icons are recolored at render time; the theme maps the
  exported paint styles to VLC Neo's UI colors.

The local `figma-icons/` collection was compared against that pinned commit by
filename and SHA-256 of each file's bytes: all 206 exports match exactly, with
no missing, extra, or same-name/different-content SVGs. The bundled
[`SHA256SUMS`](figma-icons/SHA256SUMS) also verifies the SVGs and index.

The separate `design/figma-assets/` collection from
[SpeedyPete25/Juxtopposed-VLC-Rebuild at `08bdb004`](https://github.com/SpeedyPete25/Juxtopposed-VLC-Rebuild/tree/08bdb00457fbab934413ba1f7a79cdd65101e70d/design/figma-assets)
was checked by Git blob hash against all 206 pinned SVGs above. None of its 64
SVGs is byte-identical to a file in the canonical set; 32 share a filename,
but all 32 have different bytes. Some also include non-icon content: its
`volume-high.svg` contains a dark background and a selection-frame outline, and
its `folder.svg` has different path geometry. The canonical Olmo exports remain
the source for matching icons; matching filenames in this alternate set are
not treated as proof of matching artwork.

The rest of VLC Neo's bundled icons are Lucide icons, covered by
[`icons/LICENSE.lucide`](../icons/LICENSE.lucide).
