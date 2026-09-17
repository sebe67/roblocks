-- On catch, renders a closeup of the ACTUAL monster that caught you (not a
-- flat color card) using a ViewportFrame: a GUI element that renders its
-- own isolated 3D scene, completely separate from the real game world. The
-- server hands over the live monster instance that touched you
-- (PlayerService:CatchPlayer -> Jumpscare event), we clone it into that
-- scene, and point a camera tight on its head/face -- since the clone is
-- the ONLY thing in that scene, everything else in frame is naturally
-- solid black with zero extra work.
--
-- Effects implemented now (see the user's picks -- #1 and #4 from the
-- brainstormed list, plus the shake/static/black-background asked for
-- directly):
--   1. Punch-in: camera starts very close for one beat, then eases out to
--      its held distance.
--   4. Unstable lighting: ViewportFrame.LightColor/Ambient (its built-in,
--      instance-free lighting knobs) flicker randomly instead of holding
--      steady, so the face is never calmly lit.
--   Shake: the viewport camera jitters position+rotation every single
--      rendered frame (not a separate slower loop) for a violent,
--      high-frequency tremor, decoupled from the real game camera.
--   Static: a full-screen translucent overlay whose transparency/tint
--      flickers at high frequency -- reads as signal interference. This is
--      procedural (no image asset), not real grain/noise texture -- that
--      would need an actual texture asset uploaded on your end.
--
-- NOT implemented yet, per request ("remind me" -- tracked, don't build
-- until asked): #7, a pulsing dark/red edge vignette that tightens as the
-- jumpscare holds.
--
-- Total duration is Config.Round.JumpscareDuration (also what gates
-- PlayerService:CatchPlayer's auto-respawn delay, so they always match).
--
-- Framing is a heuristic, not hand-tuned per monster: it looks for a
-- "Head" part, then a "Face" part (Thomas has no Head -- his face is a
-- part on the front of the boiler), then falls back to the whole model's
-- bounding-box center. The camera is placed along that part's LookVector,
-- which lines up well for some rigs and only approximately for others --
-- expect some framing to need per-monster tuning later once real jumpscare
-- art replaces this.

local RunService = game:GetService("RunService")
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
local Net = require(game:GetService("ReplicatedStorage").Shared.Net)
local SoundKit = require(game:GetService("ReplicatedStorage").Shared.SoundKit)
local UIUtil = require(script.Parent.UIUtil)

local JumpscareController = {}

local monsterById = {}
for _, def in ipairs(Config.Monsters) do
	monsterById[def.id] = def
end

-- How close the camera sits at rest, and how much closer it starts for the
-- punch-in beat, both expressed as a multiple of the focal part's own size
-- so it scales sensibly across very different monster scales.
local HOLD_DISTANCE_MULT = 1.6
local PUNCH_DISTANCE_MULT = 0.5
local PUNCH_IN_TIME = 0.12
local SHAKE_POSITION_STUDS = 0.35
local SHAKE_ROTATION_DEGREES = 5
local LIGHT_FLICKER_INTERVAL = 0.06 -- how often the "bulb" re-randomizes, not every frame -- a stepped flicker reads better than smooth shimmer
local STATIC_MIN_TRANSPARENCY = 0.88
local STATIC_MAX_TRANSPARENCY = 0.95

-- Returns (CFrame, size) for whatever we're framing the camera on --
-- see the framing-heuristic note at the top of this file.
--
-- Position comes from the Head/Face part (whatever's closest to the
-- actual face), but ORIENTATION comes from the root instead of that
-- part's own rotation -- a MeshPart's baked rotation is whatever the
-- mesh author's local axes happened to be when it was modeled, which
-- doesn't reliably line up with which way the character actually faces
-- (confirmed the hard way: Thomas's "Face" part's own LookVector pointed
-- to the side, giving a side-profile shot instead of head-on). The root's
-- forward direction is the same one _faceAndMove already trusts as
-- canonical "front" for movement/facing, so anchoring the camera's
-- direction to that instead is far more reliable across different rigs.
local function getFocalPoint(model)
	-- Recursive lookups (FindFirstChild's 2nd argument) since a dropped-in
	-- template's rig can end up nested a level deeper than expected -- see
	-- the matching note in MonsterAI.lua's createRigFromTemplate.
	local root = model:FindFirstChild("HumanoidRootPart", true)
	local part = model:FindFirstChild("Head", true) or model:FindFirstChild("Face", true)
	local focalPart = (part and part:IsA("BasePart")) and part or root

	if focalPart then
		local orientationSource = root or focalPart
		local rotationOnly = orientationSource.CFrame - orientationSource.CFrame.Position
		return CFrame.new(focalPart.Position) * rotationOnly, focalPart.Size.Magnitude
	end

	local ok, cframe, size = pcall(function()
		return model:GetBoundingBox()
	end)
	if ok then
		return cframe, size.Magnitude
	end
	return CFrame.new(), 4
end

function JumpscareController.Init(context)
	local gui = UIUtil.screenGui("JumpscareGui")
	gui.Enabled = false
	gui.DisplayOrder = 50
	gui.Parent = context.playerGui

	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "MonsterCloseup"
	viewport.Size = UDim2.fromScale(1, 1)
	viewport.BackgroundColor3 = Color3.new(0, 0, 0)
	viewport.BackgroundTransparency = 0
	viewport.BorderSizePixel = 0
	viewport.Parent = gui

	local staticOverlay = UIUtil.frame({
		Name = "Static",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = STATIC_MAX_TRANSPARENCY,
		ZIndex = 2,
	})
	staticOverlay.Parent = gui

	local nameLabel = UIUtil.label({
		Size = UDim2.new(1, 0, 0.2, 0),
		Position = UDim2.new(0, 0, 0.72, 0),
		TextScaled = true,
		TextStrokeTransparency = 0,
		Text = "",
		ZIndex = 3,
	})
	nameLabel.Parent = gui

	local flavorLabel = UIUtil.label({
		Size = UDim2.new(0.8, 0, 0.1, 0),
		Position = UDim2.new(0.1, 0, 0.85, 0),
		TextScaled = true,
		TextColor3 = Color3.fromRGB(220, 220, 220),
		Text = "",
		ZIndex = 3,
	})
	flavorLabel.Parent = gui

	local overtimeActive = false
	Net.GetEvent("OvertimeStarted").OnClientEvent:Connect(function()
		overtimeActive = true
	end)
	Net.GetEvent("RoundPhase").OnClientEvent:Connect(function(phase)
		if phase == "Playing" or phase == "Results" then
			overtimeActive = false
		end
	end)

	local activeConn = nil
	local activeClone = nil
	local activeCamera = nil

	local function cleanup()
		if activeConn then
			activeConn:Disconnect()
			activeConn = nil
		end
		if activeClone then
			activeClone:Destroy()
			activeClone = nil
		end
		if activeCamera then
			activeCamera:Destroy()
			activeCamera = nil
		end
		viewport.CurrentCamera = nil
	end

	Net.GetEvent("Jumpscare").OnClientEvent:Connect(function(monsterId, monsterModel)
		local def = monsterById[monsterId]
		if not def then
			return
		end

		cleanup()
		gui.Enabled = true
		nameLabel.Text = string.upper(def.displayName) .. "!!"
		nameLabel.TextColor3 = def.accentColor
		flavorLabel.Text = def.flavor

		-- During Overtime everything gets deeper/distorted for extra dread
		-- -- these two are 2D client sounds so they don't go through the
		-- server's shared "Monsters" SoundGroup; PlaybackSpeed is the cheap
		-- equivalent pitch-down for them specifically.
		local pitch = overtimeActive and 0.7 or 1
		SoundKit.PlayUI(Config.Sounds.Caught, { Volume = 0.8, PlaybackSpeed = pitch })
		-- Falls back to the shared Config.Sounds.JumpscareScream when this
		-- monster doesn't have its own jumpscareSoundId set -- currently
		-- that's every monster, so this is "the one scream everyone uses"
		-- until individual monsters get their own.
		local screamId = def.jumpscareSoundId ~= "" and def.jumpscareSoundId or Config.Sounds.JumpscareScream
		task.delay(0.15, function()
			SoundKit.PlayUI(screamId, { Volume = 1, PlaybackSpeed = pitch })
		end)

		if not (monsterModel and monsterModel.Parent) then
			-- Safety net: no live instance to clone (shouldn't normally
			-- happen -- CatchPlayer always has one). Fall back to a flat
			-- color card so a jumpscare still plays instead of nothing.
			viewport.BackgroundColor3 = def.jumpscareColor
			task.delay(Config.Round.JumpscareDuration, function()
				gui.Enabled = false
				viewport.BackgroundColor3 = Color3.new(0, 0, 0)
			end)
			return
		end
		viewport.BackgroundColor3 = Color3.new(0, 0, 0)

		local clone = monsterModel:Clone()
		-- Strip the stuff that came along for the ride but doesn't belong
		-- in a closeup: the NameTag/StateTag billboards (createRig's HUD,
		-- would float redundantly right on top of the shot) and any Sound
		-- (the footstep loop clones with whatever Playing state it had at
		-- the moment of catch, and ViewportFrames only isolate rendering,
		-- not audio -- an already-playing clone would audibly double up).
		for _, descendant in ipairs(clone:GetDescendants()) do
			if descendant:IsA("BillboardGui") or descendant:IsA("Sound") then
				descendant:Destroy()
			end
		end
		clone.Parent = viewport
		activeClone = clone

		local camera = Instance.new("Camera")
		camera.Parent = viewport
		viewport.CurrentCamera = camera
		activeCamera = camera

		local focalCFrame, focalSize = getFocalPoint(clone)
		local holdDistance = math.clamp(focalSize * HOLD_DISTANCE_MULT, 1.5, 6)
		local punchDistance = holdDistance * PUNCH_DISTANCE_MULT

		local function cameraCFrameAt(distance)
			local pos = focalCFrame.Position + focalCFrame.LookVector * distance
			return CFrame.lookAt(pos, focalCFrame.Position)
		end

		local elapsed = 0
		local nextFlickerAt = 0
		activeConn = RunService.RenderStepped:Connect(function(dt)
			elapsed += dt

			local distance
			if elapsed < PUNCH_IN_TIME then
				distance = punchDistance + (holdDistance - punchDistance) * (elapsed / PUNCH_IN_TIME)
			else
				distance = holdDistance
			end

			-- Effect #4: unstable lighting. ViewportFrame's LightColor/
			-- Ambient are its built-in lighting knobs (no separate Light
			-- instance needed) -- re-randomizing them on a short timer
			-- (not every frame) reads as a flickering bad bulb rather than
			-- a smooth shimmer.
			if elapsed >= nextFlickerAt then
				nextFlickerAt = elapsed + LIGHT_FLICKER_INTERVAL
				local flicker = 0.45 + math.random() * 0.55
				viewport.LightColor = Color3.new(flicker, flicker, flicker)
				viewport.Ambient = Color3.new(flicker * 0.5, flicker * 0.5, flicker * 0.5)
			end

			-- High-frequency shake: a fresh random offset every rendered
			-- frame, not a slower loop -- decoupled entirely from the real
			-- game camera.
			local shakeOffset = CFrame.new(
				(math.random() - 0.5) * SHAKE_POSITION_STUDS,
				(math.random() - 0.5) * SHAKE_POSITION_STUDS,
				0
			) * CFrame.Angles(
				math.rad((math.random() - 0.5) * SHAKE_ROTATION_DEGREES),
				math.rad((math.random() - 0.5) * SHAKE_ROTATION_DEGREES),
				math.rad((math.random() - 0.5) * SHAKE_ROTATION_DEGREES * 0.6)
			)
			camera.CFrame = cameraCFrameAt(distance) * shakeOffset

			-- Static: flicker a full-screen translucent overlay's
			-- transparency/tint at high frequency -- procedural signal
			-- noise, not a real grain texture (see the file header).
			local staticShade = 0.5 + math.random() * 0.5
			staticOverlay.BackgroundColor3 = Color3.new(staticShade, staticShade, staticShade)
			staticOverlay.BackgroundTransparency = STATIC_MIN_TRANSPARENCY
				+ math.random() * (STATIC_MAX_TRANSPARENCY - STATIC_MIN_TRANSPARENCY)
		end)

		task.delay(Config.Round.JumpscareDuration, function()
			gui.Enabled = false
			cleanup()
		end)
	end)
end

return JumpscareController
