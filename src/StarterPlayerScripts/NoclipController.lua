-- Debug-only free-fly for the /spectate and /back chat commands
-- (Main.server.lua). The server (PlayerService:EnableNoclip/DisableNoclip)
-- only flips state -- makes the character invisible/intangible, sets the
-- "Flying" attribute, and Anchors the HumanoidRootPart, which takes the
-- whole rig out of physics entirely (no gravity, no collision response,
-- nothing left for anything to fight). This script is what actually moves
-- the character while "Flying" is true: it directly translates root.CFrame
-- every frame by a camera-relative direction, since an Anchored part won't
-- go anywhere on its own. An earlier version drove flight through
-- AssemblyLinearVelocity with PlatformStand instead of Anchored, and that
-- fought the PlatformStand ragdoll physics -- glitchy, and still capable of
-- getting hung up on walls. Direct CFrame translation on an Anchored part
-- has nothing to fight: no velocity, no collision resolution, so it goes
-- exactly where it's told, through anything.

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local NoclipController = {}

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
	end

	local function startFlying()
		if renderConn then
			return
		end
		renderConn = RunService.RenderStepped:Connect(stepFlight)
	end

	local function stopFlying()
		if renderConn then
			renderConn:Disconnect()
			renderConn = nil
		end
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
