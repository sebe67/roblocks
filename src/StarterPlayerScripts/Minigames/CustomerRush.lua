-- "Customer Service Rush" -- several registers light up together each
-- round; click all of them before they reset. Multi-target reaction,
-- deliberately different from the single-target games.

local RunService = game:GetService("RunService")
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
local SoundKit = require(game:GetService("ReplicatedStorage").Shared.SoundKit)
local UIUtil = require(script.Parent.Parent.UIUtil)
local RetroTheme = require(script.Parent.RetroTheme)

local GRID_COUNT = 9
local LIT_PER_ROUND = 3
local ROUND_TIME = 2.2

local CustomerRush = {}

function CustomerRush.Play(container, config, onComplete)
	local finished = false
	local progress = 0
	local deadline = os.clock() + config.duration

	local statusLabel = RetroTheme.label({
		Size = UDim2.new(1, 0, 0.14, 0),
		TextScaled = true,
		TextStrokeTransparency = 0,
		Text = "Click every lit register!",
	})
	statusLabel.Parent = container

	local progressLabel = RetroTheme.label({
		Size = UDim2.new(1, 0, 0.1, 0),
		Position = UDim2.new(0, 0, 0.14, 0),
		TextScaled = true,
		TextColor3 = RetroTheme.Colors.Dim,
		Text = "",
	})
	progressLabel.Parent = container

	local gridHolder = UIUtil.frame({
		Size = UDim2.new(0.8, 0, 0.65, 0),
		Position = UDim2.new(0.1, 0, 0.28, 0),
		BackgroundTransparency = 1,
	})
	gridHolder.Parent = container
	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.new(0.31, 0, 0.31, 0)
	gridLayout.CellPadding = UDim2.new(0.03, 0, 0.03, 0)
	gridLayout.Parent = gridHolder

	local function updateProgressLabel()
		progressLabel.Text = string.format("Cleared: %d / %d", progress, config.roundsToWin)
	end
	updateProgressLabel()

	local IDLE_COLOR = Color3.fromRGB(60, 60, 70)
	local LIT_COLOR = Color3.fromRGB(80, 220, 220)
	local CLEARED_COLOR = Color3.fromRGB(60, 170, 90)

	local buttons = {}
	for i = 1, GRID_COUNT do
		local btn = RetroTheme.button({
			BackgroundColor3 = IDLE_COLOR,
			Text = "",
		})
		btn.Parent = gridHolder
		buttons[i] = btn
	end

	local litSet = {}
	local roundDeadline = 0

	local function newRound()
		for _, btn in ipairs(buttons) do
			btn.BackgroundColor3 = IDLE_COLOR
		end
		litSet = {}
		local indices = {}
		for i = 1, GRID_COUNT do
			indices[i] = i
		end
		for i = GRID_COUNT, 2, -1 do
			local j = math.random(1, i)
			indices[i], indices[j] = indices[j], indices[i]
		end
		for i = 1, LIT_PER_ROUND do
			litSet[indices[i]] = true
			buttons[indices[i]].BackgroundColor3 = LIT_COLOR
		end
		roundDeadline = os.clock() + ROUND_TIME
	end

	for i, btn in ipairs(buttons) do
		btn.MouseButton1Click:Connect(function()
			if finished or not litSet[i] then
				return
			end
			SoundKit.PlayUI(Config.Sounds.UIClick, { Volume = 0.4 })
			litSet[i] = nil
			btn.BackgroundColor3 = CLEARED_COLOR
			local anyLit = false
			for _ in pairs(litSet) do
				anyLit = true
				break
			end
			if not anyLit then
				progress += 1
				updateProgressLabel()
				if progress >= config.roundsToWin then
					finished = true
					onComplete(true)
					return
				end
				task.delay(0.2, newRound)
			end
		end)
	end
	newRound()

	local conn = RunService.Heartbeat:Connect(function()
		if finished then
			return
		end
		if os.clock() > deadline then
			finished = true
			onComplete(false, "timeout")
			return
		end
		if os.clock() > roundDeadline then
			newRound()
		end
	end)

	return function()
		if conn then
			conn:Disconnect()
		end
	end
end

return CustomerRush
