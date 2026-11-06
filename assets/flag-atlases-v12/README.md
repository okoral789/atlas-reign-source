# Owner-hosted country flags

258 existing flag SVGs from `assets/flags/` repacked into five owner-hosted
atlases. The selected source drawings' individual public-domain/CC0 provenance
remains in `assets/flags/SOURCE.txt`. These atlases do not claim new flag
authorship or a blanket CC0 licence for every source. The earlier asset IDs
failed the experience's native asset access check and are superseded.

Reproduce raster packing with `tools/assets/make_flags.py --no-upload` using
its existing renderer dependency `resvg-py` (used here: 0.5.0) and Pillow.
`rects.json` records the regenerated coordinates and names; stable flag codes
and saved cosmetic IDs are preserved. `uploaded.json` records owner IDs and
hashes. Source SVGs, generated PNGs and the final `Assets/Flags.luau` manifest
are included in corresponding source.
