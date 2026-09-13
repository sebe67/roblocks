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

-- Debug commands, both open to any player for now since this is still in
-- active testing -- gate them (e.g. to specific UserIds) before this ever
-- goes public.
local function onChatted(player, message)
	local lower = message:lower()
	if lower:match("^/godmode%s*$") then
		gameState:RequestOvertime()
		print(string.format("[Debug] %s triggered /godmode.", player.Name))
		return
	end

	-- /light <x> <y> <on|off> -- flips one specific ceiling fixture, by its
	-- grid cell, to prove out per-light control (StoreTheme.SetFixtureWorking)
	-- without needing to wire up a real in-game trigger for it yet.
	local xStr, yStr, state = lower:match("^/light%s+(%d+)%s+(%d+)%s+(on|off)%s*$")
	if xStr then
		local x, y = tonumber(xStr), tonumber(yStr)
		local ok = StoreTheme.SetFixtureWorking(maze, x, y, state == "on")
		print(string.format("[Debug] %s set light (%d,%d) %s -- %s", player.Name, x, y, state, ok and "OK" or "no such fixture"))
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
