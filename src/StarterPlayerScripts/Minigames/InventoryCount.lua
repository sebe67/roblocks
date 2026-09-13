-- "Inventory Count" -- memorize a briefly-flashed shelf of colored boxes,
-- then answer how many matched the asked color. Observation/recall, not
-- reaction speed -- deliberately different from the other stations.

local RunService = game:GetService("RunService")
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
local SoundKit = require(game:GetService("ReplicatedStorage").Shared.SoundKit)
local UIUtil = require(script.Parent.Parent.UIUtil)

local COLORS = {
	{ name = "Blue", color = Color3.fromRGB(0, 81, 186) },
	{ name = "Yellow", color = Color3.fromRGB(255, 218, 26) },
	{ name = "Red", color = Color3.fromRGB(210, 50, 50) },
	{ name = "Green", color = Color3.fromRGB(60, 170, 90) },
}
local GRID_SIZE = 9
local FLASH_TIME = 2

local InventoryCount = {}

function InventoryCount.Play(container, config, onComplete)
	local finished = false
	local progress = 0
	local deadline = os.clock() + config.duration

	local statusLabel = UIUtil.label({
		Size = UDim2.new(1, 0, 0.16, 0),
		TextScaled = true,
		TextStrokeTransparency = 0,
		Text = "Memorize the shelf...",
	})
	statusLabel.Parent = container

	local progressLabel = UIUtil.label({
		Size = UDim2.new(1, 0, 0.1, 0),
		Position = UDim2.new(0, 0, 0.16, 0),
		TextScaled = true,
		TextColor3 = Color3.fromRGB(200, 200, 200),
		Text = "",
	})
	progressLabel.Parent = container

	local gridHolder = UIUtil.frame({
		Size = UDim2.new(0.7, 0, 0.5, 0),
		Position = UDim2.new(0.15, 0, 0.28, 0),
		BackgroundTransparency = 1,
	})
	gridHolder.Parent = container
	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.new(0.3, 0, 0.3, 0)
	gridLayout.CellPadding = UDim2.new(0.03, 0, 0.05, 0)
	gridLayout.Parent = gridHolder

	local answerHolder = UIUtil.frame({
		Size = UDim2.new(0.8, 0, 0.18, 0),
		Position = UDim2.new(0.1, 0, 0.78, 0),
		BackgroundTransparency = 1,
	})
	answerHolder.Parent = container
	local answerLayout = Instance.new("UIGridLayout")
	answerLayout.CellSize = UDim2.new(0.22, 0, 0.9, 0)
	answerLayout.CellPadding = UDim2.new(0.03, 0, 0, 0)
	answerLayout.Parent = answerHolder

	local function updateProgressLabel()
		progressLabel.Text = string.format("Correct: %d / %d", progress, config.roundsToWin)
	end
	updateProgressLabel()

	local accepting = false
	local playRound

	local function clearChildren(holder, class)
		for _, child in ipairs(holder:GetChildren()) do
			if child:IsA(class) then
				child:Destroy()
			end
		end
	end

	playRound = function()
		if finished then
			return
		end
		accepting = false
		clearChildren(gridHolder, "Frame")
		clearChildren(answerHolder, "TextButton")
		statusLabel.Text = "Memorize the shelf..."

		local targetColor = COLORS[math.random(1, #COLORS)]
		local counts = {}
		for _, c in ipairs(COLORS) do
			counts[c.name] = 0
		end
		for _ = 1, GRID_SIZE do
			local c = COLORS[math.random(1, #COLORS)]
			counts[c.name] += 1
			local swatch = UIUtil.frame({ BackgroundColor3 = c.color })
			swatch.Parent = gridHolder
		end

		task.delay(FLASH_TIME, function()
			if finished then
				return
			end
			clearChildren(gridHolder, "Frame")
			statusLabel.Text = "How many " .. targetColor.name .. " boxes were there?"

			local correctCount = counts[targetColor.name]
			local options = { correctCount }
			while #options < 4 do
				local guess = math.random(0, GRID_SIZE)
				local dup = false
				for _, o in ipairs(options) do
					if o == guess then
						dup = true
					end
				end
				if not dup then
					table.insert(options, guess)
				end
			end
			for i = #options, 2, -1 do
				local j = math.random(1, i)
				options[i], options[j] = options[j], options[i]
			end

			for _, n in ipairs(options) do
				local btn = UIUtil.button({
					BackgroundColor3 = Color3.fromRGB(60, 60, 70),
					Text = tostring(n),
					TextScaled = true,
				})
				btn.Parent = answerHolder
				btn.MouseButton1Click:Connect(function()
					if not accepting or finished then
						return
					end
					SoundKit.PlayUI(Config.Sounds.UIClick, { Volume = 0.4 })
					if n == correctCount then
						progress += 1
						updateProgressLabel()
						if progress >= config.roundsToWin then
							finished = true
							onComplete(true)
							return
						end
					end
					playRound()
				end)
			end
			accepting = true
		end)
	end
	playRound()

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

return InventoryCount
