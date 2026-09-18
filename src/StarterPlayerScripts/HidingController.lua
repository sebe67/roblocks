-- Two client-side jobs tied to the server's Hidden attribute/events
-- (HidingService.lua):
--
-- 1. Face outward on entry. HidingService:_enter already orients your
--    character (PivotTo) to face out through the wardrobe's door gap, but
--    that alone does nothing for what you actually SEE: Roblox's built-in
--    first-person camera script tracks its own independent look angle
--    (driven by mouse deltas) and reasserts it every frame regardless of
--    what the server just set your character's facing to -- so without
--    this you'd keep looking wherever your mouse already pointed, usually
--    the wall you just walked up to ("staring at the back of the closet").
--    Briefly flipping CameraType to Scriptable, setting the CFrame we
--    want, then back to Custom is the standard trick to force the built-in
--    camera script to resync its internal angle from a CFrame we chose
--    instead of the one it remembers.
-- 2. Show the MaxHideDuration warning/kick toast (HidingWarning/
--    HidingKicked events) -- a wardrobe isn't a permanent hideout.

local RunService = game:GetService("RunService")
local Net = require(game:GetService("ReplicatedStorage").Shared.Net)
local UIUtil = require(script.Parent.UIUtil)

local HidingController = {}

function HidingController.Init(context)
	local player = context.player
	local camera = workspace.CurrentCamera

	local gui = UIUtil.screenGui("HidingGui")
	gui.DisplayOrder = 15
	gui.Parent = context.playerGui

	local toast = UIUtil.label({
		Size = UDim2.new(0.6, 0, 0.06, 0),
		Position = UDim2.new(0.2, 0, 0.78, 0),
		TextScaled = true,
		TextStrokeTransparency = 0,
		TextColor3 = Color3.fromRGB(255, 210, 90),
		Text = "",
		Visible = false,
	})
	toast.Parent = gui

	player:GetAttributeChangedSignal("Hidden"):Connect(function()
		if not player:GetAttribute("Hidden") then
			toast.Visible = false
			return
		end

		-- Let the server's PivotTo finish replicating before we read the
		-- character's new position/orientation off of it.
		task.wait()
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not root then
			return
		end
		local head = character:FindFirstChild("Head")
		local eyeCFrame = CFrame.new((head or root).Position) * (root.CFrame - root.CFrame.Position)

		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = eyeCFrame
		RunService.RenderStepped:Wait()
		camera.CameraType = Enum.CameraType.Custom
	end)

	Net.GetEvent("HidingWarning").OnClientEvent:Connect(function(secondsLeft)
		toast.Text = string.format("Getting cramped in here... out in %ds", secondsLeft)
		toast.Visible = true
	end)

	Net.GetEvent("HidingKicked").OnClientEvent:Connect(function()
		toast.Text = "You couldn't stay hidden any longer!"
		toast.Visible = true
		task.delay(3, function()
			if toast.Text == "You couldn't stay hidden any longer!" then
				toast.Visible = false
			end
		end)
	end)
end

return HidingController
