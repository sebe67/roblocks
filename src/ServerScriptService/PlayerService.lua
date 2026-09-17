-- Owns per-player round state (Lobby/Alive/Caught/Dead/Spectating/Escaped/
-- TimedOut), the jumpscare-on-catch flow, and respawn/spectate requests.
-- GameState drives the round; this module just reacts to it and to
-- MonsterAI/ExitService callbacks wired up in Main.server.lua.

local Players = game:GetService("Players")
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
local Net = require(game:GetService("ReplicatedStorage").Shared.Net)

local PlayerService = {}
PlayerService.__index = PlayerService

function PlayerService.new(maze)
	local self = setmetatable({}, PlayerService)
	self.maze = maze
	self.roundActive = false
	self.onStateChanged = nil -- set by GameState
	self._hiddenStash = {}
	self._noclipStash = {}
	self._flightConns = {}

	self.jumpscareEvent = Net.GetEvent("Jumpscare")
	self.deathMenuEvent = Net.GetEvent("ShowDeathMenu")
	self.respawnEvent = Net.GetEvent("RequestRespawn")
	self.spectateEvent = Net.GetEvent("RequestSpectate")
	self.escapedEvent = Net.GetEvent("PlayerEscaped")
	self.spawnEvent = Net.GetEvent("RoundSpawn")
	self.flashlightEvent = Net.GetEvent("ToggleFlashlight")
	self.flashlightPitchEvent = Net.GetEvent("ReportFlashlightPitch")

	self.respawnEvent.OnServerEvent:Connect(function(player)
		self:_handleRespawnRequest(player)
	end)
	self.spectateEvent.OnServerEvent:Connect(function(player)
		self:_handleSpectateRequest(player)
	end)
	-- Toggled server-side (not by the client directly setting the
	-- property) so the SpotLight's Enabled state is authoritative and
	-- reliably replicates to every other client watching, not just its
	-- owner.
	self.flashlightEvent.OnServerEvent:Connect(function(player)
		self:_toggleFlashlight(player)
	end)
	-- The Head's own orientation only ever turns with the character's
	-- facing (yaw) -- Roblox never tilts it with camera pitch -- so a
	-- SpotLight parented straight to Head could only ever aim level,
	-- which is the "only tracks x/z, not up/down" report. The client
	-- reports its camera pitch periodically (throttled, see
	-- FlashlightController.lua) and the server applies it to the
	-- FlashlightAim Motor6D below, clamped to Config.Flashlight.MaxPitch.
	self.flashlightPitchEvent.OnServerEvent:Connect(function(player, pitch)
		self:_applyFlashlightPitch(player, pitch)
	end)

	Players.PlayerAdded:Connect(function(player)
		player:SetAttribute("State", "Lobby")
		player.CharacterAdded:Connect(function(character)
			self:_onCharacterAdded(player, character)
		end)
		if player.Character then
			self:_onCharacterAdded(player, player.Character)
		end
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		player:SetAttribute("State", "Lobby")
		player.CharacterAdded:Connect(function(character)
			self:_onCharacterAdded(player, character)
		end)
		if player.Character then
			self:_onCharacterAdded(player, player.Character)
		end
	end

	return self
end

function PlayerService:_onCharacterAdded(player, character)
	local humanoid = character:WaitForChild("Humanoid")
	humanoid.WalkSpeed = Config.Player.WalkSpeed
	humanoid.Died:Connect(function()
		if player:GetAttribute("State") == "Alive" then
			self:MarkDead(player, nil)
		end
	end)

	-- Monsters never physically collide with players (see the collision
	-- group setup in Main.server.lua) -- only the catch's Touched event
	-- matters, not a physical block. Applied to every part (existing and
	-- any added later, e.g. accessories) so nothing on the character slips
	-- back into the default collidable group.
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CollisionGroup = "Players"
		end
	end
	character.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = "Players"
		end
	end)

	-- A real SpotLight (Face = Front), off by default, toggled by
	-- _toggleFlashlight -- a brand new one every respawn, so it never
	-- carries an "on" state across characters. It lives on a small
	-- dedicated "FlashlightAim" part rather than directly on Head: Head's
	-- own CFrame only ever turns with the character's yaw (left/right),
	-- never with camera pitch (up/down), so a light parented straight to
	-- it could only ever aim level. FlashlightAim is welded to Head with
	-- a Motor6D so it inherits that same yaw automatically, and
	-- _applyFlashlightPitch tilts it up/down on top of that by rewriting
	-- the Motor6D's C0 each time the owning client reports a new camera
	-- pitch -- Motor6D is a live constraint (Part1's CFrame is
	-- continuously re-derived from Part0.CFrame * C0), not a one-time
	-- weld, so this keeps working every frame without a server loop.
	local head = character:WaitForChild("Head")

	local aimPart = Instance.new("Part")
	aimPart.Name = "FlashlightAim"
	aimPart.Size = Vector3.new(0.2, 0.2, 0.2)
	aimPart.Transparency = 1
	aimPart.CanCollide = false
	aimPart.CanQuery = false
	aimPart.Massless = true
	aimPart.CFrame = head.CFrame
	aimPart.Parent = character

	local motor = Instance.new("Motor6D")
	motor.Name = "FlashlightAimMotor"
	motor.Part0 = head
	motor.Part1 = aimPart
	motor.C0 = CFrame.new()
	motor.Parent = head

	local light = Instance.new("SpotLight")
	light.Name = "Flashlight"
	light.Face = Enum.NormalId.Front
	light.Range = Config.Flashlight.Range
	light.Angle = Config.Flashlight.Angle
	light.Brightness = Config.Flashlight.Brightness
	light.Color = Config.Flashlight.Color
	light.Enabled = false
	light.Parent = aimPart
