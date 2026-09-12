# Sound Design Brief

Every sound in this game is now wired up in code and will "just work" the
moment you paste a real asset ID into `Config.lua` — no other file needs to
change. Right now everything defaults to `""` (silent, no error) except the
monster footstep loops, which use a sound bundled with every Roblox client
so the game isn't totally silent even before you add anything.

This doc is the shopping list: what each slot needs, roughly how it should
sound, and where to get it.

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

## Per-monster sounds (`Config.Monsters[n]`)

Each monster has four slots. `footstepSoundId` already defaults to a real
built-in Roblox sound (`rbxasset://sounds/action_footsteps_plastic.mp3`)
with a per-monster `footstepPitch` for character — swap it only if you want
something punchier than generic footsteps. The other three are empty and
are where the personality really lives:

- **`chaseSoundId`** — fires once, the instant it spots you and locks into a
  chase. This is the "oh no" stinger.
- **`jumpscareSoundId`** — fires in your ear (2D, not positional) when it
  actually catches you, ~0.15s after the `Caught` impact sound. This is the
  scream/gotcha moment.
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

Toolbox search ideas that work across the board: "monster growl", "creature
screech", "cartoon scream distorted", "horror stinger", "creepy giggle",
"train whistle", "animal roar". Pitch-shifting a handful of generic
growl/scream/giggle sounds (using each monster's existing `footstepPitch`
as a rough guide — high pitch for George/Peppa/SpongeBob, low for
Barney/Thomas) gets you eight distinguishable characters from 2-3 source
sounds if you don't want to hunt down eight unique ones.

## What's already wired and needs nothing further

- **Proximity heartbeat**: automatically ramps in as any monster (chasing
  or not) gets within `Config.Sounds.HeartbeatMaxDistance` studs, maxes out
  at `HeartbeatMinDistance`. Tune those two numbers to taste.
- **Footstep character**: volume and pitch already scale up automatically
  when a monster shifts from Patrol → Investigate/Search → Chase, so
  footsteps alone telegraph how much danger you're in.
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
