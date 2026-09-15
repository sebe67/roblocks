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
- **Sight-based AI** (`MonsterAI.lua`): exactly two states, **Patrol** and
  **Chase**, structured so neither can interfere with the other. Chase is
  entered *only* by directly seeing a player (distance + field-of-view cone
  + an unobstructed raycast — never by teleporting knowledge of your
  position into a monster) and exited *only* when `CHASE_GIVEUP_TIME` (5s)
  passes with no sight of that player, full stop — no third state, no
  "go check where I last saw them" detour, nothing else that can knock a
  monster out of one state into a muddled condition between the two. A
  noise alert (a minigame station running, Dora's callout quirk) never
  starts a real Chase either; it just gives Patrol a specific destination
  to head toward for a while instead of a random one (`ReceiveAlert`), so
  it's a variant of Patrol rather than its own state.

  **Movement itself is now fully kinematic — no Humanoid physics, no
  momentum, at all.** Every monster's `HumanoidRootPart` is `Anchored`
  (`createRig`), which takes its whole welded rig out of physics
  simulation entirely: no gravity, no collision response, nothing external
  that can ever push it off course. The one movement primitive,
  `_faceAndMove(dt, desiredDir, speed, moveForward)`, does exactly two
  things each frame: (1) turns `self.facing` toward `desiredDir` by at
  most `TURN_RATE * dt` radians — never further, never all at once — and
  (2) if `moveForward` is true, sets `root.CFrame` to the current position
  plus `self.facing * speed * dt`, facing that same direction. Next
  frame's position is *always* just last position plus this frame's
  facing times this frame's `dt` — nothing but the facing direction itself
  carries over between frames, which is the literal "a direction to face
  in, and a move-forward function, but they don't always have to be
  moving forward" this was rebuilt to. Chase calls it every frame with
  `moveForward = true` and the live direction to the player, completely
  ignoring walls and obstacles — no `PathfindingService` fallback, no
  exception for Thomas. Patrol calls it once per waypoint the same way;
  when there's no path yet (see below), it just doesn't call it at all
  that frame, which is the "not always moving forward" case in practice.
  **Nothing in `MonsterAI.lua` calls `Humanoid:Move()` or
  `Humanoid:MoveTo()` anymore** — the `Humanoid` instance is still there
  for its stats/animations, it's just no longer what moves anything.

  **Patrol** requests a route to a random point on the grid (or an alert
  location) via `PathfindingService` and walks its waypoints. Its
  `WaypointSpacing` was widened from 4 to 16: that setting is the *maximum*
  gap between waypoints, not a target, so at 4 it was forcing extra
  waypoints along dead-straight stretches through these big rooms (up to
  110 studs across) — each one a tiny excuse to nudge direction, which is
  what patrol read as erratic even with nothing chasing it. At 16, a
  straight room interior collapses to a couple of waypoints while a real
  turn (a doorway, a corner) still forces one, since the route genuinely
  bends there — so direction changes now line up with actual intersections
  instead of firing every few studs.

  Getting the steering itself right took a few more rounds than expected —
  worth recording *why*, since some of these look like they shouldn't have
  mattered:
  - `Humanoid:MoveTo()` is built for a one-shot "walk to this exact spot
    and stop." Calling it every frame toward a constantly-shifting target
    (a live player, even a fresh random patrol point) resets the
    humanoid's internal walk/turn state on every call — and that reset,
    not any particular target, was the real source of reported flailing.
    It wasn't isolated to chasing a moving player (that was just the
    easiest place to notice it): plain Patrol, aiming at a perfectly
    static point with nothing chasing anything, showed the exact same wild
    left-right/backwards/overshoot behavior once actually checked, which
    is what gave this away — chase-specific fixes across several rounds
    couldn't have touched Patrol at all, since it never shared that code.
  - Layering obstacle-awareness back on top of `Move()`-based chase (fall
    back to a `PathfindingService` route when a wall blocks the direct
    line) reintroduced the same class of bug from a different angle: the
    per-frame "is the line clear" check (`_hasClearPath`, a spherecast)
    could flicker for a single frame from ordinary geometry noise near a
    corner, and reacting to that instantly meant requesting a brand-new
    route and steering at *its* first waypoint that same frame — a real,
    brief detour off the player's position, visible as veering to the
    side. It could also clip an off-center part of the *target's own
    body* (a shoulder, an arm, their head) and misreport that as a wall
    with nothing actually in the way — which shifts with approach angle,
    so it alone produced both veering and repeated switching that read as
    erratic.
  - Monsters and players both had `CanCollide = true`, so once adjacent,
    physics would shove them apart every frame a monster (still steering
    at the player's exact center) tried to walk into someone it had
    already reached — sliding it around the player's collision shape
    instead of ever registering contact, which is what an "orbits before
    finally touching" report looks like from outside. Only Monster-vs-
    Player collision was disabled at first; **Monster-vs-Monster collision
    was the same bug from a second angle**, and with Chase now a pure,
    obstacle-blind beeline (no `PathfindingService` fallback to route
    around anything), a monster whose straight line to the player happens
    to pass through *another monster's* solid body gets physically shoved
    off-course by it, over and over — exactly the zig-zag/orbit still
    reported for some monsters and not others despite every one of them
    running identical chase code, since it comes down to whether another
    monster happened to be in the way during that specific encounter. The
    catch is purely a `Touched`-event trigger, never a physical block, so
    none of this collision ever served a purpose; monsters and players,
    and monsters and each other, are now in separate/non-collidable
    `PhysicsService` collision groups, all still colliding normally with
    walls/floor (`Main.server.lua`). `Touched` still fires the same either
    way — it depends on `CanTouch`, not `CanCollide`.
  - `_canSee`'s facing-cone (FOV) check could fail while a monster was
    actively chasing just because its own facing lagged its movement
    direction by a few degrees — steering noise, not the player leaving —
    and losing sight that way used to drop Chase into a "go check their
    last known position" detour, which could visibly loop before its
    final approach even though the target never moved. Within
    `Config.MeleeAwareRadius` (10 studs), `_canSee` now skips the facing
    check entirely: something that close doesn't need to be looked at
    head-on to know it's there.
  - SpongeBob's `lightsOut` quirk update ran inline inside the same
    `Update()` call that drives movement — the one per-frame difference
    between his chase and everyone else's — so it now runs on its own
    independent `task.spawn` timer (`_updateLightsOut`), unable to affect
    a movement command's timing regardless of what it does internally.
  - Even alone in a room with nobody else nearby, a monster could still
    orbit a completely stationary player ~2 revolutions before finally
    stopping — sometimes freezing partway there. A first pass diagnosed
    this as a "seek without arrival" overshoot (steering at the player's
    *exact* live position every frame with a momentum-carrying physics
    body, which can't redirect an existing velocity instantly when the
    required bearing suddenly swings through a wide angle up close) and
    fixed it by having Chase stop recomputing direction within a small
    arrival radius. That held up worse than hoped: further testing still
    found monsters parked and unmoving mid-Patrol facing a wall, a Chase
    target frozen right in front of the player (the new arrival-radius
    dead zone, entered while not quite lined up, with nothing left to
    correct it), and the orbit itself still recurring. Rather than patch a
    physics-momentum theory further, movement was rebuilt from scratch
    with momentum removed as a category, not tuned around — see the fully
    kinematic `_faceAndMove` system described above. It has no velocity to
    carry between frames at all, so there's structurally nothing left that
    *can* spiral into an orbit or get stuck mid-correction: the worst case
    is turning in place for a frame or two, never curling off course.

  Thomas (wideBody) no longer gets a special exception during Chase — he
  now blindly beelines like everyone else, which temporarily means he can
  aim straight through a doorway too narrow for him mid-chase. Since
  movement is now kinematic rather than physics-driven (previous
  paragraph), that's no longer even a physical wall-block — an
  Anchored, directly-`CFrame`-set part has no collision response, so
  Chase walking "through" a wall now means exactly that, visibly clipping
  through it, until obstacle-awareness returns for everyone.

  Monsters are scattered at least `Config.Maze.MonsterSpawnExclusionCells`
  cells from the (now-central) spawn point both at server boot and again at
  the start of every round (`MonsterSpawner.RepositionAll`), so one can't
  end up camping the entrance between rounds.

  **Temporary testing aid:** every monster has a small "PATROL"/"CHASE" tag
  floating just above its nametag (`createRig`'s `stateTag`), always
  matching `self.state` exactly since both are only ever changed together
  through `MonsterAI:_setState` — light blue for Patrol, red for Chase, so
  the two are easy to tell apart at a glance. Meant to make it obvious
  which state a monster is actually in while chasing behavior is still
  being tuned — remove it once that's no longer needed.
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
- **Flashlight**: press F to toggle (`FlashlightController.lua` sends the
  request; `PlayerService.lua` owns the actual light). It's a real
  server-owned `SpotLight` (`Config.Flashlight` for range/angle/
  brightness/color) — toggled authoritatively server-side so every other
  player sees your beam too, not just a client-only effect for its owner.
  Off by default and reset (a fresh light, always off) on every respawn.
  Especially useful during a blackout, when every ceiling fixture nearby
  has gone dark. Tracks camera pitch (up/down), not just facing
  (left/right): a `Head`'s own `CFrame` only ever turns with the
  character's yaw, never with camera pitch, so a light parented straight
  to it could only aim level. The light instead lives on a small
  `FlashlightAim` part welded to `Head` with a `Motor6D` (inherits yaw
  automatically), and `FlashlightController.lua` reports the local
  camera's pitch to the server every 0.1s, which rewrites that `Motor6D`'s
  `C0` (clamped to `Config.Flashlight.MaxPitch`, 89° — short of the 90°
  gimbal-degenerate case of looking exactly straight up/down, so this is
  full freedom in practice) — a live constraint, not a one-time weld, so
  it keeps tracking every frame with no server loop needed. Ceiling parts
  (`MazeGenerator.lua`) used to be near-black `Metal` (`(40,40,44)`) —
  the light genuinely reached them, but Metal's tight, angle-dependent
  specular response on a surface that dark left no visible brightness
  increase to actually see, which is what "doesn't work on the roof"
  turned out to be. Now `Concrete` at `(58,58,65)`, matching Floor's
  already-working diffuse response, so the beam reads clearly on both.
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
| Curious George | fast | *(no coded quirk yet — his `erratic` tag is currently just flavor; see below)* |
| Peppa Pig | medium | short speed bursts ("snort") while chasing |
| Thomas the Tank Engine | slow patrol, very fast chase | **too wide for narrow doorways** while patrolling — can only cross between rooms via the wider hallway-style gaps. Chase currently ignores this (see below) |
| Barney | slow, huge | loud footsteps (bigger hearing radius) — telegraphed |
| The Grinch | fast | faster and sees further in cells whose ceiling fixture is actually dead |
| Kung Fu Panda | medium | occasional straight-line dash burst |
| SpongeBob | medium | **kills every working light near him as he moves** (they come back ~15s after he leaves, see below) |
| Dora | medium | **spotting you alerts every other monster to your last position** |

Thomas's restriction isn't a special-cased graph — it falls out naturally
from giving him a much larger `pathAgentRadius` in `MonsterAI.lua`'s
PathfindingService calls than every other monster. A bigger agent radius
makes Roblox's navmesh solver treat narrow doorways as too tight to fit
through, so he's automatically routed only through wide hallway gaps and
open rooms whenever he's actually pathfinding, with zero bespoke pathing
code. Since Chase currently always steers straight regardless of walls
(see "Sight-based AI" above), this restriction is only enforced while he's
patrolling for now — his defining quirk will apply during Chase again once
obstacle-awareness comes back for everyone.

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

**Free-fly noclip for testing:** type `/spectate` in chat to go invisible
and intangible and fly anywhere — through walls, across the whole map —
with WASD (camera-relative) + Space/LeftCtrl for up/down
(`NoclipController.lua`). Monsters can't see, chase, or touch you while
it's active: it sets the same `Invulnerable` attribute
`MonsterAI.playersToCheck()` already filters out before any sight or catch
check runs, so no monster-side changes were needed. Type `/back` to return
to normal (visible, collidable, walking control restored). Also wired up in
`Main.server.lua`, same "open to any player for now, gate before this goes
public" caveat as every other debug command here.

The first version of this drove flight with `AssemblyLinearVelocity` and
`Humanoid.PlatformStand = true`, and it was glitchy and still didn't
reliably clip through walls — `PlatformStand` ragdolls the rig (every
limb's joint goes loose) rather than just suspending walk control, and
that ragdoll physics fought our velocity writes to the root every frame.
Now `EnableNoclip` (`PlayerService.lua`) sets `HumanoidRootPart.Anchored
= true` instead, which — like the monster movement rebuild above — takes
the *entire* welded rig out of physics simulation: no gravity, no ragdoll,
no collision response possible, nothing left to fight. With the root
Anchored, `NoclipController.lua` becomes the only thing moving the
character, translating `root.CFrame` directly every frame — nothing to
glitch, and nothing for a wall to stop.

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
  Main.server.lua                    Boots everything, wires services together, /godmode /spectate /back /light /blackout chat commands
  MazeGenerator.lua                  Room partitioning + doorway/hallway connectors + color zones + stations + exit
  StoreTheme.lua                     Lighting/atmosphere + dead-fixture flicker loop
  MonsterAI.lua                      Per-monster state machine + Overtime godmode + placeholder rig + monster audio
  MonsterSpawner.lua                 Spawns one of every Config.Monsters entry
  MinigameService.lua                Station wiring, noise pulses, exit-unlock trigger
  ExitService.lua                    Exit door lock/unlock + escape-zone detection
  PlayerService.lua                  Round state per player, catch/respawn/spectate/escape, flashlight toggle+aim, noclip
  GameState.lua                      Waiting → Intermission → Playing → Results loop, Overtime trigger
src/StarterPlayerScripts/
  Main.client.lua                    Boots all client controllers, each wrapped in pcall so one's error can't skip the rest
  UIUtil.lua                         Shared UI-building helpers
  CursorLock.lua                     Frees the mouse for clickable menus (fights the camera every frame)
  SprintController.lua               Shift-to-sprint
  ViewBobController.lua               Subtle first-person camera bob, scaled up while sprinting
  FlashlightController.lua            Sends the F-key toggle request + throttled camera-pitch reports for beam tilt
  NoclipController.lua                Drives free-fly movement for /spectate (server only toggles the "Flying" state)
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
