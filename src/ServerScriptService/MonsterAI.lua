-- Per-monster state machine: Patrol -> (sight) -> Chase, with an
-- Investigate state fed by noise pulses (minigames) and Dora's "callout"
-- quirk, and a brief Search state when a chase target breaks line of sight.
--
-- Monsters ONLY ever enter Chase because they directly saw a player
-- (unobstructed raycast + FOV cone + range). Investigate only ever walks
-- them toward a *location*, never straight at a player through walls.

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
		monster.state = "Chase"
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

	CollectionService:AddTag(model, "Monster")

	return model, humanoid, root
end

function MonsterAI.new(def, maze)
	local self = setmetatable({}, MonsterAI)
	self.def = def
	self.maze = maze
	self.state = "Patrol"
	self.target = nil
	self.lastKnownPos = nil
	self.investigatePos = nil
	self.lastSightTime = 0
	self.lastPathTime = 0
	self.paused = true
	self.destroyed = false
	self.catchCooldown = {}

	self.model, self.humanoid, self.root = createRig(def)
	self.model.Parent = workspace

	-- Floors/Ceiling should never occlude a sight or movement-clearance
	-- check -- monsters and players both stand on the floor and walk under
	-- the ceiling, so those are never real obstacles between them.
	-- _hasClearPath's spherecast in particular has real vertical extent
	-- (its radius), and at a monster's actual root height that sphere can
	-- dip low enough to clip the floor even on a perfectly horizontal cast
	-- straight at a stationary player standing in an otherwise empty room --
	-- reading as "blocked" and forcing an unnecessary PathfindingService
	-- detour instead of a direct sprint. Excluding both folders up front
	-- (rather than trying to tune the radius) removes that false positive
	-- entirely regardless of height/radius.
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

	table.insert(registry, self)
	return self
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
	self.state = "Patrol"
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

	local dir = toTarget.Unit
	local look = self.root.CFrame.LookVector
	local angle = math.deg(math.acos(math.clamp(look:Dot(dir), -1, 1)))
	if angle > def.sightAngle then
		return false
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

-- An unobstructed-line-of-travel check (as opposed to _canSee, which also
-- checks FOV/range for spotting). Used so chasing can just walk straight at
-- a player when nothing's in the way, only falling back to PathfindingService
-- when a wall is actually blocking the direct route.
--
-- Uses a spherecast sized to the same AgentRadius PathfindingService plans
-- clearance around (def.pathAgentRadius, same default of 2 as _pathTo), not
-- a zero-width raycast. A thin centerline ray can read "clear" for a line
-- that grazes a wall corner or doorway jamb close enough that the monster's
-- actual body still clips it -- the collision response to that scrape (a
-- shove sideways, a moment of stuck friction) is exactly the zig-zag and
-- slower-than-expected chase reported even against a fully stationary
-- player. Matching the radius to what pathfinding already treats as "fits"
-- keeps the two systems in agreement: if this says clear, the body actually
-- fits, full stop.
function MonsterAI:_hasClearPath(targetPos)
	local origin = self.root.Position
	local direction = targetPos - origin
	if direction.Magnitude < 1 then
		return true
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = self.raycastExclude
	local radius = self.def.pathAgentRadius or 2
	local result = workspace:Spherecast(origin, radius, direction, params)
	if not result then
		return true
	end
	return (result.Position - targetPos).Magnitude < 2
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
-- the store, and throttled to a few times a second -- plenty for something
-- that only needs to track "am I near this room's light," not per-frame.
function MonsterAI:_updateLightsOut(now)
	if now < (self.nextLightsOutCheck or 0) then
		return
	end
	self.nextLightsOutCheck = now + 0.25

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

function MonsterAI:ReceiveAlert(position)
	if self.state == "Chase" then
		return
	end
	self.state = "Investigate"
	self.investigatePos = position
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
		WaypointSpacing = 4,
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
	self._lastCommandedPoint = nil
end

function MonsterAI:_followCurrentPath(dt)
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
	-- Only issue a new MoveTo when the target waypoint actually changes --
	-- calling Humanoid:MoveTo() every single frame (even at the same target)
	-- repeatedly interrupts the humanoid's walk state and is what was
	-- causing the stuttery/erratic-looking movement.
	if self._lastCommandedPoint ~= targetPoint then
		self.humanoid:MoveTo(targetPoint)
		self._lastCommandedPoint = targetPoint
	end
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

function MonsterAI:_updateFootstepAudio()
	local sound = self.footstepSound
	if not sound then
		return
	end
	local pitchMultiplier, volume = 1, 0.35
	if self.state == "Chase" then
		pitchMultiplier, volume = 1.3, 0.75
	elseif self.state == "Investigate" or self.state == "Search" then
		pitchMultiplier, volume = 1.1, 0.5
	end
	sound.PlaybackSpeed = (self.def.footstepPitch or 1) * pitchMultiplier
	sound.Volume = volume
	if sound.SoundId ~= "" and not sound.Playing then
		sound:Play()
	end
end

