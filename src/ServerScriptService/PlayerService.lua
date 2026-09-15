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

-- /spectate and /back (Main.server.lua debug commands): a free-fly noclip
-- mode for testing, distinct from the death-flow "Spectating" State above
-- -- that one locks your camera onto another alive player, this one lets
-- your own character fly through walls. Invisible+intangible is just
-- CanCollide=false/Transparency=1 on every part (same stash-and-restore
-- shape as _hideCharacter, kept separate since this one must NOT anchor --
-- the character still needs to physically move); "can't be seen/chased/
-- touched by monsters" reuses the existing Invulnerable attribute, which
-- MonsterAI's playersToCheck() already filters out before any sight or
-- catch check ever runs. The actual flight movement itself is entirely
-- client-side (NoclipController.lua reacting to the Flying attribute) --
-- this just puts the character into a state that movement can act on.
function PlayerService:EnableNoclip(player)
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
			stash[part] = { Transparency = part.Transparency, CanCollide = part.CanCollide }
			part.CanCollide = false
			part.Transparency = 1
		end
	end
	self._noclipStash[player] = stash

	-- PlatformStand suspends the Humanoid's own ground-walk control so it
	-- doesn't fight NoclipController's direct velocity writes; it doesn't
	-- disable physics, which is exactly what lets those velocity writes
	-- actually move the character freely in all 3 axes.
	humanoid.PlatformStand = true
	root.AssemblyLinearVelocity = Vector3.zero

	player:SetAttribute("Invulnerable", true)
	player:SetAttribute("Flying", true)
	return true
end

function PlayerService:DisableNoclip(player)
	local character = player.Character
	local stash = self._noclipStash[player]
	if not character or not stash then
		return false
	end
	for part, original in pairs(stash) do
		if part and part.Parent then
			part.CanCollide = original.CanCollide
			part.Transparency = original.Transparency
		end
	end
	self._noclipStash[player] = nil

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if humanoid then
		humanoid.PlatformStand = false
	end
	if root then
		root.AssemblyLinearVelocity = Vector3.zero
	end

	player:SetAttribute("Invulnerable", false)
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
	self.spawnEvent:FireClient(player)
end

function PlayerService:CatchPlayer(player, monsterId)
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

	self.jumpscareEvent:FireClient(player, monsterId)

	task.delay(Config.Round.JumpscareDuration, function()
		if player.Parent then
			self:MarkDead(player, monsterId)
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
