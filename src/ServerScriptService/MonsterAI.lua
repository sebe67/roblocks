-- Per-monster state machine: Patrol -> (sight) -> Chase, with an
-- Investigate state fed by noise pulses (minigames) and Dora's "callout"
-- quirk, and a brief Search state when a chase target breaks line of sight.
--
-- Monsters ONLY ever enter Chase because they directly saw a player
-- (unobstructed raycast + FOV cone + range). Investigate only ever walks
-- them toward a *location*, never straight at a player through walls.

local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")

local MonsterAI = {}
MonsterAI.__index = MonsterAI

local registry = {}
local catchHandler = nil

function MonsterAI.SetCatchHandler(fn)
	catchHandler = fn
end

local function createRig(def)
	local model = Instance.new("Model")
	model.Name = def.displayName

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2.4, 3.2, 1.4) * def.scale
	root.Color = def.color
	root.Material = Enum.Material.SmoothPlastic
	root.CanCollide = true
	root.Parent = model
	model.PrimaryPart = root

	local head = Instance.new("Part")
	head.Name = "Head"
	head.Shape = Enum.PartType.Ball
	head.Size = Vector3.new(1.8, 1.8, 1.8) * def.scale
	head.Color = def.accentColor
	head.Material = Enum.Material.SmoothPlastic
	head.CanCollide = false
	head.Parent = model
	head.CFrame = root.CFrame * CFrame.new(0, (root.Size.Y / 2) + (head.Size.Y / 2) - 0.2, 0)

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = head
	weld.Parent = root

	local face = Instance.new("Decal")
	face.Texture = "rbxasset://textures/face.png"
	face.Face = Enum.NormalId.Front
	face.Parent = head

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.WalkSpeed = def.patrolSpeed
	humanoid.JumpPower = 0
	humanoid.BreakJointsOnDeath = false
	humanoid.Parent = model

	local nameTag = Instance.new("BillboardGui")
	nameTag.Name = "NameTag"
	nameTag.Size = UDim2.new(6, 0, 1.4, 0)
	nameTag.StudsOffset = Vector3.new(0, 2.4, 0)
	nameTag.Adornee = head
	nameTag.Parent = head
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = def.color
	label.TextStrokeTransparency = 0
	label.Text = def.displayName
	label.Parent = nameTag

	return model, humanoid, root
end

function MonsterAI.new(def, maze, waypointGraph)
	local self = setmetatable({}, MonsterAI)
	self.def = def
	self.maze = maze
	self.waypointGraph = waypointGraph
	self.state = "Patrol"
	self.target = nil
	self.lastKnownPos = nil
	self.investigatePos = nil
	self.lastSightTime = 0
	self.lastPathTime = 0
	self.paused = true
	self.destroyed = false
	self.catchCooldown = {}

	self.model, self.humanoid, self.root = createRig(def)
	self.model.Parent = workspace

	self.touchConn = self.root.Touched:Connect(function(hit)
		self:_onTouch(hit)
	end)

	table.insert(registry, self)
	return self
end

function MonsterAI:_onTouch(hit)
	if self.paused or self.state ~= "Chase" or not self.target then
		return
	end
	local character = hit:FindFirstAncestorOfClass("Model")
	if not character or character ~= self.target then
		return
	end
	local player = Players:GetPlayerFromCharacter(character)
	if not player then
		return
	end
	if player:GetAttribute("State") ~= "Alive" then
		return
	end
	if os.clock() < (self.catchCooldown[player] or 0) then
		return
	end
	self.catchCooldown[player] = os.clock() + 2
	if catchHandler then
		catchHandler(player, self.def.id)
	end
	self.state = "Patrol"
	self.target = nil
end

local function playersToCheck()
	local list = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("State") == "Alive" and player.Character then
			local hum = player.Character:FindFirstChildOfClass("Humanoid")
			local root = player.Character:FindFirstChild("HumanoidRootPart")
			if hum and root and hum.Health > 0 and not player:GetAttribute("Invulnerable") then
				table.insert(list, { player = player, root = root })
			end
		end
	end
	return list
end

