-- Subtle first-person head bob while moving, scaled up a bit while
-- sprinting. Applied as a small camera-local offset layered on top of
-- Roblox's own camera update every frame via BindToRenderStep at a priority
-- just after Camera -- the same "run every frame, after the built-in
-- camera script" trick CursorLock uses for mouse state, since a plain
-- one-time CFrame set gets overwritten by that same built-in script.

local RunService = game:GetService("RunService")
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
local StaminaState = require(script.Parent.StaminaState)

local ViewBobController = {}

-- Cycles per stud traveled (not per second) -- bob speed naturally scales
-- with how fast you're actually moving instead of needing a separate
-- frequency multiplier for sprint. Tuned to land around 1.5Hz at WalkSpeed
-- and ~2.4Hz at SprintSpeed -- a real footstep cadence; the original value
-- here worked out to ~7Hz while sprinting, which reads as a shaky vibration
-- rather than a bob.
local CYCLES_PER_STUD = 0.095
local WALK_AMPLITUDE = 0.05
local SPRINT_AMPLITUDE = 0.15 -- was 0.09, then 0.12, bumped up again per request
local SWAY_RATIO = 0.5 -- horizontal sway relative to vertical bob, half frequency (figure-8)
local SPEED_SMOOTHING = 12 -- higher = snaps to actual speed faster, lower = smoother but laggier
-- Extra shake on top of the normal sprint amplitude as stamina (see
-- SprintController.lua/StaminaState.lua) runs out -- 0.7 means running on
-- empty shakes the camera 70% harder than a fresh sprint, fading to 0 extra
-- at full stamina. Scaled by sprintT below so it only kicks in while
-- actually sprinting, not at a walk.
local LOW_STAMINA_SHAKE_BOOST = 0.7

function ViewBobController.Init(context)
	local player = context.player
	local phase = 0
	local smoothedSpeed = 0

	RunService:BindToRenderStep("ViewBob", Enum.RenderPriority.Camera.Value + 1, function(dt)
		local camera = workspace.CurrentCamera
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not camera or not humanoid or not root or humanoid.Health <= 0 then
			return
		end

		-- AssemblyLinearVelocity has small real per-frame noise (footstep
		-- impulses, floor contact, uneven frame timing) that fed straight
		-- into the bob was showing up as a shaky jitter on top of the
		-- intended bob, most noticeable at sprint's bigger amplitude. An
		-- exponential moving average smooths that out without adding
		-- noticeable input lag.
		local velocity = root.AssemblyLinearVelocity
		local rawSpeed = Vector2.new(velocity.X, velocity.Z).Magnitude
		smoothedSpeed += (rawSpeed - smoothedSpeed) * math.clamp(dt * SPEED_SMOOTHING, 0, 1)

		phase += smoothedSpeed * dt * CYCLES_PER_STUD * (2 * math.pi)

		-- Fades in smoothly from 0 as you approach WalkSpeed, then keeps
		-- growing toward SPRINT_AMPLITUDE as you approach SprintSpeed --
		-- no discrete "sprint on/off" snap, just however fast you're
		-- actually going right now.
		local moveRatio = math.clamp(smoothedSpeed / Config.Player.WalkSpeed, 0, 1)
		local sprintT = math.clamp(
			(smoothedSpeed - Config.Player.WalkSpeed) / math.max(Config.Player.SprintSpeed - Config.Player.WalkSpeed, 1),
			0,
			1
		)
		local staminaDepletion = 1 - StaminaState.Fraction -- 0 = full, 1 = empty
		local staminaBoost = 1 + staminaDepletion * LOW_STAMINA_SHAKE_BOOST * sprintT
		local amplitude = (WALK_AMPLITUDE + (SPRINT_AMPLITUDE - WALK_AMPLITUDE) * sprintT) * moveRatio * staminaBoost

		local bobY = math.sin(phase) * amplitude
		local bobX = math.cos(phase * 0.5) * amplitude * SWAY_RATIO

		camera.CFrame = camera.CFrame * CFrame.new(bobX, bobY, 0)
	end)
end

return ViewBobController
