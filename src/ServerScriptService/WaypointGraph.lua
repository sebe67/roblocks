-- Builds a small BFS-able graph over just the maze's "rail" cells (the wide
-- forced-open main walkways). Thomas the Tank Engine paths exclusively on
-- this graph instead of Roblox's navmesh PathfindingService, which is what
-- keeps him physically unable to enter narrow shelf aisles.

local WaypointGraph = {}
WaypointGraph.__index = WaypointGraph

local function key(x, y)
	return x .. "," .. y
end

function WaypointGraph.new(maze)
	local self = setmetatable({}, WaypointGraph)
	self.nodes = {}
	self.adjacency = {}

	for _, wp in ipairs(maze.railWaypoints) do
		local k = key(wp.x, wp.y)
		self.nodes[k] = wp
		self.adjacency[k] = {}
	end

	for _, wp in ipairs(maze.railWaypoints) do
		local x, y = wp.x, wp.y
		local cell = maze.cells[x][y]
		local function link(nx, ny, open)
			local nk = key(nx, ny)
			if open and self.nodes[nk] then
				table.insert(self.adjacency[key(x, y)], nk)
			end
		end
		link(x, y - 1, not cell.N)
		link(x, y + 1, not cell.S)
		link(x + 1, y, not cell.E)
		link(x - 1, y, not cell.W)
	end

	return self
end

function WaypointGraph:_nearestNode(worldPos)
	local bestKey, bestDist
	for k, node in pairs(self.nodes) do
		local d = (node.worldPos - worldPos).Magnitude
		if not bestDist or d < bestDist then
			bestDist = d
			bestKey = k
		end
	end
	return bestKey
end

-- Returns an ordered list of Vector3 waypoints from fromPos to toPos along
-- the rail graph, or nil if unreachable.
function WaypointGraph:FindPath(fromPos, toPos)
	local startKey = self:_nearestNode(fromPos)
	local goalKey = self:_nearestNode(toPos)
	if not startKey or not goalKey then
		return nil
	end
	if startKey == goalKey then
		return { self.nodes[startKey].worldPos }
	end

	local visited = { [startKey] = true }
	local prev = {}
	local queue = { startKey }
	local head = 1
	local found = false

	while head <= #queue do
		local current = queue[head]
		head += 1
		if current == goalKey then
			found = true
			break
		end
		for _, neighbor in ipairs(self.adjacency[current] or {}) do
			if not visited[neighbor] then
				visited[neighbor] = true
				prev[neighbor] = current
				table.insert(queue, neighbor)
			end
		end
	end

	if not found then
		return nil
	end

	local reversed = { goalKey }
	local cur = goalKey
	while cur ~= startKey do
		cur = prev[cur]
		if not cur then
			return nil
		end
		table.insert(reversed, cur)
	end

	local path = {}
	for i = #reversed, 1, -1 do
		table.insert(path, self.nodes[reversed[i]].worldPos)
	end
	return path
end

function WaypointGraph:RandomNode()
	local keys = {}
	for k in pairs(self.nodes) do
		table.insert(keys, k)
	end
	local pick = keys[math.random(1, #keys)]
	return self.nodes[pick].worldPos
end

return WaypointGraph
