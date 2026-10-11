--[[
	Outside the station: parking lot, the crew van, lamp posts, the antenna yard and mast, and a
	fenced perimeter that keeps the night small.
]]

local B = require("../lib/B")
local Props = require("../lib/Props")
local Common = require("./Common")

local Vector3, CFrame, Color3, Enum = B.Vector3, B.CFrame, B.Color3, B.Enum
local C = B.Colors
local at = B.at

local Exterior = {}

-- Fence perimeter (world X/Z).
Exterior.Perimeter = { minX = -96, maxX = 140, minZ = -72, maxZ = 124 }

function Exterior.build(root: any)
	local f = B.folder("Exterior", root)
	local P = Exterior.Perimeter
	local groundTop = -0.2
	-- Ground: four slabs around the building footprint X[-64,64] Z[-44,44].
	local function ground(
		minX: number,
		minZ: number,
		maxX: number,
		maxZ: number,
		material: any,
		color: any,
		name: string
	)
		B.box(
			Vector3.new(minX, groundTop - 2, minZ),
			Vector3.new(maxX, groundTop, maxZ),
			{ parent = f, name = name, role = "Structure", material = material, color = color, tags = { "Floor" } }
		)
	end
	ground(P.minX - 40, P.minZ - 40, P.maxX + 40, -44, Enum.Material.Grass, C.Grass, "GroundNorth")
	ground(P.minX - 40, -44, -64, 44, Enum.Material.Grass, C.Grass, "GroundWest")
	ground(64, -44, P.maxX + 40, 44, Enum.Material.Grass, C.Grass, "GroundEast")
	ground(P.minX - 40, 44, P.maxX + 40, P.maxZ + 40, Enum.Material.Grass, C.Grass, "GroundSouth")
	-- Parking lot asphalt laid over the south grass.
	B.box(Vector3.new(-60, groundTop, 44), Vector3.new(60, groundTop + 0.1, 112), {
		parent = f,
		name = "ParkingLot",
		role = "Detail",
		material = Enum.Material.Asphalt,
		color = C.Asphalt,
		collide = false,
	})
	-- Front walk.
	B.box(Vector3.new(-9, groundTop, 44), Vector3.new(1, groundTop + 0.15, 56), {
		parent = f,
		name = "Walkway",
		role = "Detail",
		material = Enum.Material.Concrete,
		color = C.Concrete,
		collide = false,
	})
	-- Parking stripes.
	for i = 0, 7 do
		B.part({
			parent = f,
			name = "Stripe",
			role = "Detail",
			size = Vector3.new(0.3, 0.02, 10),
			cf = at(-50 + i * 12, groundTop + 0.12, 70),
			color = Color3.fromRGB(200, 196, 170),
			collide = false,
		})
	end
	-- Vehicles: the crew van by the door, two cars that have been parked here a long time.
	Props.van(f, at(14, groundTop, 64, 180))
	Props.sedan(f, at(-34, groundTop, 70, 180), Color3.fromRGB(90, 40, 36))
	Props.sedan(f, at(-46, groundTop, 70, 176), Color3.fromRGB(60, 70, 80))
	-- Lamp posts.
	for _, pos in { { -30, 52 }, { 30, 52 }, { -30, 96 }, { 30, 96 } } do
		Props.sodiumLamp(f, at(pos[1], groundTop, pos[2], if pos[2] < 60 then 0 else 180), "Exterior")
	end
	-- Monument sign by the road.
	local sign = B.part({
		parent = f,
		name = "MonumentSign",
		size = Vector3.new(16, 5, 1.6),
		cf = at(-26, groundTop + 2.5, 108),
		color = C.Brick,
		material = Enum.Material.Brick,
	})
	B.label(
		sign,
		Enum.NormalId.Back,
		"KZRO-TV  CHANNEL 0\nHALVORSEN BROADCASTING",
		{ color = Color3.fromRGB(230, 220, 200), font = Enum.Font.Antique, ppu = 20 }
	)
	B.label(
		sign,
		Enum.NormalId.Front,
		"KZRO-TV  CHANNEL 0",
		{ color = Color3.fromRGB(230, 220, 200), font = Enum.Font.Antique, ppu = 20 }
	)
	local signLight = B.part({
		parent = f,
		name = "SignLight",
		role = "Light",
		size = Vector3.new(1, 0.5, 0.5),
		cf = at(-26, groundTop + 0.4, 105),
		color = Color3.fromRGB(255, 220, 160),
		material = Enum.Material.Neon,
	})
	B.spotLight(
		signLight,
		{ face = Enum.NormalId.Back, brightness = 1.5, range = 12, angle = 70, color = Color3.fromRGB(255, 210, 150) }
	)
	-- Antenna yard (east) and the mast.
	Props.mast(f, at(104, groundTop, 30, 0), 150)
	Props.fence(f, Vector3.new(68, groundTop, 0), Vector3.new(136, groundTop, 0))
	Props.fence(f, Vector3.new(136, groundTop, 0), Vector3.new(136, groundTop, 60))
	Props.fence(f, Vector3.new(136, groundTop, 60), Vector3.new(68, groundTop, 60))
	-- Perimeter fence.
	Props.fence(f, Vector3.new(P.minX, groundTop, P.minZ), Vector3.new(P.maxX, groundTop, P.minZ))
	Props.fence(f, Vector3.new(P.maxX, groundTop, P.minZ), Vector3.new(P.maxX, groundTop, P.maxZ))
	Props.fence(f, Vector3.new(P.maxX, groundTop, P.maxZ), Vector3.new(P.minX, groundTop, P.maxZ))
	Props.fence(f, Vector3.new(P.minX, groundTop, P.maxZ), Vector3.new(P.minX, groundTop, P.minZ))
	-- Exterior wall lamps by the doors.
	local doorLamp = B.part({
		parent = f,
		name = "EntranceLamp",
		role = "Light",
		size = Vector3.new(1, 0.6, 0.6),
		cf = at(-4, 10, 44.9),
		color = C.Sodium,
		material = Enum.Material.Neon,
	})
	local entrance = B.model("EntranceLampFixture", f)
	doorLamp.Parent = entrance
	entrance:AddTag("Fixture")
	entrance:SetAttribute("Zone", "Exterior")
	entrance:SetAttribute("Kind", "Sodium")
	local l = B.pointLight(doorLamp, { color = C.Sodium, brightness = 1.4, range = 22, shadows = true })
	l:SetAttribute("BaseBrightness", l.Brightness)
	local yardLamp = B.part({
		parent = f,
		name = "YardLamp",
		role = "Light",
		size = Vector3.new(0.8, 0.5, 0.5),
		cf = at(64.8, 9.5, 34),
		color = C.Sodium,
		material = Enum.Material.Neon,
	})
	B.pointLight(yardLamp, { color = C.Sodium, brightness = 1.2, range = 20 })
	-- Lobby spawn: the crew arrives in the parking lot next to the van.
	for i = 1, 4 do
		Common.marker(f, "Spawn_Lobby_" .. i, at(4 + i * 2.2, 1, 60, 180), "SpawnLobby")
	end
	-- Title-screen camera: low angle on the building with the mast behind.
	Common.marker(f, "TitleCamera", B.lookAt(Vector3.new(-40, 6, 118), Vector3.new(0, 14, 30)), "TitleCamera")
	Common.marker(f, "EndingCamera", B.lookAt(Vector3.new(30, 5, 100), Vector3.new(-4, 10, 44)), "EndingCamera")
	-- Taken players are held here (out of sight) while they watch the station through its cameras.
	local hold = B.model("TakenHold", f)
	B.box(
		Vector3.new(-10, -301, -10),
		Vector3.new(10, -300, 10),
		{ parent = hold, name = "HoldFloor", role = "Structure", color = C.PlasticBlack }
	)
	Common.marker(hold, "TakenHoldPoint", at(0, -297, 0), "TakenHold")
	local _ = CFrame
end

return Exterior
