--[[
	Ground floor dressing. Coordinates are world studs; each zone pulls its bounds from the layout
	so changes to the plan move the furniture with it. Interior wall faces sit 0.5 studs inside the
	cell boundary.
]]

local B = require("../lib/B")
local Props = require("../lib/Props")
local Common = require("./Common")

local Vector3, CFrame, Color3, Enum = B.Vector3, B.CFrame, B.Color3, B.Enum
local C = B.Colors
local Y = Common.YAW
local at = B.at

local Ground = {}

local function ceilingFixtures(
	parent: any,
	zone: string,
	xs: { number },
	zs: { number },
	height: number,
	opts: { [string]: any }?
)
	for _, x in xs do
		for _, z in zs do
			Props.fluorescent(parent, at(x, height, z), zone, opts)
		end
	end
end

------------------------------------------------------------------ Lobby
function Ground.Lobby(root: any)
	local zone = "Lobby"
	local b = Common.bounds(zone) -- X[-24,16] Z[4,44] h14
	local f = B.folder(zone, root)
	local h = b.height

	-- Reception counter (east side), facing west toward the entrance path.
	local counter = B.model("ReceptionCounter", f)
	B.part({
		parent = counter,
		name = "Front",
		size = Vector3.new(1, 3.6, 12),
		cf = at(4.5, 1.8, 24),
		color = C.WoodPanel,
		material = Enum.Material.Wood,
	})
	B.part({
		parent = counter,
		name = "Return",
		size = Vector3.new(8, 3.6, 1),
		cf = at(8.5, 1.8, 17.5),
		color = C.WoodPanel,
		material = Enum.Material.Wood,
	})
	B.part({
		parent = counter,
		name = "Top",
		size = Vector3.new(2, 0.25, 12.6),
		cf = at(4.5, 3.72, 24),
		color = Color3.fromRGB(70, 60, 52),
		material = Enum.Material.Marble,
	})
	B.part({
		parent = counter,
		name = "DeskTop",
		size = Vector3.new(3, 0.2, 11),
		cf = at(7, 2.6, 24.5),
		color = C.WoodLight,
		material = Enum.Material.Wood,
	})
	local logo = B.part({
		parent = counter,
		name = "CounterLogo",
		role = "Detail",
		size = Vector3.new(0.05, 1.4, 5),
		cf = at(3.97, 2.1, 24),
		color = Color3.fromRGB(30, 26, 22),
	})
	B.label(logo, Enum.NormalId.Left, "KZRO", { color = Color3.fromRGB(196, 160, 90), font = Enum.Font.Antique })
	Props.chair(f, at(10, 0, 24, Y.West))
	local phone = Props.phone(f, at(6.5, 3.85, 20.5, Y.West))
	Common.device(
		f,
		at(6.5, 4.4, 20.5),
		Vector3.new(1.4, 1, 1.4),
		"Phone",
		"Phone",
		zone,
		"prompt.phone",
		"Answer",
		{ distance = 6 }
	)
	local _ = phone
	-- The night log: a ledger open on the counter, with a pen.
	local ledger = B.part({
		parent = f,
		name = "NightLog",
		size = Vector3.new(1.6, 0.12, 2.2),
		cf = at(4.5, 3.9, 26, 10),
		color = C.Paper,
	})
	B.label(
		ledger,
		Enum.NormalId.Top,
		"NIGHT LOG — KZRO\n10/16/98 ________\n\n10/17/87  R.C.  M.S.  D.O.",
		{ font = Enum.Font.Garamond, padding = 0.1 }
	)
	B.part({
		parent = f,
		name = "Pen",
		role = "Detail",
		size = Vector3.new(0.6, 0.06, 0.06),
		cf = at(4.9, 3.99, 26.4, 40),
		color = C.PlasticBlack,
	})
	Common.device(
		f,
		at(4.5, 4.5, 26),
		Vector3.new(2, 1, 2.4),
		"SignIn",
		"SignIn",
		zone,
		"prompt.signin",
		"Sign",
		{ distance = 7 }
	)
	Common.tapeSlot(f, "Slot_LobbyDesk", zone, at(4.5, 3.96, 29.5, 75))
	-- Desk lamp
	local lampShade = B.part({
		parent = f,
		name = "DeskLampShade",
		role = "Detail",
		size = Vector3.new(0.7, 0.5, 0.7),
		cf = at(7.5, 4.1, 28.5),
		color = Color3.fromRGB(40, 70, 50),
		material = Enum.Material.Metal,
	})
	local lamp = B.model("DeskLamp", f)
	lampShade.Parent = lamp
	lamp:AddTag("Fixture")
	lamp:SetAttribute("Zone", zone)
	lamp:SetAttribute("Kind", "Lamp")
	local pl = B.pointLight(lampShade, { color = C.Warm, brightness = 0.9, range = 10 })
	pl:SetAttribute("BaseBrightness", pl.Brightness)

	-- Waiting area (west): sofas around a coffee table, a TV on the wall, dead plant.
	Props.sofa(f, at(-19.5, 0, 22, Y.East), 7)
	Props.sofa(f, at(-14, 0, 32.5, Y.North), 6)
	Props.table(f, at(-14, 0, 23, 0), 3, 5, 1.4, Color3.fromRGB(80, 60, 44))
	B.part({
		parent = f,
		name = "Magazines",
		role = "Detail",
		size = Vector3.new(1.2, 0.1, 0.9),
		cf = at(-13.6, 1.56, 22.2, 12),
		color = Color3.fromRGB(180, 60, 50),
	})
	Props.plant(f, at(-21.5, 0, 33))
	Props.plant(f, at(-21.5, 0, 12))
	B.part({
		parent = f,
		name = "Rug",
		role = "Detail",
		size = Vector3.new(14, 0.05, 16),
		cf = at(-14, 0.03, 26),
		color = Color3.fromRGB(90, 40, 38),
		material = Enum.Material.Fabric,
		collide = false,
	})
	-- Wall TV on a bracket (west wall), facing east.
	B.part({
		parent = f,
		name = "TVBracket",
		role = "Detail",
		size = Vector3.new(1.2, 0.3, 0.3),
		cf = at(-22.9, 7.6, 26),
		color = C.MetalDark,
		material = Enum.Material.Metal,
	})
	Props.crt(f, at(-21.6, 6.5, 26, Y.East), zone, "Lobby_TV", { size = "Large", role = "Lobby", lightRange = 14 })

	-- Station identity wall above the hall opening.
	local wall = B.part({
		parent = f,
		name = "LogoWall",
		role = "Detail",
		size = Vector3.new(14, 3, 0.2),
		cf = at(-4, 11, 4.65),
		color = Color3.fromRGB(26, 22, 20),
		material = Enum.Material.Wood,
	})
	B.label(
		wall,
		Enum.NormalId.Back,
		"KZRO  CHANNEL 0",
		{ color = Color3.fromRGB(205, 170, 100), font = Enum.Font.Antique, ppu = 30 }
	)
	Props.wallClock(f, at(-4, 8.2, 4.7, 180), zone)

	-- Photos (west wall): history told on the walls.
	Props.framedPhoto(f, at(-23.4, 6, 14, Y.East), 3, 2.4, "HALVORSEN BROADCASTING — SIGN-ON 1961")
	Props.framedPhoto(f, at(-23.4, 6, 38, Y.East), 3, 2.4, "NIGHT DESK CREW 1986", Color3.fromRGB(140, 120, 96))
	-- One frame has been taken down; the nail and a clean rectangle remain.
	B.part({
		parent = f,
		name = "MissingFrame",
		role = "Detail",
		size = Vector3.new(0.05, 2.4, 3),
		cf = at(-23.47, 6, 31),
		color = Color3.fromRGB(130, 96, 64),
		material = Enum.Material.Wood,
	})

	-- Vending machine and water cooler near the north-west corner.
	Props.vendingMachine(f, at(-20.5, 0, 7.2, Y.South))
	Props.waterCooler(f, at(-16.5, 0, 6.2, Y.South))
	Props.trashCan(f, at(-17.5, 0, 41.5))
	-- Entrance mat and a coat rack.
	B.part({
		parent = f,
		name = "EntranceMat",
		role = "Detail",
		size = Vector3.new(7, 0.06, 4),
		cf = at(-4, 0.03, 41.5),
		color = C.PlasticBlack,
		material = Enum.Material.Fabric,
		collide = false,
	})
	B.part({
		parent = f,
		name = "CoatRack",
		size = Vector3.new(0.3, 6, 0.3),
		cf = at(1.5, 3, 42.5),
		color = C.WoodPanel,
		material = Enum.Material.Wood,
	})

	-- Lighting: warm, a little too dim. Lobby is the "safe" room of the station.
	ceilingFixtures(f, zone, { -16, -4, 8 }, { 14, 30 }, h, {
		lightColor = Color3.fromRGB(255, 224, 180),
		color = Color3.fromRGB(255, 236, 210),
		brightness = 1.05,
		range = 18,
	})
	Common.emitter(f, "FluorescentBuzz", at(-4, h - 1, 30), zone)
	Common.monitorSwitch(f, zone, at(-23.45, 4.2, 18, Y.East))
	Common.securityCamera(f, 1, "CAM 01 — RECEPTION", zone, Vector3.new(-23, 12.5, 5.5), Vector3.new(-4, 3, 34))
	for i = 1, 4 do
		Common.marker(f, "Spawn_Shift_" .. i, at(-8 + i * 1.8, 1, 38, 0), "SpawnShift")
	end
	Common.marker(f, "Spawn_Late", at(-4, 1, 36, 0), "SpawnLate")
