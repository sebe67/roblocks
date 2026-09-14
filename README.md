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

**You can delete the default Baseplate.** Nothing in this codebase
references it — the store builds its own floors, and `MazeGenerator.lua`
creates its own `SpawnLocation`s at the entrance before any player joins, so
Roblox spawns players there regardless of whatever else is (or isn't) sitting
in Workspace. A totally blank new place works fine.

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
  this room-based layout produces. (An actual sign-flip bug in that trim's
  center-offset math was also the cause of the real, non-tiny gaps that
  outlasted the first fix — invisible whenever a wall's two ends needed the
  same trim, which is most of the time, but a real several-inch hole at any
  corner where only one side did. Fixed, plus a small guaranteed overlap
  between touching parts as a second line of defense against pure
  render/float-precision seams.) Spawn is the entrance cell at the exact
  center of the grid — the intersection point of all four color zones —
  rather than a corner, and the room-graph spanning walk starts from there
  too, so connectivity radiates outward from where the round actually
  begins. `HallwayChance` (0.4) governs how often a room-to-room connector
  is a wide open hallway gap instead of a narrow doorway.
  Plus IKEA-blue/yellow shelf units, fake-Swedish aisle signage
  (`GRÖNKVIST`, `MÖRKHUS`, ...), a lobby/entrance, a locked "loading dock"
  exit, and six minigame rooms.
- **Lighting** (`StoreTheme.lua`): dim ambient + fog + a subtle atmosphere,
  with only roughly 1-in-3 ceiling fixtures actually lit, plus some dead
  fixtures that flicker briefly at random. Dim, not pitch black. Every
  ceiling fixture is its own addressable `Part` (`Fixture_x_y` in
  `maze.model.Fixtures`, one per grid cell) with its own `PointLight` — call
  `StoreTheme.SetFixtureWorking(maze, x, y, true/false)` to flip any single
  one on or off for a scripted event (power outage, a monster ability, a
  puzzle); it updates the light, the fixture's glow color, and the
  `Working` attribute together, so a scripted toggle reads identically to a
  naturally-dead fixture everywhere else that attribute matters (the
  Grinch's darkBoost quirk). Try it live with `/light <x> <y> <on|off>` in
  chat (wired up in `Main.server.lua`, open to any player for now — gate it
  before this goes public, same as `/godmode`).
- **8 monsters**, each with its own stat block and one mechanical quirk, all
  tuned in `ReplicatedStorage/Shared/Config.lua` (see below).
- **Sight-based AI** (`MonsterAI.lua`): a Patrol → Investigate → Chase →
  Search state machine. A monster only ever starts a real chase because it
  directly saw a player (distance + field-of-view cone + an unobstructed
  raycast) — it never teleports knowledge of your position into itself.
  "Investigate" (from noise or Dora's callout) only ever sends it toward a
  *location*. Every state moves the same way: `_steerToward(point)` turns
  toward whatever point matters right now (the player's live position
  during Chase, a `PathfindingService` waypoint everywhere else, including
  Chase when a wall blocks the direct line) and calls `Humanoid:Move()` —
  a continuous "here's my desired direction this frame" input, the same
  API a player's own WASD ultimately drives. **Nothing in `MonsterAI.lua`
  calls `Humanoid:MoveTo()` anymore.**

  That used to be the movement method for anything with a fixed
  destination — every patrol point, every investigate/search target, the
  pathfinding fallback during Chase — called once per frame toward whatever
  point that state currently wanted. `MoveTo` is built for a one-shot "walk
  to this exact spot and stop," and calling it every single frame toward a
  constantly-shifting target (a fresh random patrol point, a live player,
  whatever) resets the humanoid's internal walk/turn state on every call.
  That reset turned out to be the real source of the reported flailing —
  and critically, it wasn't specific to chasing a moving player (that was
  just the easiest place to *notice* it): plain Patrol, aiming at a
  perfectly static point with nothing chasing anything, showed the exact
  same wild left-right/backwards/overshoot behavior once it was actually
  checked, which is what gave this away — chase-specific fixes across
  several rounds couldn't have touched Patrol/Investigate/Search at all,
  since those never shared any of that code. Now every state, with no
  exceptions, drives movement through the one `_steerToward` primitive.
  Thomas (wideBody) still always takes the pathfinding path rather than a
  direct line, so he can't route himself through a doorway too narrow for
  him, same as before — he just steers toward his waypoints via `Move()`
  now too, like everything else.

  Two more chase-specific wrinkles in whether the direct line reads as
  clear (`_hasClearPath`): first, right next to a corner or doorway jamb
  that single spherecast reading can flicker to "blocked" for one frame
  from ordinary geometry noise. Reacting to that instantly used to mean
  requesting a brand new `PathfindingService` route and steering at *its*
  first waypoint that same frame — a real, brief detour off the player's
  actual position, visible as the monster veering to the side mid-chase.
  `BLOCKED_DEBOUNCE` (0.15s) fixes this: the blocked reading has to hold
  for that long before chase actually reroutes, so a one-frame flicker
  gets ignored and direct-chase just continues, while a genuine wall
  (which stays blocked well past that window) still reroutes quickly.
  Second, and more impactful: the spherecast has real width (sized to
  the monster's own `pathAgentRadius`), so aimed at a player it can clip
  an off-center part of *their own body* — a shoulder, an arm, their head,
  easily more than the couple studs a naive "close enough to the target"
  distance check tolerated — and misreport that as a wall in the way, with
  nothing actually blocking anything. Which body part (if any) gets
  clipped shifts constantly with approach angle, so this alone produced
  both symptoms: veering with nothing in the way, and repeated
  direct-chase/pathfinding switching that reads as erratic. `_canSee`
  already excluded the target's own body correctly (checking whether the
  raycast hit is a descendant of the target's character); `_hasClearPath`
  now takes the target's character as a second argument and does the same,
  instead of guessing a distance threshold.

  Debugging this also turned up that the flailing was reported worse for
  SpongeBob than other monsters despite all of them sharing this exact
  movement code — the one per-frame difference was his `lightsOut` quirk
  update running inline inside the same `Update()` call that drives
  movement, so it's now been moved onto its own independent `task.spawn`
  timer (see `_updateLightsOut`), guaranteeing it can never affect a
  movement command's timing for that frame regardless of what it does
  internally.
  Monsters are scattered at least `Config.Maze.MonsterSpawnExclusionCells`
  cells from the (now-central) spawn point both at server boot and again at
  the start of every round (`MonsterSpawner.RepositionAll`), so one can't
  end up camping the entrance between rounds.
- **Sprinting**: hold Shift, infinite, no stamina bar (`SprintController.lua`).
- **View bob** (`ViewBobController.lua`): a subtle first-person camera bob
  while moving, scaled up a bit while sprinting — cycles per stud traveled
  rather than per second, so it naturally speeds up with your actual speed
  instead of needing a separate sprint-only multiplier. Applied as a
  camera-local offset layered on top of Roblox's own camera update every
  frame (`RunService:BindToRenderStep`, same "run after the built-in camera
  script" approach `CursorLock.lua` uses for mouse state). The raw physics
  velocity it reads has small real per-frame noise (footstep impulses,
  floor contact) that read as a shaky jitter on top of the bob at sprint's
  bigger amplitude; smoothed with an exponential moving average, and tuned
  down from ~7Hz to a real footstep cadence (~1.5-2.4Hz).
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
- **Random blackouts** (`StoreTheme.lua`): during an active round, every
  working light in the store can go out for `Config.Blackout.Duration`
  (10s) at once. It's checked every `Config.Blackout.CheckInterval` (5s)
  with odds of `CheckInterval / Config.Blackout.AverageInterval` each time —
  a Poisson-style process, so it averages one blackout every
  `Config.Blackout.AverageInterval` (2 minutes) with no fixed guarantee
  either way, per your call. Fires a `BlackoutEvent` to clients for a
  banner/screen-dip/sting, and is fully suspended outside of an active
  Playing round (and force-ends immediately if the round ends mid-blackout).
  SpongeBob's quirk above uses the same underlying suppression system
  (`StoreTheme.SuppressFixture`/`ReleaseFixture`, reference-counted so the
  two never fight over a fixture they're both currently holding off) — try
  a blackout on demand with `/blackout` in chat.

## The monster roster

| Monster | Vibe | Mechanical quirk |
|---|---|---|
| Curious George | fast, erratic | randomly juks direction mid-chase |
| Peppa Pig | medium | short speed bursts ("snort") while chasing |
| Thomas the Tank Engine | slow patrol, very fast chase | **too wide for narrow doorways** — can only cross between rooms via the wider hallway-style gaps |
| Barney | slow, huge | loud footsteps (bigger hearing radius) — telegraphed |
| The Grinch | fast | faster and sees further in cells whose ceiling fixture is actually dead |
| Kung Fu Panda | medium | occasional straight-line dash burst |
| SpongeBob | medium | **kills every working light near him as he moves** (they come back ~15s after he leaves, see below) |
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

## The story: why the tasks exist

Somewhere between the meatballs and the mattress showroom, this IKEA
started running itself. The staff didn't quit — the store's automated
backend, a loyalty-and-inventory system nobody remembers approving
(internally: the **Customer Retention System**, or **CRS**), quietly
absorbed their shifts, their badges, and eventually their shapes. What
patrols the aisles now are CRS's "Greeters" — mascot-shaped constructs
stitched together from whatever cheerful licensed characters were still
looping on the in-store TVs the night the changeover happened. They don't
want to hurt you. They want you to finish your visit.

CRS still runs the store like a store: nothing leaves the building — least
of all a customer — until the day's **Loyalty Quota** is met. That Quota is
just the same operational checklist a real IKEA runs every day, minus the
humans who used to run it: shelves restocked, self-checkouts logged,
inventory audited, registers covered, forklifts certified. It doesn't care
that you didn't apply for the job. Complete every task, and CRS will
consider the loading dock's automatic lockdown "no longer necessary" — its
words, stenciled right onto the door. Leave one undone, and as far as CRS is
concerned, you haven't finished shopping yet.

This is why the HUD tracks stations as a **"Loyalty Quota"**, why each
station's overlay opens with a CRS directive explaining what it thinks it's
asking of you (`Config.Minigames[i].lore`), and why the loading dock is
labeled "LOADING DOCK [LOCKED]" instead of just "EXIT."

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
`MinigameController.lua`'s `GAMES` table, and a `Config.Minigames` entry
(including a `lore` line so CRS has something to say about it) — station
placement (`MazeGenerator.lua`) automatically spreads however many entries
exist across the grid, no placement code to touch.

**Visual style**: the minigame overlay is deliberately reskinned distinct
from the rest of the game's UI — an 8-bit look (`Enum.Font.PressStart2P`,
flat high-contrast colors, square borders instead of rounded corners) via
`StarterPlayerScripts/Minigames/RetroTheme.lua`, shared by all 6 games and
the overlay shell itself, and a noticeably bigger overlay window than
before. The mechanics of each game are unchanged — only how they're drawn.

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
  Main.client.lua                    Boots all client controllers, each wrapped in pcall so one's error can't skip the rest
  UIUtil.lua                         Shared UI-building helpers
  CursorLock.lua                     Frees the mouse for clickable menus (fights the camera every frame)
  SprintController.lua               Shift-to-sprint
  ViewBobController.lua               Subtle first-person camera bob, scaled up while sprinting
  AmbienceController.lua             Store ambience loop, proximity heartbeat, round/exit/escape stingers
  JumpscareController.lua            Full-screen jumpscare on catch + catch/scream audio
  DeathController.lua                Death/respawn/spectate menu + escape banner
  SpectateController.lua             Camera-follow spectating with target cycling
  MinigameController.lua             Minigame overlay + dispatch to the 6 minigame modules + success/fail audio/toast
  HUDController.lua                  Round phase, station progress, results screen, Overtime banner/tint
  Minigames/
    RetroTheme.lua                    Shared 8-bit look (pixel font, palette, square borders) for every station's UI
    RestockShelves.lua
    FlatPackAssembly.lua
    SelfCheckout.lua
    InventoryCount.lua
    CustomerRush.lua
    ForkliftCertification.lua
```
