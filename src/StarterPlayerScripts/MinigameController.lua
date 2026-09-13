local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
local Net = require(game:GetService("ReplicatedStorage").Shared.Net)
local SoundKit = require(game:GetService("ReplicatedStorage").Shared.SoundKit)
local UIUtil = require(script.Parent.UIUtil)
local CursorLock = require(script.Parent.CursorLock)

local RestockShelves = require(script.Parent.Minigames.RestockShelves)
local FlatPackAssembly = require(script.Parent.Minigames.FlatPackAssembly)
local SelfCheckout = require(script.Parent.Minigames.SelfCheckout)
local InventoryCount = require(script.Parent.Minigames.InventoryCount)
local CustomerRush = require(script.Parent.Minigames.CustomerRush)
local ForkliftCertification = require(script.Parent.Minigames.ForkliftCertification)

local GAMES = {
	RestockShelves = RestockShelves,
	FlatPackAssembly = FlatPackAssembly,
	SelfCheckout = SelfCheckout,
	InventoryCount = InventoryCount,
	CustomerRush = CustomerRush,
	ForkliftCertification = ForkliftCertification,
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

	-- Small toast that outlives the minigame window itself (it closes
	-- immediately) so the player still sees why it ended.
	local toastGui = UIUtil.screenGui("MinigameToastGui")
	toastGui.DisplayOrder = 21
	toastGui.Parent = context.playerGui

	local toastLabel = UIUtil.label({
		Size = UDim2.new(0.5, 0, 0.07, 0),
		Position = UDim2.new(0.25, 0, 0.1, 0),
		BackgroundTransparency = 0.1,
		BackgroundColor3 = Color3.fromRGB(20, 20, 24),
		TextScaled = true,
		TextStrokeTransparency = 0,
		Visible = false,
	})
	local toastCorner = Instance.new("UICorner")
	toastCorner.CornerRadius = UDim.new(0, 8)
	toastCorner.Parent = toastLabel
	toastLabel.Parent = toastGui

	local toastToken = 0
	local function showToast(text, color)
		toastToken += 1
		local myToken = toastToken
		toastLabel.Text = text
		toastLabel.TextColor3 = color or Color3.fromRGB(255, 255, 255)
		toastLabel.Visible = true
		task.delay(2.2, function()
			if toastToken == myToken then
				toastLabel.Visible = false
			end
		end)
	end

	local REASON_MESSAGES = {
		complete = { text = "TASK COMPLETE!", color = Color3.fromRGB(90, 230, 120) },
		tooFar = { text = "You moved too far away from the task.", color = Color3.fromRGB(230, 190, 70) },
		gaveup = { text = "You gave up on the task.", color = Color3.fromRGB(230, 190, 70) },
		failed = { text = "Task failed.", color = Color3.fromRGB(230, 80, 80) },
	}

	local resultEvent = Net.GetEvent("MinigameResult")
	local activeStationId, activeCleanup

	-- reason is optional: games that just call onComplete(true/false) with
	-- no reason get sensible defaults ("complete" / "failed" -- covers both
	-- running out of time and blowing the task's own fail condition), while
	-- the Give Up button and the server's leash-distance cancel pass their
	-- own specific reason through.
	local function endGame(success, reason)
		if not activeStationId then
			return
		end
		SoundKit.PlayUI(success and Config.Sounds.MinigameSuccess or Config.Sounds.MinigameFail, { Volume = 0.7 })
		resultEvent:FireServer(activeStationId, success)
		if activeCleanup then
			activeCleanup()
		end
		activeCleanup = nil
		activeStationId = nil
		gui.Enabled = false
		CursorLock.Pop(context.player)
		for _, child in ipairs(playArea:GetChildren()) do
			child:Destroy()
		end

		local info = REASON_MESSAGES[reason or (success and "complete" or "failed")]
		if info then
			showToast(info.text, info.color)
		end
	end

	giveUpBtn.MouseButton1Click:Connect(function()
		SoundKit.PlayUI(Config.Sounds.UIClick, { Volume = 0.5 })
		endGame(false, "gaveup")
	end)

	Net.GetEvent("StartMinigame").OnClientEvent:Connect(function(stationId, config)
		if activeStationId then
			endGame(false, "gaveup")
		end
		activeStationId = stationId
		titleLabel.Text = config.stationName .. " -- " .. config.description
		gui.Enabled = true
		CursorLock.Push(context.player)

		local gameModule = GAMES[stationId]
		if gameModule then
			activeCleanup = gameModule.Play(playArea, config, endGame)
		else
			task.delay(1, function()
				endGame(false, "failed")
			end)
		end
	end)

	Net.GetEvent("CancelMinigame").OnClientEvent:Connect(function()
		endGame(false, "tooFar")
	end)
end

return MinigameController