end

------------------------------------------------------------------ Security office
function Ground.Security(root: any)
	local zone = "Security"
	local f = B.folder(zone, root) -- X[16,28] Z[24,44]
	-- Camera desk along the east wall: four small monitors, console, chair.
	Props.desk(f, at(25.2, 0, 32, Y.West), 7, 2.6, Color3.fromRGB(110, 100, 86))
	B.part({
		parent = f,
		name = "MonitorShelf",
		size = Vector3.new(1.8, 0.2, 7.6),
		cf = at(26.4, 4.9, 32),
		color = C.MetalDark,
		material = Enum.Material.Metal,
	})
	for i = 1, 4 do
		local z = 32 + (i - 2.5) * 1.8
		Props.crt(f, at(26.5, 5, z, Y.West), zone, "Security_" .. i, { size = "Small", role = "CCTV", lightRange = 6 })
	end
	Props.chair(f, at(22.6, 0, 32, Y.East))
	local console = B.part({
		parent = f,
		name = "CameraKeypad",
		size = Vector3.new(1.2, 0.2, 2),
		cf = at(24.6, 2.8, 32),
		color = C.PlasticGrey,
	})
	Props.cellPanel(
		console,
		Enum.NormalId.Top,
		3,
		6,
		{ C.PlasticBlack, Color3.fromRGB(200, 200, 190) },
		{ lightInfluence = 0.4 }
	)
	Common.device(
		f,
		at(24.4, 3.6, 32),
		Vector3.new(2.2, 1.6, 3),
		"CameraConsole",
		"CamConsole_Security",
		zone,
		"prompt.cameras",
		"View",
		{ distance = 7 }
	)
	Common.tapeSlot(f, "Slot_Security_Desk", zone, at(25.2, 2.75, 35.2, 20))
	Props.filingCabinet(f, at(17.4, 0, 41.8, Y.East))
	-- Key board: hooks with empty spaces and one tag that reads B (Studio B).
	local keys = B.part({
		parent = f,
		name = "KeyBoard",
		role = "Detail",
		size = Vector3.new(0.1, 2, 3),
		cf = at(16.56, 5.5, 28),
		color = C.WoodLight,
		material = Enum.Material.Wood,
	})
	B.label(
		keys,
		Enum.NormalId.Right,
		"KEYS\nMCR  ED  ARCH\nSTUDIO B — RETURNED 10/87",
		{ font = Enum.Font.Code, padding = 0.1 }
	)
	Props.poster(
		f,
		at(22, 6.5, 43.4, Y.North),
		3,
		2,
		"NIGHT PATROL\nCHECK STUDIO A\nEVERY HOUR\n\n(NOT AFTER 2)",
		{ font = Enum.Font.Code }
	)
	B.part({
		parent = f,
		name = "Coffee",
		role = "Detail",
		size = Vector3.new(0.35, 0.45, 0.35),
		cf = at(24.6, 2.93, 29.6),
		color = Color3.fromRGB(230, 230, 220),
	})
	Props.fluorescent(f, at(22, 12, 34), zone, { brightness = 0.9 })
	Common.monitorSwitch(f, zone, at(16.55, 4.2, 38, Y.East))
