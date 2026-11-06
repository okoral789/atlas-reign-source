# Frontier asset audit — 2026-10-31

Scope: the current native Roblox release tree (`release.project.json`), every
`src/shared/Assets` manifest, direct content references outside the manifests,
and the corresponding source asset files. This is an evidence-based technical
licensing audit, not a legal ownership warranty or a separate permission from
another creator. An accessible asset ID is not evidence of a copyright licence.

## Findings and changes

| Family | Evidence / finding | Action and licence |
| --- | --- | --- |
| Program, UI code, shaders and build tools | Pinned RoWorld source and unchanged LICENSE; derived from OpenFront | Retain AGPL v3 plus its additional terms, attribution, change notices, complete source obligation |
| Old chest model / texture | External BedWars/Tribes IDs; no separate author permission supplied | Removed all external meshes and texture; original supply case made from Roblox Parts |
| Audio / AudioUI / AudioExtra | AIRFRONT or BedWars-pack source files and separate permissions not present | Replaced every audio ID with original synthesized cues; no external samples; original outputs CC0 |
| Rodrigo Flores soundtrack | Upstream says CC BY 4.0, but original bundle/licence/files not supplied | Removed tracks rather than treating an upstream purchase as our permission; two original synthesized ambient beds, CC0 |
| Old menu icon raster images and branding | Generator points to missing AIRFRONT vector source | Replaced with 49 original geometric masks/emblem, CC0; original generators included |
| World and continent map data | Natural Earth and NOAA ETOPO1, public-domain source URLs in importer | Retain; no new private OpenFront data copied; geographical previews regenerated in new palette |
| Two new map layouts | Authored by `tools/frontier/generate_maps.py`; no imported imagery | Twin Straits and Iron Archipelago, CC0; symmetry and country spawns tested |
| Country flag drawings | Per-drawing `assets/flags/SOURCE.txt`: 251 public-domain and 7 CC0 entries | Retain sources and selected licences; alternative restricted drawings mentioned in the header are not selected; insignia rules can still apply |
| Map sprites, Arsenal art/FX | RoWorld generator declares original art; procedural sources and authored sheets included | Retain under project AGPL terms; includes upstream AI-generated sheets, not independently certified ownership |
| Shop flags | Source prompts/art in `assets/shop_flags`; generated for RoWorld | Retain as project source under AGPL; no OpenFront premium/CDN collection copied; AI artwork provenance is documented, not a warranty |
| Rail art, skin previews, UI masks/shadows, crate effects | Procedural generators or authored SVG source included | Retain upstream terms and sources; rail generator identifies shader derivation, covered by the program licence |
| Old globe art | Generator requires missing AIRFRONT world images; absent from current runtime | Quarantined from this branch/source package, along with superseded branding/menu icon PNGs; recoverable in the private baseline tag |
| Roblox fonts/UI textures/avatars | Platform-supplied font IDs, built-in `rbxasset://` textures and avatar services | Use under Roblox terms; do not claim ownership or redistribute them as CC0 files |
| OpenFront `/proprietary` and external premium/CDN assets | No reusable general grant | Not imported or licensed by this work. Do not add them. `/resources` assets, if introduced later, require their CC BY-SA terms and attribution |

## Machine-readable evidence

- `assets/baseline-inventory.json`: original manifest IDs, headers and hashes.
- `assets/register.csv`: every current manifest asset reference and its basis.
- `assets/removed.csv`: superseded references and reasons; generator asserts none
  remain in runtime manifests.
- `assets/file-register.csv`: source asset file hashes and licence evidence.
- `../assets/frontier/uploaded.json`: new IDs, source hashes and owner account.
  `universe-permissions.json` records explicit grants to universe 10774039150.
- `../NOTICE.md`, `../LICENSE`, `../licenses/CC0-1.0.txt`: shipped notices/texts.

Regenerate the register with `python tools/frontier/audit_assets.py`. The only
non-manifest `rbxassetid://` reference identified was `123` in an AudioDirector
documentation example, not a loaded asset. Dev probes are excluded from release.

