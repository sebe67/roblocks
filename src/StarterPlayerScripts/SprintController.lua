-- Infinite sprint: hold Shift for SprintSpeed, release for normal WalkSpeed.
-- No stamina meter by design.

local UserInputService = game:GetService("UserInputService")
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local SprintController = {}

local function isShift(keyCode)
	return keyCode == Enum.KeyCode.LeftShift or keyCode == Enum.KeyCode.RightShift
end

function SprintController.Init(context)
	local player = context.player
	local sprinting = false

	local function applySpeed()
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.WalkSpeed = sprinting and Config.Player.SprintSpeed or Config.Player.WalkSpeed
		end
	end

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if isShift(input.KeyCode) then
			sprinting = true
			applySpeed()
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if isShift(input.KeyCode) then
			sprinting = false
			applySpeed()
		end
	end)

	player.CharacterAdded:Connect(function()
		task.wait()
		applySpeed()
	end)
end

return SprintController
