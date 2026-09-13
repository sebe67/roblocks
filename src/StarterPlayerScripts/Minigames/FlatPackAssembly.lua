-- "Flat-Pack Rage Build" -- a Simon-says panel sequence that grows by one
-- each correct round. A wrong panel resets progress to zero, per the
-- station's tagline. Beat config.roundsToWin full sequences before the
-- overall timer runs out.

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
local SoundKit = require(game:GetService("ReplicatedStorage").Shared.SoundKit)
local UIUtil = require(script.Parent.Parent.UIUtil)
local RetroTheme = require(script.Parent.RetroTheme)

local PANEL_COLORS = {
	Color3.fromRGB(210, 50, 50),
	Color3.fromRGB(60, 170, 90),
	Color3.fromRGB(0, 81, 186),
	Color3.fromRGB(255, 218, 26),
}

local FlatPackAssembly = {}

function FlatPackAssembly.Play(container, config, onComplete)
	local finished = false
	local deadline = os.clock() + config.duration
	local sequence = {}
	local playerIndex = 1
	local accepting = false
	local roundsCompleted = 0

	local statusLabel = RetroTheme.label({
		Size = UDim2.new(1, 0, 0.18, 0),
		TextScaled = true,
		TextStrokeTransparency = 0,
		Text = "Watch the sequence...",
	})
	statusLabel.Parent = container

	local progressLabel = RetroTheme.label({
		Size = UDim2.new(1, 0, 0.1, 0),
		Position = UDim2.new(0, 0, 0.18, 0),
		TextScaled = true,
		TextColor3 = RetroTheme.Colors.Dim,
		Text = "",
	})
	progressLabel.Parent = container

	local panelHolder = UIUtil.frame({
		Size = UDim2.new(1, 0, 0.55, 0),
		Position = UDim2.new(0, 0, 0.35, 0),
		BackgroundTransparency = 1,
	})
	panelHolder.Parent = container
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.new(0.45, 0, 0.45, 0)
	layout.CellPadding = UDim2.new(0.05, 0, 0.08, 0)
	layout.Parent = panelHolder

	local function updateProgressLabel()
		progressLabel.Text = string.format("Builds completed: %d / %d", roundsCompleted, config.roundsToWin)
	end

	local playNextRound

	-- Click-confirmation flash: a white ring pulse + a quick size "pop" on
	-- whichever panel was just clicked, independent of the round's own
	-- watch/replay color animation, so the player always sees their click
	-- registered even before the correct/wrong outcome resolves.
	local function flashClick(btn)
		local stroke = btn:FindFirstChild("ClickFlash")
		local scale = btn:FindFirstChildOfClass("UIScale")
		if stroke then
			stroke.Transparency = 0
			TweenService:Create(stroke, TweenInfo.new(0.25, Enum.EasingStyle.Quad), { Transparency = 1 }):Play()
		end
		if scale then
			scale.Scale = 1.15
			TweenService:Create(scale, TweenInfo.new(0.15, Enum.EasingStyle.Quad), { Scale = 1 }):Play()
		end
	end

	local panels = {}
	for i, color in ipairs(PANEL_COLORS) do
		local btn = UIUtil.button({ BackgroundColor3 = color, Text = "", AutoButtonColor = false })
		btn.Parent = panelHolder
		panels[i] = btn

		-- Permanent thin black pixel-art outline (retro look), separate from
		-- the white click-flash ring below it.
		RetroTheme.outline(btn, Color3.new(0, 0, 0), 2)

		local stroke = Instance.new("UIStroke")
		stroke.Name = "ClickFlash"
		stroke.Thickness = 5
		stroke.Color = Color3.new(1, 1, 1)
		stroke.Transparency = 1
		stroke.Parent = btn

		local scale = Instance.new("UIScale")
		scale.Scale = 1
		scale.Parent = btn

		btn.MouseButton1Click:Connect(function()
			if not accepting or finished then
				return
			end
			SoundKit.PlayUI(Config.Sounds.UIClick, { Volume = 0.4 })
			flashClick(btn)
			if i == sequence[playerIndex] then
				playerIndex += 1
				if playerIndex > #sequence then
					roundsCompleted += 1
					updateProgressLabel()
					if roundsCompleted >= config.roundsToWin then
						finished = true
						onComplete(true)
						return
					end
					accepting = false
					task.delay(0.4, playNextRound)
				end
			else
				statusLabel.Text = "WRONG PANEL. Starting over."
				sequence = {}
				roundsCompleted = 0
				updateProgressLabel()
				accepting = false
				task.delay(0.8, playNextRound)
			end
		end)
	end

	playNextRound = function()
		if finished then
			return
		end
		accepting = false
		playerIndex = 1
		table.insert(sequence, math.random(1, #panels))
		statusLabel.Text = "Watch closely..."
		task.spawn(function()
			for _, idx in ipairs(sequence) do
				panels[idx].BackgroundColor3 = Color3.new(1, 1, 1)
				task.wait(0.35)
				panels[idx].BackgroundColor3 = PANEL_COLORS[idx]
				task.wait(0.15)
			end
			if not finished then
				statusLabel.Text = "Your turn!"
				accepting = true
			end
		end)
	end
	playNextRound()
	updateProgressLabel()

	local conn = RunService.Heartbeat:Connect(function()
		if finished then
			return
		end
		if os.clock() > deadline then
			finished = true
			onComplete(false, "timeout")
		end
	end)

	return function()
		if conn then
			conn:Disconnect()
		end
	end
end

return FlatPackAssembly
