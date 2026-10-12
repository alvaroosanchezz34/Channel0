--!strict
--[[
	Local animation of the station's hardware, driven by replicated state:
	  * fixtures per zone from the zone's LightState (Normal/Emergency/Off/Flicker/Hunt)
	  * the ON AIR sign, studio tally lights, transmitter glow, camera LEDs
	  * wall clocks (hands stall at 02:16 when the night is waiting on the crew)
	  * the tuner cabinet readout
	  * THE ANCHOR's chroma ghosts and tracking tear (local jitter, never replicated per frame)
	Everything here is cosmetic; the server never depends on it.
]]

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Net = require(script.Parent.Net)
local Store = require(script.Parent.Store)

local StationFX = {}

type Fixture = { lights: { Light }, neon: { BasePart }, zone: string, phase: number }

local fixtures: { Fixture } = {}
local zoneFolders: { [string]: Instance } = {}
local clocks: { { hour: BasePart, minute: BasePart, hourPivot: CFrame, minutePivot: CFrame, hourOffset: CFrame, minuteOffset: CFrame } } =
	{}
local rng = Random.new()
local time = 0

local function collect(station: Instance)
	for _, model in CollectionService:GetTagged("Fixture") do
		if model:IsDescendantOf(station) then
			local fixture: Fixture = {
				lights = {},
				neon = {},
				zone = (model:GetAttribute("Zone") :: string?) or "Exterior",
				phase = rng:NextNumber(0, 10),
			}
			for _, d in model:GetDescendants() do
				if d:IsA("Light") then
					if d:GetAttribute("BaseBrightness") == nil then
						d:SetAttribute("BaseBrightness", d.Brightness)
					end
					table.insert(fixture.lights, d)
				elseif d:IsA("BasePart") and d.Material == Enum.Material.Neon then
					if d:GetAttribute("BaseColor") == nil then
						d:SetAttribute("BaseColor", d.Color)
					end
					table.insert(fixture.neon, d)
				end
			end
			table.insert(fixtures, fixture)
		end
	end
	local zones = station:FindFirstChild("Zones")
	if zones then
		for _, folder in zones:GetChildren() do
			zoneFolders[folder.Name] = folder
		end
	end
	for _, model in CollectionService:GetTagged("WallClock") do
		if model:IsDescendantOf(station) then
			local hour = model:FindFirstChild("HourHand") :: BasePart?
			local minute = model:FindFirstChild("MinuteHand") :: BasePart?
			local hp = hour and hour:GetAttribute("Pivot") :: CFrame?
			local mp = minute and minute:GetAttribute("Pivot") :: CFrame?
			if hour and minute and hp and mp then
				table.insert(clocks, {
					hour = hour,
					minute = minute,
					hourPivot = hp,
					minutePivot = mp,
					hourOffset = hp:Inverse() * hour.CFrame,
					minuteOffset = mp:Inverse() * minute.CFrame,
				})
			end
		end
	end
end

local function stateOf(zone: string): string
	local folder = zoneFolders[zone]
	local state = folder and folder:GetAttribute("LightState")
	return if type(state) == "string" then state else "Normal"
end

local function applyFixture(fixture: Fixture, state: string)
	local factor = 1
	local tint: Color3? = nil
	if state == "Off" then
		factor = 0
	elseif state == "Emergency" then
		factor = 0.22
		tint = Color3.fromRGB(255, 70, 50)
	elseif state == "Flicker" then
		local n = math.noise(time * 9, fixture.phase)
		factor = if n > 0.05 then 1 elseif n > -0.25 then 0.25 else 0
	elseif state == "Hunt" then
		-- Studio lights coming up: hard, cold, stuttering.
		local beat = math.floor(time * 6 + fixture.phase) % 4
		factor = if beat == 0 then 2.2 elseif beat == 2 then 0.1 else 1.4
		tint = Color3.fromRGB(205, 225, 255)
	end
	for _, light in fixture.lights do
		local base = (light:GetAttribute("BaseBrightness") :: number?) or 1
		light.Brightness = base * factor
		light.Enabled = factor > 0.01
		if tint then
			light.Color = tint
		elseif light:GetAttribute("BaseColor") then
			light.Color = light:GetAttribute("BaseColor") :: Color3
		end
	end
	for _, part in fixture.neon do
		local base = (part:GetAttribute("BaseColor") :: Color3?) or part.Color
		local c = if tint then tint:Lerp(base, 0.4) else base
		part.Color = Color3.new(c.R * math.min(1, factor), c.G * math.min(1, factor), c.B * math.min(1, factor))
	end