end

------------------------------------------------------------------ Main hall
function Ground.MainHall(root: any)
	local zone = "MainHall"
	local f = B.folder(zone, root) -- X[-64,64] Z[-4,4]
	local xs = {}
	for x = -58, 58, 12 do
		table.insert(xs, x)
	end
	ceilingFixtures(f, zone, xs, { 0 }, 12, { brightness = 1.1, range = 16 })
	Common.emitter(f, "FluorescentBuzz", at(-30, 11, 0), zone)
	Common.emitter(f, "FluorescentBuzz", at(30, 11, 0), zone)
	-- Wall furniture placed between doors only.
	Props.framedPhoto(f, at(-12, 6, -3.4, Y.South), 2.6, 2, "EMMY — REGIONAL NEWS 1983")
	Props.framedPhoto(f, at(8, 6, -3.4, Y.South), 2.6, 2, "W. HALE — 1,000 NIGHTS")
	Props.poster(
		f,
		at(-26, 5.5, 3.42, Y.North),
		3.2,
		2.4,
		"ATTENTION ALL STAFF\nTHE OVERNIGHT CARRIER\nMUST NOT DROP.\n— MANAGEMENT",
		{ font = Enum.Font.Code }
	)
	Props.poster(
		f,
		at(28, 5.5, -3.42, Y.South),
		3,
		2.2,
		"ON AIR LIGHT = SILENCE\nIN THE HALLWAY",
		{ font = Enum.Font.Arcade, background = Color3.fromRGB(150, 30, 28), color = Color3.fromRGB(240, 230, 220) }
	)
	B.part({
		parent = f,
		name = "Bench",
		size = Vector3.new(6, 1.6, 1.6),
		cf = at(-14, 0.8, 2.8),
		color = C.WoodPanel,
		material = Enum.Material.Wood,
	})
	Props.trashCan(f, at(-18.6, 0, 3))
	Props.extinguisher(f, at(14, 0, 3.35))
	Props.extinguisher(f, at(-50, 0, -3.35))
	Props.wallClock(f, at(10, 8.6, 3.45, 0), zone)
	-- Fountain
	B.part({
		parent = f,
		name = "Fountain",
		size = Vector3.new(1.6, 3, 1.2),
		cf = at(46, 1.5, 3.2),
		color = C.Metal,
		material = Enum.Material.Metal,
	})
	Common.securityCamera(f, 2, "CAM 02 — MAIN HALL W", zone, Vector3.new(-62.5, 11, -3), Vector3.new(-20, 2.5, 1.5))
	Common.securityCamera(f, 3, "CAM 03 — MAIN HALL E", zone, Vector3.new(62.5, 11, 3), Vector3.new(20, 2.5, -1.5))
end

------------------------------------------------------------------ Service corridors
function Ground.Corridors(root: any)
	local f = B.folder("Corridors", root)
	-- West corridor: x [-64,-56]
	for z = -30, 40, 12 do
		if z < -6 or z > 6 then
			Props.fluorescent(
				f,
				at(-60, 12, z),
				"WestCorridor",
				{ brightness = 0.95, color = Color3.fromRGB(210, 232, 214) }
			)
		end
	end
	-- East corridor: x [56,64], z up to 24
	for z = -30, 20, 12 do
		if z < -6 or z > 6 then
			Props.fluorescent(
				f,
				at(60, 12, z),
				"EastCorridor",
				{ brightness = 0.95, color = Color3.fromRGB(210, 232, 214) }
			)
		end
	end
	-- Cable corridor: z [-44,-36]. Sparse caged bulbs, cable trays along the ceiling.
	for x = -56, 56, 16 do
		Props.cagedBulb(f, at(x, 12, -40), "CableCorridor", { brightness = 0.95, range = 16 })
	end
	Props.cableTray(f, Vector3.new(-62, 10.6, -37.6), Vector3.new(62, 10.6, -37.6))
	Props.cableTray(f, Vector3.new(-62, 10.6, -42.4), Vector3.new(62, 10.6, -42.4))
	Props.pipe(f, Vector3.new(-63, 9.4, -43.2), Vector3.new(63, 9.4, -43.2), 0.35, C.MetalRust)
	Props.cableTray(f, Vector3.new(-60, 10.6, -34), Vector3.new(-60, 10.6, 42))
	Props.cableTray(f, Vector3.new(60, 10.6, -34), Vector3.new(60, 10.6, 22))
	-- Clutter that makes the service corridors feel used, not designed.
	Props.boxes(f, at(-46, 0, -42.5, 7), 3, 11)
	Props.boxes(f, at(18, 0, -42.6, -12), 2, 5)
	B.part({
		parent = f,
		name = "CableSpool",
		size = Vector3.new(1.4, 3, 3),
		cf = at(36, 1.5, -42.6) * CFrame.Angles(0, 0, 0),
		color = C.WoodLight,
		material = Enum.Material.WoodPlanks,
		shape = Enum.PartType.Cylinder,
	})
	B.part({
		parent = f,
		name = "Ladder",
		size = Vector3.new(1.8, 9, 0.3),
		cf = at(-62.2, 4.6, -26) * CFrame.Angles(math.rad(-8), math.rad(90), 0),
		color = C.SafetyYellow,
		material = Enum.Material.Metal,
	})
	B.part({
		parent = f,
		name = "Cart",
		size = Vector3.new(2.4, 2.8, 4),
		cf = at(61.6, 1.4, 12),
		color = C.MetalDark,
		material = Enum.Material.Metal,
	})
	Props.extinguisher(f, at(-63.35, 0, 14))
	Common.emitter(f, "FluorescentBuzz", at(-60, 11, 20), "WestCorridor")
end

