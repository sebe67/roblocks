-- Per-monster state machine: exactly two states, Patrol and Chase, that
-- can't interfere with each other. Chase is entered ONLY by directly seeing
-- a player (unobstructed raycast + FOV cone + range) and exited ONLY by
-- CHASE_GIVEUP_TIME passing with no sight of that player -- see Update().
-- A noise alert (minigame stations, Dora's "callout" quirk) never starts a
-- real Chase; it just gives Patrol a specific destination to head toward
-- for a while instead of a random one (ReceiveAlert), so it's a variant of
-- Patrol rather than a third state.

local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local SoundService = game:GetService("SoundService")
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
local SoundKit = require(game:GetService("ReplicatedStorage").Shared.SoundKit)
local StoreTheme = require(script.Parent.StoreTheme)

local MonsterAI = {}
MonsterAI.__index = MonsterAI

local registry = {}
local catchHandler = nil
local overtimeActive = false

-- Chase gives up (reverts to Patrol) after this many seconds with no sight
-- of the target it's chasing -- see the file header and Update().
local CHASE_GIVEUP_TIME = 5

-- Once within this many studs of the player, Chase (and Overtime's
-- _updateGodChase) stops recomputing a fresh direction every frame and
-- just holds its last heading. Why: with monster-vs-player collision
-- disabled (Main.server.lua) there's nothing physically stopping the
-- monster at the player's edge anymore, so steering at their exact center
-- every single frame lets it walk straight through that point. The root
-- part is a real, momentum-carrying physics body, not a kinematic
-- teleport -- once it overshoots, the direction back to the (still very
-- close) player swings through a huge angle in one frame, and it can't
-- instantly redirect its existing momentum to match. Recomputing that
-- swung-around heading every frame while still carrying speed from the old
-- one is exactly a textbook "seek without arrival" steering bug: it
-- doesn't converge, it curls -- an orbit that tightens the closer it gets,
-- which matches "orbits ~2 revolutions, then stands still" once it finally
-- bleeds off enough speed to stop. Catching is a Touched-based proximity
-- trigger, not a precise walk-to-this-exact-point task, so there was never
-- a reason to keep correcting this tightly this close -- letting the last
-- real heading carry it the rest of the way in removes the
-- every-frame-overshoot-and-recompute cycle that caused it.
local CHASE_ARRIVE_RADIUS = 4

function MonsterAI.SetCatchHandler(fn)
	catchHandler = fn
end

-- Every monster sound (footsteps, chase stingers, idle tells) routes
-- through this one SoundGroup, so Overtime can make everything sound
-- deeper/distorted at once without touching each individual Sound.
local monsterSoundGroup
local function getMonsterSoundGroup()
	if monsterSoundGroup then
		return monsterSoundGroup
	end
	monsterSoundGroup = Instance.new("SoundGroup")
	monsterSoundGroup.Name = "Monsters"
	monsterSoundGroup.Parent = SoundService

	local pitch = Instance.new("PitchShiftSoundEffect")
	pitch.Name = "OvertimePitch"
	pitch.Octave = 1
	pitch.Enabled = false
	pitch.Parent = monsterSoundGroup

	local distortion = Instance.new("DistortionSoundEffect")
	distortion.Name = "OvertimeDistortion"
	distortion.Level = 0
	distortion.Enabled = false
	distortion.Parent = monsterSoundGroup

	return monsterSoundGroup
end

-- Flips every monster into godmode: much faster, omniscient targeting of
-- whoever's nearest (no sight/range checks), and deeper/distorted audio.
-- Called once by GameState when Config.Round.MaxRoundTime runs out.
function MonsterAI.EnterOvertime()
	overtimeActive = true
	local group = getMonsterSoundGroup()
	local pitch = group:FindFirstChild("OvertimePitch")
	local distortion = group:FindFirstChild("OvertimeDistortion")
	if pitch then
		pitch.Octave = Config.Overtime.PitchOctave
		pitch.Enabled = true
	end
	if distortion then
		distortion.Level = Config.Overtime.DistortionLevel
		distortion.Enabled = true
	end
	for _, monster in ipairs(registry) do
		monster.god = true
		monster:_setState("Chase")
	end
end

function MonsterAI.ExitOvertime()
	overtimeActive = false
	local group = getMonsterSoundGroup()
	local pitch = group:FindFirstChild("OvertimePitch")
	local distortion = group:FindFirstChild("OvertimeDistortion")
	if pitch then
		pitch.Enabled = false
	end
	if distortion then
		distortion.Enabled = false
	end
end

local function createRig(def)
	local model = Instance.new("Model")
	model.Name = def.displayName

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2.4, 3.2, 1.4) * def.scale
	root.Color = def.color
	root.Material = Enum.Material.SmoothPlastic
	root.CanCollide = true
	-- Physically colliding with players was causing the AI to shove them
	-- and get shoved right back every frame it tried to walk into someone
	-- it had already reached -- see the collision-group setup in
	-- Main.server.lua for why that's disabled and why Touched still works.
	root.CollisionGroup = "Monsters"
	root.Parent = model
	model.PrimaryPart = root

	local head = Instance.new("Part")
	head.Name = "Head"
	head.Shape = Enum.PartType.Ball
	head.Size = Vector3.new(1.8, 1.8, 1.8) * def.scale
	head.Color = def.accentColor
	head.Material = Enum.Material.SmoothPlastic
	head.CanCollide = false
	head.Parent = model
	head.CFrame = root.CFrame * CFrame.new(0, (root.Size.Y / 2) + (head.Size.Y / 2) - 0.2, 0)

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = head
	weld.Parent = root

	local face = Instance.new("Decal")
	face.Texture = "rbxasset://textures/face.png"
	face.Face = Enum.NormalId.Front
	face.Parent = head

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.WalkSpeed = def.patrolSpeed
	humanoid.JumpPower = 0
	humanoid.BreakJointsOnDeath = false
	humanoid.Parent = model

	local nameTag = Instance.new("BillboardGui")
	nameTag.Name = "NameTag"
	nameTag.Size = UDim2.new(6, 0, 1.4, 0)
	nameTag.StudsOffset = Vector3.new(0, 2.4, 0)
	nameTag.Adornee = head
	nameTag.Parent = head
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = def.color
	label.TextStrokeTransparency = 0
	label.Text = def.displayName
	label.Parent = nameTag

	-- Temporary testing aid: shows which of the two states (Patrol/Chase)
	-- this monster is currently in, right above its name. Remove once
	-- chase behavior is confirmed solid and this is no longer needed for
	-- debugging.
	local stateTag = Instance.new("BillboardGui")
	stateTag.Name = "StateTag"
	stateTag.Size = UDim2.new(4, 0, 0.9, 0)
	stateTag.StudsOffset = Vector3.new(0, 3.5, 0)
	stateTag.Adornee = head
	stateTag.Parent = head
	local stateLabel = Instance.new("TextLabel")
	stateLabel.Name = "StateLabel"
	stateLabel.Size = UDim2.fromScale(1, 1)
	stateLabel.BackgroundTransparency = 1
	stateLabel.Font = Enum.Font.FredokaOne
	stateLabel.TextScaled = true
	stateLabel.TextColor3 = Color3.fromRGB(140, 220, 255)
	stateLabel.TextStrokeTransparency = 0
	stateLabel.Text = "PATROL"
	stateLabel.Parent = stateTag

	CollectionService:AddTag(model, "Monster")

	return model, humanoid, root, stateLabel
