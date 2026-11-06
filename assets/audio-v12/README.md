# Original tactical sound cues

17 distinct mono 44.1-kHz PCM WAVs generated without external samples by
`tools/frontier/generate_battle_audio.py`. WAV recordings: CC0-1.0; generator:
project licence. `generated.json` records SHA-256, duration, peak and RMS.
`uploaded.json` records the experience owner's hosted assets. The client loads
whole cue files, avoiding playback-region seeking for the new effects.

After owner uploads using `tools/frontier/upload_assets.py`'s `upload` helper,
`python tools/frontier/install_battle_audio.py` reproduces the 65 sound bindings.
Existing cue files are fallback streams while these load. Existing music,
cooldowns, voice limits, audio groups and saved preferences remain.

`build/audio-v12-probe.json` was an initial read-only native Sound load probe;
the final release's native check repeats all 17 loads against its exact build.