end

function PlayerService:_applyFlashlightPitch(player, pitch)
	if type(pitch) ~= "number" or pitch ~= pitch then -- NaN guard
		return
	end
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	local motor = head and head:FindFirstChild("FlashlightAimMotor")
	if not motor then
		return
	end
	local maxPitch = math.rad(Config.Flashlight.MaxPitch)
	local clamped = math.clamp(pitch, -maxPitch, maxPitch)
	motor.C0 = CFrame.Angles(clamped, 0, 0)
end

function PlayerService:_toggleFlashlight(player)
	if player:GetAttribute("State") ~= "Alive" then
		return
	end
	local character = player.Character
	local aimPart = character and character:FindFirstChild("FlashlightAim")
	local light = aimPart and aimPart:FindFirstChild("Flashlight")
	if light then
		light.Enabled = not light.Enabled
	end
end

-- /spectate, /spectate2, and /back (Main.server.lua debug commands): a
-- free-fly noclip mode for testing, distinct from the death-flow
-- "Spectating" State above -- that one locks your camera onto another
-- alive player, this one lets your own character fly through walls. Both
-- commands share the exact same invisible/intangible setup
-- (CanCollide=false/Transparency=1 on every part, same stash-and-restore
-- shape as _hideCharacter) via _beginFlight, but END UP WITH DIFFERENT
-- ROOT PHYSICS, because they have opposite requirements for whether the
-- server needs to know your real position:
--   /spectate  (EnableNoclip)      -- Invulnerable=true, so MonsterAI's
--                                     playersToCheck() filters you out
--                                     before any sight/catch check runs.
--                                     Fully invisible to monster AI, so it
--                                     genuinely does not matter whether
--                                     the server ever learns your real
--                                     position -- Anchored is fine (and
--                                     is what actually fixed this mode's
--                                     glitchiness, see below).
--   /spectate2 (EnableTestSpectate) -- Invulnerable stays false: the
--                                     entire point is for monsters to
--                                     genuinely detect and chase you, so
--                                     the server MUST know your real
--                                     position. Anchored breaks exactly
--                                     that: an Anchored part has no
--                                     network ownership, so
--                                     NoclipController.lua's client-side
--                                     root.CFrame writes never replicate
--                                     to the server at all -- you see
--                                     yourself fly on your own screen,
--                                     but the server's copy of your root
--                                     never moves. That's precisely why
--                                     hovering right in front of a
--                                     monster still measured ~160 studs
--                                     server-side: only the monster's own
--                                     patrol was moving; you, as far as
--                                     the server knew, weren't.
--
-- The first version of both drove flight by setting AssemblyLinearVelocity
-- every frame with humanoid.PlatformStand = true, and it was glitchy and
-- still didn't reliably pass through walls. Root cause: PlatformStand
-- doesn't just suspend walk control, it ragdolls the rig (every limb's
-- joint goes loose), and our velocity writes to only the root were
-- fighting that ragdoll physics. Anchoring fixed /spectate outright (no
-- gravity, no ragdoll, no collision response possible, nothing to fight
-- -- exactly the same fix as the monster movement rebuild,
-- MonsterAI.lua's _faceAndMove) -- but for /spectate2 specifically, we
-- need the rig to stay a normal, network-owned physics object (so this
-- client's CFrame writes keep replicating like ordinary movement always
-- has) while STILL not fighting the Humanoid's own ground controller.
-- Humanoid:ChangeState(Physics) is the correct tool for exactly that: it
-- hands ground control to a script/physics without the PlatformStand
-- ragdoll side effect -- it's the same technique behind vehicle seats and
-- other script-driven humanoids.
function PlayerService:_beginFlight(player, invulnerable, untouchable)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not humanoid or not root then
		return false
	end
	if self._noclipStash[player] then
		return true
	end

	local stash = {}
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			stash[part] = { Transparency = part.Transparency, CanCollide = part.CanCollide, CanQuery = part.CanQuery }
			part.CanCollide = false
			part.CanQuery = false
			part.Transparency = 1
		end
	end
	self._noclipStash[player] = stash

	humanoid.PlatformStand = false
	if untouchable then
		root.Anchored = false
		humanoid:ChangeState(Enum.HumanoidStateType.Physics)
		-- Humanoid:ChangeState only sets the state NOW -- it doesn't lock
		-- it there. Roblox's humanoid state machine can silently revert
		-- away on its own (its own ground/Freefall detection kicking back
		-- in once it notices there's no floor under an unanchored,
		-- CanCollide=false body), quietly reintroducing exactly the fight
		-- this was meant to avoid. Reasserting it for the whole flight is
		-- what actually stops that revert from resurfacing as gravity
		-- sinking you or the humanoid's own ground-seeking control
		-- resisting your movement (reads as "stuck," including on walls).
		local conn = humanoid.StateChanged:Connect(function(_, new)
			if new ~= Enum.HumanoidStateType.Physics then
				humanoid:ChangeState(Enum.HumanoidStateType.Physics)
			end
		end)
		self._flightConns[player] = conn

		-- The actual fix for gravity sinking: a LinearVelocity constraint
		-- is evaluated by the physics engine on every physics step, not
		-- just once per rendered frame the way a script setting
		-- CFrame/AssemblyLinearVelocity in RenderStepped is -- so there's
		-- no window between corrections for gravity to accumulate a
		-- visible drift in. The root stays network-owned by the flying
		-- client (unanchored, unowned-by-anyone-else, the default for
		-- your own character), so the resulting motion still replicates
		-- to the server exactly like ordinary movement always has --
		-- NoclipController.lua just points this at your desired velocity
		-- each frame instead of writing CFrame directly.
		local attachment = Instance.new("Attachment")
		attachment.Name = "NoclipAttachment"
		attachment.Parent = root

		local velocity = Instance.new("LinearVelocity")
		velocity.Name = "NoclipVelocity"
		velocity.Attachment0 = attachment
		velocity.MaxForce = math.huge
		velocity.VectorVelocity = Vector3.new()
		velocity.RelativeTo = Enum.ActuatorRelativeTo.World
		velocity.Parent = root
	else
		root.Anchored = true
	end

	player:SetAttribute("Invulnerable", invulnerable)
	player:SetAttribute("Untouchable", untouchable)
	player:SetAttribute("Flying", true)
	return true
end

function PlayerService:EnableNoclip(player)
	return self:_beginFlight(player, true, false)
end

function PlayerService:EnableTestSpectate(player)
	-- MonsterAI's playersToCheck() only ever considers players whose
	-- State is "Alive" -- if you type /spectate2 without already being
	-- Alive (e.g. still sitting in the Lobby), you'd stay invisible to
	-- every monster no matter where you flew, which defeats the entire
	-- point of this command. Force it here so /spectate2 always makes you
	-- a valid target regardless of what state you were in before.
	player:SetAttribute("State", "Alive")
	return self:_beginFlight(player, false, true)
end

-- Ends either flight mode -- used by /back for both. Doesn't need to know
-- which one was active: it just restores everything _beginFlight changed.
function PlayerService:EndFlight(player)
	local character = player.Character
	local stash = self._noclipStash[player]
	if not character or not stash then
		return false
	end
	for part, original in pairs(stash) do
		if part and part.Parent then
			part.CanCollide = original.CanCollide
			part.CanQuery = original.CanQuery
			part.Transparency = original.Transparency
		end
	end
	self._noclipStash[player] = nil

	-- Stops /spectate2's StateChanged listener from re-forcing Physics
	-- state after we're done with it -- harmless no-op for /spectate,
	-- which never created one.
	local conn = self._flightConns[player]
	if conn then
		conn:Disconnect()
		self._flightConns[player] = nil
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if root then
		root.Anchored = false
		root.AssemblyLinearVelocity = Vector3.new()
		local attachment = root:FindFirstChild("NoclipAttachment")
		if attachment then
			attachment:Destroy()
		end
		local velocity = root:FindFirstChild("NoclipVelocity")
		if velocity then
			velocity:Destroy()
		end
	end
	-- Recovers a humanoid /spectate2 left in the Physics state back to
	-- normal ground control -- harmless no-op if it was /spectate's
	-- Anchored root instead, which never touched humanoid state.
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	end

	player:SetAttribute("Invulnerable", false)
	player:SetAttribute("Untouchable", false)
	player:SetAttribute("Flying", false)
	return true
end

function PlayerService:_hideCharacter(player)
	local character = player.Character
	if not character then
		return
	end
	local stash = {}
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			stash[part] = {
				Transparency = part.Transparency,
				CanCollide = part.CanCollide,
				Anchored = part.Anchored,
			}
			part.Anchored = true
			part.CanCollide = false
			part.Transparency = 1
		end
	end
	self._hiddenStash[player] = stash
end

function PlayerService:_showCharacter(player)
	local character = player.Character
	local stash = self._hiddenStash[player]
	if not character or not stash then
		return
	end
	for part, original in pairs(stash) do
		if part and part.Parent then
			part.Anchored = original.Anchored
			part.CanCollide = original.CanCollide
			part.Transparency = original.Transparency
		end
	end
	self._hiddenStash[player] = nil
end

function PlayerService:SpawnForRound(player)
	self:_showCharacter(player)

	local character = player.Character
	if not character then
		player:LoadCharacter()
		character = player.Character or player.CharacterAdded:Wait()
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if humanoid then
		humanoid.Health = humanoid.MaxHealth
		humanoid.WalkSpeed = Config.Player.WalkSpeed
		humanoid.PlatformStand = false
		humanoid.JumpPower = 50
	end
	if root then
		local offset = Vector3.new(math.random(-4, 4), 3, math.random(-4, 4))
		root.CFrame = CFrame.new(self.maze.entranceWorldPos + offset)
	end

	player:SetAttribute("State", "Alive")
	player:SetAttribute("Invulnerable", false)
	player:SetAttribute("Untouchable", false) -- safety net in case /spectate2 was left on without /back
	player:SetAttribute("Hidden", false) -- safety net in case a wardrobe hide was still active
	self.spawnEvent:FireClient(player)
end

function PlayerService:CatchPlayer(player, monsterId, monsterModel)
	if player:GetAttribute("Untouchable") then
		-- /spectate2 (EnableTestSpectate): monsters see and chase this
		-- player completely normally -- this is the ONLY thing that
		-- changes, so a real catch attempt (MonsterAI:_onTouch already
		-- fired, cooldown and all) just has no effect.
		print(string.format("[Debug] %s would have been caught by %s -- untouchable (test-spectating), no effect.", player.Name, monsterId))
		return
	end
	if player:GetAttribute("State") ~= "Alive" then
		return
	end
	player:SetAttribute("State", "Caught")

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		humanoid.PlatformStand = true
	end

	-- monsterModel is the actual live monster instance that caught this
	-- player (see MonsterAI:_onTouch) -- it's already parented under
	-- workspace, so it's already replicated to this client, and the
	-- jumpscare clones it for a closeup shot of the real rig instead of
	-- just knowing which species caught them.
	self.jumpscareEvent:FireClient(player, monsterId, monsterModel)

	task.delay(Config.Round.JumpscareDuration, function()
		if player.Parent then
			-- TEMP, for faster testing (see README): skip "Dead" and the
			-- Respawn/Spectate menu (DeathController.lua's DeathGui)
			-- entirely on a normal catch -- respawn immediately once the
			-- jumpscare finishes, no click required. MarkDead/the death
			-- menu are still used by ForceTimeout below (the round
			-- actually ending), since Respawn wouldn't do anything there
			-- anyway once roundActive is false.
			self:SpawnForRound(player)
		end
	end)
end

function PlayerService:MarkDead(player, monsterId)
	if player:GetAttribute("State") ~= "Caught" and player:GetAttribute("State") ~= "Alive" then
		return
	end
	player:SetAttribute("State", "Dead")
	self:_hideCharacter(player)
	self.deathMenuEvent:FireClient(player, monsterId)
	if self.onStateChanged then
		self.onStateChanged(player)
	end
end

function PlayerService:ForceTimeout(player)
	if player:GetAttribute("State") ~= "Alive" then
		return
	end
	player:SetAttribute("State", "TimedOut")
	self:_hideCharacter(player)
	self.deathMenuEvent:FireClient(player, "TimedOut")
	if self.onStateChanged then
		self.onStateChanged(player)
	end
end

function PlayerService:_handleRespawnRequest(player)
	if not self.roundActive then
		return
	end
	if player:GetAttribute("State") ~= "Dead" then
		return
	end
	self:SpawnForRound(player)
	player:SetAttribute("Invulnerable", true)
	task.delay(Config.Round.RespawnInvulnerability, function()
		if player:GetAttribute("State") == "Alive" then
			player:SetAttribute("Invulnerable", false)
		end
	end)
end

function PlayerService:_handleSpectateRequest(player)
	if player:GetAttribute("State") ~= "Dead" and player:GetAttribute("State") ~= "TimedOut" then
		return
	end
	player:SetAttribute("State", "Spectating")
	if self.onStateChanged then
		self.onStateChanged(player)
	end
end

function PlayerService:MarkEscaped(player)
	if player:GetAttribute("State") ~= "Alive" then
		return
	end
	player:SetAttribute("State", "Escaped")
	self:_hideCharacter(player)
	self.escapedEvent:FireClient(player)
	if self.onStateChanged then
		self.onStateChanged(player)
	end
end

function PlayerService:GetOutcomes()
	local outcomes = {}
	for _, player in ipairs(Players:GetPlayers()) do
		outcomes[player] = player:GetAttribute("State")
	end
	return outcomes
end

function PlayerService:ResetAllToLobby()
	for _, player in ipairs(Players:GetPlayers()) do
		player:SetAttribute("State", "Lobby")
	end
end

return PlayerService
