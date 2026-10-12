--[[
	Placement validator for the generated station. Runs on every `lune run tools/build/build`
	(and alone with `-- --check`). Checks:
	  * props intersecting walls/other props (penetration > tolerance, flush contact allowed)
	  * props hovering just above the floor (classic "floating furniture")
	  * door clearances (nothing solid in front of or behind a doorway)
	  * every room reachable from the entrance for a 2-stud-wide character (both floors)
	  * required devices, tape slots, cameras, monitors, fixtures, spawns and anchor nodes exist
]]

local Geometry = require("./Geometry")
local Navigation = require("./Navigation")
local Layout = require("../../src/shared/Content/StationLayout")

local Validator = {}

local TOLERANCE = 0.06

local function ownerOf(part: any): any
	-- The prop model directly under a zone/system folder.
	local node = part
	local owner = part
	while node.Parent and node.Parent.ClassName ~= "Folder" do
		owner = node.Parent
		node = node.Parent
	end
	if node.Parent and node.Parent.ClassName == "Folder" then
		return owner
	end
	return part
end

local function keyOf(instance: any): string
	local uid = instance:GetAttribute("__uid")
	if uid then
		return "m" .. tostring(uid)
	end
	-- Loose parts directly under a folder: identify by name + position.
	local p = instance.CFrame.Position
	return string.format("p%s:%.2f:%.2f:%.2f", instance.Name, p.X, p.Y, p.Z)
end

local function describe(part: any): string
	local names = {}
	local node = part
	for _ = 1, 4 do
		if not node then
			break
		end
		table.insert(names, 1, node.Name)
		node = node.Parent
	end
	return table.concat(names, "/")
end

