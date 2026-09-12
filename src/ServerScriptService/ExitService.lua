local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local Net = require(game:GetService("ReplicatedStorage").Shared.Net)

local ExitService = {}
ExitService.__index = ExitService

function ExitService.new(maze)
	local self = setmetatable({}, ExitService)
	self.maze = maze
	self.unlocked = false
	self.escapeHandler = nil
	self.exitUnlockedEvent = Net.GetEvent("ExitUnlocked")

	self.lockedCFrame = maze.exitDoor.CFrame
	self.openCFrame = maze.exitDoor.CFrame * CFrame.new(0, maze.exitDoor.Size.Y, 0)

	if maze.escapeZone then
		maze.escapeZone.Touched:Connect(function(hit)
			self:_onEscapeTouch(hit)
		end)
	end

	return self
end

function ExitService:SetEscapeHandler(fn)
	self.escapeHandler = fn
end

function ExitService:_onEscapeTouch(hit)
	if not self.unlocked then
		return
	end
	local character = hit:FindFirstAncestorOfClass("Model")
	if not character then
		return
	end
	local player = Players:GetPlayerFromCharacter(character)
	if not player or player:GetAttribute("State") ~= "Alive" then
		return
	end
	if self.escapeHandler then
		self.escapeHandler(player)
	end
end

function ExitService:Unlock()
	if self.unlocked then
		return
	end
	self.unlocked = true

	local door = self.maze.exitDoor
	local label = door:FindFirstChildWhichIsA("BillboardGui", true)
	if label then
		local text = label:FindFirstChildWhichIsA("TextLabel")
		if text then
			text.Text = "LOADING DOCK [OPEN] -- GO GO GO"
			text.TextColor3 = Color3.fromRGB(80, 255, 100)
		end
	end

	local tween = TweenService:Create(door, TweenInfo.new(2, Enum.EasingStyle.Quad), { CFrame = self.openCFrame })
	tween:Play()
	tween.Completed:Wait()
	door.CanCollide = false

	self.exitUnlockedEvent:FireAllClients()
end

function ExitService:Reset()
	self.unlocked = false
	local door = self.maze.exitDoor
	door.CFrame = self.lockedCFrame
	door.CanCollide = true
	local label = door:FindFirstChildWhichIsA("BillboardGui", true)
	if label then
		local text = label:FindFirstChildWhichIsA("TextLabel")
		if text then
			text.Text = "LOADING DOCK [LOCKED]"
			text.TextColor3 = Color3.fromRGB(255, 80, 80)
		end
	end
end

return ExitService
