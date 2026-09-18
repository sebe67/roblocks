local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local context = { player = player, playerGui = playerGui }

-- Each controller inits independently, wrapped in pcall: a bug in any one
-- module (a bad property, an invalid Enum) must not stop the rest from
-- running. Without this, a single early error here (e.g. a bad Enum.Font
-- reference blowing up on require) silently skipped every controller listed
-- after it -- including HUDController, which is why the round's Intermission
-- countdown and the minigame overlay could both go missing from one broken
-- line with no error visible in-game.
local CONTROLLERS = {
	"SprintController",
	"ViewBobController",
	"FlashlightController",
	"NoclipController",
	"AmbienceController",
	"JumpscareController",
	"HidingController",
	"DeathController",
	"MinigameController",
	"HUDController",
	"SpectateController",
}

for _, name in ipairs(CONTROLLERS) do
	local ok, err = pcall(function()
		require(script.Parent[name]).Init(context)
	end)
	if not ok then
		warn(string.format("[Main.client] %s failed to init: %s", name, tostring(err)))
	end
end