end

local function setNeon(tag: string, on: boolean, onColor: Color3, offColor: Color3)
	for _, part in CollectionService:GetTagged(tag) do
		if part:IsA("BasePart") then
			part.Color = if on then onColor else offColor
			part.Material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
			local light = part:FindFirstChildWhichIsA("Light")
			if light then
				light.Enabled = on
			end
		end
	end
end

local function updateClocks()
	local clock = Net.state(Net.Attr.Clock)
	if type(clock) ~= "number" then
		clock = -20
	end
	local minutes = clock % (12 * 60)
	local minuteAngle = -math.rad((minutes % 60) * 6)
	local hourAngle = -math.rad((minutes / 60) * 30)
	for _, c in clocks do
		c.minute.CFrame = c.minutePivot * CFrame.Angles(0, 0, minuteAngle) * c.minuteOffset
		c.hour.CFrame = c.hourPivot * CFrame.Angles(0, 0, hourAngle) * c.hourOffset
	end
end

local lastState: { [string]: string } = {}
local slowTimer = 0

local function update(dt: number)
	time += dt
	-- Only animated states need per-frame work; static states are applied on change.
	for _, fixture in fixtures do
		local state = stateOf(fixture.zone)
		if state == "Flicker" or state == "Hunt" or lastState[fixture.zone] ~= state then
			applyFixture(fixture, state)
		end
	end
	for zone in zoneFolders do
		lastState[zone] = stateOf(zone)
	end

	slowTimer += dt
	if slowTimer < 0.2 then
		return
	end
	slowTimer = 0
	local signal = Store.signal
	local anchorState = Net.state(Net.Attr.AnchorState)
	local onAir = (signal.quality or 0) > 22 and not signal.deadAir
	setNeon("OnAirSign", onAir, Color3.fromRGB(255, 40, 30), Color3.fromRGB(60, 10, 10))
	local studioLive = Net.state(Net.Attr.ProgramSource) == "Studio" or anchorState == "Broadcast"
	setNeon("TallyLight", studioLive, Color3.fromRGB(255, 20, 20), Color3.fromRGB(50, 8, 8))
	local q = (signal.quality or 0) / 100
	for _, part in CollectionService:GetTagged("TransmitterGlow") do
		if part:IsA("BasePart") then
			part.Color = Color3.fromRGB(255, 120, 40):Lerp(Color3.fromRGB(30, 10, 5), 1 - q)
		end
	end
	local blink = math.floor(time * 1.2) % 2 == 0
	for _, led in CollectionService:GetTagged("CameraLED") do
		if led:IsA("BasePart") then
			led.Color = if blink then Color3.fromRGB(255, 30, 20) else Color3.fromRGB(60, 8, 6)
		end
	end
	-- Tuner readout on the cabinet.
	for _, dial in CollectionService:GetTagged("TunerDial") do
		local cabinet = dial.Parent
		local face = cabinet and cabinet:FindFirstChild("Face")
		local gui = face and face:FindFirstChild("FreqReadout")
		local label = gui and gui:FindFirstChildOfClass("TextLabel")
		if label and signal.frequency then
			label.Text =
				string.format("EXCITER  %06.2f MHz%s", signal.frequency, if signal.tuningLocked then "  [LOCK]" else "")
		end
	end
	updateClocks()
end

-- Chroma ghosts on THE ANCHOR: a local, per-frame jitter so he never looks solid.
local function updateAnchor()
	local model = Workspace:FindFirstChild("TheAnchor")
	if not model or model:GetAttribute("Visible") ~= true then
		return
	end
	local reduce = Store.settings.reduceMotion
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d:HasTag("AnchorGhost") then
			local offset = (d:GetAttribute("Offset") :: number?) or 0.1
			local amount = if reduce then offset * 0.3 else offset * (0.6 + rng:NextNumber() * 0.8)
			d.LocalTransparencyModifier = if rng:NextNumber() < 0.15 then 1 else 0
			local weld = d:FindFirstChildWhichIsA("Weld")
			if weld then
				weld.C0 = CFrame.new(amount * (if offset > 0 then 1 else -1), 0, 0)
			end
		elseif d:IsA("BasePart") and d:HasTag("AnchorGlitch") then
			d.LocalTransparencyModifier = if rng:NextNumber() < 0.5 then 0 else 1
		end
	end
end

function StationFX.init()
	local station = Workspace:WaitForChild("Station", 60)
	if not station then
		return
	end
	collect(station)
	RunService.RenderStepped:Connect(function(dt)
		update(dt)
		updateAnchor()
	end)
end

return StationFX
