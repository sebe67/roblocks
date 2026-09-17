-- Wires up every "HidingSpot" wardrobe MazeGenerator placed: a single
-- ProximityPrompt per spot (default key E) that toggles the triggering
-- player in and out -- same key both ways, per request. Mirrors
-- MinigameService's ProximityPrompt setup.
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

local HidingService = {}
HidingService.__index = HidingService

function HidingService.new()
	local self = setmetatable({}, HidingService)
	self.occupantSpot = {} -- player -> spot
	self.returnCFrame = {} -- player -> CFrame to restore on exit
	self:_setupSpots()

	Players.PlayerRemoving:Connect(function(player)
		self:_forceExit(player)
	end)

	return self
end

function HidingService:_setupSpots()
	for _, model in ipairs(CollectionService:GetTagged("HidingSpot")) do
		local interior = model:FindFirstChild("InteriorAnchor")
		local promptAnchor = model:FindFirstChild("PromptAnchor")
		if interior and promptAnchor then
			local prompt = Instance.new("ProximityPrompt")
			prompt.ActionText = "Hide"
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
	-- Occupied by someone else -- no-op, per the accepted v1 tradeoff that
	-- the shared prompt can't say "Hide" vs. "Leave" per simultaneous viewer.
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
end

function HidingService:_exit(player, spot)
	spot.occupant = nil
	self.occupantSpot[player] = nil
	player:SetAttribute("Hidden", false)

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

-- Player left mid-hide (disconnected) -- just clears the spot so someone
-- else can use it; nothing to restore for a player who's gone.
function HidingService:_forceExit(player)
	local spot = self.occupantSpot[player]
	if spot then
		spot.occupant = nil
	end
	self.occupantSpot[player] = nil
	self.returnCFrame[player] = nil
end

-- Called by GameState at the start of every round so nobody carries a
-- stale Hidden state (or a stale occupied spot) across rounds.
function HidingService:ResetAll()
	for player, spot in pairs(self.occupantSpot) do
		spot.occupant = nil
		player:SetAttribute("Hidden", false)
	end
	self.occupantSpot = {}
	self.returnCFrame = {}
end

return HidingService