end

function MonsterAI.new(def, maze)
	local self = setmetatable({}, MonsterAI)
	self.def = def
	self.maze = maze
	self.state = "Patrol"
	self.target = nil
	self.investigatePos = nil
	self.lastSightTime = 0
	self.paused = true
	self.destroyed = false
	self.catchCooldown = {}

	self.model, self.humanoid, self.root, self.stateLabel = createRig(def)
	self.model.Parent = workspace

	-- Floors/Ceiling should never occlude a sight check (_canSee) -- monsters
	-- and players both stand on the floor and walk under the ceiling, so
	-- those are never real obstacles between them.
	self.raycastExclude = { self.model }
	local floorsFolder = maze.model:FindFirstChild("Floors")
	local ceilingFolder = maze.model:FindFirstChild("Ceiling")
	if floorsFolder then
		table.insert(self.raycastExclude, floorsFolder)
	end
	if ceilingFolder then
		table.insert(self.raycastExclude, ceilingFolder)
	end

	self.god = false
	self.footstepSound = SoundKit.CreateLoop3D(self.root, def.footstepSoundId, {
		Name = "Footsteps",
		Volume = 0.4,
		PlaybackSpeed = def.footstepPitch or 1,
		MaxDistance = def.footstepMaxDistance or 60,
		SoundGroup = getMonsterSoundGroup(),
	})
	self.nextIdleSoundAt = os.clock() + math.random((def.idleSoundInterval or { 8, 16 })[1], (def.idleSoundInterval or { 8, 16 })[2])

	self.touchConn = self.root.Touched:Connect(function(hit)
		self:_onTouch(hit)
	end)

	-- Runs independently of the shared movement Heartbeat -- see the long
	-- comment on _updateLightsOut for why this quirk's bookkeeping must
	-- never share a call with movement.
	if def.quirk == "lightsOut" then
		task.spawn(function()
			while not self.destroyed do
				task.wait(0.25)
				if not self.paused then
					local ok, err = pcall(function()
						self:_updateLightsOut()
					end)
					if not ok then
						warn(string.format("[MonsterAI] %s lightsOut error: %s", def.id, tostring(err)))
					end
				end
			end
		end)
	end

	table.insert(registry, self)
	return self
