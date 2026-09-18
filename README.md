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
  across a 28x28 grid (`GridWidth`/`GridHeight`, up from 22x22 — 1.25x the
  side length per request, so the actual floor area grows ~1.6x), each
  room a single open floor plan inside. A
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
  begins. `HallwayChance` (0.4 → 0.6) governs how often a room-to-room
  connector is a wide open hallway gap instead of a narrow doorway —
  bumped up since a hallway is the only connection type Thomas's oversized
  `pathAgentRadius` can reliably route through; a standard doorway is only
  marginally wider than his own clearance, and a route needing several
  chained doorways across the map failed often enough that he was
  standing still a lot.
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
  chat. The only real light sources in the store are these ceiling fixtures
  and a player's own flashlight — the minigame stations' floor accent decal
  used to be `Enum.Material.Neon`, which (unlike a merely bright color)
  actually contributes ambient/bounce light in Roblox, and being sized
  almost the full station cell right up against the walls, was quietly
  lighting up nearby walls near every station ("walls that just glow in
  some areas"). It's `SmoothPlastic` now — same bright cyan look, no longer
  a stray light source.
- **9 monsters**, each with its own stat block and one mechanical quirk, all
  tuned in `ReplicatedStorage/Shared/Config.lua` (see below).
- **Sight-based AI** (`MonsterAI.lua`): exactly two states, **Patrol** and
  **Chase**, structured so neither can interfere with the other. Chase is
  entered *only* by directly seeing a player (distance + field-of-view cone
  + an unobstructed raycast — never by teleporting knowledge of your
  position into a monster) and exited *only* when `CHASE_GIVEUP_TIME` (5s)
  passes with no sight of that player — **or instantly**, no grace period,
  the moment that player goes `Hidden` (a wardrobe) — full stop; no third
  state, no "go check where I last saw them" detour, nothing else that can
  knock a monster out of one state into a muddled condition between the
  two. A noise alert (a minigame station running, Dora's callout quirk, or
  **sprinting** — see below) never starts a real Chase either; it just
  gives Patrol a specific destination to head toward for a while instead of
  a random one (`ReceiveAlert`), so it's a variant of Patrol rather than
  its own state. Every monster's `sightRange` is x1.75 its original value
  per request.
  Mid-chase, a monster also re-scans every tick for a strictly closer,
  currently-visible, non-`Hidden` player than whoever it's already chasing
  (same sight rules as spotting one in the first place) and switches to
  them if found — so it doesn't tunnel-vision past someone who runs right
  in front of it.

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
  moving forward" this was rebuilt to. Patrol calls it once per waypoint;
  when there's no path yet (see below), it just doesn't call it at all
  that frame, which is the "not always moving forward" case in practice.
  **Nothing in `MonsterAI.lua` calls `Humanoid:Move()` or
  `Humanoid:MoveTo()` anymore** — the `Humanoid` instance is still there
  for its stats/animations, it's just no longer what moves anything.

  **EXPERIMENTAL — Chase obstacle-awareness is back, currently being
  playtested.** Every frame, Chase now checks `_hasClearLine(root)` (a
  plain raycast, reusing the same target's-own-body exclusion `_canSee`
  already used — not the old spherecast that misread limbs as walls). If
  clear, it beelines exactly as before with `_faceAndMove` — unchanged
  fast path, no pathfinding overhead most of the time. If blocked, it
  falls back to a `PathfindingService` route to the player's *current*
  position via `_ensureChasePath`/`_followChasePath` — entirely separate
  fields (`chaseCurrentPath`/`chasePathIndex`/`nextChasePathAttempt`) from
  Patrol's own path bookkeeping, so this can never interact with or break
  Patrol. Two deliberate differences from Patrol's pathing: `WaypointSpacing`
  is tighter (`CHASE_WAYPOINT_SPACING`, 8 vs Patrol's 16) and it replans on
  a timer (`CHASE_REPLAN_INTERVAL`, every 0.5s) even mid-path rather than
  only once a route is exhausted — Patrol's target is a fixed point, so
  walking a stale route to the end is fine, but Chase's target (the player)
  keeps moving, so a route more than half a second old risks visibly
  lagging behind where they actually went.

  This is safe to try now in a way it wasn't several rounds ago: the old
  concern with reintroducing pathfinding-based obstacle-avoidance was
  always about interacting badly with `Humanoid:Move()`'s momentum (a
  one-frame reroute causing a visible flinch/veer, or fighting an
  in-flight velocity). With movement now fully kinematic and momentum-free
  (previous section), a sudden switch between beelining and following a
  waypoint just costs a bounded turn — nothing to overshoot or fight.
  **Side effect:** Thomas's `wideBody` doorway restriction (his defining
  quirk) now naturally applies during Chase too, not just Patrol, since
  his oversized `pathAgentRadius` is used for `_pathToChase` the same way
  it already was for `_pathTo`.

  **If this makes chasing feel worse** (routes lagging too far behind,
  monsters looking like they're "giving up" chasing around a corner, CPU
  cost from `ComputeAsync` calls, anything else), everything above is
  self-contained and tagged `EXPERIMENTAL` in `MonsterAI.lua`'s comments
  for exactly this reason — reverting means deleting the tagged pieces and
  restoring Chase's live-target branch to the single unconditional
  `_faceAndMove` call it was before. Nothing about Patrol needs to change
  either way.

  **Backstop against clipping straight through a wall.** Because movement
  is a direct `CFrame` set with no physics collision response (previous
  section), `_hasClearLine` being fooled for even one frame — grazing a
  corner, a seam gap, anything — had nothing to stop a monster from
  walking its center point straight into and out the other side of solid
  geometry; once its origin was past the wall, later frames' rays started
  on the far side and never saw it as blocking again, so it looked like
  the monster just walked through the middle of a wall. `_faceAndMove`
  now takes an `enforceWallClip` flag and, when it's set, casts a second,
  much shorter ray every frame — just *this frame's* step (a few studs),
  not the tens of studs to the player — refusing to advance into whatever
  it hits. A short ray through solid wall gets hit reliably where a long
  one grazing a corner might not. It's deliberately a single ray through
  the monster's own center: a doorway narrower than the model can still be
  walked through with some visible side-clipping (allowed, on purpose),
  and only a step whose *center* is blocked — an actual wall — gets
  refused.

  **Only applied to beeline movement, not path-following.** The flag above
  is passed `true` only where normal Chase and godmode beeline straight at
  a live target's current position with no vetted route behind it — the
  only place the original clip-through-a-wall bug actually happened. It's
  deliberately left off for path-following (Patrol's own route, or either
  state's pathfound fallback): those already walk a route
  `PathfindingService` computed to avoid solid geometry, and applying the
  same check there caused a real regression instead of fixing one — a
  Patrol waypoint sending a monster through one of this game's
  deliberately-narrow doorways at a slight angle could clip the door frame
  on this single-center-ray check and simply refuse to advance, with
  nothing to make it back off and try a different angle, reading as a
  monster that just stopped moving entirely.

  **Overtime godmode** (`_updateGodChase`) is wall-restricted exactly like
  everything else — no exception in `_faceAndMove` for it. It still has no
  sight/range checks (always knows exactly where the nearest alive player
  is, re-picked fresh every frame, at a much higher speed) but now shares
  the same clear-line-or-pathfind pattern as the EXPERIMENTAL Chase branch
  above: beelines when `_hasClearLine` to the nearest player is true, falls
  back to `_ensureChasePath`/`_followChasePath` when it isn't. It reuses
  those same functions and the same `chaseCurrentPath` fields Chase uses —
  safe to share since `Update()` returns before ever reaching Chase's own
  branch while `self.god` is true, so nothing else touches them at the same
  time.

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

  Thomas (wideBody) briefly had no special exception during Chase at all
  — he'd beeline straight through a doorway too narrow for him, clipping
  through it visibly (Anchored, directly-`CFrame`-set parts have no
  collision response, so "walking through a wall" now means exactly
  that). With the EXPERIMENTAL obstacle-awareness above, his oversized
  `pathAgentRadius` applies to his Chase reroute too, so his doorway
  restriction is naturally back during Chase as well — as long as that
  experiment sticks around.

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
- **Sprinting**: hold Shift for `Config.Player.SprintSpeed`, drains a
  stamina meter over `Config.Player.SprintDuration` (10s) of continuous
  use (`SprintController.lua`). Hit empty and you're forced to walk until
  it regenerates back up to `MinSprintFraction` — regen takes
  `SprintRegenDuration` (12s) normally, `SprintRegenHiddenMultiplier` (2x)
  faster while hiding in a wardrobe. A thin bar at the bottom-center of the
  screen fades in whenever it's not full or you're holding Shift, and
  fades back out once it's topped off and you've let go — tracked entirely
  client-side (same as the sprint toggle itself always was); the server's
  own authoritative `WalkSpeed` writes (catch freeze, hiding freeze) are
  what actually keep it un-cheatable, not this meter. Added specifically
  so a chase isn't just "hold Shift forever" — see hiding spots below for
  the other half of that fix.
- **Sprinting makes noise** (`MonsterAI.StartSprintNoiseLoop`/
  `BroadcastSprintNoise`): the server polls every detectable player's
  actual ground speed (`HumanoidRootPart.AssemblyLinearVelocity`, not
  `Humanoid.WalkSpeed` — a client-set `WalkSpeed` override never actually
  replicates back to the server, only the resulting real movement does,
  which is why this didn't work reliably at first) every
  `Config.Player.SprintNoiseCheckInterval` (0.5s) and, for anyone at
  `SprintSpeed`, alerts any monster within that monster's own
  `hearingRadius` — a field that existed in `Config.Monsters` since the
  very first pass but was never actually read by any code until now. Same
  rule as any other noise alert: it only gives Patrol a destination to
  turn and walk toward, never triggers Chase directly — so sprinting past
  a monster's blind side makes it turn around, and it only actually gives
  chase if that turn brings you into its sight range/FOV/an unobstructed
  raycast, same as always. An active investigate destination bypasses
  Patrol's own random-wander pathing (which only ever repaths once its
  current route is fully empty, plus a 1-second retry throttle — both far
  too sluggish for a destination that updates every half-second) and
  instead reuses Chase's beeline-or-pathfind machinery (0.5s replan) —
  safe to share since Patrol/investigate and Chase never run at the same
  time.
- **Hiding spots** (`HidingService.lua` + `HidingController.lua` +
  `MazeGenerator.lua`'s `buildHidingSpot`): on average
  `Config.Maze.HidingSpotChance` (~1-in-3) of rooms gets a wardrobe, built
  flush against one of that room's real solid walls (never a
  doorway/hallway gap, never the exit-door wall). **E** both enters and
  leaves — a single shared `ProximityPrompt` per wardrobe toggles whoever's
  using it (a second player can't also pile into an occupied one), and its
  `ActionText` flips between "Enter Closet"/"Exit Closet" with that spot's
  own occupancy. While hidden: `humanoid.WalkSpeed = 0` (same freeze
  pattern `PlayerService:CatchPlayer` uses) and `player:GetAttribute
  ("Hidden")` is set, which `MonsterAI.lua`'s `playersToCheck()` filters
  out before any sight/catch check runs *and* which its Chase branch checks
  every tick to instantly drop that player as a target — hidden means
  genuinely invisible and untouchable, not just harder to spot, and a
  monster can't wander into the wardrobe chasing a position that no longer
  exists for it. The wardrobe's own door has a literal
  `Config.HidingSpot.DoorGap` between its two leaves — since the round
  locks the camera to first-person at the character's head, standing at
  the interior anchor and facing that gap shows a real sliver of the room;
  the character's server-set facing alone doesn't change what you actually
  see through, though, since Roblox's built-in first-person camera script
  tracks its own independent look angle — `HidingController.lua` forces a
  camera resync (`CameraType` `Scriptable` → `Custom`) the instant you go
  `Hidden` so you land facing the gap instead of the back wall. You can't
  camp forever either: `Config.HidingSpot.MaxHideDuration` (12s) force-exits
  you, with a warning toast `KickWarningTime` (3s) beforehand.
- **View bob** (`ViewBobController.lua`): a subtle first-person camera bob
  while moving, scaled up while sprinting — cycles per stud traveled rather
  than per second, so it naturally speeds up with your actual speed instead
  of needing a separate sprint-only multiplier. Applied as a camera-local
  offset layered on top of Roblox's own camera update every frame
  (`RunService:BindToRenderStep`, same "run after the built-in camera
  script" approach `CursorLock.lua` uses for mouse state). The raw physics
  velocity it reads has small real per-frame noise (footstep impulses,
  floor contact) that read as a shaky jitter on top of the bob at sprint's
  bigger amplitude; smoothed with an exponential moving average, and tuned
  down from ~7Hz to a real footstep cadence (~1.5-2.4Hz). Sprint amplitude
  also grows further as stamina runs low (`LOW_STAMINA_SHAKE_BOOST`, up to
  70% extra shake at empty) via a tiny shared `StaminaState.lua` value
  `SprintController.lua` writes every frame and this reads — the two are
  separate LocalScripts on the same client, so this is a plain shared Lua
  table, not a remote/attribute.
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
  `Range` went 45 → 60 → 120. 60 was set believing (from memory, not
  something testable in this environment) that Roblox hard-clamps
  `SpotLight.Range` to 60 studs regardless of lighting technology — if
  that's actually still true, 120 will just render identically to 60 and
  the beam won't visibly reach any farther than it already did; if it's
  not (or no longer is), 120 actually throws twice as far. Whichever one
  you see in-game settles which memory was right. `Brightness` bumped
  slightly too (3 → 3.5), so a blackout doesn't leave you relying on
  bumping into a monster to know it's there — you should be able to catch
  a distant beam-lit glimpse of one coming first.
- **3 minigame stations** that require real attention and periodically ping
  every nearby monster while active (`MinigameService.lua` +
  `StarterPlayerScripts/Minigames/*`). Clearing all of them unlocks the exit
  (`ExitService.lua`).
- **Jumpscare → Respawn/Spectate flow** (`PlayerService.lua` +
  `JumpscareController.lua` + `DeathController.lua` +
  `SpectateController.lua`): getting caught freezes you and shows a
  jumpscare for the monster that got you. **TEMP, for faster testing:**
  right now `PlayerService:CatchPlayer`'s delayed callback calls
  `SpawnForRound` directly instead of `MarkDead` — you respawn
  automatically the instant the jumpscare ends, no click required, and the
  Respawn/Spectate `DeathGui` menu (`DeathController.lua`) never actually
  shows for a normal catch. That menu and `MarkDead` still exist and are
  still used by `ForceTimeout` (the round legitimately ending on the
  overtime hard cap) — Respawn wouldn't do anything there anyway since
  `roundActive` is already false by that point. Revert by pointing
  `CatchPlayer`'s delayed call back at `self:MarkDead(player, monsterId)`
  once you want the manual choice back.
- **Real bug found alongside the above**: `GameState:_checkRoundEnd`
  originally only treated `"Alive"` and `"Dead"` as "still in progress" —
  it never accounted for `"Caught"`, the ~`JumpscareDuration` window
  between being hit and actually being marked `"Dead"`. This poll runs
  once a second, comfortably inside that window, so a solo (or
  last-remaining) player sitting in `"Caught"` could get read as "everyone
  has resolved" and trigger the Results screen — a full 14s wait, then a
  new Intermission — mid-jumpscare, before they were ever offered a
  respawn. That's very likely what "the round-over screen stays up a long
  time after death" actually was. Fixed by adding `"Caught"` to the same
  guard as `"Alive"`/`"Dead"`.
- **Jumpscare closeup rework**: `JumpscareController.lua` no longer shows a
  flat color card — it renders an actual closeup of the specific monster
  that caught you via a `ViewportFrame` (a GUI element with its own
  isolated 3D scene, entirely separate from the real game world).
  `PlayerService:CatchPlayer` now hands the live monster instance itself
  (not just its id) through to the client — it's already parented under
  `workspace` so it's already replicated, no extra work needed — and the
  client clones it into that scene and points a camera tight on its
  `Head` (falls back to `Face`, then the model's bounding-box center; see
  the Thomas note above). Since the clone is the only thing in that
  isolated scene, everything else in frame is naturally solid black with
  no extra work. Effects: the viewport camera jitters position/rotation
  every single rendered frame for a high-frequency shake, decoupled
  entirely from your real game camera (which no longer gets its own FOV
  kick — pointless once the real world is fully covered); the viewport's
  built-in `LightColor`/`Ambient` (no separate Light instance needed)
  re-randomize on a short timer for an unstable-bulb flicker; a
  translucent full-screen overlay flickers transparency/tint for
  procedural static (not a real grain texture — that needs an actual
  texture asset uploaded on your end, which nothing in this sandboxed
  environment can source or verify); and the camera punches in from very
  close before easing out to its held distance right at the start. The
  clone strips its `NameTag`/`StateTag` billboards and any `Sound`
  (footstep loops clone with whatever `Playing` state they had — a
  ViewportFrame only isolates rendering, not audio, so an already-playing
  clone would've audibly doubled up). **Deferred, reminder tracked, not
  built yet:** a pulsing dark/red edge vignette that tightens as the shot
  holds. `Config.Round.JumpscareDuration` is now 1.5s (was 2.6s) — also
  what gates the auto-respawn delay above, so both always match.
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
  either way, per your call. The affected fixtures flicker for
  `Config.Blackout.PreFlickerDuration` (3s) before actually cutting out —
  a warning beat instead of a surprise snap to dark — then fires a
  `BlackoutEvent` to clients for a banner/screen-dip/sting, and is fully
  suspended outside of an active Playing round (and force-ends immediately,
  flicker included, if the round ends mid-blackout). SpongeBob's quirk
  above uses the same underlying suppression system
  (`StoreTheme.SuppressFixture`/`ReleaseFixture`, reference-counted so the
  two never fight over a fixture they're both currently holding off) —
  his radius is now `Config.LightsOutRadius` = 60 (was 40) — try a
  blackout on demand with `/blackout` in chat.
- **Permanently-flickering light clusters** (`StoreTheme.StartFlicker`): on
  top of the existing occasional single dead-fixture flicker, a few
  (`Config.Lighting.PermanentFlickerGroups`, default 3) small clusters of
  2-4 nearby dead fixtures (`PermanentFlickerGroupSize`, within
  `PermanentFlickerGroupRadius` grid cells of each other) flicker
  continuously forever, so a couple of spots in the store read as "this
  corner's wiring is actually broken" instead of one solitary bulb
  blinking in isolation. A fixture claimed by a cluster is removed from the
  occasional-single pool so it's never double-booked.

## The monster roster

| Monster | Vibe | Mechanical quirk |
|---|---|---|
| Curious George | fast | *(no coded quirk yet — his `erratic` tag is currently just flavor; see below)* |
| Peppa Pig | medium | short speed bursts ("snort") while chasing |
| Thomas the Tank Engine | slow patrol, very fast chase | slightly wider `pathAgentRadius` than everyone else — a little more selective about routes, but no longer flatly blocked from narrow doorways (see below) |
| Barney | slow, huge | loud footsteps (bigger hearing radius) — telegraphed |
| The Grinch | fast | faster and sees further in cells whose ceiling fixture is actually dead |
| Kung Fu Panda | medium | occasional straight-line dash burst |
| SpongeBob | medium | **kills every working light within 40 studs of him as he moves** (they come back ~15s after he leaves, see below; radius doubled from 20 per request — the actual darkened area is 4x bigger, not 2x) |
| Dora | medium | **spotting you alerts every other monster to your last position** |
| Tung Tung Tung Sahur | slow patrol, decent chase, huge and loud | occasional speed burst while chasing (like Peppa/Po) that also thuds the ground loud enough to draw any monster within 45 studs toward the commotion |

Thomas's restriction isn't a special-cased graph — it falls out naturally
from giving him a larger `pathAgentRadius` in `MonsterAI.lua`'s
PathfindingService calls than every other monster. A bigger agent radius
makes Roblox's navmesh solver treat narrow passages as too tight to fit
through (roughly: a corridor needs to be wider than `2 * AgentRadius` to
be navigable), so he gets automatically routed away from anything too
tight, with zero bespoke pathing code. This now applies during Chase too,
not just Patrol, since the EXPERIMENTAL obstacle-awareness (see "Sight-based
AI" above) reuses the same `pathAgentRadius` for his Chase reroute.

**This was originally tuned too aggressively.** `pathAgentRadius = 3.5`
against `Config.Maze.DoorwayWidth = 6` needs `6 > 2*3.5 = 7`, which is
false — every single narrow doorway was flatly impassable to his
pathfinding, not just "less convenient." That's fine if he always has
*some* hallway-style route available, but if his position ever ended up
surrounded only by doorway-style connections (this map's connector type
per room-to-room link is randomized — see `Config.Maze.HallwayChance`),
he'd have zero valid route at all and freeze completely, facing whatever
he was last trying to reach. Lowered to `2.5` (`6 > 2*2.5 = 5`,
comfortably passable) — he's still slightly more restricted than the ~2
everyone else uses, but can no longer get permanently stuck with nowhere
to go. This does retire most of his original "can't fit through doorways"
bite as a player-facing evasion tactic; if you want that back with a
guaranteed-navigable map instead, the alternative is widening
`Config.Maze.DoorwayWidth` globally, which affects every doorway for every
monster and the player, not just Thomas.

You asked for more roster ideas: **Bluey, the Teletubbies (Tinky Winky),
Cocomelon's JJ, and SpongeBob/Dora's Nickelodeon stablemate Baby Shark**
would all fit the same "wholesome mascot gone wrong" tone if you want to
keep expanding past 9. Adding one is just a new entry in `Config.Monsters`
— no other code changes needed, which is exactly how Tung Tung Tung Sahur
(the internet meme, not a licensed mascot, but the same "cheerful thing
gone wrong" energy) got added.

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

**Every debug chat command below (`/godmode`, `/light`, `/blackout`,
`/spectate`, `/spectate2`, `/back`) only responds to one hardcoded
username** (`DEBUG_USERNAME` in `Main.server.lua`, currently
`"Besussero"`) — anyone else typing them is simply ignored. Update that
constant if the account name ever changes.

**Testing it without waiting 10 minutes:** type `/godmode` in chat during an
active round to skip straight to Overtime. It's wired up in
`Main.server.lua` (`Player.Chatted` → `GameState:RequestOvertime()`).

**Free-fly noclip for testing:** type `/spectate` in chat to go invisible
and intangible and fly anywhere — through walls, across the whole map —
with WASD (camera-relative) + Space/LeftCtrl for up/down
(`NoclipController.lua`). Monsters can't see, chase, or touch you while
it's active: `EnableNoclip` (`PlayerService.lua`) sets the same
`Invulnerable` attribute `MonsterAI.playersToCheck()` already filters out
before any sight or catch check runs, so no monster-side changes were
needed. Type `/back` to return to normal (visible, collidable, walking
control restored).

**`/spectate2` is the same free-fly mobility, but the opposite visibility:
monsters see and chase you exactly like a normal player would.** Useful
for testing detection/chase behavior against yourself without a catch
ending the test — `EnableTestSpectate` leaves `Invulnerable` false (so
`playersToCheck()` includes you normally) and instead sets a new
`Untouchable` attribute that only `PlayerService:CatchPlayer` checks: the
monster's `_onTouch` still fires exactly as normal (cooldown included),
`CatchPlayer` just no-ops instead of actually killing you, so it's a real
catch attempt with no consequence rather than an invisible non-event.
`/back` ends this the same way it ends `/spectate` — see below.

Getting monsters to actually detect `/spectate2` took three rounds, and
the first two genuine bugs turned out not to be the real story:
`EnableTestSpectate` force-sets your `State` to `"Alive"` (`playersToCheck()`
requires that regardless of `Invulnerable`, so typing `/spectate2` without
already being Alive left every monster unable to see you), and `_canSee`'s
facing-cone check now compares a *flattened* direction against the
monster's `LookVector` instead of the full 3D one (a monster's facing,
`_faceAndMove`, is always exactly horizontal, so hovering above one used
to inflate the angle past `sightAngle` even standing right over it — this
also means a real player jumping can no longer make a monster lose track
of them from the momentary height change). Both fixes are real and still
in place, but detection was *still* reported broken after both, with
[SightDebug] instrumentation (since removed) showing every monster's
measured distance to the player sitting at 80-400 studs even while the
player reported hovering right in front of one — proof the two positions
had nothing to do with each other.

**The actual cause: `/spectate` and `/spectate2` originally shared one
mobility rig that Anchors the `HumanoidRootPart`, and Anchored parts have
no network ownership.** `NoclipController.lua` moves you by setting
`root.CFrame` from a LocalScript; on an Anchored part that write never
replicates anywhere — you see yourself fly on your own screen, but the
server's copy of your root never moves at all. That's invisible and
harmless for `/spectate` (`Invulnerable` already makes every monster
ignore you, so it truly doesn't matter whether the server ever learns
your real position), but it's fatal for `/spectate2`, whose entire point
is for the server-side monster AI to react to where you actually are.
`EnableTestSpectate` now leaves the root unanchored and calls
`Humanoid:ChangeState(Enum.HumanoidStateType.Physics)` instead — the same
technique behind script/vehicle-driven humanoids, which hands ground
control to the physics engine without the `PlatformStand` ragdoll side
effect. An unanchored root keeps its default network ownership (your own
client), so `NoclipController.lua`'s writes now replicate to the server
exactly like ordinary movement always has.

That alone reintroduced two symptoms once the root was genuinely
physics-simulated again: slowly sinking (gravity) and getting stuck on
walls despite `CanCollide` being false everywhere. Cause: `ChangeState`
only sets the humanoid's state *once* — Roblox's own state machine can
silently revert away from it on its own (its ground/Freefall detection
kicking back in once it notices there's no floor under an unanchored
body), quietly reintroducing the exact fight this was meant to avoid, in
both directions at once. Two fixes: `_beginFlight` now keeps a
`Humanoid.StateChanged` connection alive for the whole flight that
immediately reasserts `Physics` state if it ever changes away, and
movement itself no longer works by writing `CFrame`/`AssemblyLinearVelocity`
once per rendered frame — `_beginFlight` attaches a real `LinearVelocity`
constraint (`NoclipVelocity`, via a `NoclipAttachment`) to the root, which
`NoclipController.lua` now points at the desired velocity each frame
instead. A constraint is evaluated by the physics engine on *every*
physics step, not just once per render, so there's no window left for
gravity to accumulate a visible drift in between corrections the way a
script-driven write always has one. `/spectate`'s Anchored root is
untouched by any of this — Anchored parts ignore velocity/constraints
entirely, so `NoclipController.lua` still falls back to direct `CFrame`
translation whenever `NoclipVelocity` doesn't exist.

`EnableNoclip` and `EnableTestSpectate` share one underlying
`_beginFlight` (`PlayerService.lua`) for the invisible/intangible setup,
but now diverge on root physics for exactly the reason above. `/back`
calls one shared `EndFlight` that undoes either mode without needing to
know which was active — disconnecting the `StateChanged` listener,
destroying the constraint/attachment, and recovering a humanoid
`/spectate2` left in the `Physics` state back to normal ground control,
all as no-ops for `/spectate`, which never created any of them.

After that fix, walls and the gravity-sink were confirmed gone, but the
ceiling specifically still blocked `/spectate2`. This one's less certain
than the others above — `CanCollide = false` on every one of your own
character's parts should, per how Roblox collision works, prevent contact
with *anything* regardless of the other part's own `CanCollide`, so there
isn't a fully confirmed code-level explanation. What's shipped is
defensive hardening rather than a proven root cause: `_beginFlight` now
also stashes and clears `CanQuery` (not just `CanCollide`/`Transparency`)
on every character part, and `NoclipController.lua`'s per-frame
`stepFlight` reasserts `CanCollide = false` on every character part every
single frame (not just once at flight start), in case something —
most likely the humanoid's own state machine reacting around the
`StateChanged` reassertion above — was silently flipping it back on for
whichever part happened to be leading the upward move. If the roof is
still solid after this, the next real suspect is a manually-placed Studio
object (an old Baseplate or roof piece that predates the Rojo-managed
`Ceiling` folder) that `/spectate`'s Anchored root would have always
skipped — Anchored parts don't participate in collision responses the
same way — but `/spectate2`'s real physics body wouldn't.

Both flight modes also make the ceiling see-through so monsters are easy
to spot from above (`NoclipController.lua`'s `setCeilingXray`) —
client-only via `LocalTransparencyModifier` on every part in the `Store`
model's `Ceiling` folder, which overrides how those parts render for just
that one client and never replicates, so nobody else's view of the roof
changes.

The first version of this drove flight with `AssemblyLinearVelocity` and
`Humanoid.PlatformStand = true`, and it was glitchy and still didn't
reliably clip through walls — `PlatformStand` ragdolls the rig (every
limb's joint goes loose) rather than just suspending walk control, and
that ragdoll physics fought our velocity writes to the root every frame.
Now `_beginFlight` sets `HumanoidRootPart.Anchored = true` instead, which
— like the monster movement rebuild above — takes the *entire* welded rig
out of physics simulation: no gravity, no ragdoll, no collision response
possible, nothing left to fight. With the root Anchored,
`NoclipController.lua` becomes the only thing moving the character,
translating `root.CFrame` directly every frame — nothing to glitch, and
nothing for a wall to stop.

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
this repo by default is a small placeholder rig per monster (a colored
capsule body + a ball head in that character's signature colors + a
floating name tag) built entirely from primitive `Part`s in
`MonsterAI.lua`'s `createPlaceholderRig()` function, driven by the
color/scale values in `Config.Monsters`. It's instantly readable ("that's
the blue-and-red one, that's Thomas") but it is not the character. If you
ever intend to publish this place widely, either commission your own
stylized designs (recolors, different proportions, parody-styled — not the
character itself) or verify the license on anything you drop in below.

**There's now a real pipeline for swapping in an actual model, per
monster, without touching movement/AI code at all.** Drop a rigged model
(anything with a `Humanoid` + a `HumanoidRootPart`, doesn't need to be a
strict 15-part R15 layout — a `Head` is optional too, used for the name
tag if present, falls back to the root otherwise) into
`src/ServerStorage/MonsterModels/<Name>.rbxm`, add
`templateModel = "<Name>"` to that monster's entry in `Config.Monsters`,
and `MonsterAI.lua`'s `createRig()` clones it instead of building the
placeholder — see `createRigFromTemplate()`. Missing template folder, a
missing model, or a model missing `HumanoidRootPart`/`Humanoid` all just
`warn()` and fall back to the placeholder rig rather than breaking
anything, so this is safe to try per-monster incrementally.

Mechanically: `default.project.json` now maps `ServerStorage` to
`src/ServerStorage`, so any `.rbxm`/`.rbxmx` dropped under
`MonsterModels/` syncs in via Rojo like any other file — this is the one
place in the repo where an asset is a binary model file instead of a
`.lua` script, since a real mesh/rig genuinely can't be authored as text.
`createRigFromTemplate()` anchors the cloned root (same reasoning as the
placeholder: movement is a direct `CFrame` set every frame, nothing here
ever needs gravity or physics response), applies `def.scale` via
`Model:ScaleTo()` instead of resizing a `Part` by hand, and sets
`CanCollide = true` + `CollisionGroup = "Monsters"` on every `BasePart` in
the model rather than just the root — a real rig's `HumanoidRootPart` is
usually a small part buried inside the body, not the visible extent the
way the placeholder's single big root part is, so leaving the rest
non-colliding would shrink the catchable hitbox down to that sliver. The
existing `Monsters`-vs-`Players` collision group (see above) already
strips out physical push-back regardless, so this doesn't reintroduce the
old shoving problem. `MonsterAI:_onTouch` connects to every one of those
parts instead of just the root for the same reason.

Two monsters currently have a template wired in as a working example:
Peppa (`ServerStorage.MonsterModels.Peppa`) and Thomas
(`ServerStorage.MonsterModels.Thomas`), both via `templateModel` in
`Config.lua`, both falling back to their placeholder if the model's ever
missing. Thomas's rig has no `Head` part (his face is on the front of the
boiler, named `Face` instead) — worth knowing since a few other systems
(the jumpscare closeup below) look for `Head` first and fall back from
there; his `NameTag`/`StateTag` billboards end up anchored to `Face`
instead, same as every other per-monster HUD element.

`createRigFromTemplate`'s `HumanoidRootPart`/`Humanoid`/`Head`/`Face`
lookups all search recursively (`FindFirstChild`'s second argument, or a
manual `GetDescendants()` scan for `Humanoid` specifically, since
`FindFirstChildOfClass` doesn't have a recursive option), not just a
template's direct children — how a given `.rbxm` export nests its rig
internally isn't something this repo controls per drop-in file, so this
avoids a template silently falling back to the placeholder just because
its rig sits one level deeper than expected. If a monster's real model
still isn't showing up in Studio after a fresh Rojo sync (and a full Play
restart — files already synced into a session that was already running
won't retroactively appear until it restarts), check the Output window's
Server tab for a `[MonsterAI] templateModel "..." is missing a
HumanoidRootPart/Humanoid` warning, which confirms it's a genuine
structural issue rather than a sync/restart timing one.

**Sizing and grounding a template rig.** Two related problems showed up
once Thomas's real mesh was in: he was floating/clipping into the floor a
little, and reported "a little too big." The floor issue was a real bug —
`MonsterAI:TeleportTo` (used by every spawn/reposition) placed the model a
hardcoded 3 studs above the target floor point, a safe-enough guess for
the placeholder rig (whose root part IS the whole visible body) but wrong
for a real rig, whose `HumanoidRootPart` can sit anywhere relative to its
actual mesh — hip height, nose height, the center of a train's boiler,
whatever the original rig happened to use. Fixed by computing
`self.groundOffset` once per monster, right after its rig is built and
scaled (`root.Position.Y` minus the model's actual bounding-box bottom via
`Model:GetBoundingBox()`), and `TeleportTo` uses that instead of the fixed
3. It only needs computing once because monsters only ever rotate around
yaw (`_faceAndMove`), which never changes how tall something is.

The sizing issue wasn't a bug, just a bad assumption: `def.scale` sizes
the *placeholder* rig from scratch (a small block times `scale`) and also
feeds `PathfindingService`'s agent radius, so a real mesh — already sized
on its own, unrelated to whatever `scale` happens to be tuned to for the
placeholder — was getting scaled by that same number on top of its actual
size. Added an optional `templateScale` field (`createRigFromTemplate`
prefers it over `scale` for the `Model:ScaleTo()` call specifically) so a
template's visual size can be tuned independently without touching how
much clearance its pathfinding thinks it needs. Thomas's is currently `1`
— a guess, since this environment can't render and check it — expect to
need to adjust it based on how he actually looks in Studio.

**Jumpscare closeup facing the wrong way.** Thomas's jumpscare showed a
side profile instead of head-on. The camera was oriented using the
focal part's (`Head`/`Face`) *own* rotation, but a `MeshPart`'s baked
rotation is just whatever the mesh author's local axes happened to be
when it was modeled — it doesn't reliably line up with which way the
character actually faces. `JumpscareController.lua`'s `getFocalPoint` now
takes the focal part's *position* but the *root's* orientation instead:
the root's forward direction is the same one `_faceAndMove` already
trusts as canonical "front" for movement, so it's far more reliable
across different rigs than trusting each mesh part's own rotation.

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
  MonsterAI.lua                      Per-monster state machine + Overtime godmode + placeholder/template rig + monster audio
  MonsterSpawner.lua                 Spawns one of every Config.Monsters entry
  MinigameService.lua                Station wiring, noise pulses, exit-unlock trigger
  ExitService.lua                    Exit door lock/unlock + escape-zone detection
  PlayerService.lua                  Round state per player, catch/respawn/spectate/escape, flashlight toggle+aim, noclip
  HidingService.lua                  Wardrobe ProximityPrompt wiring, Hidden attribute + WalkSpeed freeze
  GameState.lua                      Waiting → Intermission → Playing → Results loop, Overtime trigger
src/ServerStorage/
  MonsterModels/<Name>.rbxm           Real rig to clone for a monster (see "Important limitations" below) -- optional per monster, falls back to the placeholder rig if absent
src/StarterPlayerScripts/
  Main.client.lua                    Boots all client controllers, each wrapped in pcall so one's error can't skip the rest
  UIUtil.lua                         Shared UI-building helpers
  CursorLock.lua                     Frees the mouse for clickable menus (fights the camera every frame)
  SprintController.lua               Shift-to-sprint with a drain/regen stamina meter + fade in/out bar
  StaminaState.lua                    Tiny shared stamina value read by ViewBobController.lua's low-stamina shake boost
  ViewBobController.lua               Subtle first-person camera bob, scaled up while sprinting
  FlashlightController.lua            Sends the F-key toggle request + throttled camera-pitch reports for beam tilt
  NoclipController.lua                Drives free-fly movement for /spectate (server only toggles the "Flying" state)
  AmbienceController.lua             Store ambience loop, proximity heartbeat, round/exit/escape stingers
  JumpscareController.lua            Full-screen jumpscare on catch + catch/scream audio
  HidingController.lua               Camera resync to face outward on hide-entry + hide-timeout warning/kick toast
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
