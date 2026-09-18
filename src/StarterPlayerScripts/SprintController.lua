-- Hold Shift for SprintSpeed, release for normal WalkSpeed -- but sprinting
-- now drains a stamina meter over Config.Player.SprintDuration seconds of
-- continuous use. Hit empty and you're forced to walk until it regenerates
-- back up to MinSprintFraction (regen is faster while Hidden in a
-- wardrobe -- see HidingService.lua). A fade-in/out bar shows the meter
-- only while it's not full or you're actively trying to sprint.
--
-- Tracked entirely client-side, same as the sprint toggle itself always
-- was -- the server's own authoritative WalkSpeed writes (PlayerService's
-- CatchPlayer freeze, HidingService's Hidden freeze) are what actually keep
-- this un-cheatable, not the stamina math here. This script explicitly
-- skips writing WalkSpeed at all while Hidden, so it never fights that
-- server-side freeze.

local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
local UIUtil = require(script.Parent.UIUtil)
local StaminaState = require(script.Parent.StaminaState)

local SprintController = {}

local function isShift(keyCode)
	return keyCode == Enum.KeyCode.LeftShift or keyCode == Enum.KeyCode.RightShift
end

local function lerpColor(a, b, t)
	return Color3.new(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t)
end

local FULL_COLOR = Color3.fromRGB(90, 220, 130)
local EMPTY_COLOR = Color3.fromRGB(220, 60, 60)

function SprintController.Init(context)
	local player = context.player
	local holdingShift = false
	local stamina = 1 -- 0..1
	local exhausted = false

	-- Bar UI: a thin outline at the bottom-center of the screen with a fill
	-- that scales with `stamina`. barAlpha is a manually-lerped 0 (visible)
	-- .. 1 (fully faded out) value, driven from the same per-frame loop
	-- that updates stamina, so no extra Tween objects need to be created
	-- and torn down every time visibility changes.
	local gui = UIUtil.screenGui("StaminaGui")
	gui.DisplayOrder = 5
	gui.Parent = context.playerGui

	local outline = UIUtil.frame({
		Size = UDim2.new(0.16, 0, 0.018, 0),
		Position = UDim2.new(0.42, 0, 0.88, 0),
		BackgroundColor3 = Color3.fromRGB(20, 20, 24),
		BackgroundTransparency = 1,
	})
	outline.Parent = gui
	local outlineCorner = Instance.new("UICorner")
	outlineCorner.CornerRadius = UDim.new(1, 0)
	outlineCorner.Parent = outline

	local fill = UIUtil.frame({
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = FULL_COLOR,
		BackgroundTransparency = 1,
	})
	fill.Parent = outline
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = fill

	local barAlpha = 1 -- start fully faded out (full stamina, not sprinting)

	local function applySpeed()
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			return
		end
		if player:GetAttribute("Hidden") then
			return
		end
		local effectiveSprinting = holdingShift and not exhausted and stamina > 0
		humanoid.WalkSpeed = effectiveSprinting and Config.Player.SprintSpeed or Config.Player.WalkSpeed
	end

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if isShift(input.KeyCode) then
			holdingShift = true
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if isShift(input.KeyCode) then
			holdingShift = false
			applySpeed()
		end
	end)

	player.CharacterAdded:Connect(function()
		task.wait()
		stamina = 1
		exhausted = false
		applySpeed()
	end)

	RunService.Heartbeat:Connect(function(dt)
		local hidden = player:GetAttribute("Hidden")
		local effectiveSprinting = holdingShift and not exhausted and stamina > 0 and not hidden

		if effectiveSprinting then
			stamina = math.max(0, stamina - dt / Config.Player.SprintDuration)
			if stamina <= 0 then
				exhausted = true
			end
		else
			local regenRate = 1 / Config.Player.SprintRegenDuration
			if hidden then
				regenRate *= Config.Player.SprintRegenHiddenMultiplier
			end
			stamina = math.min(1, stamina + regenRate * dt)
			if exhausted and stamina >= Config.Player.MinSprintFraction then
				exhausted = false
			end
		end

		applySpeed()
		StaminaState.Fraction = stamina

		local targetAlpha = (stamina < 0.999 or holdingShift) and 0 or 1
		barAlpha += (targetAlpha - barAlpha) * math.min(1, dt * 6)
		outline.BackgroundTransparency = 0.35 + barAlpha * 0.65
		fill.BackgroundTransparency = barAlpha
		fill.Size = UDim2.new(stamina, 0, 1, 0)
		fill.BackgroundColor3 = lerpColor(EMPTY_COLOR, FULL_COLOR, stamina)
	end)
end

return SprintController