end

-- Every place that flips self.state routes through here so the temporary
-- PATROL/CHASE tag above the monster's head (createRig's stateLabel) always
-- matches, without writing to the label's Text every single frame.
function MonsterAI:_setState(state)
	if self.state == state then
		return
	end
	self.state = state
	if self.stateLabel then
		self.stateLabel.Text = state == "Chase" and "CHASE" or "PATROL"
	end
end

function MonsterAI:_onTouch(hit)
	if self.paused or self.state ~= "Chase" or not self.target then
		return
	end
	local character = hit:FindFirstAncestorOfClass("Model")
	if not character or character ~= self.target then
		return
	end
	local player = Players:GetPlayerFromCharacter(character)
	if not player then
		return
	end
	if player:GetAttribute("State") ~= "Alive" then
		return
	end
	if os.clock() < (self.catchCooldown[player] or 0) then
		return
	end
	self.catchCooldown[player] = os.clock() + 2
	if catchHandler then
		catchHandler(player, self.def.id)
	end
	self:_setState("Patrol")
	self.target = nil
end

local function playersToCheck()
	local list = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("State") == "Alive" and player.Character then
			local hum = player.Character:FindFirstChildOfClass("Humanoid")
			local root = player.Character:FindFirstChild("HumanoidRootPart")
			if hum and root and hum.Health > 0 and not player:GetAttribute("Invulnerable") then
				table.insert(list, { player = player, root = root })
			end
		end
	end
	return list
end

function MonsterAI:_canSee(targetRoot)
	local def = self.def
	local myPos = self.root.Position
	local toTarget = targetRoot.Position - myPos
	local dist = toTarget.Magnitude

	local range = def.sightRange
	if def.quirk == "darkBoost" and self:_inDarkCell() then
		range = range * 1.4
	end
	if dist > range then
		return false
	end

	-- Within melee range, skip the facing-cone check entirely -- a monster
	-- that's basically on top of someone shouldn't lose track of them
	-- purely because its facing lags its own movement direction by a few
	-- degrees (steering, not intent).
	if dist > Config.MeleeAwareRadius then
		local dir = toTarget.Unit
		local look = self.root.CFrame.LookVector
		local angle = math.deg(math.acos(math.clamp(look:Dot(dir), -1, 1)))
		if angle > def.sightAngle then
			return false
		end
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = self.raycastExclude
	local result = workspace:Raycast(myPos, toTarget, params)
	if result and not result.Instance:IsDescendantOf(targetRoot.Parent) then
		return false
	end
	return true
end

function MonsterAI:_inDarkCell()
	local cellSize = self.maze.cellSize
	local x = math.clamp(math.floor(self.root.Position.X / cellSize) + 1, 1, self.maze.gridWidth)
	local y = math.clamp(math.floor(self.root.Position.Z / cellSize) + 1, 1, self.maze.gridHeight)
	-- Checks the actual ceiling fixture for this cell rather than a proxy --
	-- genuinely dark (dead/flickering fixture) cells give the Grinch his
	-- sight/range boost.
	local fixturesFolder = self.maze.model:FindFirstChild("Fixtures")
	local fixture = fixturesFolder and fixturesFolder:FindFirstChild(string.format("Fixture_%d_%d", x, y))
	return not (fixture and fixture:GetAttribute("Working"))
