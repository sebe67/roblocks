-- Debug-only free-fly for the /spectate, /spectate2, and /back chat
-- commands (Main.server.lua). The server (PlayerService:_beginFlight/
-- EndFlight) only flips state -- makes the character invisible/
-- intangible and sets the "Flying" attribute; this script is what
-- actually moves the character while "Flying" is true.
--
-- The two modes need genuinely different movement, because they end up
-- with different root physics server-side:
--   /spectate  -- root stays Anchored (nothing server-side needs your
--                  real position, so this is fine, and is what fixed
--                  this mode's original glitchiness). Anchored parts
--                  ignore velocity/constraints entirely, so direct
--                  CFrame translation is the only thing that moves one.
--   /spectate2 -- root stays unanchored (it needs to keep its default
--                  network ownership so its real position replicates to
--                  the server -- see _beginFlight's comment). This
--                  script drives it through the LinearVelocity
--                  constraint _beginFlight attached to it
--                  ("NoclipVelocity") instead of writing CFrame
--                  directly: that constraint is evaluated by the physics
--                  engine every physics step, not just once per rendered
--                  frame, so gravity never gets a window between our
--                  corrections to accumulate a visible sink in -- which
--                  a once-per-render CFrame/velocity write couldn't
--                  fully prevent.
--
-- Detecting which mode is active is just "does NoclipVelocity exist,"
-- so this script doesn't need to know about Untouchable/Invulnerable at
-- all.
--
-- An earlier version drove flight through AssemblyLinearVelocity with
-- PlatformStand instead of Anchored, and that fought the PlatformStand
-- ragdoll physics -- glitchy, and still capable of getting hung up on
-- walls. It also makes the ceiling see-through (client-only, see
-- setCeilingXray below) so monsters are easier to spot from above while
-- flying.

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local NoclipController = {}

-- Ceiling parts are shared geometry -- setting their real Transparency
-- would make the roof see-through for every player, not just whoever's
-- flying. LocalTransparencyModifier is the client-only equivalent: it
-- overrides how a part renders for THIS client alone, invisible to
-- everyone else and never replicated. Looked up once and cached, since
-- MazeGenerator only ever builds this folder once at server boot.
local cachedCeilingFolder = nil
local function getCeilingFolder()
	if cachedCeilingFolder then
		return cachedCeilingFolder
	end
	local store = workspace:FindFirstChild("Store")
	cachedCeilingFolder = store and store:FindFirstChild("Ceiling")
	return cachedCeilingFolder
end

local function setCeilingXray(seeThrough)
	local folder = getCeilingFolder()
	if not folder then
		return
	end
	for _, part in ipairs(folder:GetChildren()) do
		if part:IsA("BasePart") then
			part.LocalTransparencyModifier = seeThrough and 1 or 0
		end
	end
end

function NoclipController.Init(context)
	local player = context.player
	local camera = workspace.CurrentCamera
	local renderConn = nil

	local function stepFlight(dt)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not root then
			return
		end

		local move = Vector3.new()
		if UserInputService:IsKeyDown(Enum.KeyCode.W) then
			move += camera.CFrame.LookVector
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.S) then
			move -= camera.CFrame.LookVector
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.D) then
			move += camera.CFrame.RightVector
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.A) then
			move -= camera.CFrame.RightVector
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
			move += Vector3.new(0, 1, 0)
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
			move -= Vector3.new(0, 1, 0)
		end

		if move.Magnitude > 0 then
			move = move.Unit
		end

		local velocity = root:FindFirstChild("NoclipVelocity")
		if velocity then
			velocity.VectorVelocity = move * Config.Noclip.FlySpeed
		else
			root.CFrame = root.CFrame + move * Config.Noclip.FlySpeed * dt
		end
	end

	local function startFlying()
		if renderConn then
			return
		end
		renderConn = RunService.RenderStepped:Connect(stepFlight)
		setCeilingXray(true)
	end

	local function stopFlying()
		if renderConn then
			renderConn:Disconnect()
			renderConn = nil
		end
		setCeilingXray(false)
	end

	player:GetAttributeChangedSignal("Flying"):Connect(function()
		if player:GetAttribute("Flying") then
			startFlying()
		else
			stopFlying()
		end
	end)

	if player:GetAttribute("Flying") then
		startFlying()
	end
end

return NoclipController
