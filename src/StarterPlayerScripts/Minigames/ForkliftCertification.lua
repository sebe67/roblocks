-- "Forklift Certification" -- hold Up/Down (or the on-screen buttons) to
-- keep your marker inside a slowly drifting target zone. Continuous
-- tracking/steering, not a discrete click or timed press -- the third
-- distinct interaction style in the roster.

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local UIUtil = require(script.Parent.Parent.UIUtil)
local RetroTheme = require(script.Parent.RetroTheme)

local ZONE_HALF_HEIGHT = 0.11
local MOVE_SPEED = 0.7
local ZONE_DRIFT_SPEED = 0.6
local TICK_INTERVAL = 0.5

local ForkliftCertification = {}

function ForkliftCertification.Play(container, config, onComplete)
	local finished = false
	local deadline = os.clock() + config.duration
	local ticks = 0

	local statusLabel = RetroTheme.label({
		Size = UDim2.new(1, 0, 0.14, 0),
		TextScaled = true,
		TextStrokeTransparency = 0,
		Text = "Hold UP/DOWN (or the buttons) to stay in the lane.",
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

	local track = UIUtil.frame({
		Size = UDim2.new(0.18, 0, 0.55, 0),
		Position = UDim2.new(0.41, 0, 0.28, 0),
		BackgroundColor3 = Color3.fromRGB(50, 50, 55),
	})
	track.Parent = container
	RetroTheme.outline(track, Color3.new(0, 0, 0), 2)

	local targetZone = UIUtil.frame({
		Size = UDim2.new(1, 0, ZONE_HALF_HEIGHT * 2, 0),
		Position = UDim2.new(0, 0, 0.5 - ZONE_HALF_HEIGHT, 0),
		BackgroundColor3 = Color3.fromRGB(60, 190, 90),
	})
	targetZone.Parent = track

	local marker = UIUtil.frame({
		Size = UDim2.new(1.3, 0, 0.04, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
	})
	marker.Parent = track

	local upBtn = RetroTheme.button({
		Size = UDim2.new(0.14, 0, 0.1, 0),
		Position = UDim2.new(0.62, 0, 0.32, 0),
		Text = "UP",
		TextScaled = true,
		BackgroundColor3 = Color3.fromRGB(0, 81, 186),
	})
	upBtn.Parent = container
	local downBtn = RetroTheme.button({
		Size = UDim2.new(0.14, 0, 0.1, 0),
		Position = UDim2.new(0.62, 0, 0.46, 0),
		Text = "DOWN",
		TextScaled = true,
		BackgroundColor3 = Color3.fromRGB(0, 81, 186),
	})
	downBtn.Parent = container

	local function updateProgressLabel()
		progressLabel.Text = string.format("Certified: %d / %d", ticks, config.roundsToWin)
	end
	updateProgressLabel()

	local markerPos = 0.5
	local zoneCenter = 0.5
	local holdingUp, holdingDown = false, false

	local function setHeld(dir, held)
		if dir == "up" then
			holdingUp = held
		else
			holdingDown = held
		end
	end

	local inputBeganConn = UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.Up or input.KeyCode == Enum.KeyCode.W then
			setHeld("up", true)
		elseif input.KeyCode == Enum.KeyCode.Down or input.KeyCode == Enum.KeyCode.S then
			setHeld("down", true)
		end
	end)
	local inputEndedConn = UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Up or input.KeyCode == Enum.KeyCode.W then
			setHeld("up", false)
		elseif input.KeyCode == Enum.KeyCode.Down or input.KeyCode == Enum.KeyCode.S then
			setHeld("down", false)
		end
	end)
	upBtn.MouseButton1Down:Connect(function()
		setHeld("up", true)
	end)
	upBtn.MouseButton1Up:Connect(function()
		setHeld("up", false)
	end)
	upBtn.MouseLeave:Connect(function()
		setHeld("up", false)
	end)
	downBtn.MouseButton1Down:Connect(function()
		setHeld("down", true)
	end)
	downBtn.MouseButton1Up:Connect(function()
		setHeld("down", false)
	end)
	downBtn.MouseLeave:Connect(function()
		setHeld("down", false)
	end)

	local tickAccumulator = 0
	local conn = RunService.Heartbeat:Connect(function(dt)
		if finished then
			return
		end

		zoneCenter = 0.5 + 0.35 * math.sin(os.clock() * ZONE_DRIFT_SPEED)
		targetZone.Position = UDim2.new(0, 0, zoneCenter - ZONE_HALF_HEIGHT, 0)

		if holdingUp then
			markerPos -= dt * MOVE_SPEED
		end
		if holdingDown then
			markerPos += dt * MOVE_SPEED
		end
		markerPos = math.clamp(markerPos, 0, 1)
		marker.Position = UDim2.new(0.5, 0, markerPos, 0)

		if math.abs(markerPos - zoneCenter) < ZONE_HALF_HEIGHT then
			tickAccumulator += dt
			if tickAccumulator >= TICK_INTERVAL then
				tickAccumulator = 0
				ticks += 1
				updateProgressLabel()
				if ticks >= config.roundsToWin then
					finished = true
					onComplete(true)
					return
				end
			end
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
		if inputBeganConn then
			inputBeganConn:Disconnect()
		end
		if inputEndedConn then
			inputEndedConn:Disconnect()
		end
	end
end

return ForkliftCertification
