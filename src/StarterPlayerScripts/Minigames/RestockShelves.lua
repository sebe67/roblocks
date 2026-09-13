-- "Restock: Aisle of Regret" -- click the button matching the named color
-- before the whole-minigame timer (config.duration) runs out.

local RunService = game:GetService("RunService")
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
local SoundKit = require(game:GetService("ReplicatedStorage").Shared.SoundKit)
local UIUtil = require(script.Parent.Parent.UIUtil)
local RetroTheme = require(script.Parent.RetroTheme)

local COLORS = {
	{ name = "Blue", color = Color3.fromRGB(0, 81, 186) },
	{ name = "Yellow", color = Color3.fromRGB(255, 218, 26) },
	{ name = "Red", color = Color3.fromRGB(210, 50, 50) },
	{ name = "Green", color = Color3.fromRGB(60, 170, 90) },
}

local RestockShelves = {}

function RestockShelves.Play(container, config, onComplete)
	local finished = false
	local progress = 0
	local deadline = os.clock() + config.duration
	local currentTarget

	local targetLabel = RetroTheme.label({
		Size = UDim2.new(1, 0, 0.25, 0),
		TextScaled = true,
		TextStrokeTransparency = 0,
		Text = "",
	})
	targetLabel.Parent = container

	local progressLabel = RetroTheme.label({
		Size = UDim2.new(1, 0, 0.12, 0),
		Position = UDim2.new(0, 0, 0.25, 0),
		TextScaled = true,
		TextColor3 = RetroTheme.Colors.Dim,
		Text = "",
	})
	progressLabel.Parent = container

	local buttonHolder = UIUtil.frame({
		Size = UDim2.new(1, 0, 0.5, 0),
		Position = UDim2.new(0, 0, 0.42, 0),
		BackgroundTransparency = 1,
	})
	buttonHolder.Parent = container
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.new(0.45, 0, 0.45, 0)
	layout.CellPadding = UDim2.new(0.05, 0, 0.08, 0)
	layout.Parent = buttonHolder

	local pickTarget
	local function updateProgressLabel(prefix)
		progressLabel.Text = string.format("%sRestocked: %d / %d", prefix or "", progress, config.roundsToWin)
	end

	for _, c in ipairs(COLORS) do
		local btn = RetroTheme.button({
			BackgroundColor3 = c.color,
			Text = c.name,
			TextScaled = true,
		})
		btn.Parent = buttonHolder
		btn.MouseButton1Click:Connect(function()
			if finished then
				return
			end
			SoundKit.PlayUI(Config.Sounds.UIClick, { Volume = 0.4 })
			if currentTarget and c.name == currentTarget.name then
				progress += 1
				updateProgressLabel()
				if progress >= config.roundsToWin then
					finished = true
					onComplete(true)
					return
				end
			end
			pickTarget()
		end)
	end

	pickTarget = function()
		currentTarget = COLORS[math.random(1, #COLORS)]
		targetLabel.Text = "Shelve the " .. currentTarget.name .. " box!"
		targetLabel.TextColor3 = currentTarget.color
	end
	pickTarget()
	updateProgressLabel()

	local conn = RunService.Heartbeat:Connect(function()
		if finished then
			return
		end
		if os.clock() > deadline then
			finished = true
			onComplete(false)
		end
	end)

	return function()
		if conn then
			conn:Disconnect()
		end
	end
end

return RestockShelves
