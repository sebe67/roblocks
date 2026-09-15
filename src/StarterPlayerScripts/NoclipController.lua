-- Debug-only free-fly for the /spectate and /back chat commands
-- (Main.server.lua). The server (PlayerService:EnableNoclip/DisableNoclip)
-- only flips state -- makes the character invisible/intangible and sets
-- the "Flying" attribute -- it doesn't drive movement itself. This script
-- is what actually moves the character while "Flying" is true, by writing
-- camera-relative velocity straight onto the HumanoidRootPart every frame
-- (the Humanoid's own WalkSpeed-driven control is suspended by
-- PlatformStand while noclip is on, so there's nothing to fight over).

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local NoclipController = {}

function NoclipController.Init(context)
	local player = context.player
	local camera = workspace.CurrentCamera
	local renderConn = nil

	local function stepFlight()
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
		root.AssemblyLinearVelocity = move * Config.Noclip.FlySpeed
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
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root then
			root.AssemblyLinearVelocity = Vector3.new()
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
