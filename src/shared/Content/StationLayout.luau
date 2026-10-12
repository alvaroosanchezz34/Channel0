--!strict
--[[
	Single source of truth for the station floor plan.
	Used by the offline map generator (tools/build), the placement validator and the server
	(position -> zone lookup). Pure data + pure functions: no Roblox services.

	The plan is a grid of 4-stud cells. Walls are generated wherever two neighbouring cells belong
	to different wall groups; doors and windows are openings declared below.
	World X = Origin.X + cellX * CellSize, World Z = Origin.Z + cellZ * CellSize.
]]

local StationLayout = {}

StationLayout.CellSize = 4
StationLayout.Origin = { x = -64, z = -44 }
StationLayout.Width = 32
StationLayout.Depth = 22
StationLayout.WallThickness = 1
StationLayout.SlabThickness = 1

export type FloorId = "Ground" | "Basement"

export type RoomDef = {
	zone: string,
	group: string,
	height: number,
	floorMaterial: string,
	wallMaterial: string,
	ceiling: boolean,
}

export type OpeningDef = {
	id: string,
	floor: FloorId,
	a: { number }, -- cell {x, z}
	b: { number }, -- neighbouring cell (may be outside the grid)
	width: number, -- cells along the wall
	kind: "Door" | "Double" | "Open" | "Window" | "Locked" | "Sealed" | "Exit",
	label: string?,
}