function MonsterAI:_canSee(targetRoot)
	local def = self.def
	local myPos = self.root.Position
	local toTarget = targetRoot.Position - myPos
	local dist = toTarget.Magnitude

	local range = def.sightRange
	if def.quirk == "darkBoost" and self:_inDarkCell() then
		range = range * 1.4
	end
	if dist > range then
		return false
	end

	local dir = toTarget.Unit
	local look = self.root.CFrame.LookVector
	local angle = math.deg(math.acos(math.clamp(look:Dot(dir), -1, 1)))
	if angle > def.sightAngle then
		return false
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { self.model }
	local result = workspace:Raycast(myPos, toTarget, params)
	if result and not result.Instance:IsDescendantOf(targetRoot.Parent) then
		return false
	end
	return true
end

function MonsterAI:_inDarkCell()
	local cellSize = self.maze.cellSize
	local x = math.floor(self.root.Position.X / cellSize) + 1
	local y = math.floor(self.root.Position.Z / cellSize) + 1
	x = math.clamp(x, 1, self.maze.gridWidth)
	y = math.clamp(y, 1, self.maze.gridHeight)
	-- Cheap proxy: rail cells are the well-lit main aisles.
	return not (self.maze.isRailIndex(x) or self.maze.isRailIndex(y))
end

function MonsterAI:_scanForTargets()
	local best, bestDist
	for _, entry in ipairs(playersToCheck()) do
		if self:_canSee(entry.root) then
			local d = (entry.root.Position - self.root.Position).Magnitude
			if not bestDist or d < bestDist then
				bestDist = d
				best = entry
			end
		end
	end
	return best
end

function MonsterAI:ReceiveAlert(position)
	if self.state == "Chase" then
		return
	end
	self.state = "Investigate"
	self.investigatePos = position
end

function MonsterAI.BroadcastNoise(position, radius)
	for _, monster in ipairs(registry) do
		if not monster.paused and not monster.destroyed then
			local d = (monster.root.Position - position).Magnitude
			if d <= radius then
				monster:ReceiveAlert(position)
			end
		end
	end
end

function MonsterAI.BroadcastCallout(position, excludeMonster)
	for _, monster in ipairs(registry) do
		if monster ~= excludeMonster and not monster.paused and not monster.destroyed then
			monster:ReceiveAlert(position)
		end
	end
end

local function computeNavmeshPath(fromPos, toPos, agentScale)
	local path = PathfindingService:CreatePath({
		AgentRadius = 2 * agentScale,
		AgentHeight = 5 * agentScale,
		AgentCanJump = false,
		WaypointSpacing = 4,
	})
	local ok = pcall(function()
		path:ComputeAsync(fromPos, toPos)
	end)
	if not ok or path.Status ~= Enum.PathStatus.Success then
		return nil
	end
	local waypoints = {}
	for _, wp in ipairs(path:GetWaypoints()) do
		table.insert(waypoints, wp.Position)
	end
	return waypoints
end

function MonsterAI:_moveAlongPath(waypoints)
	self.currentPath = waypoints
	self.pathIndex = 1
end

function MonsterAI:_followCurrentPath(dt)
	if not self.currentPath or not self.currentPath[self.pathIndex] then
		return true
	end
	local targetPoint = self.currentPath[self.pathIndex]
	local flatDist = (Vector3.new(targetPoint.X, 0, targetPoint.Z) - Vector3.new(self.root.Position.X, 0, self.root.Position.Z)).Magnitude
	if flatDist < 3 then
		self.pathIndex += 1
		if not self.currentPath[self.pathIndex] then
			return true
		end
		targetPoint = self.currentPath[self.pathIndex]
	end
	self.humanoid:MoveTo(targetPoint)
	return false
end

function MonsterAI:_randomPatrolTarget()
	if self.def.quirk == "railOnly" then
		return self.waypointGraph:RandomNode()
	end
	local x = math.random(1, self.maze.gridWidth)
	local y = math.random(1, self.maze.gridHeight)
	return self.maze.cellToWorld(x, y)
end

function MonsterAI:_pathTo(destination)
	if self.def.quirk == "railOnly" then
		return self.waypointGraph:FindPath(self.root.Position, destination)
	end
	return computeNavmeshPath(self.root.Position, destination, self.def.scale)
end

