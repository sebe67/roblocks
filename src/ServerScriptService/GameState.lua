-- Drives the round loop: Waiting -> Intermission -> Playing -> Results ->
-- back to Waiting. Playing ends when no player is left in the "Alive"
-- state (all caught, escaped, or timed out).

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
local Net = require(game:GetService("ReplicatedStorage").Shared.Net)
local MonsterAI = require(script.Parent.MonsterAI)

local GameState = {}
GameState.__index = GameState

function GameState.new(maze, playerService, monsters, minigameService, exitService)
	local self = setmetatable({}, GameState)
	self.maze = maze
	self.playerService = playerService
	self.monsters = monsters
	self.minigameService = minigameService
	self.exitService = exitService
	self.phase = "Waiting"

	self.phaseEvent = Net.GetEvent("RoundPhase")
	self.resultsEvent = Net.GetEvent("RoundResults")
	self.overtimeEvent = Net.GetEvent("OvertimeStarted")

	playerService.onStateChanged = function()
		self:_checkRoundEnd()
	end

	task.spawn(function()
		self:_loop()
	end)

	return self
end

function GameState:_setMonstersPaused(paused)
	for _, monster in ipairs(self.monsters) do
		monster:SetPaused(paused)
	end
end

function GameState:_loop()
	while true do
		self:_waitForPlayers()
		self:_intermission()
		if #Players:GetPlayers() > 0 then
			self:_playRound()
			self:_showResults()
		end
	end
end

function GameState:_waitForPlayers()
	self.phase = "Waiting"
	self.phaseEvent:FireAllClients("Waiting", {})
	while #Players:GetPlayers() < Config.Round.MinPlayers do
		task.wait(1)
	end
end

function GameState:_intermission()
	self.phase = "Intermission"
	for i = Config.Round.IntermissionTime, 1, -1 do
		if #Players:GetPlayers() == 0 then
			return
		end
		self.phaseEvent:FireAllClients("Intermission", { timeLeft = i })
		task.wait(1)
	end
end

function GameState:_playRound()
	self.phase = "Playing"
	self.playerService.roundActive = true
	self.minigameService:Reset()
	self.exitService:Reset()
	self:_resetOvertimeVisuals()
	MonsterAI.ExitOvertime()
	self:_setMonstersPaused(false)

	for _, player in ipairs(Players:GetPlayers()) do
		self.playerService:SpawnForRound(player)
	end

	self.phaseEvent:FireAllClients("Playing", {})

	local startTime = os.clock()
	self._roundEnded = false
	local overtimeStarted = false
	local overtimeDeadline

	while not self._roundEnded do
		task.wait(1)
		if not overtimeStarted and os.clock() - startTime > Config.Round.MaxRoundTime then
			overtimeStarted = true
			overtimeDeadline = os.clock() + Config.Round.OvertimeDuration
			self:_startOvertime()
		end

		if overtimeStarted and os.clock() > overtimeDeadline then
			-- Hard cap: whoever's still standing (or still respawning into
			-- it) gets swept regardless, so the round can never hang
			-- forever even if someone keeps clicking Respawn into godmode.
			for _, player in ipairs(Players:GetPlayers()) do
				self.playerService:ForceTimeout(player)
			end
			self._roundEnded = true
		else
			self:_checkRoundEnd()
		end
	end

	self.playerService.roundActive = false
	self:_setMonstersPaused(true)
end

function GameState:_startOvertime()
	MonsterAI.EnterOvertime()
	self.overtimeEvent:FireAllClients()
	Lighting.FogEnd = math.max(30, Lighting.FogEnd * 0.6)
	Lighting.Brightness = math.max(0.4, Lighting.Brightness * 0.7)
end

function GameState:_resetOvertimeVisuals()
	Lighting.FogEnd = Config.Lighting.FogEnd
	Lighting.Brightness = Config.Lighting.Brightness
end

function GameState:_checkRoundEnd()
	if self.phase ~= "Playing" then
		return
	end
	for _, player in ipairs(Players:GetPlayers()) do
		local state = player:GetAttribute("State")
		-- "Dead" means they're still sitting on the Respawn/Spectate choice --
		-- the round isn't over until every player has actually resolved that
		-- choice (Spectating/Escaped/TimedOut), otherwise a solo/last-alive
		-- player's jumpscare screen gets yanked away by the Results screen
		-- before they can click anything.
		if state == "Alive" or state == "Dead" then
			return
		end
	end
	self._roundEnded = true
end

function GameState:_showResults()
	self.phase = "Results"

	local payload = {}
	for player, state in pairs(self.playerService:GetOutcomes()) do
		table.insert(payload, { name = player.Name, state = state })
	end

	self.resultsEvent:FireAllClients(payload)
	self.phaseEvent:FireAllClients("Results", { duration = Config.Round.ResultsScreenTime })
	task.wait(Config.Round.ResultsScreenTime)

	self.playerService:ResetAllToLobby()
end

return GameState