StationLayout.Floors = {
	Ground = {
		y = 0,
		rows = {
			"cccccccccccccccccccccccccccccccc", -- z0
			"cccccccccccccccccccccccccccccccc", -- z1
			"wwAAAAAAAAAAMMMMMMMEEEEETTTTTTee", -- z2
			"wwAAAAAAAAAAMMMMMMMEEEEETTTTTTee",
			"wwAAAAAAAAAAMMMMMMMEEEEETTTTTTee",
			"wwAAAAAAAAAAMMMMMMMEEEEETTTTTTee",
			"wwAAAAAAAAAAMMMMMMMEEEEETTTTTTee",
			"wwAAAAAAAAAAMMMMMMMEEEEETTTTTTee",
			"wwAAAAAAAAAAMMMMMMMEEEEETTTTTTee",
			"wwAAAAAAAAAAMMMMMMMEEEEETTTTTTee", -- z9
			"HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH", -- z10
			"HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH", -- z11
			"wwOOOOOOOOLLLLLLLLLLDDDWWWWWWWee", -- z12
			"wwOOOOOOOOLLLLLLLLLLDDDWWWWWWWee",
			"wwOOOOOOOOLLLLLLLLLLDDDWWWWWWWee",
			"wwOOOOOOOOLLLLLLLLLLDDDWWWWWWWee",
			"wwOOOOOOOOLLLLLLLLLLDDDWWWWWWWee", -- z16
			"wwKKKKKKKKLLLLLLLLLLSSSRRRRRRRYY", -- z17
			"wwKKKKKKKKLLLLLLLLLLSSSRRRRRRRYY",
			"wwKKKKKKKKLLLLLLLLLLSSSRRRRRRRYY",
			"wwKKKKKKKKLLLLLLLLLLSSSRRRRRRRYY",
			"wwKKKKKKKKLLLLLLLLLLSSSRRRRRRRYY", -- z21
		},
		rooms = {
			c = {
				zone = "CableCorridor",
				group = "Corridor",
				height = 12,
				floorMaterial = "Concrete",
				wallMaterial = "Concrete",
				ceiling = true,
			},
			w = {
				zone = "WestCorridor",
				group = "Corridor",
				height = 12,
				floorMaterial = "Concrete",
				wallMaterial = "SmoothPlastic",
				ceiling = true,
			},
			e = {
				zone = "EastCorridor",
				group = "Corridor",
				height = 12,
				floorMaterial = "Concrete",
				wallMaterial = "SmoothPlastic",
				ceiling = true,
			},
			H = {
				zone = "MainHall",
				group = "Corridor",
				height = 12,
				floorMaterial = "Marble",
				wallMaterial = "SmoothPlastic",
				ceiling = true,
			},
			A = {
				zone = "StudioA",
				group = "StudioA",
				height = 22,
				floorMaterial = "Concrete",
				wallMaterial = "Fabric",
				ceiling = true,
			},
			M = {
				zone = "MasterControl",
				group = "MasterControl",
				height = 12,
				floorMaterial = "Carpet",
				wallMaterial = "SmoothPlastic",
				ceiling = true,
			},
			E = {
				zone = "Editing",
				group = "Editing",
				height = 12,
				floorMaterial = "Carpet",
				wallMaterial = "WoodPlanks",
				ceiling = true,
			},
			T = {
				zone = "TapeArchive",
				group = "TapeArchive",
				height = 12,
				floorMaterial = "Concrete",
				wallMaterial = "Concrete",
				ceiling = true,
			},
			O = {
				zone = "Offices",
				group = "Offices",
				height = 12,
				floorMaterial = "Carpet",
				wallMaterial = "SmoothPlastic",
				ceiling = true,
			},
			L = {
				zone = "Lobby",
				group = "Lobby",
				height = 14,
				floorMaterial = "Marble",
				wallMaterial = "Wood",
				ceiling = true,
			},
			D = {
				zone = "Stairwell",
				group = "Stairwell",
				height = 14,
				floorMaterial = "Concrete",
				wallMaterial = "Concrete",
				ceiling = true,
			},
			W = {
				zone = "Workshop",
				group = "Workshop",
				height = 12,
				floorMaterial = "DiamondPlate",
				wallMaterial = "Brick",
				ceiling = true,
			},
			K = {
				zone = "Lockers",
				group = "Lockers",
				height = 12,
				floorMaterial = "Slate",
				wallMaterial = "SmoothPlastic",
				ceiling = true,
			},
			S = {
				zone = "Security",
				group = "Security",
				height = 12,
				floorMaterial = "Carpet",
				wallMaterial = "SmoothPlastic",
				ceiling = true,
			},
			R = {
				zone = "Transmitter",
				group = "Transmitter",
				height = 14,
				floorMaterial = "DiamondPlate",
				wallMaterial = "Concrete",
				ceiling = true,
			},
			Y = {
				zone = "AntennaAccess",
				group = "AntennaAccess",
				height = 12,
				floorMaterial = "Concrete",
				wallMaterial = "Brick",
				ceiling = true,
			},
		} :: { [string]: RoomDef },
	},
	Basement = {
		y = -12,
		rows = {
			"................................", -- z0
			"................................",
			"................................",
			"................................",
			"..............ppppppgggggggggg..", -- z4
			"..............ppppppgggggggggg..",
			"..............ppppppgggggggggg..",
			"..............ppppppgggggggggg..",
			"..............ppppppgggggggggg..",
			"..............ppppppgggggggggg..", -- z9
			"..............hhhhhhhhhhhhhhhh..", -- z10
			"..............hhhhhhhhhhhhhhhh..", -- z11
			"..............BBBBBBdddqqqqqqq..", -- z12
			"..............BBBBBBdddqqqqqqq..",
			"..............BBBBBBdddqqqqqqq..",
			"..............BBBBBBdddqqqqqqq..",
			"..............BBBBBBdddqqqqqqq..", -- z16
			"................................",
			"................................",
			"................................",
			"................................",
			"................................",
		},
		rooms = {
			d = {
				zone = "Stairwell",
				group = "Stairwell",
				height = 11,
				floorMaterial = "Concrete",
				wallMaterial = "Concrete",
				ceiling = false,
			},
			h = {
				zone = "BasementHall",
				group = "BasementHall",
				height = 11,
				floorMaterial = "Concrete",
				wallMaterial = "Concrete",
				ceiling = false,
			},
			p = {
				zone = "BoilerRoom",
				group = "BoilerRoom",
				height = 11,
				floorMaterial = "Concrete",
				wallMaterial = "Brick",
				ceiling = false,
			},
			g = {
				zone = "GeneratorRoom",
				group = "GeneratorRoom",
				height = 11,
				floorMaterial = "DiamondPlate",
				wallMaterial = "Concrete",
				ceiling = false,
			},
			q = {
				zone = "Electrical",
				group = "Electrical",
				height = 11,
				floorMaterial = "Concrete",
				wallMaterial = "Concrete",
				ceiling = false,
			},
			B = {
				zone = "StudioB",
				group = "StudioB",
				height = 11,
				floorMaterial = "WoodPlanks",
				wallMaterial = "Fabric",
				ceiling = false,
			},
		} :: { [string]: RoomDef },
	},
}