------------------------------------------------------------------ Studio A
function Ground.StudioA(root: any)
	local zone = "StudioA"
	local f = B.folder(zone, root) -- X[-56,-16] Z[-36,-4] h22
	local h = 22
	-- Set: backdrop against the north wall, news desk facing the cameras (south).
	Props.backdrop(f, at(-40, 0.6, -34.6, Y.South), 15, 11, "NIGHT DESK")
	local desk, chair = Props.newsDesk(f, at(-38, 0.6, -27.5, Y.South))
	-- Riser under the set.
	B.part({
		parent = f,
		name = "Riser",
		size = Vector3.new(24, 0.6, 9),
		cf = at(-38, 0.3, -30.5),
		color = Color3.fromRGB(24, 22, 26),
		material = Enum.Material.Carpet,
	})
	local _ = chair
	local seatPos = Vector3.new(-38, 0.6, -29.7)
	Common.device(
		f,
		CFrame.new(seatPos + Vector3.new(0, 2.4, 0)),
		Vector3.new(2, 3, 2),
		"AnchorDesk",
		"AnchorDesk",
		zone,
		"prompt.desk",
		"Sit",
		{ distance = 5 }
	)
	Common.device(
		f,
		at(-36.2, 2.8, -26.4),
		Vector3.new(1.6, 1, 1.4),
		"Drawer",
		"AnchorDeskDrawer",
		zone,
		"prompt.drawer",
		"Search",
		{ distance = 5 }
	)
	Common.tapeSlot(f, "Slot_StudioA_Drawer", zone, at(-36.2, 3.75, -27.1, 0))
	Common.marker(
		f,
		"AnchorStage_Desk",
		CFrame.new(seatPos) * CFrame.Angles(0, math.rad(180), 0),
		"AnchorStage",
		{ Stage = "Desk" }
	)
	Common.marker(f, "Spawn_Recover", at(-38, 1.6, -22, 0), "SpawnRecover")

	-- Studio cameras on the floor aimed at the desk.
	Props.studioCamera(f, at(-46, 0, -15, 25), "1")
	Props.studioCamera(f, at(-38, 0, -13, 0), "2")
	Props.studioCamera(f, at(-30, 0, -15, -25), "3")
	-- Floor monitor and teleprompter.
	B.part({
		parent = f,
		name = "MonitorStand",
		size = Vector3.new(0.4, 3.6, 0.4),
		cf = at(-24, 1.8, -24),
		color = C.MetalDark,
		material = Enum.Material.Metal,
	})
	Props.crt(f, at(-24, 3.6, -24, 120), zone, "StudioA_Floor", { size = "Medium", role = "Studio", lightRange = 10 })
	-- Lighting grid.
	for _, z in { -30, -22, -14 } do
		Props.pipe(f, Vector3.new(-54, 18, z), Vector3.new(-18, 18, z), 0.2, C.MetalDark)
	end
	Props.studioLight(f, at(-44, 18, -22, 160), zone, { on = true, tilt = -42, brightness = 2.4, shadows = true })
	Props.studioLight(f, at(-32, 18, -22, -160), zone, { on = true, tilt = -42, brightness = 2.1 })
	Props.studioLight(f, at(-38, 18, -14, 180), zone, { on = false, tilt = -30 })
	Props.studioLight(f, at(-50, 18, -30, 120), zone, { on = false, tilt = -50 })
	Props.studioLight(f, at(-26, 18, -30, -120), zone, { on = false, tilt = -50 })
	-- Work lights: dim fluorescents high up so the studio is never pitch black.
	ceilingFixtures(
		f,
		zone,
		{ -48, -28 },
		{ -10 },
		h,
		{ brightness = 0.55, range = 26, color = Color3.fromRGB(200, 210, 220) }
	)
	-- Tape marks on the floor and cables snaking from the cameras.
	for i, xz in { { -46, -18 }, { -38, -16 }, { -30, -18 } } do
		B.part({
			parent = f,
			name = "FloorMark" .. i,
			role = "Detail",
			size = Vector3.new(1.2, 0.03, 0.15),
			cf = at(xz[1], 0.02, xz[2]),
			color = C.SafetyYellow,
			collide = false,
		})
	end
	for i, path in
		{
			{ Vector3.new(-46, 0.1, -14), Vector3.new(-52, 0.1, -6) },
			{ Vector3.new(-38, 0.1, -12), Vector3.new(-36, 0.1, -5) },
			{ Vector3.new(-30, 0.1, -14), Vector3.new(-18, 0.1, -12) },
		}
	do
		local cable = Props.pipe(f, path[1], path[2], 0.1, C.PlasticBlack)
		cable.Name = "FloorCable" .. i
		cable.CanCollide = false
	end
	-- Flats leaning against the west wall; an ON AIR sign over the hall doors.
	B.part({
		parent = f,
		name = "FlatA",
		size = Vector3.new(0.4, 10, 6),
		cf = at(-54.6, 5, -20) * CFrame.Angles(0, 0, math.rad(-6)),
		color = Color3.fromRGB(80, 74, 70),
		material = Enum.Material.WoodPlanks,
	})
	B.part({
		parent = f,
		name = "FlatB",
		size = Vector3.new(0.4, 9, 5),
		cf = at(-54.2, 4.5, -13) * CFrame.Angles(0, 0, math.rad(-9)),
		color = Color3.fromRGB(60, 70, 90),
		material = Enum.Material.WoodPlanks,
	})
	local onAir = B.part({
		parent = f,
		name = "OnAirSign",
		role = "Detail",
		size = Vector3.new(3, 1, 0.3),
		cf = at(-36, 10.5, -4.8, Y.North),
		color = Color3.fromRGB(60, 10, 10),
		material = Enum.Material.SmoothPlastic,
	})
	onAir:AddTag("OnAirSign")
	onAir:SetAttribute("BaseColor", onAir.Color)
	B.label(
		onAir,
		Enum.NormalId.Back,
		"ON AIR",
		{ color = Color3.fromRGB(255, 220, 210), font = Enum.Font.Arcade, lightInfluence = 0 }
	)
	Common.monitorSwitch(f, zone, at(-17.45, 4.2, -9, Y.West))
	Common.securityCamera(f, 4, "CAM 04 — STUDIO A", zone, Vector3.new(-17.5, 16, -5.5), Vector3.new(-38, 3, -28), 64)
	Common.emitter(f, "StudioRoomTone", at(-38, 8, -20), zone)
	return desk
