# Territory VFX sprites

Original code-drawn 2D neon and flame sprites. PNG outputs are dedicated under
CC0-1.0; the generator remains under the program licence. No third-party source
art or models were used. `generated.json` and `uploaded.json` retain hashes,
asset IDs and the creator account.

The renderer samples only visible owned land, limits the scan to 768 candidates
per refresh and draws at most 64 sprites (12 per owner). It skips distant zoom
and keeps the static territory mask. UI previews reuse the same sprites.
