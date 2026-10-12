--!strict
--[[
	Event Director. Every DirectorTick seconds it asks the pure selector for an event that fits the
	phase, the cooldowns, the tension budget, the facts and THE ANCHOR's state, then runs its
	handler. Faults are announced on the Night Desk frequency first and happen FaultLead seconds
	later, so a crew that listens can be waiting at the panel when it trips.

	Every handler cleans up after itself (timed overrides expire on their own; nothing is left
	permanently changed except what the event is meant to change, like Studio B's seal).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EventContent = require(Shared.Content.Events)
local EventSelector = require(Shared.Logic.EventSelector)
local GameConfig = require(Shared.Config.GameConfig)
local Layout = require(Shared.Content.StationLayout)

local Registry = require(script.Parent.Registry)
local State = require(script.Parent.State)
local World = require(script.Parent.World)

local Director = {}

Director.selector = EventSelector.new()
local rng = State.stream("director")
local tickTimer = 0
local scheduled: { { at: number, id: string } } = {}
local phoneLine = 0
local phoneRingUntil = 0
Director.log = {} :: { string }

local function log(text: string)
	table.insert(Director.log, string.format("%05.1f %s", os.clock() % 1000, text))
	if #Director.log > 30 then
		table.remove(Director.log, 1)
	end
end

local function zonesWithCrew(): { [string]: boolean }
	local zones = {}
	for _, member in State.members({ "Active" }) do
		zones[member.zone] = true
	end
	return zones
end

-- A zone next to the crew but empty: where sounds come from.
local function adjacentEmptyZone(): string?
	local occupied = zonesWithCrew()
	local graph = Layout.zoneGraph()
	local options = {}
	for zone in occupied do
		local neighbours: { string } = graph[zone] or {}
		for _, neighbour in neighbours do
			if not occupied[neighbour] and neighbour ~= "Exterior" and not table.find(options, neighbour) then
				table.insert(options, neighbour)
			end
		end
	end
	table.sort(options)
	if #options == 0 then
		return nil
	end
	return rng:Pick(options)
end

local function emptyZoneFarFromCrew(): string?
	local occupied = zonesWithCrew()
	local options = {}
	for zone in World.zoneFolders do
		if not occupied[zone] and zone ~= "Exterior" and zone ~= "StudioB" then
			table.insert(options, zone)
		end
	end
	table.sort(options)
	if #options == 0 then
		return nil
	end
	return rng:Pick(options)
end

local function playersInZones(zones: { string }): { Player }
	local list = {}
	for _, member in State.members({ "Active" }) do
		if table.find(zones, member.zone) then
			table.insert(list, member.player)
		end
	end
	return list
end

local FAULT_WHERE = {
	fault_panel_a = "@freq.where.PanelA",
	fault_panel_b = "@freq.where.PanelB",
	fault_tuning_drift = "@freq.where.Tuner",
	fault_vtr_jam = "@freq.where.VTR",
	fault_camera_offline = "@freq.where.Camera",
}

local Handlers: { [string]: () -> boolean } = {}

Handlers.distant_light_failure = function()
	local zone = emptyZoneFarFromCrew()
	if not zone then
		return false
	end
	Registry.Lighting.override(zone, "Off", 26)
	local center = World.zoneCenter(zone)
	if center then
		Registry.Session.cueNear(center, 60, { kind = "Sound", sound = "LightFail", position = center })
	end
	return true
end

Handlers.monitor_blink = function()
	Registry.Session.cueAll({ kind = "MonitorBlink" })
	return true
end

Handlers.whisper_empty_room = function()
	local zone = adjacentEmptyZone()
	local center = zone and World.zoneCenter(zone)
	if not zone or not center then
		return false
	end
	Registry.Session.cueNear(center, 40, {
		kind = "Subtitle",
		key = "sub.whisper",
		vars = { zone = "@zone." .. zone },
		speaker = "Unknown",
		duration = 3,
	})
	Registry.Session.cueNear(center, 40, { kind = "Sound", sound = "StingerLow", position = center })
	return true
end

Handlers.door_changed = function()
	local door = Registry.Doors.unobserved(20, rng)
	if not door then
		return false
	end
	Registry.Doors.setOpen(door, not door.open, nil, true)
	return true
end

Handlers.footsteps_empty = function()
	local zone = adjacentEmptyZone()
	local center = zone and World.zoneCenter(zone)
	if not zone or not center then
		return false
	end
	for i = 0, 4 do
		task.delay(i * 0.7, function()
			local offset = Vector3.new(rng:NextNumber(-3, 3), 0, rng:NextNumber(-3, 3))
			Registry.Session.cueNear(center, 50, { kind = "Sound", sound = "Footstep", position = center + offset })
		end)
	end
	Registry.Session.cueNear(center, 36, {
		kind = "Subtitle",
		key = "sub.footsteps",
		vars = { zone = "@zone." .. zone },
		speaker = "Caption",
		duration = 3,
	})
	return true
end

Handlers.phone_rings = function()
	local phone = World.devices.Phone
	if not phone then
		return false
	end
	State.setFact("phoneRinging", true)
	phoneRingUntil = os.clock() + 20
	for i = 0, 5 do
		task.delay(i * 3.2, function()
			if State.fact("phoneRinging") then
				Registry.Session.cueNear(
					phone.Position,
					90,
					{ kind = "Sound", sound = "PhoneRing", position = phone.Position }
				)
			end
		end)
	end
	return true
end

-- Called by Devices when someone answers.
function Director.answerPhone(player: Player): boolean
	if not State.fact("phoneRinging") then
		return false
	end
	State.setFact("phoneRinging", false)
	phoneLine = math.min(phoneLine + 1, 3)
	local phone = World.devices.Phone
	local speaker = if phoneLine == 3 then "Hale" else if phoneLine == 1 then "Halvorsen" else "Phone"
	Registry.Session.cueNear(
		phone.Position,
		14,
		{ kind = "Subtitle", key = "sub.phone." .. phoneLine, speaker = speaker, duration = 7 }
	)
	local _ = player
	return true
end

Handlers.impossible_broadcast = function()
	Registry.Session.cueAll({ kind = "ImpossibleBroadcast", duration = 7 })
	Registry.Session.cueAll({ kind = "Pulse", amount = 0.7, duration = 2 })
	return true
end

Handlers.figure_hall_end = function()
	-- Pick a crew member in a corridor and put him at the far end of their line of sight.
	for _, member in State.members({ "Active" }) do
		local zone = member.zone
		if zone == "MainHall" or zone == "WestCorridor" or zone == "EastCorridor" or zone == "BasementHall" then
			local character = member.player.Character
			local root = World.rootOf(member.player)
			if character and root then
				local look = root.CFrame.LookVector
				local best: BasePart? = nil
				local bestScore = -math.huge
				for _, node in World.nodes do
					local offset = node.Position - root.Position
					local distance = offset.Magnitude
					if distance > 24 and distance < 48 and math.abs(offset.Y) < 3 then
						local score = offset.Unit:Dot(look)
						if score > 0.8 and score > bestScore then
							best, bestScore = node, score
						end
					end
				end
				if best and Registry.Anchor.glimpse(best.Position, root.Position, 4.5, "Stare") then
					Registry.Session.cueNear(best.Position, 60, { kind = "Pulse", amount = 0.6, duration = 1.5 })
					local camId = Registry.Feeds.cameraForZone(World.zoneOf(best.Position + Vector3.new(0, 1, 0)))
					if camId then
						Registry.Feeds.setGlimpse(camId, best.Position, 0, 4.5)
					end
					return true
				end
			end
		end
	end
	return false
end

Handlers.personal_broadcast = function()
	local member = Registry.Crew.isolatedMember()
	if not member then
		return false
	end
	Registry.Session.cueTo(member.player, { kind = "PersonalBroadcast", name = member.name, duration = 6 })
	Registry.Radio.prophesy("freq.NightDesk.split", { zone = "@zone." .. member.zone })
	return true
end

Handlers.radio_future = function()
	local line = Registry.Radio.peek()
	local speaker = World.marker("RadioSpeaker")
	if not line or not speaker then
		return false
	end
	Registry.Session.cueNear(
		speaker.Position,
		45,
		{ kind = "Subtitle", key = "sub.radioFuture", speaker = "Caption", duration = 3 }
	)
	task.delay(2.5, function()
		Registry.Session.cueNear(
			speaker.Position,
			45,
			{ kind = "Radio", station = "NightDesk", key = line.key, vars = line.vars, clarity = 0.9 }
		)
	end)
	return true
end

Handlers.tape_extra_voice = function()
	for id, deck in Registry.Tapes.decks do
		if deck.playing then
			local device = World.devices[id]
			if device then
				Registry.Session.cueNear(
					device.Position,
					30,
					{ kind = "Subtitle", key = "sub.extraVoice", speaker = "Hale", duration = 4 }
				)
				Registry.Session.cueNear(device.Position, 30, { kind = "Pulse", amount = 0.5, duration = 1 })
				return true
			end
		end
	end
	return false
end

Handlers.studio_b_unsealed = function()
	Registry.Doors.unseal("StudioBDoor")
	State.setFact("studioBOpen", true)
	Registry.Session.cueAll({ kind = "Subtitle", key = "sub.studioB", speaker = "Caption", duration = 5 })
	Registry.Session.cueAll({ kind = "Sound", sound = "StingerReveal" })
	Registry.Session.cueAll({ kind = "Pulse", amount = 0.9, duration = 2.5 })
	Registry.Lighting.override("BasementHall", "Flicker", 5)
	return true
end

Handlers.blackout_wing = function()
	local wings = { "West", "East", "Basement" }
	local wing = rng:Pick(wings)
	local zones = Registry.Lighting.Wings[wing]
	for _, zone in zones do
		Registry.Lighting.override(zone, "Off", 30)
	end
	Registry.Session.cueList(
		playersInZones(zones),
		{ kind = "Subtitle", key = "sub.blackout", speaker = "Caption", duration = 4 }
	)
	Registry.Session.cueList(playersInZones(zones), { kind = "Sound", sound = "LightFail" })
	return true
end

Handlers.fault_panel_a = function()
	Registry.Devices.tripPanel("A")
	return true
end

Handlers.fault_panel_b = function()
	Registry.Devices.tripPanel("B")
	return true
end

Handlers.fault_tuning_drift = function()
	local amount = rng:NextNumber(0.35, 0.9) * (if rng:Chance(0.5) then 1 else -1)
	Registry.Signal.drift(amount)
	Registry.Session.cueAll({ kind = "Notice", key = "notice.tuningDrift", style = "Fault" })
	return true
end

Handlers.fault_vtr_jam = function()
	if Registry.Tapes.jam("VTR_MCR") then
		Registry.Session.cueAll({ kind = "Notice", key = "notice.vtrJam", style = "Fault" })
		local device = World.devices.VTR_MCR
		if device then
			Registry.Session.cueNear(
				device.Position,
				40,
				{ kind = "Sound", sound = "VTREject", position = device.Position }
			)
		end
		return true
	end
	return false
end

Handlers.fault_camera_offline = function()
	local ids = {}
	for id in World.cameras do
		if not Registry.Feeds.isOffline(id) then
			table.insert(ids, id)
		end
	end
	table.sort(ids)
	if #ids == 0 then
		return false
	end
	Registry.Feeds.knockOut(rng:Pick(ids), rng:NextNumber(60, 110))
	Registry.Session.cueAll({ kind = "Notice", key = "notice.cameraOffline", style = "Fault" })
	return true
end

local function facts(): { [string]: boolean }
	local f = table.clone(State.facts)
	return f
end

local function context(): EventSelector.Context
	return {
		now = os.clock(),
		phase = State.phase,
		facts = facts(),
		anchorState = Registry.Anchor.state(),
		hasIsolated = Registry.Crew.isolatedMember() ~= nil,
		blocked = State.session ~= "Running" or State.phase == "Anomaly" or State.phase == "Finale",
	}
end

-- Runs an event now. Used by the director, scheduled faults and the debug panel.
function Director.run(id: string, force: boolean?): (boolean, string?)
	local def = EventSelector.find(Director.selector, id)
	local handler = Handlers[id]
	if not def or not handler then
		return false, "unknown event"
	end
	if not force then
		local ok, reason = EventSelector.eligible(Director.selector, def, context())
		if not ok then
			return false, reason
		end
	end
	local ok, result = pcall(handler)
	if not ok then
		warn("[Channel0] event " .. id .. " failed: " .. tostring(result))
		return false, "error"
	end
	if result then
		EventSelector.record(Director.selector, def, os.clock())
		log(id)
		Registry.Session.cueDebug({ kind = "Event", id = id })
		return true, nil
	end
	return false, "no valid target"
end

local function scheduleFault(def: EventContent.EventDef)
	local lead = rng:NextNumber(EventContent.FaultLead[1], EventContent.FaultLead[2])
	table.insert(scheduled, { at = os.clock() + lead, id = def.id })
	-- Reserve it now so the selector does not pick the same fault twice in a row.
	EventSelector.record(Director.selector, def, os.clock())
	Registry.Radio.prophesy("freq.NightDesk.fault", { where = FAULT_WHERE[def.id] or "@freq.where.Camera" })
	log("scheduled " .. def.id .. string.format(" in %.0fs", lead))
end

function Director.step(dt: number)
	if State.session ~= "Running" then
		return
	end
	EventSelector.refill(Director.selector, State.phase, dt)

	-- Due faults.
	local now = os.clock()
	for i = #scheduled, 1, -1 do
		local item = scheduled[i]
		if now >= item.at then
			table.remove(scheduled, i)
			local handler = Handlers[item.id]
			if handler then
				local ok = pcall(handler)
				log((if ok then "fault " else "fault failed ") .. item.id)
			end
		end
	end
	if State.fact("phoneRinging") and now >= phoneRingUntil then
		State.setFact("phoneRinging", false)
	end

	tickTimer += dt
	if tickTimer < EventContent.DirectorTick then
		return
	end
	tickTimer = 0
	local ctx = context()
	if ctx.blocked then
		return
	end

	-- Studio B must open eventually: it is a Critical event, guaranteed once ready for a while.
	if State.fact("studioBReady") and not State.fact("studioBOpen") and Registry.Phase.studioBReadyFor() > 25 then
		Director.run("studio_b_unsealed", true)
		return
	end

	-- Faults: rate scales with crew size.
	local scale = GameConfig.Scaling.FaultRateMultiplier
	local faultChance = 0.35 * scale[math.clamp(State.shiftCount(), 1, #scale)]
	if #scheduled == 0 and rng:Chance(faultChance) then
		local fault = EventSelector.choose(Director.selector, ctx, rng, { "Fault" })
		if fault then
			scheduleFault(fault)
			return
		end
	end
	local def = EventSelector.choose(Director.selector, ctx, rng, { "Critical", "Intermediate", "Subtle" })
	if def then
		Director.run(def.id, false)
	end
end

function Director.debugInfo(): { [string]: any }
	local ctx = context()
	local events = {}
	for _, def in Director.selector.defs do
		local ok, reason = EventSelector.eligible(Director.selector, def, ctx)
		table.insert(events, { id = def.id, tier = def.tier, ok = ok, reason = reason })
	end
	return {
		budget = math.floor(Director.selector.budget * 100) / 100,
		scheduled = #scheduled,
		log = table.clone(Director.log),
		events = events,
	}
end

function Director.reset()
	Director.selector = EventSelector.new()
	rng = State.stream("director")
	tickTimer = 0
	table.clear(scheduled)
	table.clear(Director.log)
	phoneLine = 0
	phoneRingUntil = 0
end

return Director
