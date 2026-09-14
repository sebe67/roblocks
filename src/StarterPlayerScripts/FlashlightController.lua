-- Press F to toggle your flashlight. The light itself (a SpotLight on the
-- Head) is created and toggled server-side (PlayerService.lua) so it's a
-- real, replicated light every other player can see, not just a local
-- effect for its own owner -- this script only sends the request.

local UserInputService = game:GetService("UserInputService")
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
local Net = require(game:GetService("ReplicatedStorage").Shared.Net)
local SoundKit = require(game:GetService("ReplicatedStorage").Shared.SoundKit)

local FlashlightController = {}

function FlashlightController.Init(context)
	local flashlightEvent = Net.GetEvent("ToggleFlashlight")

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.F then
			flashlightEvent:FireServer()
			SoundKit.PlayUI(Config.Sounds.UIClick, { Volume = 0.4 })
		end
	end)
end

return FlashlightController
