--!strict
--[[
	Zone light states. The server decides the state of each zone and publishes it as the
	`LightState` attribute on the zone folder; clients animate the fixtures locally (flicker,
	dimming, emergency red) so nothing per-frame crosses the network.

	States: Normal | Emergency (panel down) | Off | Flicker | Hunt
]]

local Registry = require(script.Parent.Registry)
local World = require(script.Parent.World)

local Lighting = {}

-- Which breaker panel feeds which zones.
Lighting.PanelZones = {
	A = { "Workshop", "Transmitter", "AntennaAccess", "EastCorridor", "Editing", "TapeArchive" },
	B = { "BasementHall", "BoilerRoom", "GeneratorRoom", "Electrical", "StudioB", "Stairwell", "CableCorridor" },
}

Lighting.Wings = {
	West = { "Offices", "Lockers", "WestCorridor", "StudioA" },
	East = { "Workshop", "Transmitter", "EastCorridor", "Editing", "TapeArchive" },
	Basement = { "BasementHall", "BoilerRoom", "GeneratorRoom", "Electrical", "CableCorridor" },
}

type Override = { state: string, untilTime: number }
local overrides: { [string]: Override } = {}

local function powered(zone: string): boolean
	local signal = Registry.Signal.model
	if table.find(Lighting.PanelZones.A, zone) and not signal.panelA then
		return false
	end
	if table.find(Lighting.PanelZones.B, zone) and not signal.panelB then
		return false
	end
	return true
end

local function apply(zone: string)
	local now = os.clock()
	local override = overrides[zone]
	local state = if powered(zone) then "Normal" else "Emergency"
	if override and override.untilTime > now then
		state = override.state
	elseif override then
		overrides[zone] = nil
	end
	World.setZoneAttribute(zone, "LightState", state)
end

function Lighting.refreshPower()
	for zone in World.zoneFolders do
		apply(zone)
	end
end

-- Temporarily forces a zone into a state (the longer/stronger override wins).
function Lighting.override(zone: string, state: string, duration: number)
	local untilTime = os.clock() + duration
	local current = overrides[zone]
	if current and current.untilTime > untilTime and current.state == "Off" then
		return
	end
	overrides[zone] = { state = state, untilTime = untilTime }
	apply(zone)
end

function Lighting.clear(zone: string)
	overrides[zone] = nil
	apply(zone)
end

function Lighting.flickerAll(duration: number)
	for zone in World.zoneFolders do
		if zone ~= "Exterior" then
			Lighting.override(zone, "Flicker", duration)
		end
	end
end

function Lighting.reset()
	table.clear(overrides)
	Lighting.refreshPower()
	for zone in World.zoneFolders do
		World.setZoneAttribute(zone, "MonitorsOn", true)
	end
end

function Lighting.step()
	for zone, override in overrides do
		if override.untilTime <= os.clock() then
			apply(zone)
		end
	end
end

return Lighting
