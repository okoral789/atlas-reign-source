# Original 2D fleet markers

Three original grayscale masks, drawn by
`tools/frontier/generate_fleet_markers.py` and uploaded to the game owner's account.
They face right. Roblox applies the nation color to the complete mask and rotates
it as one object, avoiding the old pale outline covering the small colored fill.

- `landing.png`: broad, flat-front landing barge with an open troop bay.
- `trade.png`: compact cargo hull with three container blocks.
- `warship.png`: larger pointed hull with a bridge, two turrets and barrels.
- `preview.png`: local rotation/readability review at enlarged and game sizes.

An existing owned fleet accent remains as a narrow stern band. Native geometry
remains as a loading fallback. No ship classes or orders were added.

PNG outputs are dedicated to CC0-1.0 by the Atlas Reign contributor, to the extent
rights exist. The generator and client code retain the project source licence.
No external art was used. `generated.json` records hashes and `uploaded.json`
records owner-hosted asset IDs. The generator verifies distinct silhouettes,
alpha and grayscale masks. All three assets were Active/Approved and loaded in
the Roblox engine before the release checkpoint.
