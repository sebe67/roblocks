-- Procedurally builds the store as a series of big rectangular rooms
-- (3-5 base cells per side) connected mostly by narrow doorways and
-- occasionally by wider open "hallway" gaps, instead of a uniform
-- small-cell maze. Each room's interior is fully open floor space; walls
-- only exist at room boundaries. The whole map is split into four
-- roughly-quadrant color zones so wall color reads as "you're in a
-- different wing" rather than random noise, with an occasional
-- off-palette wall/shelf for texture.
--
-- Returns a description table other server modules use to find the
-- entrance, exit door, and minigame station anchors.

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

-- Greedily tiles the whole grid into non-overlapping rectangular rooms
-- sized between minSize and maxSize cells per side (clipped by grid edges
-- and by earlier rooms, so edge/corner rooms are sometimes smaller).
-- Returns the room list and a cellBlock[x][y] -> room index lookup.
local function partitionRooms(width, height, minSize, maxSize)
	local occupied = {}
	local cellBlock = {}
	for x = 1, width do
		occupied[x] = {}
		cellBlock[x] = {}
	end

	local function canPlace(x, y, w, h)
		if x + w - 1 > width or y + h - 1 > height then
			return false
		end
		for yy = y, y + h - 1 do
			for xx = x, x + w - 1 do
				if occupied[xx][yy] then
					return false
				end
			end
		end
		return true
	end

	local rooms = {}
	for y = 1, height do
		for x = 1, width do
			if not occupied[x][y] then
				local targetW = math.random(minSize, maxSize)
				local targetH = math.random(minSize, maxSize)
				local w, h = 1, 1
				while w < targetW and canPlace(x, y, w + 1, h) do
					w += 1
				end
				while h < targetH and canPlace(x, y, w, h + 1) do
					h += 1
				end

				local roomIndex = #rooms + 1
				table.insert(rooms, { x1 = x, y1 = y, x2 = x + w - 1, y2 = y + h - 1 })
				for yy = y, y + h - 1 do
					for xx = x, x + w - 1 do
						occupied[xx][yy] = true
						cellBlock[xx][yy] = roomIndex
					end
				end
			end
		end
	end

	return rooms, cellBlock
end