-- Requests a path toward destination unless one is already in flight, and
-- throttles retries to once a second so a destination PathfindingService
-- can't reach (or a momentary navmesh hiccup) can't turn into a
-- ComputeAsync call on every single Heartbeat frame.
function MonsterAI:_ensurePath(destination)
	if self.currentPath and #self.currentPath > 0 then
		return
	end
	local now = os.clock()
	if self.nextPathAttempt and now < self.nextPathAttempt then
		return
	end
	self.nextPathAttempt = now + 1
	self:_moveAlongPath(self:_pathTo(destination) or {})
end

function MonsterAI:_applyQuirkSpeed(baseSpeed)
	local def = self.def
	if def.quirk == "snortBurst" and self.state == "Chase" then
		if math.random() < 0.02 then
			self.burstUntil = os.clock() + 0.6
		end
	elseif def.quirk == "rollDash" and self.state == "Chase" then
		if math.random() < 0.015 then
			self.burstUntil = os.clock() + 0.8
		end
	end
	if self.burstUntil and os.clock() < self.burstUntil then
		return baseSpeed * 1.5
	end
	return baseSpeed
end

function MonsterAI:Update(dt)
	if self.paused or self.destroyed then
		return
	end

	local def = self.def
	local now = os.clock()

	if self.state ~= "Chase" then
		local seen = self:_scanForTargets()
		if seen then
			self.state = "Chase"
			self.target = seen.player.Character
			self.lastSightTime = now
			self.currentPath = nil
			if def.quirk == "callout" then
				MonsterAI.BroadcastCallout(seen.root.Position, self)
			end
		end
	end

	if self.state == "Chase" then
		local root = self.target and self.target:FindFirstChild("HumanoidRootPart")
		local hum = self.target and self.target:FindFirstChildOfClass("Humanoid")
		if not root or not hum or hum.Health <= 0 then
			self.state = "Search"
			self.currentPath = nil
		else
			if self:_canSee(root) then
				self.lastSightTime = now
				self.lastKnownPos = root.Position
			elseif now - self.lastSightTime > def.loseSightTime then
				self.state = "Search"
				self.currentPath = nil
			end

			if now - self.lastPathTime > def.repathInterval then
				self.lastPathTime = now
				self:_moveAlongPath(self:_pathTo(root.Position) or {})
			end
			self.humanoid.WalkSpeed = self:_applyQuirkSpeed(def.chaseSpeed)
			self:_followCurrentPath(dt)
			return
		end
	end

	if self.state == "Search" then
		self.humanoid.WalkSpeed = def.investigateSpeed
		self.searchUntil = self.searchUntil or (now + 4)
		self:_ensurePath(self.lastKnownPos or self:_randomPatrolTarget())
		local reachedEnd = self:_followCurrentPath(dt)
		if reachedEnd and (self.searchUntil and now > self.searchUntil) then
			self.state = "Patrol"
			self.searchUntil = nil
			self.currentPath = nil
		end
		return
	end

	if self.state == "Investigate" then
		self.humanoid.WalkSpeed = def.investigateSpeed
		self:_ensurePath(self.investigatePos)
		local reachedEnd = self:_followCurrentPath(dt)
		if reachedEnd then
			self.state = "Patrol"
			self.currentPath = nil
		end
		return
	end

	-- Patrol (default)
	self.humanoid.WalkSpeed = def.patrolSpeed
	self:_ensurePath(self:_randomPatrolTarget())
	local reachedEnd = self:_followCurrentPath(dt)
	if reachedEnd then
		self.currentPath = nil
	end
end

function MonsterAI:TeleportTo(position)
	self.model:PivotTo(CFrame.new(position + Vector3.new(0, 3, 0)))
	self.currentPath = nil
	self.state = "Patrol"
	self.target = nil
end

function MonsterAI:SetPaused(paused)
	self.paused = paused
	if paused then
		self.humanoid:MoveTo(self.root.Position)
	end
end

function MonsterAI:Destroy()
	self.destroyed = true
	if self.touchConn then
		self.touchConn:Disconnect()
	end
	for i, m in ipairs(registry) do
		if m == self then
			table.remove(registry, i)
			break
		end
	end
	self.model:Destroy()
end

function MonsterAI.GetAll()
	return registry
end

return MonsterAI