end

------------------------------------------------------------------ Master control
function Ground.MasterControl(root: any)
	local zone = "MasterControl"
	local f = B.folder(zone, root) -- X[-16,12] Z[-36,-4]
	Props.monitorWall(f, at(-2, 0, -33.2, Y.North), zone, "MCR", 5, 3)
	Props.switcherConsole(f, at(-2, 0, -25, Y.South), 12)
	Common.device(
		f,
		at(-2, 3.4, -23.6),
		Vector3.new(10, 1.6, 2),
		"Switcher",
		"Switcher",
		zone,
		"prompt.console",
		"Operate",
		{ distance = 7 }
	)
	Props.chair(f, at(-4, 0, -21, Y.North))
	Props.chair(f, at(1.5, 0, -21.4, 10))
	-- VTR rack west of the console.
	Props.rack(f, at(-12.8, 0, -27, Y.East), 21, { height = 4.4 })
	local _, vtr = Props.vtrDeck(f, at(-12.6, 4.4, -27, Y.East), "MCR VTR-1")
	local _v = vtr
	Common.device(
		f,
		at(-12, 4.9, -27),
		Vector3.new(2.6, 1.4, 3),
		"VTR",
		"VTR_MCR",
		zone,
		"prompt.vtr",
		"Use",
		{ distance = 6 }
	)
	Common.tapeSlot(f, "Slot_MCR_Rack", zone, at(-12.6, 5.35, -28.8, 90))
	-- Camera console (east side).
	Props.desk(f, at(9.4, 0, -14, Y.West), 6, 2.6, C.PlasticGrey)
	Props.crt(f, at(10.4, 2.7, -15.4, Y.West), zone, "MCR_Cam1", { size = "Small", role = "CCTV", lightRange = 5 })
	Props.crt(f, at(10.4, 2.7, -12.6, Y.West), zone, "MCR_Cam2", { size = "Small", role = "CCTV", lightRange = 5 })
	Common.device(
		f,
		at(8.4, 3.6, -14),
		Vector3.new(2.2, 1.6, 3),
		"CameraConsole",
		"CamConsole_MCR",
		zone,
		"prompt.cameras",
		"View",
		{ distance = 7 }
	)
	Props.chair(f, at(6.2, 0, -14, Y.East))
	-- Racks along the east wall.
	for i, z in { -33, -30.4, -27.8 } do
		Props.rack(f, at(10.4, 0, z, Y.West), i * 5)
	end
	-- Clocks: the station reference clock above the monitor wall.
	Props.wallClock(f, at(-2, 10.6, -35.3, 0), zone)
	local ref = B.part({
		parent = f,
		name = "ReferenceClockLabel",
		role = "Detail",
		size = Vector3.new(3, 0.4, 0.05),
		cf = at(-2, 9.2, -35.4),
		color = C.PlasticBlack,
	})
	B.label(
		ref,
		Enum.NormalId.Front,
		"STATION REFERENCE",
		{ color = Color3.fromRGB(220, 220, 210), font = Enum.Font.Arcade, lightInfluence = 0 }
	)
	-- Dim work lights + desk lamps; the monitor wall does most of the lighting.
	ceilingFixtures(f, zone, { -8, 4 }, { -14 }, 12, { brightness = 0.7, range = 14 })
	Props.fluorescent(f, at(-2, 12, -28), zone, { brightness = 0.45, range = 12 })
	local lampShade = B.part({
		parent = f,
		name = "ConsoleLamp",
		role = "Detail",
		size = Vector3.new(0.5, 0.4, 0.5),
		cf = at(4.8, 3.55, -25.6),
		color = C.PlasticBlack,
		material = Enum.Material.Metal,
	})
	local lamp = B.model("ConsoleLampFixture", f)
	lampShade.Parent = lamp
	lamp:AddTag("Fixture")
	lamp:SetAttribute("Zone", zone)
	lamp:SetAttribute("Kind", "Lamp")
	local pl = B.pointLight(lampShade, { color = C.Warm, brightness = 0.7, range = 9 })
	pl:SetAttribute("BaseBrightness", pl.Brightness)
	Props.poster(
		f,
		at(-15.4, 6, -9, Y.East),
		2.6,
		3,
		"SIGN-ON 05:58\nSIGN-OFF —\n\nOVERNIGHT:\nFILLER #3 LOOP\nVTR-1\n\nDO NOT AIR\nCH 0",
		{ font = Enum.Font.Code }
	)
	Common.monitorSwitch(f, zone, at(11.45, 4.2, -7, Y.West))
	Common.emitter(f, "CRTWhine", at(-2, 4, -32), zone)
	Common.emitter(f, "RackFans", at(10, 3, -30), zone)
end

