# Placeholder SFX

34 original, synthesized (not recorded/sampled) WAV files — one for every
`Config.Sounds` field and every per-monster `chaseSoundId` /
`jumpscareSoundId` / `idleSoundId`. See `../../SOUND_DESIGN.md` for the full
file-to-Config mapping and upload instructions.

Regenerate or tweak them with `tools/synthesize_sfx.py` (needs `numpy`:
`pip install numpy`):

```
python3 tools/synthesize_sfx.py sfx/placeholder
```
