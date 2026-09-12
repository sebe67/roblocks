-- "Self-Checkout Vibe Check" -- press Scan (Space or the button) while a
-- bouncing marker sits inside the green zone. Hit config.roundsToWin scans
-- before the overall timer runs out.

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
local SoundKit = require(game:GetService("ReplicatedStorage").Shared.SoundKit)
local UIUtil = require(script.Parent.Parent.UIUtil)

local SelfCheckout = {}

function SelfCheckout.Play(container, config, onComplete)
	local finished = false
	local deadline = os.clock() + config.duration
	local scans = 0

	local statusLabel = UIUtil.label({
		Size = UDim2.new(1, 0, 0.15, 0),
		TextScaled = true,
		TextStrokeTransparency = 0,
		Text = "Press SPACE (or tap Scan) when the marker is in the green zone!",
	})
	statusLabel.Parent = container

	local progressLabel = UIUtil.label({
		Size = UDim2.new(1, 0, 0.1, 0),
		Position = UDim2.new(0, 0, 0.15, 0),
		TextScaled = true,
		TextColor3 = Color3.fromRGB(200, 200, 200),
		Text = "",
	})
	progressLabel.Parent = container

	local track = UIUtil.frame({
		Size = UDim2.new(0.9, 0, 0.15, 0),
		Position = UDim2.new(0.05, 0, 0.35, 0),
		BackgroundColor3 = Color3.fromRGB(50, 50, 55),
	})
	track.Parent = container

	local greenZone = UIUtil.frame({
		Size = UDim2.new(0.16, 0, 1, 0),
		Position = UDim2.new(0.42, 0, 0, 0),
		BackgroundColor3 = Color3.fromRGB(60, 190, 90),
	})
	greenZone.Parent = track

	local marker = UIUtil.frame({
		Size = UDim2.new(0.02, 0, 1.2, 0),
		Position = UDim2.new(0, 0, -0.1, 0),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
	})
	marker.Parent = track

	local scanBtn = UIUtil.button({
		Size = UDim2.new(0.3, 0, 0.15, 0),
		Position = UDim2.new(0.35, 0, 0.6, 0),
		BackgroundColor3 = Color3.fromRGB(0, 81, 186),
		Text = "SCAN",
		TextScaled = true,
	})
	scanBtn.Parent = container

	local t = 0
	local speed = 3.2

	local function updateProgressLabel(prefix)
		progressLabel.Text = string.format("%sScanned: %d / %d", prefix or "", scans, config.roundsToWin)
	end
	updateProgressLabel()

	local function attemptScan()
		if finished then
			return
		end
		SoundKit.PlayUI(Config.Sounds.UIClick, { Volume = 0.4 })
		local markerScale = marker.Position.X.Scale
		local zoneStart = greenZone.Position.X.Scale
		local zoneEnd = zoneStart + greenZone.Size.X.Scale
		if markerScale >= zoneStart and markerScale <= zoneEnd then
			scans += 1
			updateProgressLabel()
			if scans >= config.roundsToWin then
				finished = true
				onComplete(true)
			end
		else
			updateProgressLabel("MISSED! ")
		end
	end

	scanBtn.MouseButton1Click:Connect(attemptScan)
	local inputConn = UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.Space then
			attemptScan()
		end
	end)

	local conn = RunService.Heartbeat:Connect(function(dt)
		if finished then
			return
		end
		t += dt * speed
		local scale = (math.sin(t) + 1) / 2
		marker.Position = UDim2.new(scale, 0, -0.1, 0)
		if os.clock() > deadline then
			finished = true
			onComplete(false)
		end
	end)

	return function()
		if conn then
			conn:Disconnect()
		end
		if inputConn then
			inputConn:Disconnect()
		end
	end
end

return SelfCheckout