StationLayout.Openings = {
	-- Ground floor
	{
		id = "LobbyEntrance",
		floor = "Ground",
		a = { 14, 21 },
		b = { 14, 22 },
		width = 2,
		kind = "Double",
		label = "MAIN ENTRANCE",
	},
	{ id = "LobbyHall", floor = "Ground", a = { 14, 12 }, b = { 14, 11 }, width = 2, kind = "Open" },
	{
		id = "LobbySecurity",
		floor = "Ground",
		a = { 19, 19 },
		b = { 20, 19 },
		width = 1,
		kind = "Door",
		label = "SECURITY",
	},
	{ id = "OfficesHall", floor = "Ground", a = { 5, 12 }, b = { 5, 11 }, width = 1, kind = "Door", label = "OFFICES" },
	{
		id = "OfficesLockers",
		floor = "Ground",
		a = { 4, 16 },
		b = { 4, 17 },
		width = 1,
		kind = "Door",
		label = "STAFF ONLY",
	},
	{ id = "LockersWest", floor = "Ground", a = { 2, 19 }, b = { 1, 19 }, width = 1, kind = "Door", label = "LOCKERS" },
	{
		id = "StairsHall",
		floor = "Ground",
		a = { 21, 12 },
		b = { 21, 11 },
		width = 1,
		kind = "Door",
		label = "STAIRS B1",
	},
	{
		id = "WorkshopHall",
		floor = "Ground",
		a = { 25, 12 },
		b = { 25, 11 },
		width = 1,
		kind = "Door",
		label = "MAINTENANCE",
	},
	{ id = "WorkshopTransmitter", floor = "Ground", a = { 26, 16 }, b = { 26, 17 }, width = 1, kind = "Door" },
	{
		id = "TransmitterAccess",
		floor = "Ground",
		a = { 29, 19 },
		b = { 30, 19 },
		width = 1,
		kind = "Door",
		label = "TRANSMITTER",
	},
	{ id = "AccessEast", floor = "Ground", a = { 30, 17 }, b = { 30, 16 }, width = 1, kind = "Door" },
	{
		id = "AntennaYard",
		floor = "Ground",
		a = { 31, 19 },
		b = { 32, 19 },
		width = 1,
		kind = "Exit",
		label = "ANTENNA YARD",
	},
	{
		id = "MCRHall",
		floor = "Ground",
		a = { 15, 9 },
		b = { 15, 10 },
		width = 1,
		kind = "Door",
		label = "MASTER CONTROL",
	},
	{ id = "MCRStudio", floor = "Ground", a = { 12, 7 }, b = { 11, 7 }, width = 1, kind = "Door", label = "STUDIO A" },
	{ id = "MCRWindow", floor = "Ground", a = { 12, 3 }, b = { 11, 3 }, width = 3, kind = "Window" },
	{
		id = "StudioHall",
		floor = "Ground",
		a = { 6, 9 },
		b = { 6, 10 },
		width = 2,
		kind = "Double",
		label = "STUDIO A",
	},
	{ id = "StudioNorth", floor = "Ground", a = { 8, 2 }, b = { 8, 1 }, width = 1, kind = "Door" },
	{
		id = "EditingHall",
		floor = "Ground",
		a = { 21, 9 },
		b = { 21, 10 },
		width = 1,
		kind = "Door",
		label = "EDIT BAY",
	},
	{ id = "EditingMCR", floor = "Ground", a = { 19, 5 }, b = { 18, 5 }, width = 1, kind = "Door" },
	{
		id = "ArchiveHall",
		floor = "Ground",
		a = { 26, 9 },
		b = { 26, 10 },
		width = 1,
		kind = "Door",
		label = "TAPE LIBRARY",
	},
	{ id = "ArchiveEast", floor = "Ground", a = { 29, 5 }, b = { 30, 5 }, width = 1, kind = "Door" },
	{
		id = "FireExit",
		floor = "Ground",
		a = { 0, 21 },
		b = { -1, 21 },
		width = 1,
		kind = "Locked",
		label = "FIRE EXIT",
	},
	{ id = "LobbyWindowW", floor = "Ground", a = { 10, 21 }, b = { 10, 22 }, width = 3, kind = "Window" },
	{ id = "LobbyWindowE", floor = "Ground", a = { 17, 21 }, b = { 17, 22 }, width = 3, kind = "Window" },
	{ id = "SecurityWindow", floor = "Ground", a = { 20, 21 }, b = { 20, 22 }, width = 2, kind = "Window" },
	-- Basement
	{
		id = "BasementStairs",
		floor = "Basement",
		a = { 22, 12 },
		b = { 22, 11 },
		width = 1,
		kind = "Door",
		label = "B1",
	},
	{
		id = "BoilerHall",
		floor = "Basement",
		a = { 16, 9 },
		b = { 16, 10 },
		width = 1,
		kind = "Door",
		label = "BOILER",
	},
	{
		id = "GeneratorHall",
		floor = "Basement",
		a = { 25, 9 },
		b = { 25, 10 },
		width = 1,
		kind = "Door",
		label = "GENERATOR",
	},
	{
		id = "ElectricalHall",
		floor = "Basement",
		a = { 25, 12 },
		b = { 25, 11 },
		width = 1,
		kind = "Door",
		label = "ELECTRICAL",
	},
	{
		id = "StudioBDoor",
		floor = "Basement",
		a = { 16, 12 },
		b = { 16, 11 },
		width = 2,
		kind = "Sealed",
		label = "STUDIO B",
	},
	{ id = "BoilerGenerator", floor = "Basement", a = { 19, 6 }, b = { 20, 6 }, width = 1, kind = "Door" },
} :: { OpeningDef }

