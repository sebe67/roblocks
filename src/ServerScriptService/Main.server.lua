-- Entry point: generates the store, spawns the monsters, and wires the
-- services together. Everything else in this folder is a module that does
-- nothing until required from here.

local MazeGenerator = require(script.Parent.MazeGenerator)
local StoreTheme = require(script.Parent.StoreTheme)
local WaypointGraph = require(script.Parent.WaypointGraph)
local MonsterAI = require(script.Parent.MonsterAI)
local MonsterSpawner = require(script.Parent.MonsterSpawner)
local MinigameService = require(script.Parent.MinigameService)
local ExitService = require(script.Parent.ExitService)
local PlayerService = require(script.Parent.PlayerService)
local GameState = require(script.Parent.GameState)

local maze = MazeGenerator.Generate()
StoreTheme.Apply()
StoreTheme.StartFlicker(maze.model)

local waypointGraph = WaypointGraph.new(maze)
local monsters = MonsterSpawner.SpawnAll(maze, waypointGraph)
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

local _gameState = GameState.new(maze, playerService, monsters, minigameService, exitService)

print("[IKEA of the Damned] Store generated:", maze.gridWidth, "x", maze.gridHeight, "cells.")
