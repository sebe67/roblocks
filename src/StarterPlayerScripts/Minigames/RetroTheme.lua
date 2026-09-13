-- Shared 8-bit look for the minigame overlay: pixel font, flat high-contrast
-- colors, and square (unrounded) buttons/panels with a thick border instead
-- of the rest of the game's softer rounded UI style -- deliberately
-- different so "you're inside a CRS Loyalty Task" reads instantly. The
-- games' mechanics are untouched; this only reskins how their UI is drawn.

local UIUtil = require(script.Parent.Parent.UIUtil)

local RetroTheme = {}

-- Enum.Font.Code: a genuinely ancient, guaranteed-to-exist legacy monospace
-- font. A flashier pixel-art Google Font (e.g. "Press Start 2P") would look
-- more authentically 8-bit, but referencing a font that turns out not to
-- exist in Enum.Font throws the instant this module loads -- and since
-- Main.client.lua requires MinigameController (which requires this module)
-- before HUDController, that error was taking down the ENTIRE client script
-- chain, silently skipping every controller listed after it (no
-- Intermission countdown, no minigame overlay -- a total soft-lock). Code
-- still reads as "terminal/retro" and can't do that.
RetroTheme.Font = Enum.Font.Code

RetroTheme.Colors = {
	Background = Color3.fromRGB(12, 12, 24),
	Panel = Color3.fromRGB(22, 22, 42),
	Border = Color3.fromRGB(255, 218, 26),
	Text = Color3.fromRGB(255, 255, 255),
	Dim = Color3.fromRGB(180, 180, 200),
	Accent = Color3.fromRGB(80, 220, 220),
	Success = Color3.fromRGB(90, 230, 120),
	Danger = Color3.fromRGB(230, 80, 80),
}

local function squareCorners(instance)
	local corner = instance:FindFirstChildOfClass("UICorner")
	if corner then
		corner:Destroy()
	end
end

-- Adds a flat, unblurred border -- the pixel-art "outline" look -- to any
-- GuiObject. Exposed on its own so individual minigames can crisp up a key
-- visual element (a track, a grid cell) without going through panel/button.
function RetroTheme.outline(instance, color, thickness)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = thickness or 3
	stroke.Color = color or RetroTheme.Colors.Border
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = instance
	return stroke
end

function RetroTheme.panel(props)
	local merged = { BackgroundColor3 = RetroTheme.Colors.Panel }
	for k, v in pairs(props or {}) do
		merged[k] = v
	end
	local p = UIUtil.frame(merged)
	squareCorners(p)
	RetroTheme.outline(p)
	return p
end

function RetroTheme.label(props)
	local merged = { Font = RetroTheme.Font, TextColor3 = RetroTheme.Colors.Text }
	for k, v in pairs(props or {}) do
		merged[k] = v
	end
	return UIUtil.label(merged)
end

function RetroTheme.button(props)
	local merged = { Font = RetroTheme.Font, TextColor3 = RetroTheme.Colors.Text }
	for k, v in pairs(props or {}) do
		merged[k] = v
	end
	local b = UIUtil.button(merged)
	squareCorners(b)
	RetroTheme.outline(b, RetroTheme.Colors.Border, 3)
	return b
end

return RetroTheme
