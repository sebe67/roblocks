local RunService = game:GetService("RunService")
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
local MonsterAI = require(script.Parent.MonsterAI)

local MonsterSpawner = {}

-- Picks a random cell at least Config.Maze.MonsterSpawnExclusionCells away
-- from the entrance (falling back to the single farthest corner if 12
-- random tries can't find one -- always true in practice for this grid
-- size). Used both at server boot and again at the start of every round, so
-- monsters can't camp the spawn point between rounds.
local function pickSpawnPosition(maze)
	local minDistance = maze.cellSize * Config.Maze.MonsterSpawnExclusionCells
	for _ = 1, 12 do
		local x = math.random(1, maze.gridWidth)
		local y = math.random(1, maze.gridHeight)
		local candidate = maze.cellToWorld(x, y)
		if (candidate - maze.entranceWorldPos).Magnitude > minDistance then
			return candidate
		end
	end
	return maze.cellToWorld(maze.gridWidth, 1)
end

-- Spawns one of every monster in Config.Monsters, places them away from the
-- entrance, and starts a single shared Heartbeat loop driving all of them
-- (cheaper than one task.spawn loop per monster).
function MonsterSpawner.SpawnAll(maze)
	local monsters = {}

	for _, def in ipairs(Config.Monsters) do
		local monster = MonsterAI.new(def, maze)
		monster:TeleportTo(pickSpawnPosition(maze))
		table.insert(monsters, monster)
	end

	local heartbeatConn = RunService.Heartbeat:Connect(function(dt)
		for _, monster in ipairs(monsters) do
			local ok, err = pcall(function()
				monster:Update(dt)
			end)
			if not ok then
				warn(string.format("[MonsterAI] %s update error: %s", monster.def.id, tostring(err)))
			end
		end
	end)

	return monsters, heartbeatConn
end

-- Re-scatters every monster away from the entrance again -- called at the
-- start of each round (not just server boot), so a monster that ended the
-- previous round camped near the (now-central) spawn point doesn't just
-- resume right there when everyone respawns in.
function MonsterSpawner.RepositionAll(monsters, maze)
	for _, monster in ipairs(monsters) do
		monster:TeleportTo(pickSpawnPosition(maze))
	end
end

return MonsterSpawner
