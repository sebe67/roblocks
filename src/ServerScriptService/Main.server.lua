-- Entry point: generates the store, spawns the monsters, and wires the
-- services together. Everything else in this folder is a module that does
-- nothing until required from here.

local Players = game:GetService("Players")

local MazeGenerator = require(script.Parent.MazeGenerator)
local StoreTheme = require(script.Parent.StoreTheme)
local MonsterAI = require(script.Parent.MonsterAI)
local MonsterSpawner = require(script.Parent.MonsterSpawner)
local MinigameService = require(script.Parent.MinigameService)
local ExitService = require(script.Parent.ExitService)
local PlayerService = require(script.Parent.PlayerService)
local GameState = require(script.Parent.GameState)

local maze = MazeGenerator.Generate()
StoreTheme.Apply()
StoreTheme.StartFlicker(maze.model)

local monsters = MonsterSpawner.SpawnAll(maze)
for _, monster in ipairs(monsters) do
	monster:SetPaused(true)
end

local exitService = ExitService.new(maze)
local minigameService = MinigameService.new(maze, exitService)
local playerService = PlayerService.new(maze)

MonsterAI.SetCatchHandler(function(player, monsterId)
	playerService:CatchPlayer(player, monsterId)
end)
exitService:SetEscapeHandler(function(player)
	playerService:MarkEscaped(player)
end)

local gameState = GameState.new(maze, playerService, monsters, minigameService, exitService)

-- Debug command: type /godmode in chat to skip straight to the Overtime
-- finale without waiting out Config.Round.MaxRoundTime. Open to any player
-- for now since this is still in active testing -- gate it (e.g. to
-- specific UserIds) before this ever goes public.
local function onChatted(player, message)
	if message:lower():match("^/godmode%s*$") then
		gameState:RequestOvertime()
		print(string.format("[Debug] %s triggered /godmode.", player.Name))
	end
end

Players.PlayerAdded:Connect(function(player)
	player.Chatted:Connect(function(message)
		onChatted(player, message)
	end)
end)
for _, player in ipairs(Players:GetPlayers()) do
	player.Chatted:Connect(function(message)
		onChatted(player, message)
	end)
end

print("[IKEA of the Damned] Store generated:", maze.gridWidth, "x", maze.gridHeight, "cells.")