-- Human-facing zone metadata. `ambience` selects the audio bed; `cameraLabel` appears on CCTV.
StationLayout.Zones = {
	Lobby = { nameKey = "zone.Lobby", ambience = "Lobby" },
	Security = { nameKey = "zone.Security", ambience = "Office" },
	MainHall = { nameKey = "zone.MainHall", ambience = "Hall" },
	WestCorridor = { nameKey = "zone.WestCorridor", ambience = "Hall" },
	EastCorridor = { nameKey = "zone.EastCorridor", ambience = "Hall" },
	CableCorridor = { nameKey = "zone.CableCorridor", ambience = "Service" },
	StudioA = { nameKey = "zone.StudioA", ambience = "Studio" },
	MasterControl = { nameKey = "zone.MasterControl", ambience = "Control" },
	Editing = { nameKey = "zone.Editing", ambience = "Control" },
	TapeArchive = { nameKey = "zone.TapeArchive", ambience = "Archive" },
	Offices = { nameKey = "zone.Offices", ambience = "Office" },
	Lockers = { nameKey = "zone.Lockers", ambience = "Office" },
	Stairwell = { nameKey = "zone.Stairwell", ambience = "Service" },
	Workshop = { nameKey = "zone.Workshop", ambience = "Service" },
	Transmitter = { nameKey = "zone.Transmitter", ambience = "Machine" },
	AntennaAccess = { nameKey = "zone.AntennaAccess", ambience = "Service" },
	BasementHall = { nameKey = "zone.BasementHall", ambience = "Basement" },
	BoilerRoom = { nameKey = "zone.BoilerRoom", ambience = "Basement" },
	GeneratorRoom = { nameKey = "zone.GeneratorRoom", ambience = "Machine" },
	Electrical = { nameKey = "zone.Electrical", ambience = "Basement" },
	StudioB = { nameKey = "zone.StudioB", ambience = "Dead" },
	Exterior = { nameKey = "zone.Exterior", ambience = "Exterior" },
}

