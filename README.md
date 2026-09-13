# IKEA of the Damned

A co-op horror party game for Roblox: escape a procedurally generated,
maze-like IKEA superstore while eight unhinged "childhood mascot" monsters
hunt you by sight. Clear every minigame station scattered through the store
to unlock the loading dock and win.

This repo is a [Rojo](https://rojo.space/) project — source-controlled Luau
code that syncs straight into Roblox Studio. There is no `.rbxl` file in
here; the whole store, every monster, and every UI screen are built by code
at runtime.

## Quick start

1. Install [Rokit](https://github.com/rojo-rbx/rokit#installation) (macOS/Linux:
   `curl -sSf https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.sh | bash`;
   Windows PowerShell:
   `Invoke-RestMethod https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.ps1 | Invoke-Expression`).
2. From the repo root, run:
   ```
   rokit install
   rojo plugin install
   ```
   The first command reads this repo's `rokit.toml` and installs the exact
   pinned Rojo version; the second installs the Rojo Studio plugin.
3. Still from the repo root, run:
   ```
   rojo serve
   ```
   and leave it running.
4. Open a new place in Roblox Studio, open the Rojo plugin panel, and click
   **Connect**.
5. Press Play (ideally with **multiple test server instances** — Studio's
   Test tab → Start → set Players to 2-4 — this is a multiplayer game).

The store, monsters, and stations are generated fresh by
`Main.server.lua` every time the server starts, so there's nothing to build
or bake ahead of time.

## What's actually implemented

- **Procedural store** (`MazeGenerator.lua`): not a uniform small-cell maze
  but a series of big rectangular rooms (`Config.Maze.MinRoomSize`-
  `MaxRoomSize`, 3-5 base cells per side — 66-110 studs) greedily tiled
  across a 22x22 grid, each room a single open floor plan inside. A
  recursive-backtracker spanning walk over the *rooms* (not fine cells)
  picks one connector per adjacent room pair — most are a narrow doorway
  (`Config.Maze.DoorwayWidth`), some (`HallwayChance`) are a wider open
  gap — plus a few extra shortcut connections (`LoopChance`). No boulevards
  or forced-open main aisles anymore; every non-open-floor passage is an
  actual doorway you have to find. The whole grid is split into four
  roughly-quadrant color "wings" (`Config.Maze.ColorZones`) so wall color
  reads as a sense of place instead of random noise, with an occasional
  off-palette wall/shelf (`ZoneAccentChance`) so it's not forced monotone.
  Wall/doorway segments trim only the end that actually meets a
  perpendicular wall or doorway (`hasWallMaterial` in `MazeGenerator.lua`)
  instead of always shaving a fixed amount off both ends — the old
  always-trim approach left thin gaps along the long open room boundaries
  this room-based layout produces.
  Plus IKEA-blue/yellow shelf units, fake-Swedish aisle signage
  (`GRÖNKVIST`, `MÖRKHUS`, ...), a lobby/entrance, a locked "loading dock"
  exit, and six minigame rooms.
- **Lighting** (`StoreTheme.lua`): dim ambient + fog + a subtle atmosphere,
  with only roughly 1-in-3 ceiling fixtures actually lit, plus some dead
  fixtures that flicker briefly at random. Dim, not pitch black.
- **8 monsters**, each with its own stat block and one mechanical quirk, all
  tuned in `ReplicatedStorage/Shared/Config.lua` (see below).
- **Sight-based AI** (`MonsterAI.lua`): a Patrol → Investigate → Chase →
  Search state machine. A monster only ever starts a real chase because it
  directly saw a player (distance + field-of-view cone + an unobstructed
  raycast) — it never teleports knowledge of your position into itself.
  "Investigate" (from noise or Dora's callout) only ever sends it toward a
  *location*.
- **Sprinting**: hold Shift, infinite, no stamina bar (`SprintController.lua`).
- **3 minigame stations** that require real attention and periodically ping
  every nearby monster while active (`MinigameService.lua` +
  `StarterPlayerScripts/Minigames/*`). Clearing all of them unlocks the exit
  (`ExitService.lua`).
- **Jumpscare → Respawn/Spectate flow** (`PlayerService.lua` +
  `JumpscareController.lua` + `DeathController.lua` +
  `SpectateController.lua`): getting caught freezes you, shows a jumpscare
  for the monster that got you, then offers Respawn (brief invulnerability)
  or Spectate (camera follows another living player, cycle with `,` / `.`).
- **Round loop** (`GameState.lua`): Waiting → Intermission countdown →
  Playing → Results, looping forever. A round also force-ends after 10
  minutes so nobody's stuck in a stalemate.
- **A Gen Z/Alpha-flavored results screen** ("CAUGHT — L + ratio", "ESCAPED
  — unbeatable NPC energy", etc.) via `HUDController.lua`.

## The monster roster

| Monster | Vibe | Mechanical quirk |
|---|---|---|
| Curious George | fast, erratic | randomly juks direction mid-chase |
| Peppa Pig | medium | short speed bursts ("snort") while chasing |
| Thomas the Tank Engine | slow patrol, very fast chase | **too wide for narrow doorways** — can only cross between rooms via the wider hallway-style gaps |
| Barney | slow, huge | loud footsteps (bigger hearing radius) — telegraphed |
| The Grinch | fast | faster and sees further in cells whose ceiling fixture is actually dead |
| Kung Fu Panda | medium | occasional straight-line dash burst |
| SpongeBob | medium | giggles while patrolling — a red herring cue |
| Dora | medium | **spotting you alerts every other monster to your last position** |

Thomas's restriction isn't a special-cased graph anymore — it falls out
naturally from giving him a much larger `pathAgentRadius` in
`MonsterAI.lua`'s PathfindingService calls than every other monster. A
bigger agent radius makes Roblox's navmesh solver treat narrow doorways as
too tight to fit through, so he's automatically routed only through wide
hallway gaps and open rooms, with zero bespoke pathing code. Simpler than
the old rail-graph approach and ties his restriction directly to the new
room/doorway structure instead of an arbitrary lattice.

You asked for more roster ideas: **Bluey, the Teletubbies (Tinky Winky),
Cocomelon's JJ, and SpongeBob/Dora's Nickelodeon stablemate Baby Shark**
would all fit the same "wholesome mascot gone wrong" tone if you want to
keep expanding past 8. Adding one is just a new entry in `Config.Monsters`
— no other code changes needed.

## The win condition (per your call)

Six stations — **Restock: Aisle of Regret** (color-matching), **Flat-Pack
Rage Build** (growing Simon-says sequence), **Self-Checkout Vibe Check**
(timing-based scanner), **Inventory Count** (memorize-then-recall),
**Customer Service Rush** (multi-target reaction), and **Forklift
Certification** (continuous hold-to-steer tracking) — are spread evenly
across the maze, each a genuinely different interaction style. Walking up
and holding the ProximityPrompt starts one; while it's active it
periodically "pings" a radius around the station, pulling any monster
within range into Investigate — so playing a station is a real risk/reward
decision, not a safe minigame break. Clear all six and the loading dock
door (`ExitDoor`) tweens open; touch the zone just past it to escape and
win.

Adding a 7th is: a new client module under `Minigames/`, a line in
`MinigameController.lua`'s `GAMES` table, and a `Config.Minigames` entry —
station placement (`MazeGenerator.lua`) automatically spreads however many
entries exist across the grid, no placement code to touch.

## Overtime

If nobody's escaped after `Config.Round.MaxRoundTime` (10 minutes), the
round doesn't just end — every monster goes into Overtime: much faster,
omniscient targeting of whoever's nearest with no more sight/range checks,
and every monster sound gets pitched down and distorted (via a shared
SoundGroup + PitchShift/Distortion effects) for extra dread, plus a red
screen tint and a warning banner. It runs for `Config.Round.OvertimeDuration`
(90s) as a hard cap — after that, whoever's still standing gets swept
regardless, so the round can never hang forever even if someone keeps
clicking Respawn into it. Dying (even during Overtime) never force-ends the
round on its own — Respawn/Spectate always stays live for anyone who hasn't
resolved their choice yet; the round only ends early once everyone has
actually escaped or given up.

**Testing it without waiting 10 minutes:** type `/godmode` in chat during an
active round to skip straight to Overtime. It's wired up in
`Main.server.lua` (`Player.Chatted` → `GameState:RequestOvertime()`) and
currently open to any player — fine for testing, but gate it (e.g. to
specific `UserId`s) before this ever goes public.

Adding a fourth station is: build its client module under
`StarterPlayerScripts/Minigames/`, register it in
`MinigameController.lua`'s `GAMES` table, and add an entry to
`Config.Minigames`. The server-side station wiring (prompt, noise pulses,
completion tracking) is entirely data-driven and needs no changes.

## Important limitations — read before you build on this

**I cannot ship the actual characters.** Curious George, Peppa Pig, Thomas
the Tank Engine, Barney, The Grinch, Kung Fu Panda, SpongeBob, and Dora are
all copyrighted characters owned by other studios. I can't generate or
legally source their 3D meshes, rigs, animations, or voice clips. What's in
this repo instead is a small placeholder rig per monster (a colored capsule
body + a ball head in that character's signature colors + a floating name
tag) built entirely from primitive `Part`s in `MonsterAI.lua`'s
`createRig()` function, driven by the color/scale values in
`Config.Monsters`. It's instantly readable ("that's the blue-and-red one,
that's Thomas") but it is not the character.

To get real characters in, you have two realistic paths:
1. **Build/commission your own stylized designs** that are inspired by
   these characters without being them (recolors, different proportions,
   parody-styled) — safest for a game you intend to publish widely.
2. **Source or model your own R15 rigs/meshes** and swap them in — replace
   the body of `createRig()` in `MonsterAI.lua` with
   `game:GetObjectFromHash(...)`/`InsertService`/your own uploaded meshes,
   keeping the `Humanoid` + `HumanoidRootPart` contract so the existing
   pathfinding/animation code keeps working unmodified.

I did not go looking for Toolbox assets or generate images of these
characters, since I can't verify licensing on your behalf.

**Other things you'll want to do before this feels finished:**
- **Audio is wired up but empty.** Footsteps (3D, pitch/volume scale with
  patrol/chase state), a proximity heartbeat, chase stingers, jumpscare
  screams, minigame success/fail, and UI clicks all have working code paths
  and safely no-op until you paste in real `rbxassetid://...` values. See
  **[SOUND_DESIGN.md](SOUND_DESIGN.md)** for the exact brief and source
  suggestions for every slot in `Config.Sounds` and `Config.Monsters` — I
  can't generate or license actual audio (especially not character voice
  clips) from here, so this is the one area that's a creative brief rather
  than a finished asset.
- **Jumpscare visuals**: currently a colored full-screen flash + text +
  a small camera-FOV shake. Swap the flash `Frame` for a full-screen
  `ImageLabel` once you have (or commission) real jumpscare art.
- **Minigame result is client-reported.** `MinigameService.lua` trusts the
  client's pass/fail message for simplicity — a friend playing legitimately
  never notices, but a determined exploiter could fire a fake "success" via
  developer console. Fine for a private game with friends; if you ever
  open this to the public, move the win/lose check for each minigame onto
  the server.
- **Visual polish**: walls/floors/ceilings are flat-colored primitive
  `Part`s. It reads as "IKEA maze" at a glance (blue/yellow palette, fake
  Swedish aisle names, shelf details) but a pass with real materials,
  textures, and actual furniture models would sell it much harder. This is
  the one thing that's genuinely easier for you to do by hand in Studio
  than for me to generate procedurally.
- **Playtesting/balance**: every number that matters (sight range, monster
  speed, minigame duration/difficulty, round timer, sprint speed) lives in
  `ReplicatedStorage/Shared/Config.lua`. I haven't been able to actually
  playtest this (no Roblox client in this environment), so treat the
  starting numbers as a first draft to tune with your friend group.

## File map

```
default.project.json                 Rojo project definition
SOUND_DESIGN.md                      Sound brief/shopping list for every Config.Sounds / per-monster slot
src/ReplicatedStorage/Shared/
  Config.lua                         All tuning: monsters, minigames, maze, lighting, round timing, sounds
  Net.lua                            Lazy RemoteEvent/RemoteFunction lookup helper
  SoundKit.lua                       Play2D/loop3D/playAt sound helpers (safe no-op on empty SoundId)
src/ServerScriptService/
  Main.server.lua                    Boots everything, wires services together, /godmode chat command
  MazeGenerator.lua                  Room partitioning + doorway/hallway connectors + color zones + stations + exit
  StoreTheme.lua                     Lighting/atmosphere + dead-fixture flicker loop
  MonsterAI.lua                      Per-monster state machine + Overtime godmode + placeholder rig + monster audio
  MonsterSpawner.lua                 Spawns one of every Config.Monsters entry
  MinigameService.lua                Station wiring, noise pulses, exit-unlock trigger
  ExitService.lua                    Exit door lock/unlock + escape-zone detection
  PlayerService.lua                  Round state per player, catch/respawn/spectate/escape
  GameState.lua                      Waiting → Intermission → Playing → Results loop, Overtime trigger
src/StarterPlayerScripts/
  Main.client.lua                    Boots all client controllers
  UIUtil.lua                         Shared UI-building helpers
  CursorLock.lua                     Frees the mouse for clickable menus (fights the camera every frame)
  SprintController.lua               Shift-to-sprint
  AmbienceController.lua             Store ambience loop, proximity heartbeat, round/exit/escape stingers
  JumpscareController.lua            Full-screen jumpscare on catch + catch/scream audio
  DeathController.lua                Death/respawn/spectate menu + escape banner
  SpectateController.lua             Camera-follow spectating with target cycling
  MinigameController.lua             Minigame overlay + dispatch to the 6 minigame modules + success/fail audio/toast
  HUDController.lua                  Round phase, station progress, results screen, Overtime banner/tint
  Minigames/
    RestockShelves.lua
    FlatPackAssembly.lua
    SelfCheckout.lua
    InventoryCount.lua
    CustomerRush.lua
    ForkliftCertification.lua
```
