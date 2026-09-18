-- Wires up every "HidingSpot" wardrobe MazeGenerator placed: a single
-- ProximityPrompt per spot (default key E) that toggles the triggering
-- player in and out -- same key both ways, per request. Mirrors
-- MinigameService's ProximityPrompt setup. The prompt's ActionText flips
-- between "Enter Closet" and "Exit Closet" with that spot's own occupancy
-- -- accurate for whoever's actually using it; a second player who walks
-- up to an already-occupied spot would see "Exit Closet" too (a single
-- shared prompt can't hold per-viewer text), but triggering it while
-- occupied by someone else is still a no-op either way.
--
-- Being Hidden does two things, both authoritative server-side so a
-- modified client can't fake either one:
--   1. humanoid.WalkSpeed = 0, same freeze pattern PlayerService:CatchPlayer
--      already uses.
--   2. player:SetAttribute("Hidden", true) -- MonsterAI's playersToCheck()
--      filters Hidden players out before any sight/catch check runs, so a
--      hidden player is completely invisible to every monster regardless
--      of range/FOV/line-of-sight.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
local Net = require(game:GetService("ReplicatedStorage").Shared.Net)

local HidingService = {}
HidingService.__index = HidingService

function HidingService.new()
	local self = setmetatable({}, HidingService)
	self.occupantSpot = {} -- player -> spot
	self.returnCFrame = {} -- player -> CFrame to restore on exit
	self.warningEvent = Net.GetEvent("HidingWarning")
	self.kickedEvent = Net.GetEvent("HidingKicked")
	self:_setupSpots()

	Players.PlayerRemoving:Connect(function(player)
		self:ForceExit(player)
	end)

	return self
end

function HidingService:_setupSpots()
	for _, model in ipairs(CollectionService:GetTagged("HidingSpot")) do
		local interior = model:FindFirstChild("InteriorAnchor")
		local promptAnchor = model:FindFirstChild("PromptAnchor")
		if interior and promptAnchor then
			local prompt = Instance.new("ProximityPrompt")
			prompt.ActionText = "Enter Closet"
			prompt.ObjectText = "Wardrobe"
			prompt.HoldDuration = 0
			prompt.MaxActivationDistance = Config.HidingSpot.MaxActivationDistance
			prompt.RequiresLineOfSight = false
			prompt.KeyboardKeyCode = Enum.KeyCode.E
			prompt.Parent = promptAnchor

			local spot = {
				interior = interior,
				promptAnchor = promptAnchor,
				prompt = prompt,
				occupant = nil,
				enterToken = 0,
			}

			prompt.Triggered:Connect(function(player)
				self:_onTriggered(player, spot)
			end)
		end
	end
end

function HidingService:_onTriggered(player, spot)
	if spot.occupant == player then
		self:_exit(player, spot)
	elseif not spot.occupant and player:GetAttribute("State") == "Alive" then
		self:_enter(player, spot)
	end
	-- Occupied by someone else -- no-op (see the file header on the
	-- shared-prompt-text tradeoff).
end

function HidingService:_enter(player, spot)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not humanoid or not root or self.occupantSpot[player] then
		return
	end

	spot.occupant = player
	self.occupantSpot[player] = spot
	self.returnCFrame[player] = root.CFrame

	character:PivotTo(spot.interior.CFrame)
	humanoid.WalkSpeed = 0
	player:SetAttribute("Hidden", true)
	spot.prompt.ActionText = "Exit Closet"

	-- Can't camp in here forever -- warn, then force out at
	-- MaxHideDuration. enterToken distinguishes THIS occupancy from any
	-- later one (a leave-then-re-enter of the same spot before this fires),
	-- so a stale timer from a previous stay can never kick the wrong stay.
	spot.enterToken += 1
	local token = spot.enterToken
	local warnIn = Config.HidingSpot.MaxHideDuration - Config.HidingSpot.KickWarningTime
	task.delay(warnIn, function()
		if spot.occupant == player and spot.enterToken == token then
			self.warningEvent:FireClient(player, Config.HidingSpot.KickWarningTime)
		end
	end)
	task.delay(Config.HidingSpot.MaxHideDuration, function()
		if spot.occupant == player and spot.enterToken == token then
			self:_exit(player, spot)
			self.kickedEvent:FireClient(player)
		end
	end)
end

function HidingService:_exit(player, spot)
	spot.occupant = nil
	self.occupantSpot[player] = nil
	player:SetAttribute("Hidden", false)
	spot.prompt.ActionText = "Enter Closet"

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if character then
		character:PivotTo(self.returnCFrame[player] or spot.promptAnchor.CFrame)
	end
	if humanoid then
		humanoid.WalkSpeed = Config.Player.WalkSpeed
	end
	self.returnCFrame[player] = nil
end

-- Public: called whenever a player leaves the round (disconnect) or
-- transitions out of being hideable (caught, died, timed out, escaped,
-- respawned -- see PlayerService) without ever pressing E to leave on
-- their own. Without this, a player who dies/respawns while Hidden would
-- keep occupying that spot forever -- permanently blocking it for
-- everyone AND permanently blocking themself from entering ANY spot,
-- since _enter bails out early while self.occupantSpot[player] is set.
function HidingService:ForceExit(player)
	local spot = self.occupantSpot[player]
	if spot then
		spot.occupant = nil
		spot.prompt.ActionText = "Enter Closet"
	end
	self.occupantSpot[player] = nil
	self.returnCFrame[player] = nil
	player:SetAttribute("Hidden", false)
end

-- Called by GameState at the start of every round so nobody carries a
-- stale Hidden state (or a stale occupied spot) across rounds.
function HidingService:ResetAll()
	for player in pairs(self.occupantSpot) do
		self:ForceExit(player)
	end
	self.occupantSpot = {}
	self.returnCFrame = {}
end

return HidingService
