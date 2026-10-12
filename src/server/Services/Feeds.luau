--!strict
--[[
	Security camera feeds. The server decides what every camera shows (FeedDirective) and the
	clients render it. The zero channel's delay runs AHEAD of real time: while THE ANCHOR is in
	Displacement, the camera covering where he will appear already shows him there, with a
	timestamp that is ahead of the station clock. Reading the timestamp is the skill.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local Registry = require(script.Parent.Registry)
local Remotes = require(script.Parent.Remotes)
local State = require(script.Parent.State)
local World = require(script.Parent.World)

local Feeds = {}

type PreEcho = { camId: number, at: { x: number, y: number, z: number, yaw: number }, untilTime: number, lead: number }

local offlineUntil: { [number]: number } = {}
local preEcho: PreEcho? = nil
local glimpse: PreEcho? = nil
local last = ""
local timer = 0

function Feeds.cameraForZone(zone: string): number?
	local ids = {}
	for id, part in World.cameras do
		if part:GetAttribute("Zone") == zone then
			table.insert(ids, id)
		end
	end
	table.sort(ids)
	return ids[1]
end

-- Zones that have a camera (where pre-echo appearances can be read from a console).
function Feeds.coveredZones(): { string }
	local zones = {}
	for _, part in World.cameras do
		local zone = part:GetAttribute("Zone") :: string
		if zone and not table.find(zones, zone) then
			if zone ~= "StudioB" or State.fact("studioBOpen") then
				table.insert(zones, zone)
			end
		end
	end
	table.sort(zones)
	return zones
end

function Feeds.setPreEcho(zone: string, position: Vector3, yaw: number, lead: number)
	local camId = Feeds.cameraForZone(zone)
	if not camId then
		return
	end
	preEcho = {
		camId = camId,
		at = { x = position.X, y = position.Y, z = position.Z, yaw = yaw },
		untilTime = os.clock() + lead + 4,
		lead = lead,
	}
	Feeds.publish(true)
end

function Feeds.clearPreEcho()
	preEcho = nil
	Feeds.publish(true)
end

-- A camera briefly shows him somewhere he is not (figure at the end of the hall, etc.).
function Feeds.setGlimpse(camId: number, position: Vector3, yaw: number, duration: number)
	glimpse = {
		camId = camId,
		at = { x = position.X, y = position.Y, z = position.Z, yaw = yaw },
		untilTime = os.clock() + duration,
		lead = 0,
	}
	Feeds.publish(true)
end

function Feeds.knockOut(camId: number, duration: number)
	offlineUntil[camId] = os.clock() + duration
	Feeds.publish(true)
end

function Feeds.restore(camId: number): boolean
	if offlineUntil[camId] and offlineUntil[camId] > os.clock() then
		offlineUntil[camId] = nil
		Feeds.publish(true)
		return true
	end
	return false
end

function Feeds.isOffline(camId: number): boolean
	return (offlineUntil[camId] or 0) > os.clock()
end

function Feeds.directives(): { [string]: any }
	local now = os.clock()
	local result = {}
	local offline = 0
	local anchor = Registry.Anchor
	local anchorZone = anchor.physicalZone()
	local anchorAt = anchor.feedPose()
	local phantoms = {}
	for _, member in State.members({ "Taken" }) do
		table.insert(phantoms, member.userId)
	end
	for id, part in World.cameras do
		local zone = part:GetAttribute("Zone") :: string
		local directive: { [string]: any } = { mode = "Live", leadSeconds = 0 }
		if (offlineUntil[id] or 0) > now then
			directive.mode = "Offline"
			offline += 1
		elseif zone == "StudioB" and not State.fact("studioBOpen") then
			directive.mode = "Memory"
		else
			if preEcho and preEcho.camId == id and preEcho.untilTime > now then
				directive.mode = "Displaced"
				directive.leadSeconds = preEcho.lead
				directive.anchorAt = preEcho.at
			elseif glimpse and glimpse.camId == id and glimpse.untilTime > now then
				directive.anchorAt = glimpse.at
			elseif anchorZone == zone and anchorAt then
				directive.anchorAt = anchorAt
			end
			-- Taken crew appear standing in the feeds, facing the lens.
			if #phantoms > 0 and (id % 3 == State.seed % 3) then
				directive.phantoms = phantoms
			end
		end
		result[tostring(id)] = directive
	end
	Registry.Signal.setCamerasOffline(offline)
	return result
end

function Feeds.publish(force: boolean?)
	local directives = Feeds.directives()
	-- Cheap change detection on a stable serialisation.
	local parts = {}
	for id = 1, 16 do
		local d = directives[tostring(id)]
		if d then
			local a = d.anchorAt
			table.insert(
				parts,
				string.format(
					"%d:%s:%d:%s:%s",
					id,
					d.mode,
					d.leadSeconds,
					if a then string.format("%.0f,%.0f,%.0f", a.x, a.y, a.z) else "-",
					if d.phantoms then tostring(#d.phantoms) else "0"
				)
			)
		end
	end
	local key = table.concat(parts, "|")
	if force or key ~= last then
		last = key
		Remotes.fireAll("Feeds", directives)
	end
end

function Feeds.step(dt: number)
	timer += dt
	if timer >= 0.5 then
		timer = 0
		Feeds.publish(false)
	end
end

function Feeds.reset()
	table.clear(offlineUntil)
	preEcho = nil
	glimpse = nil
	last = ""
	Feeds.publish(true)
end

local _ = Shared
return Feeds