New uploads use Koralxok's account and explicit permissions for this universe.
Retained legacy IDs still depend on their owner's availability/permissions;
copyright permission and Roblox asset access are separate questions. Keep source
images/generators available for a controlled migration if these IDs stop loading.
Cloud validation must check the actual image workflow, not just 1×1 allocation.

## Public/monetized release

Commercial use is allowed by the code licence while its conditions are met; a
percentage of graphical changes does not remove copyleft. This audit has not
obtained a separate proprietary/commercial licence, certified every third-party
author's chain of title, cleared the Frontier trademark, or approved a public
launch under all local laws. See PUBLIC-RELEASE.md for the concrete unresolved
source-distribution/platform-policy point and the Robux price proposal.

Primary evidence:
- https://github.com/lukechatton/roworld/blob/2bc850dbc253f644fe2640d73b544d963e82fe51/LICENSE
- https://github.com/openfrontio/OpenFrontIO/blob/main/LICENSE-ASSETS
- https://www.naturalearthdata.com/about/terms-of-use/
- https://www.ngdc.noaa.gov/mgg/global/dem_faq.html
- https://creativecommons.org/publicdomain/zero/1.0/
- https://create.roblox.com/docs/projects/assets

## Atlas Reign identity update (v0.4)

Five original AI-assisted PNGs replace the old emblem/Credits mark and case UI,
and add a three-column fleet atlas. See `assets/atlas/PROMPTS.json` for prompt
briefs, source hashes and owner-owned Roblox asset IDs; `permissions.json` grants
use to this universe. All five were loaded as EditableImages in Roblox. The
fleet is processed to 1023x341 pixels, so the runtime uses 341x341 UV cells.
The new support preview uses native GUI geometry, with no remote demo-map dependency.
These outputs are CC0 to the extent rights exist, without a trademark or
third-party ownership warranty. Prior upstream notices remain applicable.


## Crest collection and border effects (v0.13)

Eight original text-free crest flags are generated from geometric primitives by
`tools/frontier/generate_crest_flags.py`; PNG artwork is CC0 1.0. Their source
files and eight owner-hosted image IDs are recorded in the asset registers.
The flag motifs, eight appended gradients and four border variants add no
third-party images or fonts. The shared continuous border shader is project
code under the repository licence. Existing upstream artwork notices remain.
No paid audio is added: `AUDIO-SHORTLIST.md` records candidates, primary licence
links and the explicit WOW Sound Roblox exclusion. Vendor game-use permission
has not been treated as automatic permission to grant Roblox's platform rights.

## Owner-supplied Cute & Cozy UI audition (2026-11-05)

The owner supplied Case Portman Audio's full Cute & Cozy UI SFX Pack and its
Royalty-Free Sound Effects License. That text permits game use, commercial
projects, editing and inclusion in distributed projects; attribution is optional.
It prohibits standalone redistribution of recordings and does not make them CC0.
Atlas Reign uses 19 selected recordings for 20 existing cues. Original
ZIP/WAV files, licence evidence, content hashes and Roblox upload records remain
under ignored `build/cozy-ui-test/`, `build/cozy-ui-fixes/` and `build/camera-hud-audio/`. Elimination uses
`Success_04` and construction `Confirm_09`, with playback trims of -6 and -4 dB.
Missile launch uses a separate CC BY 3.0 battle recording. The public source
includes the Roblox asset IDs for the licensed UI audio. The recordings
themselves require a separate licence for reuse in another project.

The owner selected launch C + explosion E on 2026-11-05. Those two lossless
sources are Michel Baradari's `flaunch.wav` (4 projectile launches) and dklon's
`explosion_4.wav` (Boom Pack 2), licensed CC BY 3.0. The transport recording is
jcpmcdonald's Skippy Fish Water Sound Collection, CC0 1.0. Author/source URLs,
processing and hashes are in `assets/audio-cartoony/sources.json`; original
CC BY files and the licence are included. Help & Credits names the authors,
works, licences and edits. They are not Case Portman recordings.
The rejected v35 Missile/Cartoon Explosion and subsequent A/B variants are inactive.
