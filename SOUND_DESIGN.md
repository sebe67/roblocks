# Sound Design Brief

Every sound in this game is wired up in code and will "just work" the
moment you paste a real asset ID into `Config.lua` — no other file needs to
change. Right now everything defaults to `""` (silent, no error) except the
monster footstep loops, which use a sound bundled with every Roblox client
so the game isn't totally silent even before you add anything.

## Placeholder audio is already generated for every slot

I can't reach the general internet from here (only a couple of allowlisted
hosts, none of them audio libraries) and I don't have the ability to record
real voices or upload anything to Roblox on your behalf — that last step
needs your account either way, since Roblox only accepts audio through
Studio/the Creator Dashboard, moderated. What I *can* do is synthesize
original audio with plain DSP (sine/noise/envelope math via numpy, no
samples, nothing lifted from anywhere), so that's what's in `sfx/placeholder/`
in this repo: **39 finished, non-infringing WAV files, one for every single
`Config.Sounds` / per-monster slot** — including Tung Tung Tung Sahur and
`OvertimeWarning`/`BlackoutSting`, both added to the roster/Config after the
original 34 were generated, backfilled the same way.

They're synthesized, not recorded — so `chase_barney.wav` is a low
distorted-roar-style stinger and `idle_george.wav` is a rapid high tremolo
"chatter", not an actual barney/monkey sound. Genuinely usable as real
placeholders (there's audible signal, sensible duration, no clipping), not
just tone-generator noise, and every monster's pitch/style is derived from
its existing `footstepPitch` in `Config.lua` so the roster keeps sounding
consistent per-character. Treat these as v1 — swap any of them out later
using the sourcing brief further down whenever you have time to hunt for
(or record) something better.

### File → Config field mapping

Global (`sfx/placeholder/*.wav` → `Config.Sounds.*`):

| File | Config field |
|---|---|
| `store_ambience.wav` | `StoreAmbience` |
| `heartbeat.wav` | `Heartbeat` |
| `round_start.wav` | `RoundStart` |
| `intermission_start.wav` | `IntermissionStart` |
| `exit_unlocked.wav` | `ExitUnlocked` |
| `escape_success.wav` | `EscapeSuccess` |
| `caught.wav` | `Caught` |
| `ui_click.wav` | `UIClick` |
| `minigame_success.wav` | `MinigameSuccess` |
| `minigame_fail.wav` | `MinigameFail` |
| `overtime_warning.wav` | `OvertimeWarning` |
| `blackout_sting.wav` | `BlackoutSting` |

Per-monster (`chase_<id>.wav` / `jumpscare_<id>.wav` / `idle_<id>.wav`, `<id>`
lowercased, e.g. `chase_thomas.wav`, `chase_tungsahur.wav`) → that monster's `chaseSoundId` /
`jumpscareSoundId` / `idleSoundId` in `Config.Monsters`.

### Getting them into the game

1. In Studio: **View → Toolbox → Inventory tab → Audio**, then use the
   upload button (or drag the `.wav` file in) — or upload via the
   [Creator Dashboard](https://create.roblox.com/) under Creations → Audio.
2. Once approved, Roblox gives you an asset ID. Paste
   `"rbxassetid://123456789"` into the matching `Config.lua` field from the
   table above.
3. Done — no other code changes. These are fully original synthesized
   waveforms, so there's nothing for Roblox's copyright moderation to flag.

## If you want better/real sounds later

This is the shopping list: what each slot is going for, and where to look
for something closer to the real thing than a synthesized placeholder.

## How to fill in a slot

1. Get a sound onto Roblox as an **Audio** asset (Studio → Toolbox → Audio
   tab to browse/upload, or the [Creator Dashboard](https://create.roblox.com/)
   to upload your own file). Approved audio gets an asset ID.
2. Paste `"rbxassetid://123456789"` into the matching field in
   `src/ReplicatedStorage/Shared/Config.lua`.
3. That's it — no script changes. Test in Studio Play mode.

If you don't have your own audio and don't want to record anything, Studio's
Toolbox **Audio** tab has a large library of free, pre-approved sounds
(search terms suggested below for each slot) that you can drop in in
minutes.

## Legal note — read this before sourcing monster voices

**Do not use actual clips of these characters' voices, catchphrases, or
theme songs** (a real Barney "I love you" song, Thomas's whistle from the
show, etc.) unless you have the rights to them. Roblox actively moderates
uploaded audio for copyright and a match will get the asset (and
potentially your account) actioned. Every brief below is written to evoke
the character through *generic, non-infringing* sound design (pitch, tone,
animal/mechanical noises) rather than lifting anything from the source
media.

## Global / UI sounds (`Config.Sounds`)

| Field | What it's for | Brief | Toolbox search idea |
|---|---|---|---|
| `StoreAmbience` | Loops for everyone, all the time | Low, dry, slightly unsettling retail hum — HVAC drone, distant flickering fluorescent buzz, maybe a faint muzak loop turned dissonant. Should sit under everything else without being noticed consciously. | "ambient drone loop", "horror ambience", "fluorescent hum" |
| `Heartbeat` | Loops, volume/pitch ramp as any monster gets close | A single heartbeat loop, works at both a slow resting pace and (via the game's automatic pitch bump) a panicked pace. | "heartbeat loop", "horror heartbeat" |
| `RoundStart` | One-shot when a round begins | A short, upbeat-but-ominous bell/horn — think "store opening" chime with a wrong note in it. | "store bell", "cash register ding", "wrong note chime" |
| `IntermissionStart` | One-shot when the between-rounds countdown begins | Something that says "get ready" — a low synth swell or a single ominous gong. | "tension riser short", "dark swell" |
| `ExitUnlocked` | One-shot for everyone when all stations clear | Triumphant but short — a fanfare or unlock/clunk + chime combo. | "unlock fanfare", "door unlock chime" |
| `EscapeSuccess` | One-shot for the escaping player | Bright, victorious, brief — this is their "you won" sting. | "success jingle", "win sound short" |
| `Caught` | One-shot, plays instantly on capture (before the jumpscare scream) | A hard, physical impact — thud, slam, or a sharp orchestral hit. This is the "gotcha" punch that lands before the scream. | "impact hit", "horror stinger hit" |
| `UIClick` | Reused on every button/interaction across the whole game | A small, neutral click/blip. Should be unobtrusive since it plays a lot. | "ui click soft", "button tap" |
| `MinigameSuccess` | One-shot, any station cleared | Short positive chime, distinct from `ExitUnlocked` (that one should feel bigger). | "success chime short", "correct answer ding" |
| `MinigameFail` | One-shot, any station failed/given up | Short negative buzz/thud — not too harsh, players will hear it a lot while learning the minigames. | "fail buzz short", "wrong answer buzz" |
| `OvertimeWarning` | One-shot, the instant Overtime begins (10 min mark) | Big and alarming — a klaxon, a discordant orchestral hit, something that says "everything just got worse." This is the one sound in the whole game that's allowed to be jarring. | "alarm klaxon", "horror sting dramatic", "dissonant orchestral hit" |
| `BlackoutSting` | One-shot, the instant a store-wide blackout kills the lights | Quick and electrical, not musical — power cutting out, not a chime. SpongeBob's own local `lightsOut` quirk is silent and doesn't use this; it's only the global random blackout event. | "power outage sound", "electrical zap short", "lights out sting" |

Overtime also automatically pitches down and distorts every *monster* sound
(footsteps, chase stingers, jumpscares, idle tells) via a shared SoundGroup
— tune `Config.Overtime.PitchOctave`/`DistortionLevel` to taste, no extra
audio asset needed for that part.

## Per-monster sounds (`Config.Monsters[n]`)

Each monster has four slots. `footstepSoundId` already defaults to a real
built-in Roblox sound (`rbxasset://sounds/action_footsteps_plastic.mp3`)
with a per-monster `footstepPitch` for character — swap it only if you want
something punchier than generic footsteps. The other three are empty and
are where the personality really lives:

- **`chaseSoundId`** — fires once, the instant it spots you and locks into a
  chase. This is the "oh no" stinger.
- **`jumpscareSoundId`** — fires in your ear (2D, not positional) the
  instant it catches you, at the same moment as the `Caught` impact sound
  (was staggered 0.15s later, but that read as a delay rather than a
  deliberate beat). This is the scream/gotcha moment. **Currently empty for
  every monster on purpose**:
  `JumpscareController.lua` falls back to `Config.Sounds.JumpscareScream`
  whenever a monster's own slot is blank, so right now every monster shares
  one scream (`sfx/sourced/jumpscare_scream.mp3` — a real sourced sound,
  not a synthesized placeholder — still needs uploading through
  Studio/the Creator Dashboard and its `rbxassetid://...` pasted into that
  field). Filling in an individual monster's `jumpscareSoundId` later
  overrides just that one, no code changes needed.
- **`idleSoundId`** — fires occasionally while patrolling as an audio tell
  players can learn to recognize and avoid. For Dora specifically, this
  slot is repurposed as her signature "callout" line, fired the instant she
  spots a player (see `MonsterAI.lua`'s `callout` quirk handling) instead of
  randomly.

| Monster | `chaseSoundId` brief | `jumpscareSoundId` brief | `idleSoundId` brief |
|---|---|---|---|
| Curious George | Sharp, high-pitched screech/chatter | Loud, prolonged shriek | Curious chittering/chatter, short |
| Peppa Pig | Excited, distorted snorting | Cheerful giggle pitched down into something wrong | Oink/snort, playful |
| Thomas the Tank Engine | Whistle blast + accelerating mechanical chug | Loud horn blast layered with metal screech | Rhythmic chuffing/train wheel clack, short loop-able burst |
| Barney | Deep, guttural roar | Distorted, layered laugh — big and bassy | Low contented hum/purr |
| The Grinch | Sinister cackle, sudden | Loud cackle into a screech | Sly, quiet chuckle |
| Kung Fu Panda | Whoosh + heavy impact thud | Loud battle shout | Grunt or a soft belly laugh |
| SpongeBob | Excited, high-pitched laugh | Maniacal laugh, pitched/distorted | Giggle — **this is his whole "giggler" quirk's audio tell**, make it recognizable and a little unsettling |
| Dora | Declarative "spotted you" alert sting | Loud, sudden shout | Her "callout" line — something declarative/announcing, since narratively she's telling every other monster where you are |
| Tung Tung Tung Sahur | Heavy, resonant wooden thud/knock building into a chant-like rhythm | Deep, distorted roar with a wooden-percussion edge | Rhythmic knocking (like wood-on-wood), slow and deliberate |

Toolbox search ideas that work across the board: "monster growl", "creature
screech", "cartoon scream distorted", "horror stinger", "creepy giggle",
"train whistle", "animal roar". Pitch-shifting a handful of generic
growl/scream/giggle sounds (using each monster's existing `footstepPitch`
as a rough guide — high pitch for George/Peppa/SpongeBob, low for
Barney/Thomas) gets you eight distinguishable characters from 2-3 source
sounds if you don't want to hunt down eight unique ones.

### Where to look beyond Studio's Toolbox

I can search the web from here but can't download binary files or verify
licenses myself, so treat these as starting points — always check the
license on the specific file you grab, not just the site's homepage:

- [OpenGameArt.org CC0 Sound Effects](https://opengameart.org/content/cc0-sound-effects) — includes a public-domain creature/growl pack.
- [99Sounds free jumpscare & cinematic impacts pack](https://99sounds.org/rumore-cinematic-impacts/) — 50 free stingers/impacts, good for `Caught`/`chaseSoundId`.
- [Freesound.org](https://freesound.org) — huge searchable library; filter by CC0 specifically, since not everything there is.
- [itch.io sound packs](https://itch.io) — search "monster sfx" or "horror sfx"; many are name-your-price, some CC0 — read the included license file.
- [ElevenLabs' free sound effect generator](https://elevenlabs.io/sound-effects/scary-jumpscare) — type a text description ("high-pitched cartoon monkey screech") and it generates a custom AI sound effect you can preview/download for free without an account for occasional use — probably the fastest way to get closer-to-real character sounds without recording anything yourself.

## What's already wired and needs nothing further

- **Proximity heartbeat**: automatically ramps in as any monster (chasing
  or not) gets within `Config.Sounds.HeartbeatMaxDistance` studs *by line of
  sight*, maxes out at `HeartbeatMinDistance`. A monster on the other side
  of a wall doesn't count no matter how close it is in raw distance
  (`AmbienceController.lua`'s `hasLineOfSight`, a client-side raycast with
  the same Floors/Ceiling-never-occlude exclusions `MonsterAI.lua` uses for
  its own sight checks) — tune the two distance numbers to taste. One
  shared heartbeat for every monster right now (deliberately, not a bug —
  it's a generic "something's near" dread cue, not "which monster is
  near"); making it per-monster later would mean the client looking up the
  nearest monster's `def.id` and checking for a per-monster override before
  falling back to this shared one, no bigger a change than that.
- **Footstep character**: volume and pitch already scale up automatically
  when a monster shifts from Patrol → Chase (the only two states that
  exist), so footsteps alone telegraph how much danger you're in.
- **Minigame click feedback**: every interactive button in all three
  minigames already plays `Config.Sounds.UIClick` — filling in that one
  field covers all of them at once.

## If you want to go further

- Distinct success/fail stingers **per minigame station** (currently all
  three share `MinigameSuccess`/`MinigameFail`) — would mean adding
  `successSoundId`/`failSoundId` to each `Config.Minigames` entry and
  reading them in `MinigameController.lua`'s `endGame` instead of the
  global fields.
- A countdown tick in the last few seconds of a minigame — not wired yet;
  would need a small addition to each minigame module's Heartbeat loop.
- Voice-acted `flavor` lines (the death-screen taglines) read aloud —
  would need actual recorded lines per monster, which is a bigger lift than
  short SFX.