local function generateGrid(width, height)
	local cells = {}
	for x = 1, width do
		cells[x] = {}
		for y = 1, height do
			cells[x][y] = { N = true, S = true, E = true, W = true }
		end
	end

	local rooms, cellBlock = partitionRooms(width, height, Config.Maze.MinRoomSize, Config.Maze.MaxRoomSize)

	-- Every cell inside a room is open to every other cell in that same
	-- room -- one big open floor, not a mini-maze.
	for _, room in ipairs(rooms) do
		for x = room.x1, room.x2 do
			for y = room.y1, room.y2 do
				if x < room.x2 then
					cells[x][y].E = false
					cells[x + 1][y].W = false
				end
				if y < room.y2 then
					cells[x][y].S = false
					cells[x][y + 1].N = false
				end
			end
		end
	end

	-- Candidate connector edges between two DIFFERENT rooms, grouped by
	-- room-pair so a spanning-tree walk can pick one connector per pair
	-- (rather than working at the fine-cell level, which would ignore room
	-- shape entirely).
	local pairEdges = {}
	local function addCandidate(x, y, dir, nx, ny)
		local a, b = cellBlock[x][y], cellBlock[nx][ny]
		if a == b then
			return
		end
		local key = a < b and (a .. "-" .. b) or (b .. "-" .. a)
		pairEdges[key] = pairEdges[key] or {}
		table.insert(pairEdges[key], { x = x, y = y, dir = dir })
	end
	for x = 1, width do
		for y = 1, height do
			if x < width then
				addCandidate(x, y, "E", x + 1, y)
			end
			if y < height then
				addCandidate(x, y, "S", x, y + 1)
			end
		end
	end

	local adjacency = {}
	for key in pairs(pairEdges) do
		local aStr, bStr = key:match("(%d+)-(%d+)")
		local a, b = tonumber(aStr), tonumber(bStr)
		adjacency[a] = adjacency[a] or {}
		adjacency[b] = adjacency[b] or {}
		table.insert(adjacency[a], { other = b, key = key })
		table.insert(adjacency[b], { other = a, key = key })
	end

	local edgeStyle = {}
	local function markStyle(x, y, dir, style)
		edgeStyle[x] = edgeStyle[x] or {}
		edgeStyle[x][y] = edgeStyle[x][y] or {}
		edgeStyle[x][y][dir] = style
	end

	local function openConnector(key)
		local candidates = pairEdges[key]
		local edge = candidates[math.random(1, #candidates)]
		cells[edge.x][edge.y][edge.dir] = false
		local opposite = DIRS[edge.dir].opposite
		local nx, ny = edge.x + DIRS[edge.dir].dx, edge.y + DIRS[edge.dir].dy
		cells[nx][ny][opposite] = false
		-- Most connections are a proper doorway; occasionally a wider,
		-- fully-open "hallway" gap instead -- and the only kind of
		-- connection Thomas (too wide for doorways) can use between rooms.
		local style = (math.random() < Config.Maze.HallwayChance) and "hallway" or "doorway"
		markStyle(edge.x, edge.y, edge.dir, style)
		markStyle(nx, ny, opposite, style)
	end

	-- Recursive-backtracker spanning walk over ROOMS (not fine cells) --
	-- guarantees every room is reachable from the entrance's room.
	local startRoom = cellBlock[1][1]
	local visited = { [startRoom] = true }
	local usedKeys = {}
	local stack = { startRoom }
	while #stack > 0 do
		local current = stack[#stack]
		local options = {}
		for _, edge in ipairs(adjacency[current] or {}) do
			if not visited[edge.other] then
				table.insert(options, edge)
			end
		end
		if #options == 0 then
			table.remove(stack)
		else
			local pick = options[math.random(1, #options)]
			openConnector(pick.key)
			usedKeys[pick.key] = true
			visited[pick.other] = true
			table.insert(stack, pick.other)
		end
	end

	-- A few extra connections between already-linked rooms for shortcuts.
	for key in pairs(pairEdges) do
		if not usedKeys[key] and math.random() < Config.Maze.LoopChance then
			openConnector(key)
		end
	end

	return cells, edgeStyle, rooms
end

function MazeGenerator.Generate()
	local W, H = Config.Maze.GridWidth, Config.Maze.GridHeight
	local cellSize = Config.Maze.CellSize
	local wallHeight = Config.Maze.WallHeight
	local wallThickness = Config.Maze.WallThickness

	local cells, edgeStyle = generateGrid(W, H)

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

	-- Four roughly-quadrant color "wings" so wall color reads as a sense of
	-- place rather than randomness, with an occasional off-palette wall or
	-- shelf so it doesn't read as forced monotone either.
	local midX, midY = math.ceil(W / 2), math.ceil(H / 2)
	local function pickWallColor(x, y)
		if math.random() < Config.Maze.ZoneAccentChance then
			return WALL_PALETTE[math.random(1, #WALL_PALETTE)]
		end
		local zoneIndex = (x <= midX and 1 or 2) + (y <= midY and 0 or 2)
		local zone = Config.Maze.ColorZones[zoneIndex]
		return zone and zone.primary or WALL_PALETTE[math.random(1, #WALL_PALETTE)]
	end

	local entranceCell = { x = 1, y = 1 }
	local exitCell = { x = W, y = H }

	-- Spreads however many minigame stations Config.Minigames defines
	-- roughly evenly across the grid as a cols x rows lattice, so adding a
	-- 4th/7th/10th station just needs a Config entry -- no placement code
	-- to update.
	local minigameCells = {}
	do
		local count = #Config.Minigames
		local cols = math.ceil(math.sqrt(count))
		local rows = math.ceil(count / cols)
		local placed = 0
		for r = 1, rows do
			for c = 1, cols do
				if placed >= count then
					break
				end
				placed += 1
				local fracX = c / (cols + 1)
				local fracY = r / (rows + 1)
				table.insert(minigameCells, {
					x = math.clamp(math.floor(fracX * W), 2, W - 1),
					y = math.clamp(math.floor(fracY * H), 2, H - 1),
				})
			end
		end
	end

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
			fixture.CanQuery = false
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

	local function addShelfDetail(wallPart, dir, x, y)
		if math.random() > 0.4 then
			return
		end
		local horizontal = (dir == "N" or dir == "S")
		local depth = 1
		-- Offset the shelf off the wall's own centerline toward whichever
		-- face actually opens into this cell's room, so it protrudes from
		-- the wall instead of being buried inside it (which was causing
		-- z-fighting flicker between the shelf and its parent wall).
		local sign = (dir == "N" or dir == "W") and 1 or -1
		local thickness = horizontal and wallPart.Size.Z or wallPart.Size.X
		local outwardOffset = sign * (thickness / 2 + depth / 2)

		for _, frac in ipairs({ 0.35, 0.65 }) do
			local shelf = Instance.new("Part")
			shelf.Name = "Shelf"
			shelf.Anchored = true
			shelf.CanCollide = false
			-- Purely decorative (juts out from the wall into the room for
			-- looks), but a raycast query still hits a part with CanCollide
			-- false unless CanQuery is off too -- left on, these were being
			-- treated as real obstacles by monster sight/chase raycasts,
			-- flipping "is there a clear line to the player" on and off as
			-- shelves entered/left the line and causing exactly the
			-- zig-zag/stop-and-restart chase behavior reported.
			shelf.CanQuery = false
			shelf.Material = Enum.Material.Metal
			-- Shelves get their own occasional-accent roll too, independent
			-- of the wall they're on -- keeps "other colors here and there"
			-- from being tied 1:1 to whichever wall happens to have one.
			shelf.Color = math.random() < 0.5 and Color3.fromRGB(90, 90, 96) or pickWallColor(x, y)
			if horizontal then
				shelf.Size = Vector3.new(wallPart.Size.X * 0.9, 0.3, depth)
				shelf.CFrame = wallPart.CFrame * CFrame.new(0, wallPart.Size.Y * (frac - 0.5), outwardOffset)
			else
				shelf.Size = Vector3.new(depth, 0.3, wallPart.Size.Z * 0.9)
				shelf.CFrame = wallPart.CFrame * CFrame.new(outwardOffset, wallPart.Size.Y * (frac - 0.5), 0)
			end
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

	-- True if the boundary at (x,y) facing dir has actual wall material on
	-- it -- either a solid wall or a doorway (whose stubs always reach the
	-- corners even though the middle is open). False for a hallway gap, a
	-- plain open interior boundary, or anything off the grid edge.
	local function hasWallMaterial(x, y, dir)
		if x < 1 or x > W or y < 1 or y > H then
			return false
		end
		if cells[x][y][dir] then
			return true
		end
		local style = edgeStyle[x] and edgeStyle[x][y] and edgeStyle[x][y][dir]
		return style == "doorway"
	end

	local function buildWall(x, y, dir)
		local center = cellToWorld(x, y)
		local size, cf
		if dir == "N" or dir == "S" then
			-- E/W walls are always full-length (see below), so an N/S wall
			-- only needs to trim half a wallThickness off an end when a
			-- perpendicular wall/doorway actually exists there to meet --
			-- checking BOTH rows that share that corner, since either one's
			-- E/W boundary can supply that material. Skipping the trim when
			-- neither does (common now that big rooms leave long open runs)
			-- is what closes the gaps that used to appear along those runs;
			-- trimming when one does is what avoids z-fighting at a true
			-- corner.
			local neighborY = (dir == "N") and (y - 1) or (y + 1)
			local westTrim = (hasWallMaterial(x, y, "W") or hasWallMaterial(x, neighborY, "W")) and (wallThickness / 2)
				or 0
			local eastTrim = (hasWallMaterial(x, y, "E") or hasWallMaterial(x, neighborY, "E")) and (wallThickness / 2)
				or 0
			local length = cellSize - westTrim - eastTrim
			local xOffset = (eastTrim - westTrim) / 2
			local z = (dir == "N") and (-cellSize / 2) or (cellSize / 2)
			size = Vector3.new(length, wallHeight, wallThickness)
			cf = CFrame.new(center + Vector3.new(xOffset, wallHeight / 2, z))
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
		wall.Color = pickWallColor(x, y)
		wall.Parent = folders.Walls

		addShelfDetail(wall, dir, x, y)
		maybeAddSign(wall)
	end

	local doorwayWidth = Config.Maze.DoorwayWidth

	local function buildDoorway(x, y, dir)
		local center = cellToWorld(x, y)

		local function makeStub(offsetX, offsetZ, sizeX, sizeZ)
			local stub = Instance.new("Part")
			stub.Name = string.format("Doorway_%d_%d_%s", x, y, dir)
			stub.Anchored = true
			stub.Size = Vector3.new(sizeX, wallHeight, sizeZ)
			stub.CFrame = CFrame.new(center + Vector3.new(offsetX, wallHeight / 2, offsetZ))
			stub.Material = math.random() < 0.3 and Enum.Material.Wood or Enum.Material.SmoothPlastic
			stub.Color = pickWallColor(x, y)
			stub.Parent = folders.Walls
			return stub
		end

		if dir == "E" or dir == "W" then
			-- E/W stubs always reach their full corner, matching buildWall's
			-- E/W convention.
			local stubLength = (cellSize - doorwayWidth) / 2
			if stubLength <= 0.5 then
				return
			end
			local edgeOffset = doorwayWidth / 2 + stubLength / 2
			local xOff = (dir == "E") and (cellSize / 2) or (-cellSize / 2)
			makeStub(xOff, -edgeOffset, wallThickness, stubLength)
			makeStub(xOff, edgeOffset, wallThickness, stubLength)
			return
		end

		-- N/S: each stub's outer (corner-facing) end independently trims by
		-- half a wallThickness only when a perpendicular wall/doorway
		-- actually meets it there -- same rule as buildWall -- so a doorway
		-- along an open room boundary reaches the full corner instead of
		-- leaving the same kind of gap the walls used to.
		local neighborY = (dir == "N") and (y - 1) or (y + 1)
		local z = (dir == "N") and (-cellSize / 2) or (cellSize / 2)

		local westTrim = (hasWallMaterial(x, y, "W") or hasWallMaterial(x, neighborY, "W")) and (wallThickness / 2)
			or 0
		local eastTrim = (hasWallMaterial(x, y, "E") or hasWallMaterial(x, neighborY, "E")) and (wallThickness / 2)
			or 0

		local westStubLength = cellSize / 2 - doorwayWidth / 2 - westTrim
		local eastStubLength = cellSize / 2 - doorwayWidth / 2 - eastTrim

		if westStubLength > 0.5 then
			makeStub(-(doorwayWidth / 2 + westStubLength / 2), z, westStubLength, wallThickness)
		end
		if eastStubLength > 0.5 then
			makeStub(doorwayWidth / 2 + eastStubLength / 2, z, eastStubLength, wallThickness)
		end
	end

	-- Wall present -> solid wall. Open + tagged "doorway" -> narrow gap.
	-- Open + tagged "hallway" (or untagged, i.e. inside one big room) ->
	-- nothing, fully open.
	local function processEdge(x, y, dir)
		if cells[x][y][dir] then
			buildWall(x, y, dir)
		else
			local style = edgeStyle[x] and edgeStyle[x][y] and edgeStyle[x][y][dir]
			if style == "doorway" then
				buildDoorway(x, y, dir)
			end
		end
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
			processEdge(x, y, "N")
			processEdge(x, y, "W")
			if y == H and x ~= exitCell.x then
				processEdge(x, y, "S")
			end
			if x == W then
				processEdge(x, y, "E")
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

	storeModel.Parent = workspace

	return {
		model = storeModel,
		cells = cells,
		gridWidth = W,
		gridHeight = H,
		cellSize = cellSize,
		cellToWorld = cellToWorld,
		entranceCell = entranceCell,
		exitCell = exitCell,
		exitDoor = exitDoor,
		escapeZone = escapeZone,
		minigameCells = minigameCells,
		entranceWorldPos = cellToWorld(entranceCell.x, entranceCell.y),
	}
end

return MazeGenerator
