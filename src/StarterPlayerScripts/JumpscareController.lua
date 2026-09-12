-- Full-screen flash + name card + a quick camera-FOV shake when the server
-- says a monster caught you. Swap the flash color for a real splash image
-- and add a scream SoundId once you have licensed/owned audio assets.

local TweenService = game:GetService("TweenService")
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
local Net = require(game:GetService("ReplicatedStorage").Shared.Net)
local UIUtil = require(script.Parent.UIUtil)

local JumpscareController = {}

local monsterById = {}
for _, def in ipairs(Config.Monsters) do
	monsterById[def.id] = def
end

function JumpscareController.Init(context)
	local gui = UIUtil.screenGui("JumpscareGui")
	gui.Enabled = false
	gui.DisplayOrder = 50
	gui.Parent = context.playerGui

	local flash = UIUtil.frame({
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0,
	})
	flash.Parent = gui

	local nameLabel = UIUtil.label({
		Size = UDim2.new(1, 0, 0.2, 0),
		Position = UDim2.new(0, 0, 0.72, 0),
		TextScaled = true,
		TextStrokeTransparency = 0,
		Text = "",
	})
	nameLabel.Parent = gui

	local flavorLabel = UIUtil.label({
		Size = UDim2.new(0.8, 0, 0.1, 0),
		Position = UDim2.new(0.1, 0, 0.85, 0),
		TextScaled = true,
		TextColor3 = Color3.fromRGB(220, 220, 220),
		Text = "",
	})
	flavorLabel.Parent = gui

	Net.GetEvent("Jumpscare").OnClientEvent:Connect(function(monsterId)
		local def = monsterById[monsterId]
		if not def then
			return
		end

		gui.Enabled = true
		flash.BackgroundColor3 = def.jumpscareColor
		flash.BackgroundTransparency = 0
		nameLabel.Text = string.upper(def.displayName) .. "!!"
		nameLabel.TextColor3 = def.accentColor
		flavorLabel.Text = def.flavor

		local camera = workspace.CurrentCamera
		task.spawn(function()
			local originalFov = camera.FieldOfView
			for _ = 1, 10 do
				camera.FieldOfView = originalFov + math.random(-4, 4)
				task.wait(0.03)
			end
			camera.FieldOfView = originalFov
		end)

		TweenService:Create(flash, TweenInfo.new(Config.Round.JumpscareDuration - 0.3), {
			BackgroundTransparency = 1,
		}):Play()

		task.delay(Config.Round.JumpscareDuration, function()
			gui.Enabled = false
		end)
	end)
end

return JumpscareController