end

-- SpongeBob's "lightsOut" quirk: suppress every naturally-lit fixture
-- within Config.LightsOutRadius studs of him, and release each one
-- Config.LightsOutGrace seconds after he's no longer near it (canceled if
-- he comes back within range before that timer fires). Scans only the 3x3
-- block of grid cells around his current cell rather than every fixture in
-- the store, and only needs to run a few times a second -- plenty for
-- something that only tracks "am I near this room's light," not per-frame.
--
-- Runs on its own task.spawn loop (started in MonsterAI.new), NOT from
-- inside Update(): Update() runs on the single shared Heartbeat connection
-- that drives every monster's movement every frame, so anything slow or
-- (if a bug ever crept in here) error-prone sharing that same call would
-- eat into -- or in the pcall-wrapped worst case, entirely skip -- that
-- monster's movement command for the frame. Since SpongeBob was the one
-- monster reported with noticeably worse chase movement than the others
-- despite running the exact same chase code, and this quirk update was the
-- one per-frame thing only he ran, putting it on a fully independent timer
-- removes it as a suspect regardless of whether a concrete bug is ever
-- found in it.
function MonsterAI:_updateLightsOut()
	local maze = self.maze
	local fixturesFolder = maze.model:FindFirstChild("Fixtures")
	if not fixturesFolder then
		return
	end
	local cellSize = maze.cellSize
	local cx = math.clamp(math.floor(self.root.Position.X / cellSize) + 1, 1, maze.gridWidth)
	local cy = math.clamp(math.floor(self.root.Position.Z / cellSize) + 1, 1, maze.gridHeight)
	local radius = Config.LightsOutRadius

	self.litFixtures = self.litFixtures or {}
	self.pendingRelease = self.pendingRelease or {}
	local stillNear = {}

	for dx = -1, 1 do
		for dy = -1, 1 do
			local fx, fy = cx + dx, cy + dy
			if fx >= 1 and fx <= maze.gridWidth and fy >= 1 and fy <= maze.gridHeight then
				local fixture = fixturesFolder:FindFirstChild(string.format("Fixture_%d_%d", fx, fy))
				if fixture and fixture:GetAttribute("NaturallyOn") then
					if (fixture.Position - self.root.Position).Magnitude <= radius then
						stillNear[fixture] = true
						if not self.litFixtures[fixture] then
							self.litFixtures[fixture] = true
							StoreTheme.SuppressFixture(fixture)
						end
						-- Bump the token so any release scheduled from a
						-- previous departure sees a mismatch and no-ops --
						-- coming back within range cancels the countdown.
						self.pendingRelease[fixture] = (self.pendingRelease[fixture] or 0) + 1
					end
				end
			end
		end
	end

	for fixture in pairs(self.litFixtures) do
		if not stillNear[fixture] then
			self.litFixtures[fixture] = nil
			local token = (self.pendingRelease[fixture] or 0) + 1
			self.pendingRelease[fixture] = token
			task.delay(Config.LightsOutGrace, function()
				if not self.destroyed and self.pendingRelease[fixture] == token then
					StoreTheme.ReleaseFixture(fixture)
				end
			end)
		end
	end
end

function MonsterAI:_scanForTargets()
	local best, bestDist
	for _, entry in ipairs(playersToCheck()) do
		if self:_canSee(entry.root) then
			local d = (entry.root.Position - self.root.Position).Magnitude
			if not bestDist or d < bestDist then
				bestDist = d
				best = entry
			end
		end
	end
	return best
end

