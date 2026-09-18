-- Global Lighting setup ("dim but not too dark"), a lightweight ambient
-- flicker loop over the dead-but-flicker-capable ceiling fixtures the
-- MazeGenerator scattered through the store, and the light-suppression
-- system (random blackouts + SpongeBob's lightsOut quirk) that sits on top
-- of both.

local Lighting = game:GetService("Lighting")
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
local Net = require(game:GetService("ReplicatedStorage").Shared.Net)

local StoreTheme = {}

-- Several independent systems (a random blackout, SpongeBob standing
-- nearby) can each want a given fixture off at once; a fixture only
-- actually turns back on once every one of them has released it. Keyed by
-- fixture instance, value is how many active suppressors currently want it
-- off -- a missing/zero entry means "nobody's suppressing this one."
local suppressCounts = setmetatable({}, { __mode = "k" })
local blackoutActive = false
local blackoutsEnabled = false
local blackoutEvent = Net.GetEvent("BlackoutEvent")

local function applyFixtureVisual(fixture)
	local light = fixture:FindFirstChildOfClass("PointLight")
	local naturallyOn = fixture:GetAttribute("NaturallyOn")
	local lit = naturallyOn and (suppressCounts[fixture] or 0) <= 0
	if light then
		light.Enabled = lit
	end
	fixture.Color = lit and Config.Lighting.FixtureColor or Color3.fromRGB(60, 60, 60)
	fixture:SetAttribute("Working", lit)
end

-- Adds one suppressor to a fixture (turning it off if this is the first).
-- Safe to call on a fixture that was never naturally lit -- it just has
-- nothing to turn off.
function StoreTheme.SuppressFixture(fixture)
	if not fixture then
		return
	end
	suppressCounts[fixture] = (suppressCounts[fixture] or 0) + 1
	applyFixtureVisual(fixture)
end

-- Removes one suppressor; the fixture only actually re-lights once its
-- count reaches zero. Clamped so a stray extra release (e.g. a blackout
-- force-ending while its own timer is also about to fire) can't go
-- negative and leave the fixture permanently "owed" a suppression.
function StoreTheme.ReleaseFixture(fixture)
	if not fixture then
		return
	end
	local n = math.max((suppressCounts[fixture] or 0) - 1, 0)
	if n == 0 then
		suppressCounts[fixture] = nil
	else
		suppressCounts[fixture] = n
	end
	applyFixtureVisual(fixture)
end

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

-- Turns one specific ceiling fixture on or off long-term -- for a scripted
-- event, a puzzle, whatever -- as opposed to SuppressFixture/ReleaseFixture,
-- which are a temporary, stackable override on top of this. Sets its
-- permanent "NaturallyOn" assignment and re-applies the visual (which still
-- respects any active suppression, so switching this on while a blackout or
-- SpongeBob currently has it suppressed correctly leaves it dark until
-- that's released).
function StoreTheme.SetFixtureWorking(maze, x, y, working)
	local fixture = StoreTheme.GetFixture(maze, x, y)
	if not fixture then
		return false
	end
	if working and not fixture:FindFirstChildOfClass("PointLight") then
		local light = Instance.new("PointLight")
		light.Range = Config.Lighting.FixtureRange
		light.Brightness = Config.Lighting.FixtureBrightness
		light.Color = Config.Lighting.FixtureColor
		light.Parent = fixture
	end
	fixture:SetAttribute("NaturallyOn", working)
	fixture:SetAttribute("Flickering", nil)
	applyFixtureVisual(fixture)
	return true
end

-- Enables/disables the random blackout loop -- gated to an active Playing
-- round by GameState, same pattern as pausing the monsters. Turning it off
-- also immediately ends any blackout in progress so a round never ends
-- (into Intermission/Results) with the lights still out.
function StoreTheme.SetBlackoutsEnabled(maze, enabled)
	blackoutsEnabled = enabled
	if not enabled and blackoutActive then
		StoreTheme.ForceEndBlackout(maze)
	end
end

-- Immediately restores every fixture the current blackout suppressed,
-- without waiting for its own Duration timer. The timer's own release loop
-- still runs afterward and finds nothing left to release (ReleaseFixture is
-- clamped at zero), so this is safe to call at any point.
function StoreTheme.ForceEndBlackout(maze)
	if not blackoutActive then
		return
	end
	blackoutActive = false
	blackoutEvent:FireAllClients(false)
	local fixturesFolder = maze.model:FindFirstChild("Fixtures")
	if not fixturesFolder then
		return
	end
	for _, fixture in ipairs(fixturesFolder:GetChildren()) do
		if fixture:GetAttribute("NaturallyOn") and (suppressCounts[fixture] or 0) > 0 then
			StoreTheme.ReleaseFixture(fixture)
		end
	end
end

-- Flickers a set of currently-lit fixtures for `duration` seconds -- a
-- warning beat before the real cutout instead of snapping straight from
-- lit to dark. Bails out early (mid-flicker) if the blackout it's warming
-- up for gets force-ended (round over, etc.) -- checked via the
-- `blackoutActive` upvalue, set true by the caller before this runs.
local function preCutoutFlicker(fixtures, duration)
	local lights = {}
	for _, fixture in ipairs(fixtures) do
		local light = fixture:FindFirstChildOfClass("PointLight")
		-- Only flicker lights that are actually ON right now -- one already
		-- dark because SpongeBob is standing under it stays exactly as dark
		-- as his own quirk left it, and gets restored to that same state
		-- (not forced back on) once the flicker phase ends.
		if light and light.Enabled then
			table.insert(lights, light)
		end
	end
	if #lights == 0 then
		task.wait(duration)
		return
	end
	local elapsed = 0
	while elapsed < duration and blackoutActive do
		local step = math.random(6, 14) / 40
		for _, light in ipairs(lights) do
			if math.random() < 0.6 then
				light.Enabled = not light.Enabled
			end
		end
		task.wait(step)
		elapsed += step
	end
	for _, light in ipairs(lights) do
		light.Enabled = true
	end
end

-- Kills every currently-lit fixture for Config.Blackout.Duration seconds,
-- then restores exactly the ones it turned off (anything SpongeBob is also
-- suppressing at that moment correctly stays dark -- see
-- SuppressFixture/ReleaseFixture's reference counting).
function StoreTheme.TriggerBlackout(maze)
	if blackoutActive then
		return
	end
	local fixturesFolder = maze.model:FindFirstChild("Fixtures")
	if not fixturesFolder then
		return
	end

	local affected = {}
	for _, fixture in ipairs(fixturesFolder:GetChildren()) do
		if fixture:GetAttribute("NaturallyOn") then
			table.insert(affected, fixture)
		end
	end
	if #affected == 0 then
		return
	end

	blackoutActive = true
	preCutoutFlicker(affected, Config.Blackout.PreFlickerDuration)
	if not blackoutActive then
		-- ForceEndBlackout fired mid-flicker -- nothing was ever actually
		-- suppressed, so there's nothing left to do.
		return
	end

	blackoutEvent:FireAllClients(true)
	for _, fixture in ipairs(affected) do
		StoreTheme.SuppressFixture(fixture)
	end

	task.wait(Config.Blackout.Duration)

	if blackoutActive then
		for _, fixture in ipairs(affected) do
			StoreTheme.ReleaseFixture(fixture)
		end
		blackoutActive = false
		blackoutEvent:FireAllClients(false)
	end
end

-- Starts the background loop that rolls the dice for a random blackout.
-- Call once at server boot; StoreTheme.SetBlackoutsEnabled gates whether it
-- can actually fire (only during an active Playing round).
function StoreTheme.StartBlackoutLoop(maze)
	task.spawn(function()
		while true do
			task.wait(Config.Blackout.CheckInterval)
			if blackoutsEnabled and not blackoutActive then
				if math.random() < (Config.Blackout.CheckInterval / Config.Blackout.AverageInterval) then
					StoreTheme.TriggerBlackout(maze)
				end
			end
		end
	end)
end

-- Randomly clicks a handful of "dead" fixtures on for a moment then off
-- again (an occasional single flicker, unpredictable across the whole
-- map), PLUS a small number of permanently-flickering clusters -- a few
-- nearby dead fixtures that flicker together continuously instead of
-- returning to a steady off state, so at least a couple of spots read as
-- "this whole corner's wiring is bad" rather than one solitary blinking
-- bulb. Both draw from the same pool of Fixture parts tagged
-- Flickering=true by MazeGenerator; a fixture claimed by a group is
-- removed from the occasional-single pool so it's never double-booked.
function StoreTheme.StartFlicker(storeModel)
	local fixturesFolder = storeModel:FindFirstChild("Fixtures")
	if not fixturesFolder then
		return
	end

	local candidates = {}
	for _, fixture in ipairs(fixturesFolder:GetChildren()) do
		if fixture:GetAttribute("Flickering") then
			local light = fixture:FindFirstChildOfClass("PointLight")
			local xStr, yStr = fixture.Name:match("Fixture_(%d+)_(%d+)")
			if light and xStr then
				table.insert(candidates, { light = light, x = tonumber(xStr), y = tonumber(yStr) })
			end
		end
	end
	if #candidates == 0 then
		return
	end

	local function runGroup(members)
		task.spawn(function()
			while true do
				task.wait(math.random(2, 6) / 10)
				if not blackoutActive then
					for _, m in ipairs(members) do
						if math.random() < 0.5 then
							m.light.Enabled = not m.light.Enabled
						end
					end
				end
			end
		end)
	end

	local claimed = {}
	local minSize, maxSize = Config.Lighting.PermanentFlickerGroupSize[1], Config.Lighting.PermanentFlickerGroupSize[2]
	local radius = Config.Lighting.PermanentFlickerGroupRadius
	for _ = 1, Config.Lighting.PermanentFlickerGroups do
		local pool = {}
		for _, c in ipairs(candidates) do
			if not claimed[c] then
				table.insert(pool, c)
			end
		end
		if #pool == 0 then
			break
		end

		-- Seed the cluster, then greedily grab nearby unclaimed candidates
		-- (within `radius` grid cells) to fill it out.
		local seed = pool[math.random(1, #pool)]
		local group = { seed }
		claimed[seed] = true
		for _, c in ipairs(pool) do
			if #group >= maxSize then
				break
			end
			if c ~= seed and math.abs(c.x - seed.x) <= radius and math.abs(c.y - seed.y) <= radius then
				table.insert(group, c)
				claimed[c] = true
			end
		end

		if #group >= minSize then
			runGroup(group)
		else
			-- Not enough nearby dead fixtures to make a real cluster here --
			-- release the claim rather than leaving a lone flickerer.
			for _, c in ipairs(group) do
				claimed[c] = nil
			end
		end
	end

	local singleLights = {}
	for _, c in ipairs(candidates) do
		if not claimed[c] then
			table.insert(singleLights, c.light)
		end
	end
	if #singleLights == 0 then
		return
	end

	task.spawn(function()
		while true do
			task.wait(math.random(20, 45) / 10)
			-- Skip a flicker entirely during a blackout -- "the power's out"
			-- shouldn't have dead fixtures spontaneously sparking to life.
			if not blackoutActive then
				local light = singleLights[math.random(1, #singleLights)]
				light.Enabled = true
				for _ = 1, math.random(2, 5) do
					task.wait(math.random(1, 3) / 20)
					light.Enabled = not light.Enabled
				end
				light.Enabled = false
			end
		end
	end)
end

return StoreTheme
