local Net = require(game:GetService("ReplicatedStorage").Shared.Net)
local UIUtil = require(script.Parent.UIUtil)

local RestockShelves = require(script.Parent.Minigames.RestockShelves)
local FlatPackAssembly = require(script.Parent.Minigames.FlatPackAssembly)
local SelfCheckout = require(script.Parent.Minigames.SelfCheckout)

local GAMES = {
	RestockShelves = RestockShelves,
	FlatPackAssembly = FlatPackAssembly,
	SelfCheckout = SelfCheckout,
}

local MinigameController = {}

function MinigameController.Init(context)
	local gui = UIUtil.screenGui("MinigameGui")
	gui.Enabled = false
	gui.DisplayOrder = 20
	gui.Parent = context.playerGui

	local container = UIUtil.frame({
		Size = UDim2.new(0.5, 0, 0.55, 0),
		Position = UDim2.new(0.25, 0, 0.2, 0),
		BackgroundColor3 = Color3.fromRGB(25, 25, 30),
		BackgroundTransparency = 0.05,
	})
	container.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = container

	local titleLabel = UIUtil.label({
		Size = UDim2.new(0.94, 0, 0.12, 0),
		Position = UDim2.new(0.03, 0, 0, 0),
		TextScaled = true,
		TextStrokeTransparency = 0,
		Text = "",
	})
	titleLabel.Parent = container

	local giveUpBtn = UIUtil.button({
		Size = UDim2.new(0.25, 0, 0.08, 0),
		Position = UDim2.new(0.375, 0, 0.9, 0),
		BackgroundColor3 = Color3.fromRGB(170, 60, 60),
		TextScaled = true,
		Text = "Give Up",
	})
	giveUpBtn.Parent = container

	local playArea = UIUtil.frame({
		Size = UDim2.new(0.94, 0, 0.72, 0),
		Position = UDim2.new(0.03, 0, 0.15, 0),
		BackgroundTransparency = 1,
	})
	playArea.Parent = container

	local resultEvent = Net.GetEvent("MinigameResult")
	local activeStationId, activeCleanup

	local function endGame(success)
		if not activeStationId then
			return
		end
		resultEvent:FireServer(activeStationId, success)
		if activeCleanup then
			activeCleanup()
		end
		activeCleanup = nil
		activeStationId = nil
		gui.Enabled = false
		for _, child in ipairs(playArea:GetChildren()) do
			child:Destroy()
		end
	end

	giveUpBtn.MouseButton1Click:Connect(function()
		endGame(false)
	end)

	Net.GetEvent("StartMinigame").OnClientEvent:Connect(function(stationId, config)
		if activeStationId then
			endGame(false)
		end
		activeStationId = stationId
		titleLabel.Text = config.stationName .. " -- " .. config.description
		gui.Enabled = true

		local gameModule = GAMES[stationId]
		if gameModule then
			activeCleanup = gameModule.Play(playArea, config, endGame)
		else
			task.delay(1, function()
				endGame(false)
			end)
		end
	end)

	Net.GetEvent("CancelMinigame").OnClientEvent:Connect(function()
		endGame(false)
	end)
end

return MinigameController
