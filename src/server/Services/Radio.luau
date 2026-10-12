--!strict
--[[
	The dial. The exciter tuner doubles as a receiver: whatever frequency it sits on plays through
	the monitor speaker in the Transmitter Room. Every station carries something useful: rules,
	warnings, the Night Desk prophecy (lines composed from what the director and THE ANCHOR are
	ABOUT to do), the zero channel, and teammates who have been taken.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Frequencies = require(Shared.Content.Frequencies)
local PhaseOrder = require(Shared.Logic.PhaseOrder)

local Registry = require(script.Parent.Registry)
local Remotes = require(script.Parent.Remotes)
local State = require(script.Parent.State)
local World = require(script.Parent.World)

local Radio = {}

type Line = { key: string, vars: { [string]: any }? }

local prophecy: { Line } = {}
local loopIndex: { [string]: number } = {}
local timer = 0
local LISTEN_RADIUS = 34

function Radio.prophesy(key: string, vars: { [string]: any }?)
	table.insert(prophecy, { key = key, vars = vars })
	while #prophecy > 4 do
		table.remove(prophecy, 1)
	end
end

-- The next Night Desk line without consuming it (radio_future event).
function Radio.peek(): Line?
	return prophecy[1]
end

local function listeners(): { Player }
	local speaker = World.marker("RadioSpeaker")
	local list = {}
	for _, member in State.members({ "Active" }) do
		local position = World.positionOf(member.player)
		if
			position
			and (member.zone == "Transmitter" or (speaker and (position - speaker.Position).Magnitude <= LISTEN_RADIUS))
		then
			table.insert(list, member.player)
		end
	end
	return list
end

-- What is audible at `mhz`: station id, clarity 0..1, and the line to say.
local function resolve(mhz: number): (string?, number, Line?)
	local best: string? = nil
	local bestClarity = 0
	local bestLine: Line? = nil
	local window = Frequencies.AudibleWindow
	local function consider(id: string, value: number, line: Line?)
		local clarity = 1 - math.abs(mhz - value) / window
		if clarity > bestClarity then
			best, bestClarity, bestLine = id, clarity, line
		end
	end
	for _, def in Frequencies.Defs do
		if PhaseOrder.atLeast(State.phase, def.minPhase) then
			if def.kind == "Loop" or def.kind == "Carrier" then
				local index = loopIndex[def.id] or 1
				consider(def.id, def.mhz :: number, { key = def.lines[index] })
			elseif def.kind == "Dynamic" then
				local line = prophecy[1]
					or { key = if State.phase == "Crisis" then "freq.NightDesk.crisis" else "freq.NightDesk.calm" }
				consider(def.id, def.mhz :: number, line)
			elseif def.kind == "Lost" and State.lostFrequency > 0 then
				local key = if State.fact("lostFrequencyLocked")
					then "freq.Lost.locked"
					else def.lines[loopIndex[def.id] or 1]
				consider(def.id, State.lostFrequency, { key = key })
			end
		end
	end
	for _, taken in Registry.Crew.takenFrequencies() do
		consider("Taken", taken.mhz, { key = "freq.Taken.line", vars = { name = taken.name } })
	end
	return best, math.max(0, bestClarity), bestLine
end

local function advance(id: string)
	for _, def in Frequencies.Defs do
		if def.id == id and #def.lines > 0 then
			loopIndex[id] = ((loopIndex[id] or 1) % #def.lines) + 1
		end
	end
	if id == "NightDesk" and #prophecy > 0 then
		table.remove(prophecy, 1)
	end
end

function Radio.step(dt: number)
	if State.session ~= "Running" then
		return
	end
	timer += dt
	if timer < Frequencies.LineInterval then
		return
	end
	timer = 0
	local who = listeners()
	if #who == 0 then
		return
	end
	local mhz = Registry.Signal.model.frequency
	local station, clarity, line = resolve(mhz)
	if station and line and clarity > 0.05 then
		Remotes.fireList(who, "Cue", {
			kind = "Radio",
			station = station,
			key = line.key,
			vars = line.vars,
			clarity = clarity,
		})
		if clarity > 0.6 then
			advance(station)
		end
	else
		Remotes.fireList(who, "Cue", { kind = "Radio", station = "Static", key = "freq.Static", clarity = 0 })
	end
end

function Radio.reset()
	table.clear(prophecy)
	table.clear(loopIndex)
	timer = 0
end

return Radio