function Validator.run(
	station: any,
	assets: any,
	registry: { { part: any, role: string } },
	tapesDefs: { [string]: any }
): { errors: { string }, warnings: { string }, stats: { [string]: number } }
	local errors, warnings = {}, {}
	local stats = { parts = 0, lights = 0, props = 0 }

	-- Collect solid items in the station.
	local items = {}
	for _, entry in registry do
		local part = entry.part
		if part:IsDescendantOf(station) then
			stats.parts += 1
			local solid = part.CanCollide
				and (
					entry.role == "Prop"
					or entry.role == "Structure"
					or entry.role == "Trim"
					or entry.role == "Dynamic"
					or entry.role == "Glass"
				)
			if solid then
				table.insert(
					items,
					{ part = part, role = entry.role, box = Geometry.fromPart(part), owner = keyOf(ownerOf(part)) }
				)
			end
		end
	end
	for _, d in station:GetDescendants() do
		if d:IsA("Light") then
			stats.lights += 1
		end
	end

	-- 1. Intersections.
	local grid = Geometry.hash(items, 8)
	local checked = {}
	local reported = 0
	for _, bucket in grid do
		for i = 1, #bucket do
			for j = i + 1, #bucket do
				local ia, ib = bucket[i], bucket[j]
				local key = if ia < ib then ia * 100000 + ib else ib * 100000 + ia
				if not checked[key] then
					checked[key] = true
					local a, b = items[ia], items[ib]
					local relevant = a.owner ~= b.owner
						and not (a.role == "Structure" and b.role == "Structure")
						and not (a.role == "Trim" and b.role == "Structure")
						and not (a.role == "Structure" and b.role == "Trim")
						and not (a.role == "Trim" and b.role == "Trim")
						and not (a.role == "Dynamic" and b.role == "Trim")
						and not (a.role == "Trim" and b.role == "Dynamic")
					if relevant and Geometry.aabbOverlap(a.box, b.box, TOLERANCE) then
						local depth = Geometry.penetration(a.box, b.box)
						if depth > TOLERANCE then
							reported += 1
							if reported <= 60 then
								table.insert(
									errors,
									string.format(
										"intersection %.2f: %s <> %s",
										depth,
										describe(a.part),
										describe(b.part)
									)
								)
							end
						end
					end
				end
			end
		end
	end
	if reported > 60 then
		table.insert(errors, string.format("... %d more intersections", reported - 60))
	end

	-- 2. Floating props: a prop whose lowest solid part hovers 0.05–0.8 above its floor.
	local lowest = {}
	for _, item in items do
		if item.role == "Prop" then
			local current = lowest[item.owner]
			if not current or item.box.min.Y < current.box.min.Y then
				lowest[item.owner] = item
			end
		end
	end
	for owner, item in lowest do
		local y = item.box.min.Y
		local floorY = Layout.Floors[Layout.floorAtHeight(y)].y
		local zone = Layout.zoneAt(item.box.center.X, y + 0.5, item.box.center.Z)
		if zone == "Exterior" then
			floorY = -0.2
		end
		local gap = y - floorY
		if gap > 0.05 and gap < 0.8 then
			-- Allow a prop resting on another solid part (e.g. a riser or desk).
			local supported = false
			for _, other in items do
				if
					other.owner ~= owner
					and math.abs(other.box.max.Y - y) < 0.08
					and item.box.center.X >= other.box.min.X
					and item.box.center.X <= other.box.max.X
					and item.box.center.Z >= other.box.min.Z
					and item.box.center.Z <= other.box.max.Z
				then
					supported = true
					break
				end
			end
			if not supported then
				table.insert(errors, string.format("floating %.2f above floor: %s", gap, describe(item.part)))
			end
		end
	end

	-- 3. Door clearance.
	for _, door in station:GetDescendants() do
		if door:HasTag("Door") then
			local hinge = door:FindFirstChild("Hinge1")
			local leaf = door:FindFirstChild("Leaf1")
			if not hinge or not leaf then
				table.insert(errors, "door without hinge/leaf: " .. door.Name)
			end
			local kind = door:GetAttribute("Kind")
			if leaf and kind ~= "Locked" and kind ~= "Sealed" then
				local frame = leaf.CFrame
				for _, side in { -1, 1 } do
					local probe = frame * (require("@lune/roblox") :: any).CFrame.new(0, 0, side * 2.2)
					local probeBox = {
						center = probe.Position,
						axes = { probe.RightVector, probe.UpVector, -probe.LookVector },
						half = { 1.4, 2.5, 1.6 },
						min = probe.Position - (require("@lune/roblox") :: any).Vector3.new(2.2, 2.5, 2.2),
						max = probe.Position + (require("@lune/roblox") :: any).Vector3.new(2.2, 2.5, 2.2),
					}
					for _, item in items do
						if
							(item.role == "Prop")
							and Geometry.aabbOverlap(item.box, probeBox, 0)
							and Geometry.penetration(item.box, probeBox) > 0.1
						then
							table.insert(errors, string.format("door %s blocked by %s", door.Name, describe(item.part)))
						end
					end
				end
			end
		end
	end

	-- 4. Reachability per floor.
	local ground = Navigation.build(registry, "Ground")
	local basement = Navigation.build(registry, "Basement")
	local spawn = station:FindFirstChild("Spawn_Late", true)
	if not spawn then
		table.insert(errors, "missing Spawn_Late")
	else
		local reached = Navigation.reach(ground, spawn.CFrame.Position.X, spawn.CFrame.Position.Z, 1)
		local reachedB = Navigation.reach(basement, 25, 6, 1)
		local zonesSeen = {}
		for floorId, data in
			{ Ground = { grid = ground, seen = reached }, Basement = { grid = basement, seen = reachedB } }
		do
			for key in data.seen do
				local x, z = key % data.grid.w, math.floor(key / data.grid.w)
				local wx, wz = Navigation.gridToWorld(x, z)
				zonesSeen[floorId .. ":" .. Layout.zoneAt(wx, data.grid.y + 1, wz)] = true
			end
		end
		for floorId, floor in Layout.Floors do
			for _, roomDef in floor.rooms do
				local key = floorId .. ":" .. roomDef.zone
				if not zonesSeen[key] then
					table.insert(errors, "unreachable zone " .. key)
				end
			end
		end
		stats.walkableGround = 0
		for _ in reached do
			stats.walkableGround += 1
		end
	end

	-- 5. Required content.
	local devices = {}
	for _, d in station:GetDescendants() do
		if d:HasTag("Device") then
			local id = d:GetAttribute("DeviceId")
			if devices[id] then
				table.insert(errors, "duplicate device id " .. tostring(id))
			end
			devices[id] = d
			if not d:FindFirstChildOfClass("ProximityPrompt") then
				table.insert(errors, "device without prompt " .. tostring(id))
			end
		end
	end
	for _, id in
		{
			"SignIn",
			"Switcher",
			"CamConsole_Security",
			"CamConsole_MCR",
			"VTR_MCR",
			"VTR_Editing",
			"Tuner",
			"PanelA",
			"PanelB",
			"Phone",
			"AnchorDeskDrawer",
			"AnchorDesk",
			"CarrierKeyswitch",
			"Locker_MARSH",
		}
	do
		if not devices[id] then
			table.insert(errors, "missing device " .. id)
		end
	end

	local slots = {}
	for _, d in station:GetDescendants() do
		if d:HasTag("TapeSlot") then
			slots[d:GetAttribute("SlotId")] = true
		end
	end
	for id, def in tapesDefs do
		for _, slot in def.slots do
			if not slots[slot] then
				table.insert(errors, string.format("tape %s references missing slot %s", id, slot))
			end
		end
	end

	local cams = {}
	for _, d in station:GetDescendants() do
		if d:HasTag("SecurityCamera") then
			local id = d:GetAttribute("CamId")
			if cams[id] then
				table.insert(errors, "duplicate camera id " .. tostring(id))
			end
			cams[id] = true
		end
	end
	for id = 1, 8 do
		if not cams[id] then
			table.insert(errors, "missing camera " .. id)
		end
	end

	local monitorIds, monitorZones = {}, {}
	for _, d in station:GetDescendants() do
		if d:HasTag("Monitor") then
			local id = d:GetAttribute("MonitorId")
			if monitorIds[id] then
				table.insert(errors, "duplicate monitor " .. tostring(id))
			end
			monitorIds[id] = true
			monitorZones[d:GetAttribute("Zone")] = true
			if not d:FindFirstChild("Screen") then
				table.insert(errors, "monitor without screen " .. tostring(id))
			end
		end
	end
	for id, d in devices do
		if d:GetAttribute("Device") == "MonitorSwitch" and not monitorZones[d:GetAttribute("Zone")] then
			table.insert(errors, "monitor switch in a zone without monitors: " .. tostring(id))
		end
	end

	local fixtureZones = {}
	for _, d in station:GetDescendants() do
		if d:HasTag("Fixture") then
			fixtureZones[d:GetAttribute("Zone")] = true
		end
	end
	for _, floor in Layout.Floors do
		for _, roomDef in floor.rooms do
			if not fixtureZones[roomDef.zone] and roomDef.zone ~= "Stairwell" then
				table.insert(errors, "zone without light fixtures: " .. roomDef.zone)
			end
		end
	end

	local function count(tag: string): number
		local n = 0
		for _, d in station:GetDescendants() do
			if d:HasTag(tag) then
				n += 1
			end
		end
		return n
	end
	for tag, minimum in
		{
			SpawnLobby = 4,
			SpawnShift = 4,
			SpawnRecover = 1,
			TakenHold = 1,
			TitleCamera = 1,
			AnchorStage = 2,
			RadioSpeaker = 1,
			Door = 20,
		}
	do
		local n = count(tag)
		if n < minimum then
			table.insert(errors, string.format("need >= %d %s, found %d", minimum, tag, n))
		end
	end
	local nodeZones = {}
	for _, d in station:GetDescendants() do
		if d:HasTag("AnchorNode") then
			local zone = d:GetAttribute("Zone")
			nodeZones[zone] = (nodeZones[zone] or 0) + 1
		end
	end
	for _, zone in
		{ "Lobby", "MainHall", "StudioA", "TapeArchive", "Transmitter", "StudioB", "BasementHall", "MasterControl" }
	do
		if (nodeZones[zone] or 0) < 2 then
			table.insert(errors, "too few anchor nodes in " .. zone)
		end
	end
	stats.anchorNodes = count("AnchorNode")
	stats.devices = 0
	for _ in devices do
		stats.devices += 1
	end

	-- Assets
	local anchor = assets:FindFirstChild("Anchor")
	if not anchor or not anchor.PrimaryPart then
		table.insert(errors, "Assets.Anchor missing or without PrimaryPart")
	else
		local motors = 0
		for _, d in anchor:GetDescendants() do
			if d:IsA("Motor6D") then
				motors += 1
			end
		end
		if motors < 10 then
			table.insert(errors, "Anchor rig has too few joints: " .. motors)
		end
	end
	local scenes = assets:FindFirstChild("Scenes")
	for _, id in
		{ "StudioADesk", "StudioBMemory", "MasterControlDay", "MasterControlNight", "LobbyParty", "HallwaySecurity" }
	do
		local s = scenes and scenes:FindFirstChild(id)
		if not s or not s:FindFirstChild("Cam") then
			table.insert(errors, "scene missing or without Cam: " .. id)
		end
	end

	if stats.lights > 220 then
		table.insert(warnings, "high dynamic light count: " .. stats.lights)
	end
	return { errors = errors, warnings = warnings, stats = stats }
end

-- Place THE ANCHOR's standing nodes in open floor space, every few studs, inside each room.
function Validator.placeAnchorNodes(
	station: any,
	registry: { { part: any, role: string } },
	makeMarker: (name: string, cf: any, attrs: { [string]: any }) -> ()
)
	local roblox = require("@lune/roblox")
	local CFrame = roblox.CFrame
	for floorId, floor in Layout.Floors do
		local grid = Navigation.build(registry, floorId)
		local perZone = {}
		for gz = 3, grid.d - 4, 5 do
			for gx = 3, grid.w - 4, 5 do
				if Navigation.free(grid, gx, gz, 2) then
					local wx, wz = Navigation.gridToWorld(gx, gz)
					local zone = Layout.zoneAt(wx, floor.y + 1, wz)
					if zone ~= "Exterior" and zone ~= "Stairwell" then
						perZone[zone] = (perZone[zone] or 0) + 1
						makeMarker(
							string.format("Node_%s_%d", zone, perZone[zone]),
							CFrame.new(wx, floor.y, wz),
							{ Zone = zone, Floor = floorId }
						)
					end
				end
			end
		end
	end
	local _ = station
end

return Validator
