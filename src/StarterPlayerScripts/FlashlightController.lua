-- Press F to toggle your flashlight. The light itself (a SpotLight on a
-- FlashlightAim part) is created and toggled server-side (PlayerService.lua)
-- so it's a real, replicated light every other player can see, not just a
-- local effect for its own owner -- this script only sends the toggle
-- request, plus a throttled camera-pitch report so the beam can tilt
-- up/down (see PlayerService:_applyFlashlightPitch for why that can't just
-- come from the character's own Head orientation).

local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
local Net = require(game:GetService("ReplicatedStorage").Shared.Net)
local SoundKit = require(game:GetService("ReplicatedStorage").Shared.SoundKit)

local FlashlightController = {}

-- No need to report every single RenderStepped frame -- the beam tilting a
-- little late is imperceptible, and this keeps it cheap over the network.
local REPORT_INTERVAL = 0.1

function FlashlightController.Init(context)
	local flashlightEvent = Net.GetEvent("ToggleFlashlight")
	local pitchEvent = Net.GetEvent("ReportFlashlightPitch")
	local camera = workspace.CurrentCamera

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.F then
			flashlightEvent:FireServer()
			SoundKit.PlayUI(Config.Sounds.UIClick, { Volume = 0.4 })
		end
	end)

	local nextReportAt = 0
	RunService.RenderStepped:Connect(function()
		local now = os.clock()
		if now < nextReportAt then
			return
		end
		nextReportAt = now + REPORT_INTERVAL
		local look = camera.CFrame.LookVector
		local pitch = math.asin(math.clamp(look.Y, -1, 1))
		pitchEvent:FireServer(pitch)
	end)
end

return FlashlightController
