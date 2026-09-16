-- Central tuning table. Every system reads from here so the game can be
-- rebalanced without touching logic code.
--
-- SOUND: every *SoundId field below defaults to "" (silent, no error) except
-- footstepSoundId, which points at a real sound bundled with every Roblox
-- client. Paste in your own rbxassetid://... once you've uploaded audio and
-- everything wires up automatically -- no code changes needed. See
-- SOUND_DESIGN.md at the repo root for what to source for each empty slot.

local Config = {}

Config.Maze = {
	CellSize = 22, -- base cell unit; a room is MinRoomSize-MaxRoomSize of these per side
	GridWidth = 28, -- 22 * 1.25 (rounded), per request -- side length, so the actual floor area grows ~1.6x
	GridHeight = 28,
	WallHeight = 12,
	WallThickness = 1,
	MinRoomSize = 3, -- rooms are 3-5 base cells per side (66-110 studs) -- big open spaces, not a mini-maze
	MaxRoomSize = 5,
	LoopChance = 0.15, -- chance an extra room-to-room connection is added beyond the minimum spanning layout
	HallwayChance = 0.4, -- of any room-to-room connection, the odds it's a wide open gap instead of a narrow doorway
	DoorwayWidth = 6, -- narrow connections are this wide instead of the full room edge
	MonsterSpawnExclusionCells = 4, -- monsters won't spawn/reposition within this many cells of the entrance at round start
	ZoneAccentChance = 0.15, -- chance a wall/shelf ignores its zone color and picks any palette color instead
	-- The grid is split into four roughly-quadrant color "wings" so wall
	-- color reads as "you're in a different part of the store" instead of
	-- random noise. ZoneAccentChance above keeps it from being forced
	-- monotone within a wing.
	ColorZones = {
		{ name = "Blue Wing", primary = Color3.fromRGB(0, 81, 186) },
		{ name = "Yellow Wing", primary = Color3.fromRGB(255, 218, 26) },
		{ name = "White Wing", primary = Color3.fromRGB(232, 226, 212) },
		{ name = "Wood Wing", primary = Color3.fromRGB(150, 116, 78) },
	},
}

Config.Lighting = {
	Brightness = 1,
	Ambient = Color3.fromRGB(46, 46, 54),
	OutdoorAmbient = Color3.fromRGB(30, 30, 38),
	ColorShift_Bottom = Color3.fromRGB(20, 20, 30),
	FogColor = Color3.fromRGB(18, 18, 24),
	FogStart = 12, -- shorter visibility distance -- you shouldn't see the next 2-3 junctions from here
	FogEnd = 65,
	ExposureCompensation = -0.2,
	FixtureRange = 28, -- bumped up to match the bigger rooms so lit cells still feel adequately lit
	FixtureBrightness = 2.2,
	FixtureColor = Color3.fromRGB(255, 238, 200),
	FixtureFrequency = 3, -- roughly 1 in N cells gets a working ceiling fixture; rest stay dim
	DeadFixtureFlickerChance = 0.35,
}

-- Random store-wide blackouts during an active round. Checked once every
-- CheckInterval seconds, each check rolling CheckInterval/AverageInterval
-- odds of firing -- a Poisson-style process, so the average gap between
-- blackouts is AverageInterval but there's never a guaranteed one, per your
-- call ("no guarantee, just on average every 2 minutes").
Config.Blackout = {
	AverageInterval = 120,
	CheckInterval = 5,
	Duration = 10,
}

-- SpongeBob's "lightsOut" quirk (MonsterAI): kills every working light
-- within LightsOutRadius studs of him as he moves, and lets each one turn
-- back on this many seconds after he's no longer near it. Doubled from
-- 20 -- since this is a radius, the actual darkened area is 4x bigger.
Config.LightsOutRadius = 40
Config.LightsOutGrace = 15

-- Within this many studs of a chase target, MonsterAI:_canSee skips the
-- facing-cone check -- a monster this close shouldn't lose track of
-- someone just because its own facing lags its movement direction.
Config.MeleeAwareRadius = 10

