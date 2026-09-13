-- Global store ambience, a proximity "heartbeat" that ramps up as any
-- monster gets close (whether or not it's chasing you -- pure dread cue),
-- and one-shot stingers for round/exit/escape events. All positions used
-- here are ordinary replicated Part positions -- no new remotes needed.

local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local CollectionService = game:GetService("CollectionService")
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
local Net = require(game:GetService("ReplicatedStorage").Shared.Net)
local SoundKit = require(game:GetService("ReplicatedStorage").Shared.SoundKit)

local AmbienceController = {}

function AmbienceController.Init(context)
	local player = context.player
	local sounds = Config.Sounds

	local ambience = SoundKit.CreateLoop3D(SoundService, sounds.StoreAmbience, {
		Name = "StoreAmbience",
		Volume = 0.35,
		MaxDistance = 10000,
	})

	local heartbeat = SoundKit.CreateLoop3D(SoundService, sounds.Heartbeat, {
		Name = "Heartbeat",
		Volume = 0,
		MaxDistance = 10000,
	})

	local overtimeActive = false

	local nextProximityCheck = 0
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if now < nextProximityCheck then
			return
		end
		nextProximityCheck = now + 0.2

		if heartbeat.SoundId == "" then
			return
		end

		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not root then
			heartbeat.Volume = 0
			return
		end

		local nearest = math.huge
		for _, monsterModel in ipairs(CollectionService:GetTagged("Monster")) do
			local monsterRoot = monsterModel:FindFirstChild("HumanoidRootPart")
			if monsterRoot then
				local d = (monsterRoot.Position - root.Position).Magnitude
				if d < nearest then
					nearest = d
				end
			end
		end

		local far, near = sounds.HeartbeatMaxDistance, sounds.HeartbeatMinDistance
		local t = 1 - math.clamp((nearest - near) / math.max(far - near, 1), 0, 1)
		if overtimeActive then
			t = math.max(t, 0.6) -- never lets you forget, even mid-corridor
		end
		heartbeat.Volume = t * 0.8
		heartbeat.PlaybackSpeed = 1 + t * 0.5
		if t > 0 and not heartbeat.Playing then
			heartbeat:Play()
		end
	end)

	Net.GetEvent("RoundPhase").OnClientEvent:Connect(function(phase, data)
		if phase == "Intermission" and data.timeLeft == Config.Round.IntermissionTime then
			SoundKit.PlayUI(sounds.IntermissionStart, { Volume = 0.5 })
		elseif phase == "Playing" then
			SoundKit.PlayUI(sounds.RoundStart, { Volume = 0.8 })
			overtimeActive = false
		elseif phase == "Results" then
			overtimeActive = false
		end
	end)

	Net.GetEvent("OvertimeStarted").OnClientEvent:Connect(function()
		overtimeActive = true
		SoundKit.PlayUI(sounds.OvertimeWarning, { Volume = 1 })
	end)

	Net.GetEvent("ExitUnlocked").OnClientEvent:Connect(function()
		SoundKit.PlayUI(sounds.ExitUnlocked, { Volume = 0.9 })
	end)

	Net.GetEvent("PlayerEscaped").OnClientEvent:Connect(function()
		SoundKit.PlayUI(sounds.EscapeSuccess, { Volume = 0.9 })
	end)
end

return AmbienceController