------------------------------------------------------------------ Edit bay
function Ground.Editing(root: any)
	local zone = "Editing"
	local f = B.folder(zone, root) -- X[12,32] Z[-36,-4]
	-- Main edit station against the north wall.
	Props.desk(f, at(22, 0, -33.4, Y.South), 10, 3, C.WoodPanel)
	Props.crt(f, at(19.5, 2.7, -34, Y.South), zone, "Editing_1", { size = "Medium", role = "Preview", lightRange = 9 })
	Props.crt(f, at(23.5, 2.7, -34, Y.South), zone, "Editing_2", { size = "Medium", role = "Preview", lightRange = 9 })
	Props.vtrDeck(f, at(27, 2.7, -33.6, Y.South), "EDIT VTR-A")
	Common.device(
		f,
		at(27, 3.4, -32.6),
		Vector3.new(2.8, 1.6, 2.6),
		"VTR",
		"VTR_Editing",
		zone,
		"prompt.vtr",
		"Use",
		{ distance = 6 }
	)
	Props.chair(f, at(22, 0, -29.6, Y.North))
	-- Second station (west wall).
	Props.desk(f, at(14.2, 0, -13, Y.East), 6, 2.6, C.WoodPanel)
	Props.crt(f, at(13.4, 2.7, -14.4, Y.East), zone, "Editing_3", { size = "Small", role = "Preview", lightRange = 6 })
	Props.crt(f, at(13.4, 2.7, -11.6, Y.East), zone, "Editing_4", { size = "Small", role = "Preview", lightRange = 6 })
	Props.chair(f, at(17.2, 0, -13, Y.West))
	-- Tape shelf for the current projects.
	Props.tapeShelf(f, at(29.6, 0, -14, Y.West), 6, 9, "EDIT — CURRENT")
	Common.tapeSlot(f, "Slot_Editing_Shelf", zone, at(29.4, 3.1, -15.8, 90))
	Props.poster(
		f,
		at(22, 6.5, -4.55, Y.North),
		4,
		2.6,
		"EDIT LOG 10/98\nPROMO — HARVEST FEST\nNEWS PKG — RT 9\nNIGHT DESK RESTORE? (NO)",
		{ font = Enum.Font.Code }
	)
	Props.boxes(f, at(30, 0, -6.5, 4), 2, 3)
	-- Warm desk lamps only.
	for i, pos in { Vector3.new(17, 3.6, -33.6), Vector3.new(15, 3.6, -16) } do
		local shade = B.part({
			parent = f,
			name = "LampShade" .. i,
			role = "Detail",
			size = Vector3.new(0.6, 0.45, 0.6),
			cf = CFrame.new(pos),
			color = Color3.fromRGB(60, 50, 40),
			material = Enum.Material.Metal,
		})
		local lamp = B.model("EditLamp" .. i, f)
		shade.Parent = lamp
		lamp:AddTag("Fixture")
		lamp:SetAttribute("Zone", zone)
		lamp:SetAttribute("Kind", "Lamp")
		local pl = B.pointLight(shade, { color = C.Warm, brightness = 0.85, range = 11 })
		pl:SetAttribute("BaseBrightness", pl.Brightness)
	end
	Props.fluorescent(f, at(22, 12, -20), zone, { brightness = 0.6 })
	Common.monitorSwitch(f, zone, at(12.55, 4.2, -9, Y.East))
end

------------------------------------------------------------------ Tape archive
function Ground.TapeArchive(root: any)
	local zone = "TapeArchive"
	local f = B.folder(zone, root) -- X[32,56] Z[-36,-4]
	-- Three rows of shelving running north-south, aisles between.
	local rows = { 36.2, 43.2, 50.2 }
	for r, x in rows do
		for s = 0, 2 do
			Props.tapeShelf(
				f,
				at(x - 0.8, 0, -31 + s * 6.2, Y.East),
				6,
				r * 7 + s,
				if s == 0 then string.format("ROW %d", r) else nil
			)
			Props.tapeShelf(f, at(x + 0.8, 0, -31 + s * 6.2, Y.West), 6, r * 11 + s + 3)
		end
	end
	Common.tapeSlot(f, "Slot_Archive_A", zone, at(39.7, 1.95, -24.6, 90))
	Common.tapeSlot(f, "Slot_Archive_B", zone, at(46.8, 4.7, -30.8, -90))
	-- Filler cart at the front: the night crew's tapes live here.
	Props.table(f, at(36, 0, -9, 0), 4, 2.4, 3, C.MetalDark)
	local sign = B.part({
		parent = f,
		name = "FillerSign",
		role = "Detail",
		size = Vector3.new(3, 0.6, 0.05),
		cf = at(36, 3.5, -10.2),
		color = C.Paper,
	})
	B.label(sign, Enum.NormalId.Front, "OVERNIGHT FILLER", { font = Enum.Font.Code })
	Common.tapeSlot(f, "Slot_ArchiveFiller", zone, at(36, 3.25, -8.6, 10))
	-- Restricted cage (north-east): chain-link around a single shelf.
	local cage = B.model("RestrictedCage", f)
	for _, seg in
		{
			{ Vector3.new(52.5, 0, -24), Vector3.new(55.5, 0, -24) },
			{ Vector3.new(52.5, 0, -35.5), Vector3.new(52.5, 0, -27) },
		}
	do
		local d = seg[2] - seg[1]
		B.part({
			parent = cage,
			name = "Mesh",
			size = Vector3.new(0.1, 9, d.Magnitude),
			cf = B.lookAt((seg[1] + seg[2]) / 2 + Vector3.new(0, 4.5, 0), seg[2] + Vector3.new(0, 4.5, 0)),
			color = C.Metal,
			material = Enum.Material.Metal,
			transparency = 0.5,
		})
	end
	local cageSign = B.part({
		parent = cage,
		name = "CageSign",
		role = "Detail",
		size = Vector3.new(2.4, 1, 0.05),
		cf = at(52.4, 6, -31, Y.West),
		color = Color3.fromRGB(150, 30, 28),
	})
	B.label(
		cageSign,
		Enum.NormalId.Front,
		"RESTRICTED\nLEGAL HOLD 10/87",
		{ color = Color3.fromRGB(240, 230, 220), font = Enum.Font.Arcade }
	)
	Props.tapeShelf(f, at(54.6, 0, -31, Y.West), 6, 99, "HOLD")
	Common.tapeSlot(f, "Slot_Archive_Restricted", zone, at(54.4, 3.4, -32.6, 90))
	-- Hanging bulbs over the aisles; one already dead.
	for _, x in { 39.7, 46.7 } do
		for _, z in { -28, -16 } do
			Props.cagedBulb(f, at(x, 12, z), zone, { brightness = 1, range = 16 })
		end
	end
	Props.cagedBulb(f, at(36, 12, -8), zone, { brightness = 0.9, range = 14 })
	Common.securityCamera(f, 5, "CAM 05 — TAPE LIBRARY", zone, Vector3.new(33, 11, -35), Vector3.new(46, 2, -10))
end