Config.Round = {
	MinPlayers = 1,
	IntermissionTime = 5, -- was 15; lowered for faster test iteration
	RespawnInvulnerability = 3,
	ResultsScreenTime = 14,
	JumpscareDuration = 2.6,
	-- Dying is never a dead end on its own -- Respawn/Spectate stays live and
	-- the round keeps running for anyone still Alive or deciding. This is
	-- the "how long do you have to actually escape" clock instead.
	MaxRoundTime = 600, -- 10 minutes
	-- Once MaxRoundTime is up, monsters go into Overtime (see MonsterAI's
	-- EnterOvertime): much faster, omniscient targeting of whoever's
	-- nearest, no more sight checks. This is the hard cap after which
	-- anyone still standing gets swept regardless -- guarantees the round
	-- can't hang forever even if someone keeps respawning into it.
	OvertimeDuration = 90,
	OvertimeSpeedMultiplier = 2.4,
	OvertimeRepathInterval = 0.15,
}

Config.Player = {
	WalkSpeed = 16,
	SprintSpeed = 25,
}

-- /spectate and /back debug chat commands (Main.server.lua, PlayerService,
-- NoclipController.lua) -- free-fly noclip for testing, not a real gameplay
-- feature.
Config.Noclip = {
	FlySpeed = 50,
}

-- Toggled with F (FlashlightController.lua). A real SpotLight on the
-- character, toggled server-side, so everyone sees everyone else's beam --
-- not just a client-only visual effect for its owner.
Config.Flashlight = {
	-- Roblox's docs describe SpotLight.Range as clamped to [0, 60] studs,
	-- which is why this was previously capped at 60 -- but that's from
	-- memory, not something verifiable in this environment (no live
	-- Roblox client here to test against). Set to 120 (2x) per your ask;
	-- if that clamp is real, this will just render identically to 60 and
	-- you'll see no change -- if it's not (or no longer is), you'll
	-- actually see the beam throw twice as far. Report back which one
	-- happens, since that settles it either way.
	Range = 120,
	Angle = 40, -- full cone angle in degrees (SpotLight.Angle), not a half-angle
	Brightness = 3.5, -- up slightly from 3
	Color = Color3.fromRGB(255, 250, 220),
	-- How far up/down (degrees) the beam can tilt from level, clamped
	-- server-side against the pitch the client reports (PlayerService's
	-- FlashlightAim Motor6D) -- see FlashlightController.lua. 89, not 90,
	-- only to dodge the gimbal-degenerate case of looking exactly straight
	-- up/down -- this is "full freedom, wherever you're looking" in
	-- practice. Yaw needs no separate handling: the round locks the camera
	-- to first-person the whole time the flashlight is usable, and Roblox
	-- always keeps the character's own yaw matched to the camera's in that
	-- mode, so Head (and FlashlightAim, welded to it) already turns
	-- left/right with your look direction for free.
	MaxPitch = 89,
}

