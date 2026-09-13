local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
local Net = require(game:GetService("ReplicatedStorage").Shared.Net)
local SoundKit = require(game:GetService("ReplicatedStorage").Shared.SoundKit)
local UIUtil = require(script.Parent.UIUtil)
local CursorLock = require(script.Parent.CursorLock)
local RetroTheme = require(script.Parent.Minigames.RetroTheme)

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

	-- Bigger and visibly different from the rest of the game's UI (8-bit
	-- pixel font, square panel, thick yellow border) so stepping into a CRS
	-- Loyalty Task feels like its own distinct "mode."
	local container = RetroTheme.panel({
		Size = UDim2.new(0.72, 0, 0.78, 0),
		Position = UDim2.new(0.14, 0, 0.09, 0),
		BackgroundColor3 = RetroTheme.Colors.Background,
	})
	container.Parent = gui

	local titleLabel = RetroTheme.label({
		Size = UDim2.new(0.94, 0, 0.08, 0),
		Position = UDim2.new(0.03, 0, 0.015, 0),
		TextScaled = true,
		TextStrokeTransparency = 0,
		TextColor3 = RetroTheme.Colors.Border,
		Text = "",
	})
	titleLabel.Parent = container

	local subtitleLabel = RetroTheme.label({
		Size = UDim2.new(0.94, 0, 0.09, 0),
		Position = UDim2.new(0.03, 0, 0.095, 0),
		TextScaled = true,
		TextWrapped = true,
		TextColor3 = RetroTheme.Colors.Dim,
		Text = "",
	})
	subtitleLabel.Parent = container

	local giveUpBtn = RetroTheme.button({
		Size = UDim2.new(0.25, 0, 0.07, 0),
		Position = UDim2.new(0.375, 0, 0.91, 0),
		BackgroundColor3 = Color3.fromRGB(170, 60, 60),
		TextScaled = true,
		Text = "GIVE UP",
	})
	giveUpBtn.Parent = container

	local playArea = UIUtil.frame({
		Size = UDim2.new(0.94, 0, 0.7, 0),
		Position = UDim2.new(0.03, 0, 0.2, 0),
		BackgroundTransparency = 1,
	})
	playArea.Parent = container

	-- Small toast that outlives the minigame window itself (it closes
	-- immediately) so the player still sees why it ended.
	local toastGui = UIUtil.screenGui("MinigameToastGui")
	toastGui.DisplayOrder = 21
	toastGui.Parent = context.playerGui

	local toastLabel = RetroTheme.label({
		Size = UDim2.new(0.5, 0, 0.07, 0),
		Position = UDim2.new(0.25, 0, 0.1, 0),
		BackgroundTransparency = 0.1,
		BackgroundColor3 = RetroTheme.Colors.Panel,
		TextScaled = true,
		TextStrokeTransparency = 0,
		Visible = false,
	})
	RetroTheme.outline(toastLabel)
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
		complete = { text = "TASK COMPLETE!", color = RetroTheme.Colors.Success },
		tooFar = { text = "You moved too far away from the task.", color = Color3.fromRGB(230, 190, 70) },
		gaveup = { text = "You gave up on the task.", color = Color3.fromRGB(230, 190, 70) },
		timeout = { text = "TASK FAILED -- you ran out of time.", color = RetroTheme.Colors.Danger },
		failed = { text = "Task failed.", color = RetroTheme.Colors.Danger },
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
		titleLabel.Text = config.stationName
		subtitleLabel.Text = (config.lore and (config.lore .. " ") or "") .. config.description
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
