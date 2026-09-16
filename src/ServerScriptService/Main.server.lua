-- Entry point: generates the store, spawns the monsters, and wires the
-- services together. Everything else in this folder is a module that does
-- nothing until required from here.

local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")

-- Monsters physically colliding with players -- OR with each other -- was
-- never needed: the catch is a Touched-event trigger (MonsterAI:_onTouch),
-- not a physical block, and letting Roblox's rigid-body physics resolve
-- the overlap between two CanCollide parts every frame something tries to
-- walk into something it's already reached is exactly the "orbits before
-- finally touching" bug: each frame's push-apart-and-reaim-at-center cycle
-- can slide the mover sideways around the other's collision shape instead
-- of ever registering contact. With Chase now a pure, obstacle-blind
-- beeline at the player (no PathfindingService fallback), a chasing
-- monster whose straight line happens to pass through ANOTHER monster's
-- body has nothing to route around it with -- it just gets physically
-- shoved off-course by that monster over and over, which reads as
-- zig-zagging/orbiting and explains why this showed up for some
-- encounters (another monster happened to be in the way) and not others,
-- with all of them running identical chase code. Touched still fires
-- between non-colliding parts (it depends on CanTouch, not CanCollide), so
-- disabling collision between these groups only removes the physical
-- shove -- catching still works exactly the same. All three groups still
-- collide normally with Default (walls, floor, everything else), and
-- registering an already-registered group is a harmless no-op.
pcall(function()
	PhysicsService:RegisterCollisionGroup("Monsters")
	PhysicsService:RegisterCollisionGroup("Players")
	PhysicsService:CollisionGroupSetCollidable("Monsters", "Players", false)
	PhysicsService:CollisionGroupSetCollidable("Monsters", "Monsters", false)
end)

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
StoreTheme.StartBlackoutLoop(maze)

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

-- Debug commands, gated to your own username so anyone else joining the
-- game can't trigger them. Checked against Name rather than UserId since
-- that's what you asked to gate against; Name can change if you ever
-- rename your account, in which case update DEBUG_USERNAME below.
local DEBUG_USERNAME = "Besussero"

local function onChatted(player, message)
	if player.Name ~= DEBUG_USERNAME then
		return
	end
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
		return
	end

	-- /blackout -- fires a store-wide blackout immediately instead of
	-- waiting on the random average-every-2-minutes roll, to test it.
	if lower:match("^/blackout%s*$") then
		task.spawn(function()
			StoreTheme.TriggerBlackout(maze)
		end)
		print(string.format("[Debug] %s triggered /blackout.", player.Name))
		return
	end

	-- /spectate and /back -- free-fly noclip for testing: invisible,
	-- intangible, and invulnerable to monsters (see
	-- PlayerService:EnableNoclip/DisableNoclip), so you can fly anywhere
	-- to check on things without being seen, chased, or caught.
	if lower:match("^/spectate%s*$") then
		local ok = playerService:EnableNoclip(player)
		print(string.format("[Debug] %s used /spectate -- %s", player.Name, ok and "OK" or "no character to spectate with"))
		return
	end
	if lower:match("^/back%s*$") then
		local ok = playerService:DisableNoclip(player)
		print(string.format("[Debug] %s used /back -- %s", player.Name, ok and "OK" or "wasn't spectating"))
		return
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