-- Zone adjacency (through doors) is derived; this lists which zones are "isolated" pockets
-- the event director treats as far from help.
StationLayout.RemoteZones = { "BoilerRoom", "GeneratorRoom", "Electrical", "StudioB", "CableCorridor", "TapeArchive" }

function StationLayout.cellToWorld(cx: number, cz: number): (number, number)
	local size = StationLayout.CellSize
	return StationLayout.Origin.x + cx * size, StationLayout.Origin.z + cz * size
end

function StationLayout.worldToCell(x: number, z: number): (number, number)
	local size = StationLayout.CellSize
	return math.floor((x - StationLayout.Origin.x) / size), math.floor((z - StationLayout.Origin.z) / size)
end

function StationLayout.roomKeyAt(floorId: FloorId, cx: number, cz: number): string?
	local floor = StationLayout.Floors[floorId]
	local row = floor.rows[cz + 1]
	if not row or cx < 0 or cx >= #row then
		return nil
	end
	local key = string.sub(row, cx + 1, cx + 1)
	if key == "." then
		return nil
	end
	return key
end

function StationLayout.floorAtHeight(y: number): FloorId
	return (if y < -3 then "Basement" else "Ground") :: FloorId
end

-- Returns the zone id at a world position ("Exterior" outside the building).
function StationLayout.zoneAt(x: number, y: number, z: number): string
	local floorId: FloorId = StationLayout.floorAtHeight(y)
	local cx, cz = StationLayout.worldToCell(x, z)
	local key = StationLayout.roomKeyAt(floorId, cx, cz)
	if not key then
		return "Exterior"
	end
	local room = StationLayout.Floors[floorId].rooms[key]
	return if room then room.zone else "Exterior"
end

-- Axis-aligned bounds of a zone on a floor, in world studs (min/max x and z).
function StationLayout.zoneBounds(zone: string): {
	minX: number,
	maxX: number,
	minZ: number,
	maxZ: number,
	floor: FloorId,
	y: number,
	height: number,
}?
	for floorId, floorAny in StationLayout.Floors do
		local floor: any = floorAny
		local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
		local height = 0
		for cz, row in floor.rows do
			for cx = 1, #row do
				local key = string.sub(row, cx, cx)
				local room = floor.rooms[key]
				if room and room.zone == zone then
					local x0, z0 = StationLayout.cellToWorld(cx - 1, cz - 1)
					minX = math.min(minX, x0)
					maxX = math.max(maxX, x0 + StationLayout.CellSize)
					minZ = math.min(minZ, z0)
					maxZ = math.max(maxZ, z0 + StationLayout.CellSize)
					height = room.height
				end
			end
		end
		if minX < math.huge then
			return {
				minX = minX,
				maxX = maxX,
				minZ = minZ,
				maxZ = maxZ,
				floor = floorId :: FloorId,
				y = floor.y,
				height = height,
			}
		end
	end
	return nil
end

-- Doors as zone-graph edges (used for Anchor routing heuristics and the event director).
function StationLayout.zoneGraph(): { [string]: { string } }
	local graph: { [string]: { string } } = {}
	local function link(a: string, b: string)
		graph[a] = graph[a] or {}
		if not table.find(graph[a], b) then
			table.insert(graph[a], b)
		end
	end
	for _, opening in StationLayout.Openings do
		if opening.kind ~= "Window" and opening.kind ~= "Locked" then
			local floor = StationLayout.Floors[opening.floor]
			local ka = StationLayout.roomKeyAt(opening.floor, opening.a[1], opening.a[2])
			local kb = StationLayout.roomKeyAt(opening.floor, opening.b[1], opening.b[2])
			local za = if ka then floor.rooms[ka].zone else "Exterior"
			local zb = if kb then floor.rooms[kb].zone else "Exterior"
			link(za, zb)
			link(zb, za)
		end
	end
	-- Corridor segments share a wall group, so they connect without doors.
	local corridors = { "MainHall", "WestCorridor", "EastCorridor", "CableCorridor" }
	for _, a in corridors do
		for _, b in corridors do
			if a ~= b then
				link(a, b)
			end
		end
	end
	link("Stairwell", "BasementHall")
	link("BasementHall", "Stairwell")
	return graph
end

return StationLayout
