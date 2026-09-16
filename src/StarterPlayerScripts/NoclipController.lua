-- Debug-only free-fly for the /spectate, /spectate2, and /back chat
-- commands (Main.server.lua). The server (PlayerService:_beginFlight/
-- EndFlight) only flips state -- makes the character invisible/
-- intangible and sets the "Flying" attribute; this script is what
-- actually moves the character while "Flying" is true, by directly
-- translating root.CFrame every frame by a camera-relative direction.
--
-- /spectate Anchors the root server-side (nothing to fight -- no
-- gravity, no collision response possible -- so it goes exactly where
-- it's told, through anything). /spectate2 deliberately does NOT anchor
-- (see _beginFlight's comment for why: the server needs your real
-- position for monster detection to mean anything, and an Anchored part
-- has no network ownership, so this script's CFrame writes would never
-- replicate). This script doesn't need to know which mode is active --
-- it always sets AssemblyLinearVelocity to zero right after positioning,
-- which is a harmless no-op on an Anchored part but, on /spectate2's
-- unanchored one, stops gravity from accumulating real velocity between
-- our CFrame overrides (a direct CFrame set doesn't clear existing
-- velocity on its own, so without this the character would pick up a
-- growing downward velocity fighting each frame's reposition).
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

		root.CFrame = root.CFrame + move * Config.Noclip.FlySpeed * dt
		root.AssemblyLinearVelocity = Vector3.new()
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
