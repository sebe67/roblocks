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

	self.jumpscareEvent = Net.GetEvent("Jumpscare")
	self.deathMenuEvent = Net.GetEvent("ShowDeathMenu")
	self.respawnEvent = Net.GetEvent("RequestRespawn")
	self.spectateEvent = Net.GetEvent("RequestSpectate")
	self.escapedEvent = Net.GetEvent("PlayerEscaped")
	self.spawnEvent = Net.GetEvent("RoundSpawn")

	self.respawnEvent.OnServerEvent:Connect(function(player)
		self:_handleRespawnRequest(player)
	end)
	self.spectateEvent.OnServerEvent:Connect(function(player)
		self:_handleSpectateRequest(player)
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