------------------------------------------------------------------ Offices
function Ground.Offices(root: any)
	local zone = "Offices"
	local f = B.folder(zone, root) -- X[-56,-24] Z[4,24]
	local partition = Color3.fromRGB(120, 116, 104)
	-- Cubicle block: four desks with low fabric partitions.
	for i, pos in { { -50, 10 }, { -50, 18 }, { -34.5, 10 }, { -34.5, 18 } } do
		local x, z = pos[1], pos[2]
		Props.desk(f, at(x, 0, z - 1.4, Y.South), 5, 2.4, Color3.fromRGB(150, 140, 120))
		Props.chair(f, at(x, 0, z + 1.6, Y.North))
		B.part({
			parent = f,
			name = "Partition",
			size = Vector3.new(6.4, 5, 0.3),
			cf = at(x, 2.5, z - 3),
			color = partition,
			material = Enum.Material.Fabric,
		})
		B.part({
			parent = f,
			name = "PartitionSide",
			size = Vector3.new(0.3, 5, 4),
			cf = at(x + 3.36, 2.5, z - 1),
			color = partition,
			material = Enum.Material.Fabric,
		})
		if i ~= 3 then
			Props.crt(
				f,
				at(x - 1, 2.7, z - 1.9, 0),
				zone,
				"Office_" .. i,
				{ size = "Small", role = "Office", lightRange = 5, casing = C.PlasticBeige }
			)
		end
	end
	Common.tapeSlot(f, "Slot_Office_Desk", zone, at(-33.5, 2.75, 8.2, -30))
	-- Station manager's corner: old desk, portrait of Halvorsen, a calendar stopped on October 1987.
	Props.desk(f, at(-28, 0, 19.5, Y.West), 5, 3, C.WoodPanel)
	Props.chair(f, at(-25.6, 0, 19.5, Y.West))
	Props.framedPhoto(f, at(-24.6, 6.4, 14, Y.West), 2.4, 3, "ARNE HALVORSEN 1903–1979")
	Props.poster(f, at(-24.56, 5.5, 20.5, Y.West), 2, 2.4, "OCTOBER 1987\n\n17 ■", { font = Enum.Font.Code })
	Props.filingCabinet(f, at(-54.4, 0, 22, Y.East))
	Props.filingCabinet(f, at(-54.4, 0, 19.8, Y.East))
	Props.bookshelf(f, at(-54.6, 0, 8, Y.East), 4, 7)
	Props.plant(f, at(-26, 0, 6))
	Props.waterCooler(f, at(-30, 0, 5.3, Y.South))
	ceilingFixtures(f, zone, { -48, -32 }, { 9, 19 }, 12, { brightness = 0.9 })
	Common.monitorSwitch(f, zone, at(-55.45, 4.2, 14, Y.East))
end

------------------------------------------------------------------ Lockers
function Ground.Lockers(root: any)
	local zone = "Lockers"
	local f = B.folder(zone, root) -- X[-56,-24] Z[24,44]
	local names = { "OKAFOR", "SEIDEL", "CALLOWAY", "—", "—", "MARSH", "—", "NIGHT 1", "NIGHT 2", "—" }
	for i, name in names do
		local x = -50 + (i - 1) * 2
		local _, body = Props.locker(f, at(x, 0, 42.6, Y.North), name)
		local _b = body
		if name ~= "—" then
			Common.device(
				f,
				at(x, 3.4, 41.2),
				Vector3.new(1.8, 2.4, 1),
				"Locker",
				"Locker_" .. string.gsub(name, " ", ""),
				zone,
				"prompt.locker",
				"Open",
				{ distance = 5 }
			)
		end
	end
	B.part({
		parent = f,
		name = "BenchA",
		size = Vector3.new(16, 1.6, 1.4),
		cf = at(-41, 0.8, 37),
		color = C.WoodLight,
		material = Enum.Material.Wood,
	})
	Common.tapeSlot(f, "Slot_Lockers_Bench", zone, at(-44.5, 1.72, 37.1, 5))
	-- Sinks and a mirror on the east wall.
	for i = 0, 2 do
		B.part({
			parent = f,
			name = "Sink",
			size = Vector3.new(2, 0.8, 2.4),
			cf = at(-25.8, 3, 30 + i * 3.4),
			color = Color3.fromRGB(220, 220, 214),
			material = Enum.Material.Marble,
		})
	end
	B.part({
		parent = f,
		name = "Mirror",
		role = "Detail",
		size = Vector3.new(0.1, 3, 10),
		cf = at(-24.55, 6, 33.4),
		color = Color3.fromRGB(160, 170, 175),
		material = Enum.Material.Glass,
		reflectance = 0.45,
	})
	Props.trashCan(f, at(-26, 0, 42))
	Props.fluorescent(f, at(-46, 12, 34), zone, { brightness = 0.85 })
	Props.fluorescent(f, at(-32, 12, 34), zone, { brightness = 0.85 })
end

------------------------------------------------------------------ Workshop
function Ground.Workshop(root: any)
	local zone = "Workshop"
	local f = B.folder(zone, root) -- X[28,56] Z[4,24]
	Props.workbench(f, at(54, 0, 14, Y.West), 9)
	Props.chair(f, at(50.4, 0, 12.6, Y.East), C.PlasticBlack)
	Common.tapeSlot(f, "Slot_Workshop_Bench", zone, at(53.6, 3.25, 16.8, 30))
	local _, panel = Props.breakerPanel(f, at(28.9, 0, 14, Y.East), "A")
	local _p = panel
	Common.device(
		f,
		at(29.8, 4.2, 14),
		Vector3.new(1.4, 4.4, 3),
		"BreakerPanel",
		"PanelA",
		zone,
		"prompt.panel",
		"Open",
		{ distance = 6 }
	)
	Props.bookshelf(f, at(32, 0, 5.3, Y.South), 4, 6)
	Props.boxes(f, at(48, 0, 22.4, 10), 3, 7)
	Props.boxes(f, at(51.4, 0, 22.6, -15), 2, 13)
	B.part({
		parent = f,
		name = "CableSpool",
		size = Vector3.new(1.4, 3.4, 3.4),
		cf = at(32, 1.7, 21.5),
		color = C.WoodLight,
		material = Enum.Material.WoodPlanks,
		shape = Enum.PartType.Cylinder,
	})
	B.part({
		parent = f,
		name = "MopBucket",
		size = Vector3.new(1.4, 1.2, 1.4),
		cf = at(48, 0.6, 5.6),
		color = C.SafetyYellow,
	})
	Props.extinguisher(f, at(55.4, 0, 6))
	Props.poster(
		f,
		at(42, 6.5, 4.6, Y.South),
		3.6,
		2.6,
		"DAYS WITHOUT\nAN INCIDENT\n\n0",
		{ font = Enum.Font.Arcade, background = Color3.fromRGB(240, 220, 120) }
	)
	ceilingFixtures(f, zone, { 36, 48 }, { 14 }, 12, { brightness = 1.0 })
	Common.emitter(f, "FluorescentBuzz", at(42, 11, 14), zone)
