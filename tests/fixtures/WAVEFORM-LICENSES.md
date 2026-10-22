# Waveform audio fixtures

These 10-second mono Vorbis excerpts are included to exercise waveform decoding
with real audio that has different timbral and dynamic profiles. The excerpts
are trimmed from the following CC0 1.0 works; CC0 does not require attribution,
but the source details are retained here for clarity.

- `waveform-jazz.ogg`: “Jazz at the park”, Manwithmetalpig, [Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Jazz_at_the_park.ogg), [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/). Trimmed to 10 seconds, converted to mono 48 kHz Vorbis.
- `waveform-classical.ogg`: “Forget Me Not”, Kistol, [OpenGameArt](https://opengameart.org/content/forget-me-not), [CC0](https://creativecommons.org/publicdomain/zero/1.0/). Trimmed to 10 seconds, converted to mono 48 kHz Vorbis.
- `waveform-electronic.ogg`: “Empacotatron”, Fupi, [OpenGameArt](https://opengameart.org/content/empacotatron), [CC0](https://creativecommons.org/publicdomain/zero/1.0/). Trimmed to 10 seconds, converted to mono 48 kHz Vorbis.

Run `scripts/test-waveform-variety.sh` to verify the asynchronous VLC waveform
decoder on all three samples and write screenshots for visual inspection. Set
`NEO_WAVEFORM_OUTPUT_DIR` to choose where the screenshots are saved; by default
the script creates a retained temporary artifact directory and prints its path.
