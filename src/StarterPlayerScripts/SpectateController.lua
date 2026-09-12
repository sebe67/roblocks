-- Once the server flips our State attribute to "Spectating" we point the
-- camera at another alive player's Humanoid (CameraType.Custom does the
-- rest) and let , / . cycle targets.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Net = require(game:GetService("ReplicatedStorage").Shared.Net)
local UIUtil = require(script.Parent.UIUtil)

local SpectateController = {}

function SpectateController.Init(context)
	local player = context.player
	local camera = workspace.CurrentCamera
	local spectating = false
	local index = 1

	local gui = UIUtil.screenGui("SpectateGui")
	gui.Enabled = false
	gui.DisplayOrder = 30
	gui.Parent = context.playerGui

	local label = UIUtil.label({
		Size = UDim2.new(0.6, 0, 0.06, 0),
		Position = UDim2.new(0.2, 0, 0.9, 0),
		TextScaled = true,
		TextStrokeTransparency = 0,
		Text = "Spectating",
	})
	label.Parent = gui

	local function aliveTargets()
		local list = {}
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= player and p:GetAttribute("State") == "Alive" and p.Character then
				table.insert(list, p)
			end
		end
		return list
	end

	local function applyTarget()
		local targets = aliveTargets()
		if #targets == 0 then
			label.Text = "Spectating: nobody left alive"
			return
		end
		index = ((index - 1) % #targets) + 1
		local target = targets[index]
		local humanoid = target.Character and target.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			camera.CameraSubject = humanoid
			camera.CameraType = Enum.CameraType.Custom
			label.Text = "Spectating: " .. target.Name .. "  [ , prev | next . ]"
		end
	end

	local function startSpectating()
		spectating = true
		gui.Enabled = true
		index = 1
		applyTarget()
	end

	local function stopSpectating()
		spectating = false
		gui.Enabled = false
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			camera.CameraSubject = humanoid
		end
		camera.CameraType = Enum.CameraType.Custom
	end

	player:GetAttributeChangedSignal("State"):Connect(function()
		local state = player:GetAttribute("State")
		if state == "Spectating" then
			startSpectating()
		elseif spectating and state ~= "Spectating" then
			stopSpectating()
		end
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if not spectating or processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.Comma then
			index -= 1
			applyTarget()
		elseif input.KeyCode == Enum.KeyCode.Period then
			index += 1
			applyTarget()
		end
	end)

	Net.GetEvent("RoundSpawn").OnClientEvent:Connect(function()
		if spectating then
			stopSpectating()
		end
	end)
end

return SpectateController
