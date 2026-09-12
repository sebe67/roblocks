local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local context = { player = player, playerGui = playerGui }

require(script.Parent.SprintController).Init(context)
require(script.Parent.JumpscareController).Init(context)
require(script.Parent.DeathController).Init(context)
require(script.Parent.MinigameController).Init(context)
require(script.Parent.HUDController).Init(context)
require(script.Parent.SpectateController).Init(context)