-- Noise (a minigame station running, Dora's callout) never starts a real
-- Chase by itself -- only directly seeing a player does that (see the file
-- header). It just gives Patrol a specific destination to walk to instead
-- of a random one for a while, rather than being its own state: with only
-- Patrol and Chase existing, there's nothing else for a state machine
-- transition to conflict with.
function MonsterAI:ReceiveAlert(position)
	if self.state == "Chase" then
		return
	end
	self.investigatePos = position
	self.investigateUntil = os.clock() + 6
	self.currentPath = nil
end

function MonsterAI.BroadcastNoise(position, radius)
	for _, monster in ipairs(registry) do
		if not monster.paused and not monster.destroyed then
			local d = (monster.root.Position - position).Magnitude
			if d <= radius then
				monster:ReceiveAlert(position)
			end
		end
	end
end

function MonsterAI.BroadcastCallout(position, excludeMonster)
	for _, monster in ipairs(registry) do
		if monster ~= excludeMonster and not monster.paused and not monster.destroyed then
			monster:ReceiveAlert(position)
		end
	end
end

local function computeNavmeshPath(fromPos, toPos, agentRadius, agentScale)
	local path = PathfindingService:CreatePath({
		AgentRadius = agentRadius,
		AgentHeight = 5 * agentScale,
		AgentCanJump = false,
		-- WaypointSpacing is the MAX gap between waypoints, not a target --
		-- at 4 it was forcing extra waypoints along dead-straight stretches
		-- through these big rooms (up to 110 studs across), each one a tiny
		-- excuse to nudge direction, which is what patrol read as erratic
		-- even with nothing chasing it. Widening it lets a straight room
		-- interior collapse to a couple of waypoints; real turns (doorways,
		-- corners) still force one because the underlying route actually
		-- bends there, so direction changes now line up with intersections.
		WaypointSpacing = 16,
	})
	local ok = pcall(function()
		path:ComputeAsync(fromPos, toPos)
	end)
	if not ok or path.Status ~= Enum.PathStatus.Success then
		return nil
	end
	local waypoints = {}
	for _, wp in ipairs(path:GetWaypoints()) do
		table.insert(waypoints, wp.Position)
	end
	return waypoints
end

function MonsterAI:_moveAlongPath(waypoints)
	self.currentPath = waypoints
	self.pathIndex = 1
end

-- Walks the current waypoint list, advancing to the next one once within 3
-- studs of the current target so the monster never needs to precisely
-- "arrive" anywhere. Steers with _steerToward (Humanoid:Move()) the same as
-- every other kind of movement in this file -- see _steerToward's comment
-- for why nothing here ever calls Humanoid:MoveTo() anymore.
function MonsterAI:_followCurrentPath()
	if not self.currentPath or not self.currentPath[self.pathIndex] then
		return true
	end
	local targetPoint = self.currentPath[self.pathIndex]
	local flatDist = (Vector3.new(targetPoint.X, 0, targetPoint.Z) - Vector3.new(self.root.Position.X, 0, self.root.Position.Z)).Magnitude
	if flatDist < 3 then
		self.pathIndex += 1
		if not self.currentPath[self.pathIndex] then
			return true
		end
		targetPoint = self.currentPath[self.pathIndex]
	end
	self:_steerToward(targetPoint)
	return false
end

function MonsterAI:_randomPatrolTarget()
	local x = math.random(1, self.maze.gridWidth)
	local y = math.random(1, self.maze.gridHeight)
	return self.maze.cellToWorld(x, y)
end

function MonsterAI:_pathTo(destination)
	return computeNavmeshPath(self.root.Position, destination, self.def.pathAgentRadius or 2, self.def.scale)
end

-- Requests a path toward destination unless one is already in flight, and
-- throttles retries to once a second so a destination PathfindingService
-- can't reach (or a momentary navmesh hiccup) can't turn into a
-- ComputeAsync call on every single Heartbeat frame.
function MonsterAI:_ensurePath(destination)
	if self.currentPath and #self.currentPath > 0 then
		return
	end
	local now = os.clock()
	if self.nextPathAttempt and now < self.nextPathAttempt then
		return
	end
	self.nextPathAttempt = now + 1
	self:_moveAlongPath(self:_pathTo(destination) or {})
end

function MonsterAI:_applyQuirkSpeed(baseSpeed)
	local def = self.def
	if def.quirk == "snortBurst" and self.state == "Chase" then
		if math.random() < 0.02 then
			self.burstUntil = os.clock() + 0.6
		end
	elseif def.quirk == "rollDash" and self.state == "Chase" then
		if math.random() < 0.015 then
			self.burstUntil = os.clock() + 0.8
		end
	end
	if self.burstUntil and os.clock() < self.burstUntil then
		return baseSpeed * 1.5
	end
	return baseSpeed
end

-- The ONE movement primitive for every monster in every state: turns
-- toward targetPos (a live player position or a pathfinding waypoint, it
-- doesn't care which) and steers that way this frame, via Humanoid:Move()
-- -- a per-frame "here's my desired direction," exactly like a player's own
-- WASD input. Nothing in this file calls Humanoid:MoveTo() anymore.
--
-- MoveTo is a one-shot "walk to this exact waypoint and stop" command, and
-- every state (Patrol, Investigate, Search, Chase) used to call it once per
-- frame toward its own kind of constantly-shifting target -- a fresh random
-- patrol point, a moving player, whatever. Each call resets the humanoid's
-- internal walk/turn state, and that reset is where the flailing was really
-- coming from: it wasn't isolated to chasing a moving player (recalling it
-- toward player was only where it was easiest to notice) -- it happened to
-- every monster, in every state, including plain Patrol with nothing to
-- chase at all, exactly as reported. Move() has none of that: it just sets
-- a desired direction each frame and lets the humanoid's normal turn/walk
-- physics carry it smoothly, so a moving target (or a changing waypoint)
-- never needs a state reset to follow.
function MonsterAI:_steerToward(targetPos)
	local toTarget = targetPos - self.root.Position
	toTarget = Vector3.new(toTarget.X, 0, toTarget.Z)
	if toTarget.Magnitude > 0.1 then
		self.humanoid:Move(toTarget.Unit)
	end
end

function MonsterAI:_updateFootstepAudio()
	local sound = self.footstepSound
	if not sound then
		return
	end
	local pitchMultiplier, volume = 1, 0.35
	if self.state == "Chase" then
		pitchMultiplier, volume = 1.3, 0.75
	end
	sound.PlaybackSpeed = (self.def.footstepPitch or 1) * pitchMultiplier
	sound.Volume = volume
	if sound.SoundId ~= "" and not sound.Playing then
		sound:Play()
	end
end

-- Overtime: no sight/range checks, just always know exactly where the
-- nearest alive player is and beeline for them at a much higher speed.
-- Same simple, unconditional direct steering as the normal Chase case
-- below -- no obstacle awareness, no exception for Thomas either, per your
-- call to isolate the steering itself for now.
function MonsterAI:_updateGodChase()
	local def = self.def
	local nearestPlayer, nearestRoot, nearestDist
	for _, entry in ipairs(playersToCheck()) do
		local d = (entry.root.Position - self.root.Position).Magnitude
		if not nearestDist or d < nearestDist then
			nearestDist = d
			nearestPlayer = entry.player
			nearestRoot = entry.root
		end
	end
	if not nearestRoot then
		return
	end

	self.target = nearestPlayer.Character
	self.humanoid.WalkSpeed = def.chaseSpeed * Config.Round.OvertimeSpeedMultiplier
	self:_updateFootstepAudio()
	self.currentPath = nil
	local flatDist = (Vector3.new(nearestRoot.Position.X, 0, nearestRoot.Position.Z) - Vector3.new(self.root.Position.X, 0, self.root.Position.Z)).Magnitude
	if flatDist > CHASE_ARRIVE_RADIUS then
		self:_steerToward(nearestRoot.Position)
	end
end

-- Exactly two states, Patrol and Chase, and they can't interfere with each
-- other: Chase is entered ONLY by directly seeing a player (never by
-- noise/proximity alone) and exited ONLY by CHASE_GIVEUP_TIME passing with
-- no sight of that player, full stop -- nothing else can knock a monster
-- out of one state and into a muddled third condition.
--
-- Chase itself is deliberately simple right now, at your request: once
-- chasing, always steer straight at the player's live position with
-- Humanoid:Move(), completely ignoring walls/obstacles. No
-- PathfindingService fallback, no exception for Thomas -- this is a
-- reset back to the simplest possible version of chasing, to confirm the
-- underlying steering itself reads as smooth before any obstacle-awareness
-- comes back (a version of that layered on top of direct Move() steering
-- caused more problems than it solved across several rounds of tuning).
-- CHASE_GIVEUP_TIME and CHASE_ARRIVE_RADIUS are declared near the top of
-- this file (both _updateGodChase above and Update below need them).

function MonsterAI:Update(dt)
	if self.paused or self.destroyed then
		return
	end

	local now = os.clock()

	if self.god then
		self:_updateGodChase()
		return
	end

	local def = self.def

	if self.state ~= "Chase" then
		local seen = self:_scanForTargets()
		if seen then
			self:_setState("Chase")
			self.target = seen.player.Character
			self.lastSightTime = now
			self.currentPath = nil
			SoundKit.PlayAt(self.root, def.chaseSoundId, { Volume = 0.9, MaxDistance = 80, SoundGroup = getMonsterSoundGroup() })
			if def.quirk == "callout" then
				MonsterAI.BroadcastCallout(seen.root.Position, self)
				-- Dora's idleSoundId is reserved for this exact moment -- her
				-- "callout" line, not a random patrol tell.
				SoundKit.PlayAt(self.root, def.idleSoundId, { Volume = 0.8, MaxDistance = 70, SoundGroup = getMonsterSoundGroup() })
			end
		end
	end

	self:_updateFootstepAudio()

	if self.state == "Chase" then
		local root = self.target and self.target:FindFirstChild("HumanoidRootPart")
		local hum = self.target and self.target:FindFirstChildOfClass("Humanoid")
		if root and hum and hum.Health > 0 then
			if self:_canSee(root) then
				self.lastSightTime = now
			end
			if now - self.lastSightTime > CHASE_GIVEUP_TIME then
				-- Haven't seen them in CHASE_GIVEUP_TIME -- give up and
				-- resume Patrol. No "go check where I last saw them"
				-- detour; that PathfindingService-routed detour was
				-- exactly what could visibly loop before finally reaching
				-- a target that never even moved.
				self:_setState("Patrol")
				self.target = nil
				self.currentPath = nil
			else
				self.humanoid.WalkSpeed = self:_applyQuirkSpeed(def.chaseSpeed)
				self.currentPath = nil
				local flatDist = (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(self.root.Position.X, 0, self.root.Position.Z)).Magnitude
				if flatDist > CHASE_ARRIVE_RADIUS then
					self:_steerToward(root.Position)
				end
			end
		else
			self:_setState("Patrol")
			self.target = nil
			self.currentPath = nil
		end
		return
	end

	-- Patrol (the only other state). A noise alert (ReceiveAlert -- a
	-- minigame station running, Dora's callout) just swaps in a specific
	-- destination here for a while instead of a random one; it never
	-- becomes a different state.
	self.humanoid.WalkSpeed = def.patrolSpeed
	local destination
	if self.investigatePos and now < (self.investigateUntil or 0) then
		destination = self.investigatePos
	else
		self.investigatePos = nil
		destination = self:_randomPatrolTarget()
	end
	self:_ensurePath(destination)
	local reachedEnd = self:_followCurrentPath()
	if reachedEnd then
		self.currentPath = nil
		self.investigatePos = nil
	end

	-- Occasional audio tell (SpongeBob's giggle, George's chatter, etc).
	-- Dora's idleSoundId is reserved for her callout line, not this roll.
	if def.quirk ~= "callout" and now > self.nextIdleSoundAt then
		SoundKit.PlayAt(self.root, def.idleSoundId, { Volume = 0.6, MaxDistance = 40, SoundGroup = getMonsterSoundGroup() })
		local interval = def.idleSoundInterval or { 8, 16 }
		self.nextIdleSoundAt = now + math.random(interval[1], interval[2])
	end
end

function MonsterAI:TeleportTo(position)
	self.model:PivotTo(CFrame.new(position + Vector3.new(0, 3, 0)))
	self.currentPath = nil
	self:_setState("Patrol")
	self.target = nil
end

function MonsterAI:SetPaused(paused)
	self.paused = paused
	if paused then
		self.humanoid:MoveTo(self.root.Position)
		if self.footstepSound then
			self.footstepSound:Stop()
		end
		-- Godmode is strictly a this-round-only escalation.
		self.god = false
		-- Don't leave lights suppressed forever across a round reset --
		-- release everything this monster's lightsOut quirk currently has
		-- off rather than waiting out their individual grace timers.
		if self.litFixtures then
			for fixture in pairs(self.litFixtures) do
				StoreTheme.ReleaseFixture(fixture)
			end
			self.litFixtures = {}
			self.pendingRelease = {}
		end
	end
end

function MonsterAI:Destroy()
	self.destroyed = true
	if self.touchConn then
		self.touchConn:Disconnect()
	end
	for i, m in ipairs(registry) do
		if m == self then
			table.remove(registry, i)
			break
		end
	end
	self.model:Destroy()
end

function MonsterAI.GetAll()
	return registry
end

return MonsterAI
