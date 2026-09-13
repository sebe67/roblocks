local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
local Net = require(game:GetService("ReplicatedStorage").Shared.Net)
local SoundKit = require(game:GetService("ReplicatedStorage").Shared.SoundKit)
local UIUtil = require(script.Parent.UIUtil)
local CursorLock = require(script.Parent.CursorLock)

local DeathController = {}

local monsterById = {}
for _, def in ipairs(Config.Monsters) do
	monsterById[def.id] = def
end

function DeathController.Init(context)
	local gui = UIUtil.screenGui("DeathGui")
	gui.Enabled = false
	gui.DisplayOrder = 40
	gui.Parent = context.playerGui

	local backdrop = UIUtil.frame({
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.35,
	})
	backdrop.Parent = gui

	local title = UIUtil.label({
		Size = UDim2.new(0.8, 0, 0.15, 0),
		Position = UDim2.new(0.1, 0, 0.25, 0),
		TextScaled = true,
		TextStrokeTransparency = 0,
		Text = "YOU DIED",
	})
	title.Parent = gui

	local subtitle = UIUtil.label({
		Size = UDim2.new(0.7, 0, 0.08, 0),
		Position = UDim2.new(0.15, 0, 0.4, 0),
		TextScaled = true,
		TextColor3 = Color3.fromRGB(210, 210, 210),
		Text = "",
	})
	subtitle.Parent = gui

	local respawnBtn = UIUtil.button({
		Size = UDim2.new(0.25, 0, 0.08, 0),
		Position = UDim2.new(0.2, 0, 0.55, 0),
		BackgroundColor3 = Color3.fromRGB(60, 170, 90),
		TextScaled = true,
		Text = "Respawn",
	})
	respawnBtn.Parent = gui

	local spectateBtn = UIUtil.button({
		Size = UDim2.new(0.25, 0, 0.08, 0),
		Position = UDim2.new(0.55, 0, 0.55, 0),
		BackgroundColor3 = Color3.fromRGB(90, 90, 200),
		TextScaled = true,
		Text = "Spectate",
	})
	spectateBtn.Parent = gui

	local respawnEvent = Net.GetEvent("RequestRespawn")
	local spectateEvent = Net.GetEvent("RequestSpectate")
	local menuOpen = false

	local function closeMenu()
		gui.Enabled = false
		if menuOpen then
			menuOpen = false
			CursorLock.Pop(context.player)
		end
	end

	respawnBtn.MouseButton1Click:Connect(function()
		SoundKit.PlayUI(Config.Sounds.UIClick, { Volume = 0.5 })
		respawnEvent:FireServer()
		closeMenu()
	end)
	spectateBtn.MouseButton1Click:Connect(function()
		SoundKit.PlayUI(Config.Sounds.UIClick, { Volume = 0.5 })
		spectateEvent:FireServer()
		closeMenu()
	end)

	-- The camera locks the mouse to screen-center in first person (and
	-- re-locks it every frame even if we fight it once), so there's no way
	-- to click Respawn/Spectate without dropping out of that mode while
	-- this menu is up.
	Net.GetEvent("ShowDeathMenu").OnClientEvent:Connect(function(monsterId)
		if monsterId == "TimedOut" then
			title.Text = "THE STORE CLOSED. YOU DID NOT MAKE IT."
			subtitle.Text = "Ratio'd by the loading dock clock."
		else
			local def = monsterById[monsterId]
			title.Text = def and ("CAUGHT BY " .. string.upper(def.displayName)) or "YOU DIED"
			subtitle.Text = def and def.flavor or ""
		end
		gui.Enabled = true
		menuOpen = true
		CursorLock.Push(context.player)
	end)

	local escapedGui = UIUtil.screenGui("EscapedGui")
	escapedGui.Enabled = false
	escapedGui.DisplayOrder = 40
	escapedGui.Parent = context.playerGui
	local escLabel = UIUtil.label({
		Size = UDim2.new(0.8, 0, 0.2, 0),
		Position = UDim2.new(0.1, 0, 0.4, 0),
		TextScaled = true,
		TextColor3 = Color3.fromRGB(120, 255, 140),
		TextStrokeTransparency = 0,
		Text = "YOU ESCAPED. Certified W rizz.",
	})
	escLabel.Parent = escapedGui

	Net.GetEvent("PlayerEscaped").OnClientEvent:Connect(function()
		escapedGui.Enabled = true
		task.delay(6, function()
			escapedGui.Enabled = false
		end)
	end)

	Net.GetEvent("RoundSpawn").OnClientEvent:Connect(function()
		closeMenu()
		escapedGui.Enabled = false
	end)
end

return DeathController
