-- Procedurally builds the store: a grid maze of "showroom" cells carved with
-- a recursive backtracker, with a handful of forced-open "rail" rows/columns
-- that form wide main walkways (these double as the only cells Thomas the
-- Tank Engine is allowed to travel through -- see WaypointGraph.lua).
--
-- Returns a description table other server modules use to find the
-- entrance, exit door, minigame station anchors, and rail-cell positions.

local CollectionService = game:GetService("CollectionService")
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local MazeGenerator = {}

local DIRS = {
	N = { dx = 0, dy = -1, opposite = "S" },
	S = { dx = 0, dy = 1, opposite = "N" },
	E = { dx = 1, dy = 0, opposite = "W" },
	W = { dx = -1, dy = 0, opposite = "E" },
}

local WALL_PALETTE = {
	Color3.fromRGB(0, 81, 186), -- IKEA blue
	Color3.fromRGB(255, 218, 26), -- IKEA yellow
	Color3.fromRGB(232, 226, 212), -- showroom off-white
	Color3.fromRGB(150, 116, 78), -- particleboard tan
}

local function inBounds(x, y, w, h)
	return x >= 1 and x <= w and y >= 1 and y <= h
end

local function generateGrid(width, height)
	local cells = {}
	for x = 1, width do
		cells[x] = {}
		for y = 1, height do
			cells[x][y] = { N = true, S = true, E = true, W = true, visited = false }
		end
	end

	local stack = { { 1, 1 } }
	cells[1][1].visited = true

	while #stack > 0 do
		local cx, cy = stack[#stack][1], stack[#stack][2]
		local candidates = {}
		for name, dir in pairs(DIRS) do
			local nx, ny = cx + dir.dx, cy + dir.dy
			if inBounds(nx, ny, width, height) and not cells[nx][ny].visited then
				table.insert(candidates, { name = name, nx = nx, ny = ny })
			end
		end

		if #candidates == 0 then
			table.remove(stack)
		else
			local pick = candidates[math.random(1, #candidates)]
			cells[cx][cy][pick.name] = false
			cells[pick.nx][pick.ny][DIRS[pick.name].opposite] = false
			cells[pick.nx][pick.ny].visited = true
			table.insert(stack, { pick.nx, pick.ny })
		end
	end

	-- Knock down extra walls so the maze has loops/shortcuts, not just one
	-- true path -- makes evasion actually possible.
	for x = 1, width do
		for y = 1, height do
			if x < width and cells[x][y].E and math.random() < Config.Maze.LoopChance then
				cells[x][y].E = false
				cells[x + 1][y].W = false
			end
			if y < height and cells[x][y].S and math.random() < Config.Maze.LoopChance then
				cells[x][y].S = false
				cells[x][y + 1].N = false
			end
		end
	end

	return cells
end

local function isRailIndex(i)
	return (i - 1) % Config.Maze.MainCorridorEvery == 0
end

-- Every rail COLUMN is forced open top-to-bottom and every rail ROW is
-- forced open left-to-right, turning them into continuous wide boulevards
-- that cut through the shelf-maze at regular intervals -- and guaranteeing
-- the rail sub-graph WaypointGraph builds for Thomas is fully connected.
local function forceOpenRailLattice(cells, width, height)
	for x = 1, width do
		for y = 1, height do
			if isRailIndex(x) and y < height then
				cells[x][y].S = false
				cells[x][y + 1].N = false
			end
			if isRailIndex(y) and x < width then
				cells[x][y].E = false
				cells[x + 1][y].W = false
			end
		end
	end
end

function MazeGenerator.Generate()
	local W, H = Config.Maze.GridWidth, Config.Maze.GridHeight
	local cellSize = Config.Maze.CellSize
	local wallHeight = Config.Maze.WallHeight
	local wallThickness = Config.Maze.WallThickness

	local cells = generateGrid(W, H)
	forceOpenRailLattice(cells, W, H)

	local storeModel = Instance.new("Model")
	storeModel.Name = "Store"

	local folders = {}
	for _, n in ipairs({ "Floors", "Walls", "Ceiling", "Fixtures", "Stations", "Doors", "Signs" }) do
		local f = Instance.new("Folder")
		f.Name = n
		f.Parent = storeModel
		folders[n] = f
	end

	local function cellToWorld(x, y)
		return Vector3.new((x - 1) * cellSize, 0, (y - 1) * cellSize)
	end

	local entranceCell = { x = 1, y = 1 }
	local exitCell = { x = W, y = H }
	local minigameCells = {
		{ x = math.clamp(math.floor(W / 4), 2, W - 1), y = math.clamp(math.floor(H / 2), 2, H - 1) },
		{ x = math.clamp(math.floor(W / 2), 2, W - 1), y = math.clamp(math.floor(H * 3 / 4), 2, H - 1) },
		{ x = math.clamp(math.floor(W * 3 / 4), 2, W - 1), y = math.clamp(math.floor(H / 4), 2, H - 1) },
	}

	-- Floors + ceilings
	for x = 1, W do
		for y = 1, H do
			local center = cellToWorld(x, y)

			local floor = Instance.new("Part")
			floor.Name = string.format("Floor_%d_%d", x, y)
			floor.Anchored = true
			floor.Size = Vector3.new(cellSize, 1, cellSize)
			floor.CFrame = CFrame.new(center + Vector3.new(0, -0.5, 0))
			floor.Material = (x + y) % 2 == 0 and Enum.Material.Concrete or Enum.Material.WoodPlanks
			floor.Color = Color3.fromRGB(198, 194, 186)
			floor.Parent = folders.Floors

			local ceiling = Instance.new("Part")
			ceiling.Name = string.format("Ceiling_%d_%d", x, y)
			ceiling.Anchored = true
			ceiling.Size = Vector3.new(cellSize, 1, cellSize)
			ceiling.CFrame = CFrame.new(center + Vector3.new(0, wallHeight + 0.5, 0))
			ceiling.Material = Enum.Material.Metal
			ceiling.Color = Color3.fromRGB(40, 40, 44)
			ceiling.Parent = folders.Ceiling

			local isWorking = math.random(1, Config.Lighting.FixtureFrequency) == 1
			local fixture = Instance.new("Part")
			fixture.Name = string.format("Fixture_%d_%d", x, y)
			fixture.Anchored = true
			fixture.CanCollide = false
			fixture.Size = Vector3.new(cellSize * 0.35, 0.3, cellSize * 0.35)
			fixture.CFrame = CFrame.new(center + Vector3.new(0, wallHeight - 0.3, 0))
			fixture.Material = Enum.Material.Neon
			fixture.Color = isWorking and Config.Lighting.FixtureColor or Color3.fromRGB(60, 60, 60)
			fixture.Parent = folders.Fixtures

			if isWorking then
				local light = Instance.new("PointLight")
				light.Range = Config.Lighting.FixtureRange
				light.Brightness = Config.Lighting.FixtureBrightness
				light.Color = Config.Lighting.FixtureColor
				light.Parent = fixture
				fixture:SetAttribute("Working", true)
			elseif math.random() < Config.Lighting.DeadFixtureFlickerChance then
				local light = Instance.new("PointLight")
				light.Range = Config.Lighting.FixtureRange * 0.6
				light.Brightness = Config.Lighting.FixtureBrightness * 0.5
				light.Color = Config.Lighting.FixtureColor
				light.Enabled = false
				light.Parent = fixture
				fixture:SetAttribute("Flickering", true)
			end
		end
	end

	local function addShelfDetail(wallPart, horizontal)
		if math.random() > 0.4 then
			return
		end
		for i, frac in ipairs({ 0.35, 0.65 }) do
			local shelf = Instance.new("Part")
			shelf.Name = "Shelf"
			shelf.Anchored = true
			shelf.CanCollide = false
			shelf.Material = Enum.Material.Metal
			shelf.Color = Color3.fromRGB(90, 90, 96)
			if horizontal then
				shelf.Size = Vector3.new(wallPart.Size.X * 0.9, 0.3, 1)
			else
				shelf.Size = Vector3.new(1, 0.3, wallPart.Size.Z * 0.9)
			end
			shelf.CFrame = wallPart.CFrame * CFrame.new(0, wallPart.Size.Y * (frac - 0.5), 0)
			shelf.Parent = wallPart
		end
	end

	local function maybeAddSign(wallPart)
		if math.random() > 0.22 then
			return
		end
		local gui = Instance.new("BillboardGui")
		gui.Name = "AisleSign"
		gui.Size = UDim2.new(6, 0, 2, 0)
		gui.StudsOffset = Vector3.new(0, wallPart.Size.Y * 0.25, 0)
		gui.Adornee = wallPart
		gui.AlwaysOnTop = false
		gui.Parent = wallPart

		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(255, 255, 255)
		label.TextStrokeTransparency = 0.3
		label.Text = Config.AisleSigns[math.random(1, #Config.AisleSigns)]
		label.Parent = gui
	end

	local function buildWall(x, y, dir)
		local center = cellToWorld(x, y)
		local horizontal = (dir == "N" or dir == "S") -- wall spans along X
		local size, cf
		if dir == "N" then
			size = Vector3.new(cellSize, wallHeight, wallThickness)
			cf = CFrame.new(center + Vector3.new(0, wallHeight / 2, -cellSize / 2))
		elseif dir == "S" then
			size = Vector3.new(cellSize, wallHeight, wallThickness)
			cf = CFrame.new(center + Vector3.new(0, wallHeight / 2, cellSize / 2))
		elseif dir == "E" then
			size = Vector3.new(wallThickness, wallHeight, cellSize)
			cf = CFrame.new(center + Vector3.new(cellSize / 2, wallHeight / 2, 0))
		else -- W
			size = Vector3.new(wallThickness, wallHeight, cellSize)
			cf = CFrame.new(center + Vector3.new(-cellSize / 2, wallHeight / 2, 0))
		end

		local wall = Instance.new("Part")
		wall.Name = string.format("Wall_%d_%d_%s", x, y, dir)
		wall.Anchored = true
		wall.Size = size
		wall.CFrame = cf
		wall.Material = math.random() < 0.3 and Enum.Material.Wood or Enum.Material.SmoothPlastic
		wall.Color = WALL_PALETTE[math.random(1, #WALL_PALETTE)]
		wall.Parent = folders.Walls

		addShelfDetail(wall, horizontal)
		maybeAddSign(wall)
	end

	local exitDoor
	local escapeZone

	local function buildExitDoor(x, y)
		local center = cellToWorld(x, y)
		local door = Instance.new("Part")
		door.Name = "ExitDoor"
		door.Anchored = true
		door.Size = Vector3.new(cellSize * 0.8, wallHeight * 0.85, wallThickness * 2)
		door.CFrame = CFrame.new(center + Vector3.new(0, door.Size.Y / 2, cellSize / 2))
		door.Material = Enum.Material.CorrodedMetal
		door.Color = Color3.fromRGB(235, 170, 20)
		door.Parent = folders.Doors

		local stripe = Instance.new("Texture")
		stripe.Texture = "rbxasset://textures/StudsDiagonal.png"
		stripe.StudsPerTileU = 4
		stripe.StudsPerTileV = 4
		stripe.Face = Enum.NormalId.Front
		stripe.Parent = door

		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.new(8, 0, 2, 0)
		gui.StudsOffset = Vector3.new(0, door.Size.Y / 2 + 1.5, 0)
		gui.Adornee = door
		gui.Parent = door
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(255, 80, 80)
		label.TextStrokeTransparency = 0
		label.Text = "LOADING DOCK [LOCKED]"
		label.Parent = gui

		local zone = Instance.new("Part")
		zone.Name = "EscapeZone"
		zone.Anchored = true
		zone.CanCollide = false
		zone.Transparency = 1
		zone.Size = Vector3.new(cellSize * 0.8, wallHeight * 0.85, 4)
		zone.CFrame = CFrame.new(center + Vector3.new(0, zone.Size.Y / 2, cellSize / 2 + 4))
		zone.Parent = folders.Doors

		exitDoor = door
		escapeZone = zone
	end

	for x = 1, W do
		for y = 1, H do
			if x == exitCell.x and y == exitCell.y and cells[x][y].S then
				buildExitDoor(x, y)
			end
			if cells[x][y].N then
				buildWall(x, y, "N")
			end

			if cells[x][y].W then
				buildWall(x, y, "W")
			end
			if y == H and x ~= exitCell.x and cells[x][y].S then
				buildWall(x, y, "S")
			end
			if x == W and cells[x][y].E then
				buildWall(x, y, "E")
			end
		end
	end

	-- If exit cell's south wall was somehow already open (loop chance), force
	-- a door there anyway so there is always a real, findable exit.
	if not exitDoor then
		buildExitDoor(exitCell.x, exitCell.y)
	end

	-- Entrance lobby signage + spawn points
	do
		local center = cellToWorld(entranceCell.x, entranceCell.y)
		local gui = Instance.new("Part")
		gui.Name = "WelcomeSignAnchor"
		gui.Anchored = true
		gui.CanCollide = false
		gui.Transparency = 1
		gui.Size = Vector3.new(1, 1, 1)
		gui.CFrame = CFrame.new(center + Vector3.new(0, wallHeight * 0.6, 0))
		gui.Parent = folders.Signs

		local billboard = Instance.new("BillboardGui")
		billboard.Size = UDim2.new(14, 0, 3, 0)
		billboard.Adornee = gui
		billboard.Parent = gui
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(255, 218, 26)
		label.TextStrokeTransparency = 0.2
		label.Text = "IKEA OF THE DAMNED"
		label.Parent = billboard

		for i = 1, 4 do
			local spawn = Instance.new("SpawnLocation")
			spawn.Name = "Spawn_" .. i
			spawn.Anchored = true
			spawn.CanCollide = true
			spawn.Neutral = true
			spawn.Size = Vector3.new(4, 1, 4)
			spawn.Transparency = 1
			spawn.TopSurface = Enum.SurfaceType.Smooth
			local offset = Vector3.new((i - 2.5) * 3, 0, 3)
			spawn.CFrame = CFrame.new(center + offset)
			spawn.Parent = storeModel
		end
	end

	-- Minigame station anchors
	local minigameConfigs = Config.Minigames
	for i, cellPos in ipairs(minigameCells) do
		local mgConfig = minigameConfigs[i]
		if mgConfig then
			local center = cellToWorld(cellPos.x, cellPos.y)

			local anchor = Instance.new("Part")
			anchor.Name = "Station_" .. mgConfig.id
			anchor.Anchored = true
			anchor.CanCollide = true
			anchor.Size = Vector3.new(4, 3, 2)
			anchor.CFrame = CFrame.new(center + Vector3.new(0, 1.5, 0))
			anchor.Material = Enum.Material.Metal
			anchor.Color = Color3.fromRGB(220, 220, 225)
			anchor.Parent = folders.Stations
			anchor:SetAttribute("StationId", mgConfig.id)
			CollectionService:AddTag(anchor, "MinigameStation")

			local accent = Instance.new("Part")
			accent.Name = "Accent"
			accent.Anchored = true
			accent.CanCollide = false
			accent.Size = Vector3.new(cellSize - 1, 0.15, cellSize - 1)
			accent.CFrame = CFrame.new(center + Vector3.new(0, 0.1, 0))
			accent.Material = Enum.Material.Neon
			accent.Color = Color3.fromRGB(80, 220, 220)
			accent.Parent = anchor

			local billboard = Instance.new("BillboardGui")
			billboard.Size = UDim2.new(8, 0, 2, 0)
			billboard.StudsOffset = Vector3.new(0, 3, 0)
			billboard.Adornee = anchor
			billboard.Parent = anchor
			local label = Instance.new("TextLabel")
			label.Size = UDim2.fromScale(1, 1)
			label.BackgroundTransparency = 1
			label.Font = Enum.Font.FredokaOne
			label.TextScaled = true
			label.TextColor3 = Color3.fromRGB(80, 220, 220)
			label.TextStrokeTransparency = 0.2
			label.Text = mgConfig.stationName
			label.Parent = billboard

			cellPos.worldPos = center
			cellPos.anchor = anchor
			cellPos.id = mgConfig.id
		end
	end

	-- Rail waypoints (for Thomas's restricted graph) -- every rail cell.
	local railWaypoints = {}
	for x = 1, W do
		for y = 1, H do
			if isRailIndex(x) or isRailIndex(y) then
				table.insert(railWaypoints, { x = x, y = y, worldPos = cellToWorld(x, y) })
			end
		end
	end

	storeModel.Parent = workspace

	return {
		model = storeModel,
		cells = cells,
		gridWidth = W,
		gridHeight = H,
		cellSize = cellSize,
		cellToWorld = cellToWorld,
		isRailIndex = isRailIndex,
		entranceCell = entranceCell,
		exitCell = exitCell,
		exitDoor = exitDoor,
		escapeZone = escapeZone,
		minigameCells = minigameCells,
		railWaypoints = railWaypoints,
		entranceWorldPos = cellToWorld(entranceCell.x, entranceCell.y),
	}
end

return MazeGenerator