-- Global / UI / ambient sounds not tied to a specific monster. All default
-- to "" (silent) -- see SOUND_DESIGN.md for a brief on each one.
Config.Sounds = {
	StoreAmbience = "", -- looping low dread drone/hum, plays for everyone throughout
	Heartbeat = "", -- looping heartbeat; volume/pitch ramp with nearest monster distance
	RoundStart = "", -- one-shot horn/bell when Playing begins
	IntermissionStart = "", -- one-shot when the "next round starts in..." countdown begins
	ExitUnlocked = "", -- triumphant one-shot when all stations are cleared
	EscapeSuccess = "", -- one-shot for the player who reaches the exit
	Caught = "", -- immediate impact/thud the instant a monster catches you
	UIClick = "", -- generic button/interaction click, reused everywhere
	MinigameSuccess = "", -- one-shot when any station is cleared
	MinigameFail = "", -- one-shot when any station attempt is failed/given up
	OvertimeWarning = "", -- one-shot dramatic stinger the instant Overtime begins
	BlackoutSting = "", -- one-shot the instant a store-wide blackout event kills the lights (SpongeBob's own local quirk is silent, no global event)
	HeartbeatMaxDistance = 55, -- studs at which the heartbeat starts fading in
	HeartbeatMinDistance = 10, -- studs at which the heartbeat hits full volume/pitch
}

-- Audio/visual escalation once Overtime kicks in (see Config.Round.MaxRoundTime).
Config.Overtime = {
	PitchOctave = 0.65, -- <1 = deeper; applied to every monster sound via a shared SoundGroup
	DistortionLevel = 0.55,
	WarningText = "THE STORE IS CLOSING. THEY WILL FIND YOU.",
	TintColor = Color3.fromRGB(120, 0, 0),
}

-- Per-monster sound fields:
--   footstepSoundId    looping 3D sound while alive, pitch/volume scale with state
--   footstepPitch      base PlaybackSpeed for that loop (character via pitch)
--   footstepMaxDistance  how far away the footsteps can be heard (Barney = far)
--   chaseSoundId       one-shot 3D stinger the instant it spots you and gives chase
--   jumpscareSoundId   one-shot 2D sound played in your ear at the jumpscare
--   idleSoundId        one-shot 3D sound played occasionally during Patrol
--                       (doubles as Dora's "callout" voice line -- see MonsterAI.lua)
--   idleSoundInterval  {min, max} seconds between idle sound rolls
--   pathAgentRadius    PathfindingService AgentRadius (default ~2 if unset)
--                       -- a bigger value makes narrow doorways impassable
--                       to that monster's pathfinding, forcing it through
--                       hallway-width gaps and open rooms only (Thomas).
Config.Monsters = {
	{
		id = "George",
		displayName = "Curious George",
		color = Color3.fromRGB(120, 78, 42),
		accentColor = Color3.fromRGB(230, 220, 190),
		scale = 1,
		patrolSpeed = 14,
		chaseSpeed = 24,
		investigateSpeed = 17,
		sightRange = 46,
		sightAngle = 65,
		hearingRadius = 20,
		loseSightTime = 4,
		repathInterval = 0.4,
		quirk = "erratic",
		jumpscareColor = Color3.fromRGB(120, 78, 42),
		flavor = "Insatiably curious. Unfortunately, currently curious about your skull.",
		footstepSoundId = "rbxasset://sounds/action_footsteps_plastic.mp3",
		footstepPitch = 1.15,
		footstepMaxDistance = 55,
		chaseSoundId = "",
		jumpscareSoundId = "",
		idleSoundId = "",
		idleSoundInterval = { 8, 16 },
	},
	{
		id = "Peppa",
		displayName = "Peppa Pig",
		color = Color3.fromRGB(235, 150, 170),
		accentColor = Color3.fromRGB(255, 255, 255),
		scale = 0.9,
		patrolSpeed = 12,
		chaseSpeed = 20,
		investigateSpeed = 15,
		sightRange = 40,
		sightAngle = 70,
		hearingRadius = 18,
		loseSightTime = 3.5,
		repathInterval = 0.4,
		quirk = "snortBurst",
		jumpscareColor = Color3.fromRGB(235, 150, 170),
		flavor = "She has found a muddy puddle. She would like you to join her. Permanently.",
		footstepSoundId = "rbxasset://sounds/action_footsteps_plastic.mp3",
		footstepPitch = 1.05,
		footstepMaxDistance = 50,
		chaseSoundId = "",
		jumpscareSoundId = "",
		idleSoundId = "",
		idleSoundInterval = { 7, 14 },
	},
	{
		id = "Thomas",
		displayName = "Thomas the Tank Engine",
		color = Color3.fromRGB(20, 90, 160),
		accentColor = Color3.fromRGB(200, 30, 30),
		scale = 1.3,
		patrolSpeed = 16,
		chaseSpeed = 32,
		investigateSpeed = 20,
		sightRange = 55,
		sightAngle = 50,
		hearingRadius = 26,
		loseSightTime = 5,
		repathInterval = 0.5,
		quirk = "wideBody", -- too wide for narrow doorways -- can only cross rooms via hallway-style gaps
		pathAgentRadius = 3.5, -- vs. the ~2 everyone else uses; this alone makes narrow doorways impassable to his pathfinding
		jumpscareColor = Color3.fromRGB(20, 90, 160),
		flavor = "A really useful engine. Useful for absolutely flattening you.",
		footstepSoundId = "rbxasset://sounds/action_footsteps_plastic.mp3",
		footstepPitch = 0.8,
		footstepMaxDistance = 75,
		chaseSoundId = "",
		jumpscareSoundId = "",
		idleSoundId = "",
		idleSoundInterval = { 10, 20 },
	},
	{
		id = "Barney",
		displayName = "Barney",
		color = Color3.fromRGB(110, 40, 140),
		accentColor = Color3.fromRGB(60, 200, 90),
		scale = 1.6,
		patrolSpeed = 10,
		chaseSpeed = 17,
		investigateSpeed = 12,
		sightRange = 35,
		sightAngle = 80,
		hearingRadius = 30,
		loseSightTime = 5,
		repathInterval = 0.5,
		quirk = "stomper",
		jumpscareColor = Color3.fromRGB(110, 40, 140),
		flavor = "He loves you. You do not love him back.",
		footstepSoundId = "rbxasset://sounds/action_footsteps_plastic.mp3",
		footstepPitch = 0.6,
		footstepMaxDistance = 90, -- his whole quirk is that you hear him coming from far away
		chaseSoundId = "",
		jumpscareSoundId = "",
		idleSoundId = "",
		idleSoundInterval = { 6, 12 },
	},
	{
		id = "Grinch",
		displayName = "The Grinch",
		color = Color3.fromRGB(60, 130, 70),
		accentColor = Color3.fromRGB(200, 40, 40),
		scale = 1.05,
		patrolSpeed = 15,
		chaseSpeed = 23,
		investigateSpeed = 17,
		sightRange = 42,
		sightAngle = 65,
		hearingRadius = 20,
		loseSightTime = 4,
		repathInterval = 0.4,
		quirk = "darkBoost",
		jumpscareColor = Color3.fromRGB(60, 130, 70),
		flavor = "His heart grew three sizes today. So did his appetite for chaos.",
		footstepSoundId = "rbxasset://sounds/action_footsteps_plastic.mp3",
		footstepPitch = 0.95,
		footstepMaxDistance = 45, -- he's sneaky; you should barely hear him until it's too late
		chaseSoundId = "",
		jumpscareSoundId = "",
		idleSoundId = "",
		idleSoundInterval = { 9, 18 },
	},
	{
		id = "Po",
		displayName = "Kung Fu Panda",
		color = Color3.fromRGB(28, 28, 28),
		accentColor = Color3.fromRGB(240, 240, 240),
		scale = 1.15,
		patrolSpeed = 13,
		chaseSpeed = 21,
		investigateSpeed = 16,
		sightRange = 38,
		sightAngle = 65,
		hearingRadius = 19,
		loseSightTime = 4,
		repathInterval = 0.4,
		quirk = "rollDash",
		jumpscareColor = Color3.fromRGB(28, 28, 28),
		flavor = "There is no charge for awesomeness. Or for what happens next.",
		footstepSoundId = "rbxasset://sounds/action_footsteps_plastic.mp3",
		footstepPitch = 0.9,
		footstepMaxDistance = 55,
		chaseSoundId = "",
		jumpscareSoundId = "",
		idleSoundId = "",
		idleSoundInterval = { 8, 15 },
	},
	{
		id = "SpongeBob",
		displayName = "SpongeBob SquarePants",
		color = Color3.fromRGB(235, 210, 60),
		accentColor = Color3.fromRGB(120, 190, 230),
		scale = 0.95,
		patrolSpeed = 13,
		chaseSpeed = 19,
		investigateSpeed = 14,
		sightRange = 36,
		sightAngle = 75,
		hearingRadius = 22,
		loseSightTime = 3.5,
		repathInterval = 0.4,
		quirk = "lightsOut", -- kills every working light near him as he moves (see MonsterAI:_updateLightsOut); they come back Config.LightsOutGrace seconds after he leaves
		jumpscareColor = Color3.fromRGB(235, 210, 60),
		flavor = "He is ready. He was born ready. Are you?",
		footstepSoundId = "rbxasset://sounds/action_footsteps_plastic.mp3",
		footstepPitch = 1.1,
		footstepMaxDistance = 50,
		chaseSoundId = "",
		jumpscareSoundId = "",
		idleSoundId = "", -- the giggle itself -- this is the "giggler" quirk's audio tell
		idleSoundInterval = { 5, 11 },
	},
	{
		id = "Dora",
		displayName = "Dora",
		color = Color3.fromRGB(150, 60, 130),
		accentColor = Color3.fromRGB(255, 200, 60),
		scale = 0.95,
		patrolSpeed = 13,
		chaseSpeed = 20,
		investigateSpeed = 15,
		sightRange = 40,
		sightAngle = 70,
		hearingRadius = 20,
		loseSightTime = 4,
		repathInterval = 0.4,
		quirk = "callout",
		jumpscareColor = Color3.fromRGB(150, 60, 130),
		flavor = "She sees you. She is telling EVERYONE she sees you.",
		footstepSoundId = "rbxasset://sounds/action_footsteps_plastic.mp3",
		footstepPitch = 1,
		footstepMaxDistance = 50,
		chaseSoundId = "",
		jumpscareSoundId = "",
		idleSoundId = "", -- her "callout" voice line -- fired the instant she spots you, not randomly
		idleSoundInterval = { 8, 16 },
	},
	{
		id = "TungSahur",
		displayName = "Tung Tung Tung Sahur",
		color = Color3.fromRGB(92, 64, 38),
		accentColor = Color3.fromRGB(200, 180, 140),
		scale = 1.7,
		patrolSpeed = 11,
		chaseSpeed = 22,
		investigateSpeed = 14,
		sightRange = 38,
		sightAngle = 70,
		hearingRadius = 28,
		loseSightTime = 4,
		repathInterval = 0.4,
		-- Same occasional-burst mechanic as snortBurst/rollDash, but the
		-- burst itself also thuds the ground hard enough to be a real
		-- noise event (MonsterAI.BroadcastNoise) within a radius -- see
		-- _applyQuirkSpeed. A burst mid-chase can now pull in whichever
		-- other monsters happen to be nearby, on top of speeding him up.
		quirk = "groundPound",
		jumpscareColor = Color3.fromRGB(92, 64, 38),
		flavor = "Tung tung tung tung sahur. It just wants you to wake up. It will make sure you do.",
		footstepSoundId = "rbxasset://sounds/action_footsteps_plastic.mp3",
		footstepPitch = 0.5,
		footstepMaxDistance = 95, -- the loudest of all of them -- it's a giant wooden club banging with every step
		chaseSoundId = "",
		jumpscareSoundId = "",
		idleSoundId = "",
		idleSoundInterval = { 4, 9 },
	},
}

-- How far (in studs) a player can wander from a station's anchor while
-- playing its minigame before it auto-cancels. Deliberately not a movement
-- freeze -- you can still bail and run if a monster shows up mid-minigame.
Config.MinigameLeashDistance = 16

-- "lore" is CRS's in-universe justification for each task (see the story in
-- README.md) -- shown in the minigame overlay's title alongside the
-- existing "description" (which stays the actual how-to-play hint).
Config.Minigames = {
	{
		id = "RestockShelves",
		stationName = "Restock: Aisle of Regret",
		lore = "CRS Directive: Shelf-Fill Compliance. Aisle inventory has fallen below acceptable thresholds.",
		description = "Match falling boxes to the correct shelf slot before time runs out.",
		duration = 16,
		roundsToWin = 8,
		noiseInterval = 2.5,
		noiseRadius = 55,
	},
	{
		id = "FlatPackAssembly",
		stationName = "Flat-Pack Rage Build",
		lore = "CRS Directive: Customer Assembly Verification. Build it exactly as instructed. CRS is always watching build quality.",
		description = "Repeat the build sequence exactly. One wrong panel and you start over.",
		duration = 18,
		roundsToWin = 5,
		noiseInterval = 2.5,
		noiseRadius = 55,
	},
	{
		id = "SelfCheckout",
		stationName = "Self-Checkout Vibe Check",
		lore = "CRS Directive: Checkout Throughput Audit. Scan accuracy affects your Loyalty standing.",
		description = "Hold the scanner steady in the green zone. It will not make this easy.",
		duration = 14,
		roundsToWin = 10,
		noiseInterval = 2,
		noiseRadius = 60,
	},
	{
		id = "InventoryCount",
		stationName = "Inventory Count",
		lore = "CRS Directive: Manual Stock Reconciliation. The system trusts nothing it hasn't seen a human confirm.",
		description = "Memorize the shelf, then answer before you forget.",
		duration = 20,
		roundsToWin = 5,
		noiseInterval = 3,
		noiseRadius = 50,
	},
	{
		id = "CustomerRush",
		stationName = "Customer Service Rush",
		lore = "CRS Directive: Service Coverage Requirement. Every register must appear staffed at all times.",
		description = "Every lit register needs you. All of them. At once.",
		duration = 16,
		roundsToWin = 8,
		noiseInterval = 2.5,
		noiseRadius = 55,
	},
	{
		id = "ForkliftCertification",
		stationName = "Forklift Certification",
		lore = "CRS Directive: Heavy Equipment Certification. Uncertified operation voids your Loyalty standing immediately.",
		description = "Keep it between the lines. Do not think about what's behind you.",
		duration = 20,
		roundsToWin = 10,
		noiseInterval = 2.5,
		noiseRadius = 55,
	},
}

Config.AisleSigns = {
	"GRÖNKVIST", "GNORPFJÄLL", "BLÖRD", "SKUGGVASK", "FNURKA",
	"GRUNTSTAD", "MÖRKHUS", "VÄNTAKORV", "SLAPPFJORD", "GNARBÖRK",
	"DÖVSKÅP", "TRUBBEL", "HÖLKSTAD", "BJÖRKÄNGEN", "SKRIKMOSS",
}

return Config
