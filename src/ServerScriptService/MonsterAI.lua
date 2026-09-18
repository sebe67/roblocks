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
local ServerStorage = game:GetService("ServerStorage")
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

-- Max turning speed for _faceAndMove below -- see that function's comment
-- for why this whole movement model no longer needs an "arrival radius"
-- hack the way the old Humanoid:Move()-based one did.
local TURN_RATE = math.rad(300)

-- _updateChaseGrowlAudio's fade target/timing -- see that function.
local CHASE_GROWL_MAX_VOLUME = 0.7
local CHASE_GROWL_FADE_TIME = 1.5

-- _updateChaseProximityLaugh: how close (studs) the target needs to be
-- during Chase to trigger the evil laugh, and the gap between retriggers.
-- It's not a single one-shot per chase -- as long as the target stays
-- within CHASE_LAUGH_PROXIMITY, it keeps firing again every
-- CHASE_LAUGH_COOLDOWN seconds for as long as that stays true; the
-- cooldown only exists so it can't fire every single frame while
-- lingering close, not to cap it to once. Lowered from 8s so the repeat
-- actually reads as repeating instead of a single taunt.
local CHASE_LAUGH_PROXIMITY = 15
local CHASE_LAUGH_COOLDOWN = 4

-- EXPERIMENTAL -- Chase obstacle-awareness. Everything tagged with this
-- same "EXPERIMENTAL" word (these two constants, _hasClearLine,
-- _ensureChasePath, _followChasePath, _pathToChase, the chaseCurrentPath/
-- chasePathIndex/nextChasePathAttempt fields, and the branch inside
-- Update()'s Chase case that reads "if self:_hasClearLine(root)") is new
-- and easy to lift back out as one unit if it makes chasing feel worse --
-- see README's "Sight-based AI" section for the up-to-date status of this
-- experiment. None of it touches Patrol's own path system in any way
-- (separate fields, separate functions) -- reverting this only means
-- deleting the tagged pieces and restoring Chase's "else" branch to just
-- self:_faceAndMove(dt, root.Position - self.root.Position, speed, true)
-- unconditionally.
local CHASE_WAYPOINT_SPACING = 8 -- tighter than Patrol's 16 -- a stale route should lag a moving player less between replans
local CHASE_REPLAN_INTERVAL = 0.5 -- vs Patrol's 1s -- keeps the reroute from going too stale while chasing a moving target

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

-- Shared by both createRig paths below (placeholder block rig and a real
-- template model): the name tag and the temporary Patrol/Chase debug tag,
-- both billboarded above whatever "head" part we're given.
local function attachHudTags(head, def)
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

	return stateLabel
end

local function createPlaceholderRig(def)
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
	-- Anchored: movement is now fully driven by _faceAndMove setting
	-- root.CFrame directly every frame (see that function's comment) --
	-- there's no Humanoid:Move()/WalkSpeed physics involved anymore, so
	-- there's nothing left for gravity or collision response to apply to.
	-- Anchoring the HumanoidRootPart takes the WHOLE welded rig (head
	-- included) out of physics simulation entirely: no falling, no
	-- get-shoved-by-a-wall knockback, no possible source of momentum ever
	-- again. Touched still fires normally for Anchored parts, so catching
	-- (MonsterAI:_onTouch) is unaffected.
	root.Anchored = true
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

	local stateLabel = attachHudTags(head, def)

	CollectionService:AddTag(model, "Monster")

	return model, humanoid, root, stateLabel, nil
end

-- TEST path: clone a real model dropped in ServerStorage.MonsterModels
-- (see Config.lua's templateModel field and the README) instead of
-- building the blocky placeholder above. Returns nil (falls back to the
-- placeholder) if the template doesn't look usable, so a bad/incomplete
-- drop-in can never hard-crash monster spawning.
local function createRigFromTemplate(def, template)
	local model = template:Clone()
	model.Name = def.displayName

	-- FindFirstChild's second (recursive) argument covers a rig that's
	-- nested a level deeper than expected (a wrapper Model, an inner
	-- rig group, etc.) -- exactly how it was saved isn't something we
	-- control per drop-in file, so look anywhere in the model rather
	-- than assuming a flat, direct-children layout.
	local root = model:FindFirstChild("HumanoidRootPart", true)
	local humanoid
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("Humanoid") then
			humanoid = descendant
			break
		end
	end
	if not (root and root:IsA("BasePart") and humanoid) then
		warn(string.format("[MonsterAI] templateModel %q for %s is missing a HumanoidRootPart/Humanoid -- falling back to the placeholder rig.", def.templateModel, def.id))
		model:Destroy()
		return nil
	end
	model.PrimaryPart = root

	-- Movement is a direct root.CFrame set every frame (_faceAndMove) --
	-- same reasoning as the placeholder rig above: anchor the root to take
	-- the whole welded/jointed body out of physics simulation, since
	-- nothing here ever needs gravity or collision response.
	root.Anchored = true

	-- Unlike the placeholder (one big root part IS the whole visible body,
	-- so only it needs to collide), a real rig's HumanoidRootPart is
	-- normally a small part buried inside the model, nowhere near its
	-- full visible extent -- leaving every mesh part CanCollide=false
	-- would shrink the actual catchable hitbox down to that sliver.
	-- Collide on every part instead, same as a normal player rig; the
	-- Monsters-vs-Players collision group already strips out the physical
	-- push-back (see the placeholder rig's comment above), and Touched
	-- firing doesn't depend on CanCollide either way, so this only widens
	-- the hitbox without reintroducing the old shoving problem.
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CollisionGroup = "Monsters"
			part.CanCollide = true
		end
	end

	-- def.scale also sizes the placeholder rig from scratch (a small block
	-- times scale) AND feeds PathfindingService's agent radius
	-- (_pathTo/_pathToChase's computeNavmeshPath call) -- a real mesh is
	-- already sized on its own, unrelated to whatever def.scale happens to
	-- be tuned to for the placeholder, so an optional templateScale lets
	-- the VISUAL size be tuned independently without touching how much
	-- clearance this monster's pathfinding thinks it needs.
	local visualScale = def.templateScale or def.scale
	if visualScale and visualScale ~= 1 then
		local ok, err = pcall(function()
			model:ScaleTo(visualScale)
		end)
		if not ok then
			warn(string.format("[MonsterAI] templateModel %q failed to scale: %s", def.templateModel, tostring(err)))
		end
	end

	local head = model:FindFirstChild("Head", true) or model:FindFirstChild("Face", true) or root
	local stateLabel = attachHudTags(head, def)

	CollectionService:AddTag(model, "Monster")

	-- The placeholder rig only ever needed one Touched connection (its
	-- single big root part WAS the whole visible body). A real model's
	-- HumanoidRootPart is normally a small internal part, not the visible
	-- body extent, so relying on it alone here would make catching feel
	-- unreliable -- hand back every visible part so MonsterAI.new can
	-- connect Touched on each instead of just the root.
	local touchParts = {}
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			table.insert(touchParts, part)
		end
	end

	return model, humanoid, root, stateLabel, touchParts
end

local function createRig(def)
	if def.templateModel then
		local modelsFolder = ServerStorage:FindFirstChild("MonsterModels")
		local template = modelsFolder and modelsFolder:FindFirstChild(def.templateModel)
		if template then
			local model, humanoid, root, stateLabel, touchParts = createRigFromTemplate(def, template)
			if model then
				return model, humanoid, root, stateLabel, touchParts
			end
		else
			warn(string.format("[MonsterAI] %s has templateModel %q but ServerStorage.MonsterModels.%s doesn't exist -- falling back to the placeholder rig.", def.id, def.templateModel, def.templateModel))
		end
	end
	return createPlaceholderRig(def)
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
	-- EXPERIMENTAL (Chase obstacle-awareness) -- entirely separate from
	-- Patrol's currentPath/pathIndex/nextPathAttempt.
	self.chaseCurrentPath = nil
	self.chasePathIndex = nil
	self.nextChasePathAttempt = nil

	local touchParts
	self.model, self.humanoid, self.root, self.stateLabel, touchParts = createRig(def)
	self.model.Parent = workspace

	-- How far the root sits above the model's own lowest point, in
	-- studs -- used by TeleportTo below to actually ground the model
	-- instead of assuming every rig's root-to-feet distance is the same.
	-- The placeholder rig's root IS the whole visible body, so that used
	-- to be a safe-enough fixed guess (3 studs), but a real template rig's
	-- HumanoidRootPart can sit anywhere relative to its actual mesh (nose
	-- height, hip height, center of a train's boiler, whatever the
	-- original rig happened to use) -- computed once here, right after
	-- scaling, instead of assumed, so it holds for any rig. Rotation
	-- around yaw only (see _faceAndMove -- monsters never pitch or roll)
	-- means this vertical measurement stays valid for the model's whole
	-- lifetime, no matter which way it's currently facing.
	local boundingCFrame, boundingSize = self.model:GetBoundingBox()
	self.groundOffset = self.root.Position.Y - (boundingCFrame.Position.Y - boundingSize.Y / 2)

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
	-- Continuous growl/tension loop, silent while Patrolling and faded in
	-- while Chasing (see _updateChaseGrowlAudio) -- distinct from
	-- chaseSoundId (a one-shot stinger fired only at the exact instant
	-- Chase begins). One shared sound for every monster for now
	-- (Config.Sounds.ChaseGrowl), same reasoning as JumpscareScream's
	-- shared fallback -- cheaper to source and ship than 9 unique loops,
	-- and it's still genuinely positional/3D per monster since each one
	-- gets its own Sound instance on its own root.
	self.chaseGrowlSound = SoundKit.CreateLoop3D(self.root, Config.Sounds.ChaseGrowl, {
		Name = "ChaseGrowl",
		Volume = 0,
		MaxDistance = def.footstepMaxDistance or 60,
		SoundGroup = getMonsterSoundGroup(),
	})
	self.nextIdleSoundAt = os.clock() + math.random((def.idleSoundInterval or { 8, 16 })[1], (def.idleSoundInterval or { 8, 16 })[2])

	-- Placeholder rigs return no touchParts (nil) -- one Touched connection
	-- on the root, which IS the whole visible body, is enough. A real
	-- template model returns every visible BasePart instead (see
	-- createRigFromTemplate's comment on why the root alone isn't enough
	-- there).
	self.touchConns = {}
	for _, part in ipairs(touchParts or { self.root }) do
		table.insert(self.touchConns, part.Touched:Connect(function(hit)
			self:_onTouch(hit)
		end))
	end

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
		if state == "Chase" then
			self.stateLabel.Text = "CHASE"
			self.stateLabel.TextColor3 = Color3.fromRGB(255, 60, 60)
		else
			self.stateLabel.Text = "PATROL"
			self.stateLabel.TextColor3 = Color3.fromRGB(140, 220, 255)
		end
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
	if player:GetAttribute("Hidden") then
		-- Belt-and-braces: Update()'s Chase branch already drops a target
		-- the instant it goes Hidden, but Touched can fire from stale
		-- contact in the same frame HidingService moves them -- a Hidden
		-- player must never be catchable no matter how this fires.
		return
	end
	if os.clock() < (self.catchCooldown[player] or 0) then
		return
	end
	self.catchCooldown[player] = os.clock() + 2
	if catchHandler then
		-- self.model is handed along so the jumpscare can clone this
		-- exact monster's actual rig/mesh for its closeup shot instead of
		-- just knowing its id -- see PlayerService:CatchPlayer.
		catchHandler(player, self.def.id, self.model)
	end
	self:_setState("Patrol")
	self.target = nil
	self.chaseCurrentPath = nil
end

local function playersToCheck()
	local list = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("State") == "Alive" and player.Character then
			local hum = player.Character:FindFirstChildOfClass("Humanoid")
			local root = player.Character:FindFirstChild("HumanoidRootPart")
			if
				hum
				and root
				and hum.Health > 0
				and not player:GetAttribute("Invulnerable")
				and not player:GetAttribute("Hidden")
			then
				table.insert(list, { player = player, root = root })
			end
		end
	end
	return list
end

-- Shared by _canSee (below) and the EXPERIMENTAL _hasClearLine: a plain
-- raycast from this monster to targetRoot, excluding Floors/Ceiling and
-- this monster's own body (self.raycastExclude) and, critically, ignoring
-- a hit that's just part of the target's OWN body (a shoulder, an arm) --
-- an earlier obstacle-avoidance attempt didn't do that last exclusion and
-- misread the target's own limbs as a wall in the way. Returns true if
-- something real is actually blocking the line.
function MonsterAI:_rayBlocked(targetRoot, toTarget)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = self.raycastExclude
	local result = workspace:Raycast(self.root.Position, toTarget, params)
	return result ~= nil and not result.Instance:IsDescendantOf(targetRoot.Parent)
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
		-- Flattened on purpose: a monster's facing (_faceAndMove) is
		-- always exactly horizontal, it never tilts up or down, so
		-- judging the cone against the FULL 3D direction penalized pure
		-- altitude the same as it would an actual behind-you offset --
		-- hovering well above a monster could push the angle past
		-- sightAngle even standing right over it. Height genuinely
		-- doesn't affect whether you're in a level gaze's cone.
		local flatDir = Vector3.new(toTarget.X, 0, toTarget.Z)
		if flatDir.Magnitude > 0.01 then
			local look = self.root.CFrame.LookVector
			local angle = math.deg(math.acos(math.clamp(look:Dot(flatDir.Unit), -1, 1)))
			if angle > def.sightAngle then
				return false
			end
		end
	end

	return not self:_rayBlocked(targetRoot, toTarget)
end

-- EXPERIMENTAL (Chase obstacle-awareness, see the constants near the top
-- of this file) -- unlike _canSee, this has no FOV cone or sight range:
-- it only answers "is the straight line to the player physically blocked
-- right now," which is all Chase needs to decide whether to beeline or
-- fall back to a pathfound route.
function MonsterAI:_hasClearLine(targetRoot)
	return not self:_rayBlocked(targetRoot, targetRoot.Position - self.root.Position)
end

-- Same idea as _hasClearLine, but for a bare Vector3 (an alert/noise
-- position, not a player's own root part) -- used by investigate movement
-- below. No target body to exclude from the raycast since there isn't a
-- real target instance, so this is a plain "does anything real block this
-- line" check.
function MonsterAI:_hasClearLineToPoint(point)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = self.raycastExclude
	return workspace:Raycast(self.root.Position, point - self.root.Position, params) == nil
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
	-- How many cells out the scan needs to reach to guarantee covering a
	-- circle of this radius, regardless of exactly where within his own
	-- cell he's standing -- was hardcoded to 1 (a fixed 3x3) back when
	-- LightsOutRadius (20) comfortably fit inside one cellSize (22); now
	-- that it's bigger than a cell, a fixed 3x3 could miss fixtures near
	-- the edge of range.
	local cellReach = math.ceil(radius / cellSize)

	self.litFixtures = self.litFixtures or {}
	self.pendingRelease = self.pendingRelease or {}
	local stillNear = {}

	for dx = -cellReach, cellReach do
		for dy = -cellReach, cellReach do
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
	-- Force an immediate re-evaluation (beeline check first) toward the new
	-- position instead of continuing whatever investigate route was mid-
	-- flight toward the previous one -- see the Patrol branch of Update()
	-- for why investigate movement uses these Chase fields, not Patrol's
	-- own currentPath/_ensurePath.
	self.chaseCurrentPath = nil
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

-- Sprinting is loud: unlike BroadcastNoise's single shared radius (a
-- minigame station, a ground-pound thud), each monster hears it at its own
-- def.hearingRadius -- previously a dead, unused field left over from
-- before the Patrol/Chase restructuring, now finally read here. Still just
-- an alert, not a sight check: a monster this close turns to walk toward
-- you (see ReceiveAlert), and only actually enters Chase if that turn
-- brings you into its FOV/range/raycast -- exactly how "sprint past a
-- monster's blind side and it turns to spot you" should work without
-- teleporting knowledge of your position into it.
function MonsterAI.BroadcastSprintNoise(position)
	for _, monster in ipairs(registry) do
		if not monster.paused and not monster.destroyed then
			local radius = monster.def.hearingRadius or 20
			local d = (monster.root.Position - position).Magnitude
			if d <= radius then
				monster:ReceiveAlert(position)
			end
		end
	end
end

-- Polls every currently-detectable player's actual ground speed and
-- broadcasts sprint noise for anyone moving at/near SprintSpeed.
--
-- Deliberately does NOT read Humanoid.WalkSpeed: that property is set by
-- SprintController.lua from a LocalScript, and a client changing a
-- property on an Instance only ever affects what that one client sees --
-- it does not replicate back to the server (or to other clients), so the
-- server's own copy of WalkSpeed just sits at whatever value PlayerService
-- last set it to server-side and never reflects the client's sprint
-- override at all. This is exactly why sprint noise wasn't firing
-- reliably. What DOES genuinely replicate to the server is the actual
-- physics: the local player's character has network ownership of its own
-- HumanoidRootPart, so AssemblyLinearVelocity correctly reflects real
-- movement speed -- same technique ViewBobController.lua already uses
-- client-side for its own speed-based amplitude.
--
-- Reuses playersToCheck() so this respects exactly the same population
-- sight checks already do (Alive, not Invulnerable, not Hidden) -- a
-- shielded respawn or a player tucked in a wardrobe shouldn't give away
-- their position by "sprinting" either. Call once at server boot; safe to
-- leave running always, since paused monsters and non-Alive players both
-- no-op out on their own (same as StoreTheme's blackout/flicker loops).
local SPRINT_NOISE_SPEED_MARGIN = 2 -- studs/sec of slack below SprintSpeed, for physics/network jitter
function MonsterAI.StartSprintNoiseLoop()
	task.spawn(function()
		while true do
			task.wait(Config.Player.SprintNoiseCheckInterval)
			for _, entry in ipairs(playersToCheck()) do
				local velocity = entry.root.AssemblyLinearVelocity
				local speed = Vector2.new(velocity.X, velocity.Z).Magnitude
				if speed >= Config.Player.SprintSpeed - SPRINT_NOISE_SPEED_MARGIN then
					MonsterAI.BroadcastSprintNoise(entry.root.Position)
				end
			end
		end
	end)
end

-- waypointSpacing defaults to 16 (Patrol's value) when omitted -- the
-- EXPERIMENTAL Chase obstacle-awareness path (_pathToChase) passes
-- CHASE_WAYPOINT_SPACING (8) instead; Patrol's own calls (_pathTo) are
-- unchanged.
local function computeNavmeshPath(fromPos, toPos, agentRadius, agentScale, waypointSpacing)
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
		WaypointSpacing = waypointSpacing or 16,
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
-- "arrive" anywhere. Moves with _faceAndMove, same as every other kind of
-- movement in this file.
function MonsterAI:_followCurrentPath(dt, speed)
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
	self:_faceAndMove(dt, targetPoint - self.root.Position, speed, true)
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

-- EXPERIMENTAL (Chase obstacle-awareness) -- everything below through
-- _followChasePath mirrors _pathTo/_ensurePath/_followCurrentPath above,
-- but through entirely separate fields (chaseCurrentPath/chasePathIndex/
-- nextChasePathAttempt) so Patrol's own path bookkeeping is never touched
-- by anything here.
function MonsterAI:_pathToChase(destination)
	return computeNavmeshPath(self.root.Position, destination, self.def.pathAgentRadius or 2, self.def.scale, CHASE_WAYPOINT_SPACING)
end

-- Unlike Patrol's _ensurePath (which only ever requests a fresh path once
-- the current one is exhausted), this replans on a timer
-- (CHASE_REPLAN_INTERVAL) even while a path is still mid-progress -- the
-- destination is the player's live position, which keeps moving, so
-- walking an old route all the way to its end could mean walking all the
-- way to where they used to be before ever getting a fresh read on where
-- they actually are now.
function MonsterAI:_ensureChasePath(destination)
	local now = os.clock()
	local havePath = self.chaseCurrentPath and #self.chaseCurrentPath > 0
	if havePath and self.nextChasePathAttempt and now < self.nextChasePathAttempt then
		return
	end
	self.nextChasePathAttempt = now + CHASE_REPLAN_INTERVAL
	self.chaseCurrentPath = self:_pathToChase(destination) or {}
	self.chasePathIndex = 1
end

function MonsterAI:_followChasePath(dt, speed)
	if not self.chaseCurrentPath or not self.chaseCurrentPath[self.chasePathIndex] then
		return true
	end
	local targetPoint = self.chaseCurrentPath[self.chasePathIndex]
	local flatDist = (Vector3.new(targetPoint.X, 0, targetPoint.Z) - Vector3.new(self.root.Position.X, 0, self.root.Position.Z)).Magnitude
	if flatDist < 3 then
		self.chasePathIndex += 1
		if not self.chaseCurrentPath[self.chasePathIndex] then
			return true
		end
		targetPoint = self.chaseCurrentPath[self.chasePathIndex]
	end
	self:_faceAndMove(dt, targetPoint - self.root.Position, speed, true)
	return false
end

-- How far (in studs) a groundPound burst's thud reaches other monsters --
-- see _applyQuirkSpeed's "groundPound" branch.
local GROUND_POUND_NOISE_RADIUS = 45

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
	elseif def.quirk == "groundPound" and self.state == "Chase" then
		if math.random() < 0.015 then
			self.burstUntil = os.clock() + 0.8
			-- The burst is loud enough to be its own noise event, same as a
			-- minigame station running -- pulls in whichever other
			-- monsters happen to be nearby, on top of speeding him up.
			MonsterAI.BroadcastNoise(self.root.Position, GROUND_POUND_NOISE_RADIUS)
		end
	end
	if self.burstUntil and os.clock() < self.burstUntil then
		return baseSpeed * 1.5
	end
	return baseSpeed
end

-- Rotates a flat (Y=0) unit vector currentDir toward desiredDir by at most
-- maxRadians, and returns the result -- never further, never all at once.
-- Pure math, no physics: given the same two directions and the same
-- maxRadians, this always returns the same answer, with no memory of
-- velocity or where either monster was a frame ago.
local function rotateTowards(currentDir, desiredDir, maxRadians)
	desiredDir = Vector3.new(desiredDir.X, 0, desiredDir.Z)
	if desiredDir.Magnitude < 0.01 then
		return currentDir
	end
	desiredDir = desiredDir.Unit
	if currentDir.Magnitude < 0.01 then
		return desiredDir
	end
	currentDir = currentDir.Unit
	local angle = math.acos(math.clamp(currentDir:Dot(desiredDir), -1, 1))
	if angle <= maxRadians then
		return desiredDir
	end
	local blended = CFrame.lookAt(Vector3.new(), currentDir):Lerp(CFrame.lookAt(Vector3.new(), desiredDir), maxRadians / angle)
	return blended.LookVector
end

-- The ONE movement primitive for every monster in every state, replacing
-- the old Humanoid:Move()-based _steerToward. At your request, this has no
-- momentum of any kind: it doesn't touch Humanoid or physics velocity at
-- all (the root is Anchored -- see createRig), it just (1) turns
-- self.facing toward desiredDir by at most TURN_RATE * dt radians this
-- frame, then (2) if moveForward is true, sets root.CFrame to the current
-- position plus self.facing * speed * dt, facing that same direction.
-- Position next frame is ALWAYS last position + this frame's facing * this
-- frame's dt -- nothing carries over except the facing direction itself,
-- which is exactly the "a direction to face in, and a move forward
-- function, but they don't always have to be moving forward" you asked
-- for. Since there's no velocity to carry through a sudden change in
-- bearing, there's nothing left that CAN spiral into an orbit the way the
-- old momentum-carrying physics body did when it overshot a target and had
-- to fight its own existing motion to correct -- the worst case now is
-- just turning in place for a frame or two, never curling off course.
-- Since the root is Anchored and every move is a direct CFrame set (see
-- the comment above), nothing here ever gets stopped by Roblox's own
-- collision response the way a real physics body would -- a monster can
-- walk its center point straight through a solid wall and nothing will
-- object. _hasClearLine (used to decide beeline-vs-pathfind in Chase)
-- doesn't fully guard against this either: it's a single long ray to the
-- player, and grazing a corner or a seam gap can read "clear" for one
-- frame even when the wall between here and there is real -- and once
-- the monster's origin is even slightly past that wall, later frames'
-- rays start on the far side and never see it as an obstacle again. This
-- checks only the short step this one frame is about to take (a few
-- studs, not the tens of studs to the player), which a stray grazing hit
-- can't fool the same way, and just refuses to advance into the wall it
-- finds -- the monster keeps turning and will route around on a later
-- frame (path replan, or the line clearing once it's turned). It's a
-- single ray through the monster's own center, on purpose: a doorway
-- narrower than the monster's model can still get walked through with
-- some visible side-clipping, which is fine -- only a step whose CENTER
-- is blocked (i.e. an actual wall, not just a tight-but-passable gap)
-- gets refused.
--
-- ONLY applied to beeline movement (_faceAndMove's enforceWallClip
-- parameter, see below) -- the two places a monster walks a straight
-- line to a live target's current position with no vetted route behind
-- it (normal Chase and godmode both beeline when _hasClearLine is true).
-- It's deliberately NOT applied to path-following (Patrol's own route,
-- or either state's pathfound fallback): those already walk a route
-- PathfindingService computed to avoid solid geometry, and turned out to
-- be exactly the case where this backstop caused a NEW problem instead
-- of fixing one -- a Patrol waypoint sending a monster through one of
-- this game's deliberately-narrow doorways at a slight angle could clip
-- the door frame on this single-center-ray check and simply refuse to
-- advance, with nothing to make it back off and re-approach differently,
-- reading as a monster that just stopped moving entirely.
function MonsterAI:_stepBlocked(step)
	if step.Magnitude < 0.001 then
		return false
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = self.raycastExclude
	return workspace:Raycast(self.root.Position, step, params) ~= nil
end

function MonsterAI:_faceAndMove(dt, desiredDir, speed, moveForward, enforceWallClip)
	local currentFacing = self.facing or Vector3.new(self.root.CFrame.LookVector.X, 0, self.root.CFrame.LookVector.Z)
	self.facing = rotateTowards(currentFacing, desiredDir, TURN_RATE * dt)

	local position = self.root.Position
	if moveForward then
		local step = self.facing * speed * dt
		if not (enforceWallClip and self:_stepBlocked(step)) then
			position = position + step
		end
	end
	self.root.CFrame = CFrame.lookAt(position, position + self.facing)
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

-- Fades the growl loop in over CHASE_GROWL_FADE_TIME seconds when Chase
-- starts and back out over the same span when it ends, rather than an
-- abrupt cut/snap-in -- a smooth ramp reads as "closing in"/"backing off"
-- instead of a jarring toggle.
function MonsterAI:_updateChaseGrowlAudio(dt)
	local sound = self.chaseGrowlSound
	if not sound or sound.SoundId == "" then
		return
	end
	local target = (self.state == "Chase") and CHASE_GROWL_MAX_VOLUME or 0
	local step = (CHASE_GROWL_MAX_VOLUME / CHASE_GROWL_FADE_TIME) * dt
	if sound.Volume < target then
		sound.Volume = math.min(target, sound.Volume + step)
	elseif sound.Volume > target then
		sound.Volume = math.max(target, sound.Volume - step)
	end
	if sound.Volume > 0 and not sound.Playing then
		sound:Play()
	elseif sound.Volume <= 0 and sound.Playing then
		sound:Stop()
	end
end

-- def.idleSoundId falls back to the shared Config.Sounds.EvilLaugh
-- whenever a monster doesn't have its own (currently every monster) --
-- same pattern as JumpscareScream/ChaseGrowl. Used both by the existing
-- random Patrol tell and the proximity laugh below.
function MonsterAI:_resolveIdleSoundId()
	local def = self.def
	return def.idleSoundId ~= "" and def.idleSoundId or Config.Sounds.EvilLaugh
end

-- Repeats for as long as it stays true, not a single one-shot per
-- chase: while actually Chasing (not just Patrolling with a noise
-- alert), if the target is within CHASE_LAUGH_PROXIMITY, play the same
-- evil-laugh sound the random Patrol tell uses -- then it can fire
-- again the moment CHASE_LAUGH_COOLDOWN clears, and again after that,
-- for as long as the target stays that close. The cooldown only exists
-- so it can't fire every single frame while lingering inside range.
function MonsterAI:_updateChaseProximityLaugh(targetRoot)
	local laughId = self:_resolveIdleSoundId()
	if laughId == "" then
		return
	end
	local now = os.clock()
	if self.nextChaseLaughAt and now < self.nextChaseLaughAt then
		return
	end
	local dist = (targetRoot.Position - self.root.Position).Magnitude
	if dist <= CHASE_LAUGH_PROXIMITY then
		SoundKit.PlayAt(self.root, laughId, { Volume = 0.8, MaxDistance = 60, SoundGroup = getMonsterSoundGroup() })
		self.nextChaseLaughAt = now + CHASE_LAUGH_COOLDOWN
	end
end

-- Overtime: no sight/range checks, just always know exactly where the
-- nearest alive player is and head straight for them at a much higher
-- speed. Wall-restricted like everything else, though -- _faceAndMove's
-- per-frame wall-clip backstop applies here same as Patrol/Chase, so this
-- reuses the same clear-line-or-pathfind pattern as the EXPERIMENTAL Chase
-- branch below (_hasClearLine/_ensureChasePath/_followChasePath, the same
-- chaseCurrentPath/chasePathIndex/nextChasePathAttempt fields -- safe to
-- share since Update() returns before ever touching Chase's branch while
-- self.god is true, so nothing else is using them at the same time).
function MonsterAI:_updateGodChase(dt)
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
	self:_updateFootstepAudio()
	self:_updateChaseGrowlAudio(dt)
	self:_updateChaseProximityLaugh(nearestRoot)
	self.currentPath = nil
	local speed = def.chaseSpeed * Config.Round.OvertimeSpeedMultiplier
	if self:_hasClearLine(nearestRoot) then
		self.chaseCurrentPath = nil
		self:_faceAndMove(dt, nearestRoot.Position - self.root.Position, speed, true, true)
	else
		self:_ensureChasePath(nearestRoot.Position)
		local reachedEnd = self:_followChasePath(dt, speed)
		if reachedEnd then
			self.chaseCurrentPath = nil
		end
	end
end

-- Exactly two states, Patrol and Chase, and they can't interfere with each
-- other: Chase is entered ONLY by directly seeing a player (never by
-- noise/proximity alone) and exited ONLY by CHASE_GIVEUP_TIME passing with
-- no sight of that player, full stop -- nothing else can knock a monster
-- out of one state and into a muddled third condition.
--
-- Chase beelines straight at the player's live position (_faceAndMove)
-- when the line between here and there is clear, falling back to a
-- pathfound route when it isn't -- see the EXPERIMENTAL Chase
-- obstacle-awareness section near the top of this file for the full
-- writeup. CHASE_GIVEUP_TIME and TURN_RATE are declared near the top of
-- this file (both _updateGodChase above and Update below need them).

function MonsterAI:Update(dt)
	if self.paused or self.destroyed then
		return
	end

	local now = os.clock()

	if self.god then
		self:_updateGodChase(dt)
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
				SoundKit.PlayAt(self.root, self:_resolveIdleSoundId(), { Volume = 0.8, MaxDistance = 70, SoundGroup = getMonsterSoundGroup() })
			end
		end
	end

	self:_updateFootstepAudio()
	self:_updateChaseGrowlAudio(dt)

	if self.state == "Chase" then
		local root = self.target and self.target:FindFirstChild("HumanoidRootPart")
		local hum = self.target and self.target:FindFirstChildOfClass("Humanoid")
		local targetPlayer = self.target and Players:GetPlayerFromCharacter(self.target)
		local targetHidden = targetPlayer and targetPlayer:GetAttribute("Hidden")
		if root and hum and hum.Health > 0 and not targetHidden then
			self:_updateChaseProximityLaugh(root)
			if self:_canSee(root) then
				self.lastSightTime = now
			end

			-- Retarget mid-chase to a strictly closer player we can
			-- actually see right now -- same sight rules _scanForTargets
			-- uses to enter Chase in the first place -- so a monster
			-- already chasing someone far away doesn't tunnel-vision past
			-- a second player who runs right in front of it.
			local currentDist = (root.Position - self.root.Position).Magnitude
			local closer, closerDist
			for _, entry in ipairs(playersToCheck()) do
				if entry.player.Character ~= self.target then
					local d = (entry.root.Position - self.root.Position).Magnitude
					if d < currentDist and (not closerDist or d < closerDist) and self:_canSee(entry.root) then
						closer = entry
						closerDist = d
					end
				end
			end
			if closer then
				self.target = closer.player.Character
				root = closer.root
				hum = closer.player.Character:FindFirstChildOfClass("Humanoid")
				self.lastSightTime = now
				self.chaseCurrentPath = nil
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
				self.chaseCurrentPath = nil
			else
				self.currentPath = nil
				local speed = self:_applyQuirkSpeed(def.chaseSpeed)
				-- EXPERIMENTAL: beeline when the direct line is clear
				-- (unchanged fast path, no pathfinding overhead most of
				-- the time); fall back to a pathfound route only while
				-- something's actually in the way. See the constants near
				-- the top of this file for how to remove this cleanly.
				if self:_hasClearLine(root) then
					self.chaseCurrentPath = nil
					self:_faceAndMove(dt, root.Position - self.root.Position, speed, true, true)
				else
					self:_ensureChasePath(root.Position)
					local reachedEnd = self:_followChasePath(dt, speed)
					if reachedEnd then
						self.chaseCurrentPath = nil
					end
				end
			end
		else
			-- Target is gone/dead OR just went Hidden (a wardrobe) -- give
			-- up immediately in both cases, no CHASE_GIVEUP_TIME grace.
			-- Hidden in particular must drop the beeline target THIS frame:
			-- otherwise the monster keeps walking straight at their now
			-- Hidden root position (inside the wardrobe) for up to
			-- CHASE_GIVEUP_TIME seconds and can walk right into it.
			self:_setState("Patrol")
			self.target = nil
			self.currentPath = nil
			self.chaseCurrentPath = nil
		end
		return
	end

	-- Patrol (the only other state). A noise alert (ReceiveAlert -- a
	-- minigame station running, Dora's callout, a sprinting player) just
	-- swaps in a specific destination here for a while instead of a random
	-- one; it never becomes a different state.
	--
	-- An active investigate destination deliberately does NOT go through
	-- the random-wander path below (_ensurePath/_followCurrentPath): that
	-- system only ever repaths once currentPath is fully empty, plus a
	-- 1-second retry throttle -- both tuned for "occasionally retry an
	-- unreachable random cell," not for reacting to something that can
	-- update every half-second (a sprinting player). Those two limits
	-- combined could leave a freshly-alerted monster simply standing still
	-- for up to a second at a time instead of visibly reacting -- which is
	-- exactly what "the sprint noise doesn't seem to work well" turned out
	-- to be. Investigate instead reuses Chase's beeline-or-pathfind
	-- machinery (_hasClearLineToPoint/_ensureChasePath/_followChasePath,
	-- 0.5s replan) -- safe to share since Patrol/investigate and Chase are
	-- never active at the same time, same reasoning godmode's reuse of
	-- these same fields already relies on.
	if self.investigatePos and now < (self.investigateUntil or 0) then
		local reachedEnd
		if self:_hasClearLineToPoint(self.investigatePos) then
			-- Arrived (within the same 3-stud "close enough" every other
			-- waypoint/destination check in this file uses) -- stop
			-- investigating rather than idling at the noise's last known
			-- spot for the rest of the 6-second window.
			if (self.investigatePos - self.root.Position).Magnitude < 3 then
				reachedEnd = true
			else
				self.chaseCurrentPath = nil
				self:_faceAndMove(dt, self.investigatePos - self.root.Position, def.patrolSpeed, true, true)
			end
		else
			self:_ensureChasePath(self.investigatePos)
			reachedEnd = self:_followChasePath(dt, def.patrolSpeed)
		end
		if reachedEnd then
			self.investigatePos = nil
			self.chaseCurrentPath = nil
		end
	else
		self.investigatePos = nil
		local destination = self:_randomPatrolTarget()
		self:_ensurePath(destination)
		-- If PathfindingService couldn't find a route (bad luck on the
		-- random cell, or a genuinely unreachable one), currentPath is
		-- empty and _followCurrentPath returns true immediately without
		-- calling _faceAndMove at all -- the monster just doesn't move
		-- this frame rather than facing/walking into nothing, and
		-- _ensurePath's 1-second retry throttle tries a fresh destination
		-- shortly after. This is the "they don't always have to be moving
		-- forward" case.
		local reachedEnd = self:_followCurrentPath(dt, def.patrolSpeed)
		if reachedEnd then
			self.currentPath = nil
		end
	end

	-- Occasional audio tell (SpongeBob's giggle, George's chatter, etc).
	-- Dora's idleSoundId is reserved for her callout line, not this roll.
	if def.quirk ~= "callout" and now > self.nextIdleSoundAt then
		SoundKit.PlayAt(self.root, self:_resolveIdleSoundId(), { Volume = 0.6, MaxDistance = 40, SoundGroup = getMonsterSoundGroup() })
		local interval = def.idleSoundInterval or { 8, 16 }
		self.nextIdleSoundAt = now + math.random(interval[1], interval[2])
	end
end

function MonsterAI:TeleportTo(position)
	self.model:PivotTo(CFrame.new(position + Vector3.new(0, self.groundOffset, 0)))
	self.currentPath = nil
	self.chaseCurrentPath = nil
	self:_setState("Patrol")
	self.target = nil
end

function MonsterAI:SetPaused(paused)
	self.paused = paused
	if paused then
		-- Nothing to cancel anymore: Update() (the only thing that ever
		-- moves this monster) already bails out immediately while paused,
		-- and there's no Humanoid:Move()/MoveTo command left in flight to
		-- stop the way the old physics-driven movement needed.
		if self.footstepSound then
			self.footstepSound:Stop()
		end
		if self.chaseGrowlSound then
			self.chaseGrowlSound.Volume = 0
			self.chaseGrowlSound:Stop()
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
	for _, conn in ipairs(self.touchConns or {}) do
		conn:Disconnect()
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
