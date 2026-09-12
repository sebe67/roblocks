-- Small helpers so every controller builds UI the same way without a Studio
-- GUI-editing pass. Swap fonts/colors here to reskin everything at once.

local UIUtil = {}

function UIUtil.screenGui(name)
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	return gui
end

function UIUtil.frame(props)
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	for k, v in pairs(props or {}) do
		f[k] = v
	end
	return f
end

function UIUtil.label(props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.FredokaOne
	l.TextColor3 = Color3.fromRGB(255, 255, 255)
	l.TextStrokeColor3 = Color3.new(0, 0, 0)
	for k, v in pairs(props or {}) do
		l[k] = v
	end
	return l
end

function UIUtil.button(props)
	local b = Instance.new("TextButton")
	b.Font = Enum.Font.FredokaOne
	b.TextColor3 = Color3.fromRGB(255, 255, 255)
	b.BorderSizePixel = 0
	b.AutoButtonColor = true
	for k, v in pairs(props or {}) do
		b[k] = v
	end
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = b
	return b
end

return UIUtil
