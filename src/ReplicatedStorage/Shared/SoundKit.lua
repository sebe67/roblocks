-- Tiny sound helpers used by both server (positional monster sounds) and
-- client (UI/ambience) code. Every function treats an empty/nil SoundId as
-- "do nothing" -- so the whole audio system is safe to wire up before any
-- real asset IDs exist; it just stays silent until you paste one in.

local Debris = game:GetService("Debris")

local SoundKit = {}

-- One-shot, non-positional sound (menu clicks, fanfares, jumpscare stingers).
-- Parented to `parent` (usually SoundService) and self-destroys when done.
function SoundKit.PlayUI(soundId, props, parent)
	if not soundId or soundId == "" then
		return nil
	end
	props = props or {}
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = props.Volume or 0.6
	sound.PlaybackSpeed = props.PlaybackSpeed or 1
	sound.Parent = parent or game:GetService("SoundService")
	sound:Play()
	Debris:AddItem(sound, 12)
	return sound
end

-- Persistent looping 3D sound parented to a BasePart (e.g. a monster's
-- HumanoidRootPart). Returns the Sound instance so callers can retune its
-- Volume/PlaybackSpeed live (e.g. louder while chasing).
function SoundKit.CreateLoop3D(part, soundId, props)
	props = props or {}
	local sound = Instance.new("Sound")
	sound.Name = props.Name or "Loop3D"
	sound.SoundId = soundId or ""
	sound.Looped = true
	sound.Volume = props.Volume or 0.5
	sound.PlaybackSpeed = props.PlaybackSpeed or 1
	sound.RollOffMaxDistance = props.MaxDistance or 60
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.Parent = part
	if soundId and soundId ~= "" then
		sound:Play()
	end
	return sound
end

-- One-shot 3D sound anchored to a part's current position (clones itself so
-- overlapping plays -- e.g. two monsters chasing at once -- don't cut off).
function SoundKit.PlayAt(part, soundId, props)
	if not soundId or soundId == "" or not part then
		return nil
	end
	props = props or {}
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = props.Volume or 0.7
	sound.PlaybackSpeed = props.PlaybackSpeed or 1
	sound.RollOffMaxDistance = props.MaxDistance or 60
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.Parent = part
	sound:Play()
	Debris:AddItem(sound, 10)
	return sound
end

return SoundKit
