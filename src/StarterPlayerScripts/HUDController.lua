local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
local Net = require(game:GetService("ReplicatedStorage").Shared.Net)
local UIUtil = require(script.Parent.UIUtil)

local HUDController = {}

local OUTCOME_FLAVOR = {
	Escaped = "ESCAPED -- unbeatable NPC energy",
	Dead = "CAUGHT -- L + ratio",
	Caught = "CAUGHT -- L + ratio",
	TimedOut = "TIMED OUT -- never had the rizz to begin with",
	Spectating = "SPECTATED -- built different (in a bad way)",
	Alive = "SOMEHOW STILL ALIVE??",
	Lobby = "sat this one out",
}

function HUDController.Init(context)
	local gui = UIUtil.screenGui("HUDGui")
	gui.DisplayOrder = 10
	gui.Parent = context.playerGui

	local phaseLabel = UIUtil.label({
		Size = UDim2.new(0.5, 0, 0.06, 0),
		Position = UDim2.new(0.25, 0, 0.02, 0),
		TextScaled = true,
		TextStrokeTransparency = 0,
		Text = "",
	})
	phaseLabel.Parent = gui

	local progressLabel = UIUtil.label({
		Size = UDim2.new(0.4, 0, 0.05, 0),
		Position = UDim2.new(0.02, 0, 0.02, 0),
		TextScaled = true,
		TextStrokeTransparency = 0,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "Loyalty Quota: 0 / 0",
	})
	progressLabel.Parent = gui

	local banner = UIUtil.label({
		Size = UDim2.new(0.6, 0, 0.08, 0),
		Position = UDim2.new(0.2, 0, 0.12, 0),
		TextScaled = true,
		TextStrokeTransparency = 0,
		TextColor3 = Color3.fromRGB(255, 218, 26),
		Text = "",
		Visible = false,
	})
	banner.Parent = gui

	-- Red vignette for Overtime -- a plain ColorCorrectionEffect the client
	-- owns and tweens, separate from anything the server touches on
	-- Lighting directly (fog/brightness).
	local overtimeTint = Lighting:FindFirstChild("OvertimeTint")
	if not overtimeTint then
		overtimeTint = Instance.new("ColorCorrectionEffect")
		overtimeTint.Name = "OvertimeTint"
		overtimeTint.TintColor = Color3.new(1, 1, 1)
		overtimeTint.Brightness = 0
		overtimeTint.Saturation = 0
		overtimeTint.Parent = Lighting
	end
	-- A separate dip from OvertimeTint (so the two stack cleanly if a
	-- blackout ever lands during Overtime) that darkens the screen for the
	-- duration of a blackout.
	local blackoutTint = Lighting:FindFirstChild("BlackoutTint")
	if not blackoutTint then
		blackoutTint = Instance.new("ColorCorrectionEffect")
		blackoutTint.Name = "BlackoutTint"
		blackoutTint.Brightness = 0
		blackoutTint.Parent = Lighting
	end

	local overtimeActive = false

	local function setOvertimeTint(active)
		local goal = active
				and { TintColor = Config.Overtime.TintColor, Saturation = -0.3, Brightness = -0.05 }
			or { TintColor = Color3.new(1, 1, 1), Saturation = 0, Brightness = 0 }
		TweenService:Create(overtimeTint, TweenInfo.new(1.5), goal):Play()
	end

	Net.GetEvent("RoundPhase").OnClientEvent:Connect(function(phase, data)
		if phase == "Waiting" then
			phaseLabel.Text = "Waiting for more players..."
		elseif phase == "Intermission" then
			phaseLabel.Text = string.format("Next round starts in %d...", data.timeLeft)
		elseif phase == "Playing" then
			phaseLabel.Text = ""
			phaseLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
			progressLabel.Text = "Loyalty Quota: 0 / 0"
			overtimeActive = false
			setOvertimeTint(false)
		elseif phase == "Results" then
			phaseLabel.Text = "Round over."
			overtimeActive = false
			setOvertimeTint(false)
		end
	end)

	Net.GetEvent("OvertimeStarted").OnClientEvent:Connect(function()
		overtimeActive = true
		setOvertimeTint(true)
		banner.TextColor3 = Color3.fromRGB(255, 60, 60)
		banner.Text = Config.Overtime.WarningText
		banner.Visible = true
		task.delay(8, function()
			if overtimeActive then
				banner.Visible = false
			end
		end)
		phaseLabel.TextColor3 = Color3.fromRGB(255, 60, 60)
		phaseLabel.Text = "OVERTIME"
	end)

	Net.GetEvent("MinigameProgress").OnClientEvent:Connect(function(completed, total, stationName)
		progressLabel.Text = string.format("Loyalty Quota: %d / %d", completed, total)
		banner.TextColor3 = Color3.fromRGB(255, 218, 26)
		banner.Text = stationName .. " CLEARED"
		banner.Visible = true
		task.delay(3, function()
			banner.Visible = false
		end)
	end)

	Net.GetEvent("ExitUnlocked").OnClientEvent:Connect(function()
		banner.TextColor3 = Color3.fromRGB(80, 255, 100)
		banner.Text = "THE LOADING DOCK IS OPEN. RUN."
		banner.Visible = true
		task.delay(6, function()
			banner.Visible = false
		end)
	end)

	local blackoutBannerActive = false
	Net.GetEvent("BlackoutEvent").OnClientEvent:Connect(function(starting)
		TweenService:Create(blackoutTint, TweenInfo.new(0.15), { Brightness = starting and -0.35 or 0 }):Play()
		if starting then
			blackoutBannerActive = true
			banner.TextColor3 = Color3.fromRGB(200, 200, 210)
			banner.Text = "THE LIGHTS JUST WENT OUT."
			banner.Visible = true
			task.delay(4, function()
				if blackoutBannerActive then
					banner.Visible = false
				end
			end)
		else
			blackoutBannerActive = false
		end
	end)

	local resultsGui = UIUtil.screenGui("ResultsGui")
	resultsGui.Enabled = false
	resultsGui.DisplayOrder = 45
	resultsGui.Parent = context.playerGui

	local resultsBackdrop = UIUtil.frame({
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.2,
	})
	resultsBackdrop.Parent = resultsGui

	local resultsTitle = UIUtil.label({
		Size = UDim2.new(0.8, 0, 0.1, 0),
		Position = UDim2.new(0.1, 0, 0.08, 0),
		TextScaled = true,
		TextStrokeTransparency = 0,
		Text = "ROUND RESULTS",
	})
	resultsTitle.Parent = resultsGui

	local list = UIUtil.frame({
		Size = UDim2.new(0.6, 0, 0.7, 0),
		Position = UDim2.new(0.2, 0, 0.2, 0),
		BackgroundTransparency = 1,
	})
	list.Parent = resultsGui

	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 4)
	listLayout.Parent = list

	Net.GetEvent("RoundResults").OnClientEvent:Connect(function(payload)
		for _, child in ipairs(list:GetChildren()) do
			if child:IsA("TextLabel") then
				child:Destroy()
			end
		end
		for _, entry in ipairs(payload) do
			local row = UIUtil.label({
				Size = UDim2.new(1, 0, 0, 32),
				TextScaled = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				Text = string.format("%s -- %s", entry.name, OUTCOME_FLAVOR[entry.state] or entry.state),
			})
			row.Parent = list
		end
		resultsGui.Enabled = true
		task.delay(Config.Round.ResultsScreenTime, function()
			resultsGui.Enabled = false
		end)
	end)
end

return HUDController