-- Overtime: no sight/range checks, just always know exactly where the
-- nearest alive player is and beeline for them at a much higher speed.
-- Still respects Thomas's wide-body restriction (see def.quirk == "wideBody"
-- below) and still falls back to PathfindingService (much more frequently)
-- when a wall blocks the direct line -- "godlevel pathfinding," not "walks
-- through walls."
function MonsterAI:_updateGodChase(now)
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

	if def.quirk ~= "wideBody" and self:_hasClearPath(nearestRoot.Position) then
		self.currentPath = nil
		local moved = (not self._lastCommandedPoint)
			or (self._lastCommandedPoint - nearestRoot.Position).Magnitude > 0.5
		if moved then
			self.humanoid:MoveTo(nearestRoot.Position)
			self._lastCommandedPoint = nearestRoot.Position
		end
	else
		local pathExhausted = not self.currentPath or not self.currentPath[self.pathIndex]
		if pathExhausted or now - self.lastPathTime > Config.Round.OvertimeRepathInterval then
			self.lastPathTime = now
			self:_moveAlongPath(self:_pathTo(nearestRoot.Position) or {})
		end
		self:_followCurrentPath(0)
	end
end

function MonsterAI:Update(dt)
	if self.paused or self.destroyed then
		return
	end

	local now = os.clock()
	if self.def.quirk == "lightsOut" then
		self:_updateLightsOut(now)
	end

	if self.god then
		self:_updateGodChase(now)
		return
	end

	local def = self.def

	if self.state ~= "Chase" then
		local seen = self:_scanForTargets()
		if seen then
			self.state = "Chase"
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
		if not root or not hum or hum.Health <= 0 then
			self.state = "Search"
			self.currentPath = nil
		else
			if self:_canSee(root) then
				self.lastSightTime = now
				self.lastKnownPos = root.Position
			elseif now - self.lastSightTime > def.loseSightTime then
				self.state = "Search"
				self.currentPath = nil
			end

			self.humanoid.WalkSpeed = self:_applyQuirkSpeed(def.chaseSpeed)

			-- Straight line available (and not rail-restricted): just walk
			-- directly at the player's live position. No waypoints, no
			-- PathfindingService, nothing to flip-flop between -- this is
			-- deliberately the simple case. Only fall back to pathfinding
			-- when a wall is actually blocking that direct route.
			if def.quirk ~= "wideBody" and self:_hasClearPath(root.Position) then
				self.currentPath = nil
				local moved = (not self._lastCommandedPoint)
					or (self._lastCommandedPoint - root.Position).Magnitude > 0.5
				if moved then
					self.humanoid:MoveTo(root.Position)
					self._lastCommandedPoint = root.Position
				end
			else
				local pathExhausted = not self.currentPath or not self.currentPath[self.pathIndex]
				if pathExhausted then
					-- No path in flight at all right now -- e.g. we just lost
					-- the direct line rounding a corner. Get one immediately;
					-- don't sit still waiting out the repath throttle below,
					-- which was causing a freeze right at the moments (corner
					-- transitions) where responsiveness matters most.
					self.lastPathTime = now
					self.lastChaseTargetPos = root.Position
					self:_moveAlongPath(self:_pathTo(root.Position) or {})
				elseif now - self.lastPathTime > def.repathInterval then
					-- Recomputing a brand new PathfindingService route every
					-- single interval -- even when the target has barely
					-- moved -- lets it flip-flop between two similarly-good
					-- routes through the maze's loops/shortcuts, which reads
					-- as indecisive/erratic. Only replace an in-flight route
					-- once the target has moved meaningfully.
					local targetMoved = (not self.lastChaseTargetPos)
						or (root.Position - self.lastChaseTargetPos).Magnitude > 8
					if targetMoved then
						self.lastPathTime = now
						self.lastChaseTargetPos = root.Position
						self:_moveAlongPath(self:_pathTo(root.Position) or {})
					end
				end
				self:_followCurrentPath(dt)
			end
			return
		end
	end

	if self.state == "Search" then
		self.humanoid.WalkSpeed = def.investigateSpeed
		self.searchUntil = self.searchUntil or (now + 4)
		self:_ensurePath(self.lastKnownPos or self:_randomPatrolTarget())
		local reachedEnd = self:_followCurrentPath(dt)
		if reachedEnd and (self.searchUntil and now > self.searchUntil) then
			self.state = "Patrol"
			self.searchUntil = nil
			self.currentPath = nil
		end
		return
	end

	if self.state == "Investigate" then
		self.humanoid.WalkSpeed = def.investigateSpeed
		self:_ensurePath(self.investigatePos)
		local reachedEnd = self:_followCurrentPath(dt)
		if reachedEnd then
			self.state = "Patrol"
			self.currentPath = nil
		end
		return
	end

	-- Patrol (default)
	self.humanoid.WalkSpeed = def.patrolSpeed
	self:_ensurePath(self:_randomPatrolTarget())
	local reachedEnd = self:_followCurrentPath(dt)
	if reachedEnd then
		self.currentPath = nil
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
	self.state = "Patrol"
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
