-- Global Lighting setup ("dim but not too dark") plus a lightweight
-- ambient flicker loop over the dead-but-flicker-capable ceiling fixtures
-- the MazeGenerator scattered through the store.

local Lighting = game:GetService("Lighting")
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local StoreTheme = {}

function StoreTheme.Apply()
	local cfg = Config.Lighting
	Lighting.Brightness = cfg.Brightness
	Lighting.Ambient = cfg.Ambient
	Lighting.OutdoorAmbient = cfg.OutdoorAmbient
	Lighting.ExposureCompensation = cfg.ExposureCompensation
	Lighting.ClockTime = 0
	Lighting.GlobalShadows = true
	Lighting.FogColor = cfg.FogColor
	Lighting.FogStart = cfg.FogStart
	Lighting.FogEnd = cfg.FogEnd

	if not Lighting:FindFirstChildOfClass("Atmosphere") then
		local atmosphere = Instance.new("Atmosphere")
		atmosphere.Density = 0.35
		atmosphere.Offset = 0.2
		atmosphere.Color = cfg.FogColor
		atmosphere.Decay = Color3.fromRGB(10, 10, 14)
		atmosphere.Glare = 0
		atmosphere.Haze = 1.6
		atmosphere.Parent = Lighting
	end

	if not Lighting:FindFirstChildOfClass("ColorCorrectionEffect") then
		local cc = Instance.new("ColorCorrectionEffect")
		cc.Brightness = -0.02
		cc.Contrast = 0.08
		cc.Saturation = -0.08
		cc.TintColor = Color3.fromRGB(235, 235, 255)
		cc.Parent = Lighting
	end
end

-- Every ceiling light is its own addressable Part ("Fixture_x_y" under
-- maze.model.Fixtures, one per grid cell) with its own PointLight -- there's
-- no single shared light to dim, each one can be driven independently.
function StoreTheme.GetFixture(maze, x, y)
	local fixturesFolder = maze.model:FindFirstChild("Fixtures")
	return fixturesFolder and fixturesFolder:FindFirstChild(string.format("Fixture_%d_%d", x, y))
end

-- Turns one specific ceiling fixture on or off -- for a scripted
-- power-outage event, a monster ability that kills nearby lights, a puzzle,
-- whatever. Updates the PointLight, the fixture's own glow color, and its
-- "Working" attribute together, so a scripted toggle behaves exactly like a
-- naturally-dead fixture would to everything that already reads that
-- attribute (MonsterAI:_inDarkCell, and through it the Grinch's darkBoost
-- sight-range quirk).
function StoreTheme.SetFixtureWorking(maze, x, y, working)
	local fixture = StoreTheme.GetFixture(maze, x, y)
	if not fixture then
		return false
	end
	local cfg = Config.Lighting
	local light = fixture:FindFirstChildOfClass("PointLight")
	if working then
		if not light then
			light = Instance.new("PointLight")
			light.Range = cfg.FixtureRange
			light.Brightness = cfg.FixtureBrightness
			light.Color = cfg.FixtureColor
			light.Parent = fixture
		end
		light.Enabled = true
		fixture.Color = cfg.FixtureColor
		fixture:SetAttribute("Working", true)
		fixture:SetAttribute("Flickering", nil)
	else
		if light then
			light.Enabled = false
		end
		fixture.Color = Color3.fromRGB(60, 60, 60)
		fixture:SetAttribute("Working", false)
		fixture:SetAttribute("Flickering", nil)
	end
	return true
end

-- Randomly clicks a handful of "dead" fixtures on for a moment then off
-- again, sourced from Fixture parts tagged Flickering=true by MazeGenerator.
function StoreTheme.StartFlicker(storeModel)
	local fixturesFolder = storeModel:FindFirstChild("Fixtures")
	if not fixturesFolder then
		return
	end

	local flickerFixtures = {}
	for _, fixture in ipairs(fixturesFolder:GetChildren()) do
		if fixture:GetAttribute("Flickering") then
			local light = fixture:FindFirstChildOfClass("PointLight")
			if light then
				table.insert(flickerFixtures, light)
			end
		end
	end

	if #flickerFixtures == 0 then
		return
	end

	task.spawn(function()
		while true do
			task.wait(math.random(20, 45) / 10)
			local light = flickerFixtures[math.random(1, #flickerFixtures)]
			light.Enabled = true
			for _ = 1, math.random(2, 5) do
				task.wait(math.random(1, 3) / 20)
				light.Enabled = not light.Enabled
			end
			light.Enabled = false
		end
	end)
end

return StoreTheme
