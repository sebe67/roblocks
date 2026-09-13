-- Wires up every "MinigameStation" anchor the MazeGenerator placed: gives it
-- a ProximityPrompt, starts/ends the minigame on the client, emits a noise
-- pulse (which pulls nearby monsters into Investigate) for the whole time
-- it's being played, and unlocks the exit once every station is cleared.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
local Net = require(game:GetService("ReplicatedStorage").Shared.Net)
local MonsterAI = require(script.Parent.MonsterAI)

local MinigameService = {}
MinigameService.__index = MinigameService

function MinigameService.new(maze, exitService)
	local self = setmetatable({}, MinigameService)
	self.maze = maze
	self.exitService = exitService
	self.stations = {}
	self.completedCount = 0
	self.total = 0

	self.startEvent = Net.GetEvent("StartMinigame")
	self.resultEvent = Net.GetEvent("MinigameResult")
	self.cancelEvent = Net.GetEvent("CancelMinigame")
	self.progressEvent = Net.GetEvent("MinigameProgress")

	self:_setupStations()

	self.resultEvent.OnServerEvent:Connect(function(player, stationId, success)
		self:_onResult(player, stationId, success)
	end)

	Players.PlayerRemoving:Connect(function(player)
		self:PlayerLeftStation(player)
	end)

	return self
end

function MinigameService:_setupStations()
	for _, anchor in ipairs(CollectionService:GetTagged("MinigameStation")) do
		local id = anchor:GetAttribute("StationId")
		local def
		for _, d in ipairs(Config.Minigames) do
			if d.id == id then
				def = d
				break
			end
		end
		if def then
			local prompt = Instance.new("ProximityPrompt")
			prompt.ActionText = "Play"
			prompt.ObjectText = def.stationName
			prompt.HoldDuration = 0.4
			prompt.MaxActivationDistance = 8
			prompt.RequiresLineOfSight = false
			prompt.Parent = anchor

			local station = {
				id = id,
				config = def,
				anchor = anchor,
				prompt = prompt,
				completed = false,
				inUse = false,
			}
			self.stations[id] = station
			self.total += 1

			prompt.Triggered:Connect(function(player)
				self:_tryStart(player, station)
			end)
		end
	end
end

function MinigameService:_tryStart(player, station)
	if station.completed or station.inUse then
		return
	end
	if player:GetAttribute("State") ~= "Alive" then
		return
	end

	station.inUse = true
	station.activePlayer = player
	station.prompt.Enabled = false
	self.startEvent:FireClient(player, station.id, station.config)

	local noiseThread = task.spawn(function()
		local elapsed = 0
		while station.inUse and elapsed < station.config.duration + 1 do
			MonsterAI.BroadcastNoise(station.anchor.Position, station.config.noiseRadius)
			task.wait(station.config.noiseInterval)
			elapsed += station.config.noiseInterval
		end
	end)
	station.noiseThread = noiseThread

	-- Auto-cancel (not freeze) if the player wanders too far from the
	-- station -- deliberately not a movement lock, so you can still bail
	-- and run if a monster shows up mid-minigame.
	task.spawn(function()
		while station.inUse and station.activePlayer == player do
			task.wait(0.5)
			if station.inUse and station.activePlayer == player then
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				if not root or (root.Position - station.anchor.Position).Magnitude > Config.MinigameLeashDistance then
					self.cancelEvent:FireClient(player)
					self:_onResult(player, station.id, false)
				end
			end
		end
	end)

	task.delay(station.config.duration + 2, function()
		if station.inUse and station.activePlayer == player then
			self:_onResult(player, station.id, false)
		end
	end)
end

function MinigameService:_onResult(player, stationId, success)
	local station = self.stations[stationId]
	if not station or not station.inUse or station.activePlayer ~= player then
		return
	end
	station.inUse = false
	station.activePlayer = nil

	if success and not station.completed then
		station.completed = true
		self.completedCount += 1
		local accent = station.anchor:FindFirstChild("Accent")
		if accent then
			accent.Color = Color3.fromRGB(70, 220, 90)
		end
		self.progressEvent:FireAllClients(self.completedCount, self.total, station.config.stationName)
		if self.completedCount >= self.total and self.exitService then
			self.exitService:Unlock()
		end
	else
		station.prompt.Enabled = true
	end
end

function MinigameService:PlayerLeftStation(player)
	for _, station in pairs(self.stations) do
		if station.activePlayer == player then
			self:_onResult(player, station.id, false)
		end
	end
end

function MinigameService:Reset()
	for _, station in pairs(self.stations) do
		station.completed = false
		station.inUse = false
		station.activePlayer = nil
		station.prompt.Enabled = true
		local accent = station.anchor:FindFirstChild("Accent")
		if accent then
			accent.Color = Color3.fromRGB(80, 220, 220)
		end
	end
	self.completedCount = 0
end

return MinigameService