end

------------------------------------------------------------------ Transmitter
function Ground.Transmitter(root: any)
	local zone = "Transmitter"
	local f = B.folder(zone, root) -- X[28,56] Z[24,44] h14
	for i = 0, 3 do
		Props.transmitterCabinet(f, at(36 + i * 4.6, 0, 41.6, Y.North), i + 1)
	end
	-- Waveguide pipes from the cabinets up through the ceiling.
	Props.pipe(f, Vector3.new(40.6, 8.6, 42), Vector3.new(40.6, 14, 42), 0.8, C.Metal)
	Props.pipe(f, Vector3.new(40.6, 13, 42), Vector3.new(54, 13, 42), 0.8, C.Metal)
	-- Exciter tuner (west), facing east.
	Props.tunerCabinet(f, at(30, 0, 33, Y.East))
	Common.device(
		f,
		at(31.6, 2.6, 33),
		Vector3.new(1.4, 3, 3.6),
		"Tuner",
		"Tuner",
		zone,
		"prompt.tuner",
		"Tune",
		{ distance = 6 }
	)
	-- Carrier keyswitch on the first cabinet.
	local plate = B.part({
		parent = f,
		name = "KeyswitchPlate",
		role = "Detail",
		size = Vector3.new(1, 1.2, 0.08),
		cf = at(36, 3.4, 39.85, Y.North),
		color = C.SafetyYellow,
		material = Enum.Material.Metal,
	})
	B.label(plate, Enum.NormalId.Front, "CARRIER\nKEY", { font = Enum.Font.Arcade, padding = 0.15 })
	Common.device(
		f,
		at(36, 3.4, 39.2),
		Vector3.new(1.4, 1.6, 1),
		"Keyswitch",
		"CarrierKeyswitch",
		zone,
		"prompt.keyswitch",
		"Use",
		{ distance = 5 }
	)
	-- Racks along the north wall; a monitor showing the waveform.
	Props.rack(f, at(46, 0, 25.9, Y.South), 4)
	Props.rack(f, at(48.4, 0, 25.9, Y.South), 8)
	Props.rack(f, at(50.8, 0, 25.9, Y.South), 12)
	Props.desk(f, at(36, 0, 26, Y.South), 5, 2.4, C.PlasticGrey)
	Props.crt(
		f,
		at(36, 2.7, 25.6, Y.South),
		zone,
		"Transmitter_Wave",
		{ size = "Small", role = "Waveform", lightRange = 6 }
	)
	-- Monitor speaker that sometimes turns itself on.
	local speaker = B.part({
		parent = f,
		name = "MonitorSpeaker",
		size = Vector3.new(1.2, 1.6, 1),
		cf = at(30.6, 8, 27),
		color = C.PlasticBlack,
	})
	Props.cellPanel(speaker, Enum.NormalId.Right, 1, 6, { Color3.fromRGB(50, 50, 50) }, { background = C.PlasticBlack })
	Common.marker(f, "RadioSpeaker", at(31.4, 8, 27), "RadioSpeaker")
	Props.poster(
		f,
		at(28.56, 6.5, 40, Y.East),
		2.6,
		2.6,
		"IF CARRIER DROPS:\n1. DO NOT GO TO STUDIO A\n2. RESTORE CARRIER\n3. LOG IT",
		{ font = Enum.Font.Code }
	)
	ceilingFixtures(
		f,
		zone,
		{ 36, 48 },
		{ 32 },
		14,
		{ brightness = 0.8, range = 18, color = Color3.fromRGB(205, 225, 235) }
	)
	Common.emitter(f, "RackFans", at(42, 4, 40), zone)
	Common.securityCamera(f, 6, "CAM 06 — TRANSMITTER", zone, Vector3.new(55, 12.5, 25), Vector3.new(36, 2, 38))
end

------------------------------------------------------------------ Antenna access
function Ground.AntennaAccess(root: any)
	local zone = "AntennaAccess"
	local f = B.folder(zone, root) -- X[56,64] Z[24,44]
	local warn = B.part({
		parent = f,
		name = "RFWarning",
		role = "Detail",
		size = Vector3.new(0.05, 2.2, 3),
		cf = at(63.45, 9.6, 34),
		color = C.SafetyYellow,
	})
	B.label(warn, Enum.NormalId.Left, "ANTENNA YARD\nRF EXPOSURE\nAUTHORIZED ONLY", { font = Enum.Font.Arcade })
	for i = 0, 2 do
		B.part({
			parent = f,
			name = "Hook",
			role = "Detail",
			size = Vector3.new(0.2, 0.2, 0.5),
			cf = at(56.7, 6, 38 + i * 1.5),
			color = C.MetalDark,
		})
	end
	B.part({
		parent = f,
		name = "HardHat",
		role = "Detail",
		size = Vector3.new(1, 0.6, 1.2),
		cf = at(57, 5.6, 39.5),
		color = C.SafetyYellow,
	})
	Props.emergencyLight(f, at(60, 11, 43.4, Y.North), zone)
	Props.fluorescent(f, at(60, 12, 32), zone, { brightness = 0.7 })
end

function Ground.build(root: any)
	Ground.Lobby(root)
	Ground.Security(root)
	Ground.MainHall(root)
	Ground.Corridors(root)
	Ground.StudioA(root)
	Ground.MasterControl(root)
	Ground.Editing(root)
	Ground.TapeArchive(root)
	Ground.Offices(root)
	Ground.Lockers(root)
	Ground.Workshop(root)
	Ground.Transmitter(root)
	Ground.AntennaAccess(root)
end

return Ground
