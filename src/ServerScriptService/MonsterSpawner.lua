local RunService = game:GetService("RunService")
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
local MonsterAI = require(script.Parent.MonsterAI)

local MonsterSpawner = {}

-- Spawns one of every monster in Config.Monsters, places them away from the
-- entrance, and starts a single shared Heartbeat loop driving all of them
-- (cheaper than one task.spawn loop per monster).
function MonsterSpawner.SpawnAll(maze)
	local monsters = {}

	for _, def in ipairs(Config.Monsters) do
		local monster = MonsterAI.new(def, maze)

		local spawnPos
		for _ = 1, 12 do
			local x = math.random(1, maze.gridWidth)
			local y = math.random(1, maze.gridHeight)
			local candidate = maze.cellToWorld(x, y)
			if (candidate - maze.entranceWorldPos).Magnitude > maze.cellSize * 3 then
				spawnPos = candidate
				break
			end
		end
		monster:TeleportTo(spawnPos or maze.cellToWorld(maze.gridWidth, 1))

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

return MonsterSpawner
