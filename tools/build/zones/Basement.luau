--[[
	Basement (B1). Floor at y=-12, ceiling is the underside of the ground slab at y=-1.
	Darker, warmer, older. Studio B is the burned 1987 studio.
]]

local B = require("../lib/B")
local Props = require("../lib/Props")
local Common = require("./Common")

local Vector3, CFrame, Color3, Enum = B.Vector3, B.CFrame, B.Color3, B.Enum
local C = B.Colors
local Y = Common.YAW
local at = B.at

local Basement = {}
local FY = -12
local CEIL = -1

function Basement.Hall(root: any)
	local zone = "BasementHall"
	local f = B.folder(zone, root) -- X[-8,56] Z[-4,4]
	for x = -2, 54, 14 do
		Props.cagedBulb(f, at(x, CEIL, 0), zone, { brightness = 0.95, range = 15 })
	end
	Props.pipe(f, Vector3.new(-7.5, -2.6, -3), Vector3.new(55.5, -2.6, -3), 0.5, C.MetalRust)
	Props.pipe(f, Vector3.new(-7.5, -2.2, 3.1), Vector3.new(55.5, -2.2, 3.1), 0.3, C.Metal)
	Props.pipe(f, Vector3.new(-7.5, -3.4, 3.1), Vector3.new(55.5, -3.4, 3.1), 0.2, Color3.fromRGB(150, 40, 30))
	-- Puddles: glossy and thin, they pick up the bulbs.
	for i, pos in { { 10, 1 }, { 30, -1.5 }, { 46, 0.5 } } do
		B.part({
			parent = f,
			name = "Puddle" .. i,
			role = "Detail",
			size = Vector3.new(3, 0.03, 2),
			cf = at(pos[1], FY + 0.02, pos[2], i * 25),
			color = Color3.fromRGB(30, 34, 36),
			material = Enum.Material.Glass,
			reflectance = 0.3,
			collide = false,
		})
	end
	B.part({
		parent = f,
		name = "Cart",
		size = Vector3.new(4, 2.6, 2),
		cf = at(52, FY + 1.3, 2.6),
		color = C.MetalDark,
		material = Enum.Material.Metal,
	})
	local arrow = B.part({
		parent = f,
		name = "StencilB",
		role = "Detail",
		size = Vector3.new(4, 1.4, 0.05),
		cf = at(14, FY + 6, 3.45, Y.North),
		color = C.ConcreteDark,
	})
	B.label(
		arrow,
		Enum.NormalId.Front,
		"◄ STUDIO B",
		{ color = Color3.fromRGB(200, 196, 180), font = Enum.Font.Arcade }
	)
	Common.securityCamera(f, 8, "CAM 08 — BASEMENT HALL", zone, Vector3.new(55, -2.5, -3), Vector3.new(10, FY + 2, 1))
	Common.emitter(f, "BasementDrone", at(24, -6, 0), zone)
end

function Basement.Boiler(root: any)
	local zone = "BoilerRoom"
	local f = B.folder(zone, root) -- X[-8,16] Z[-28,-4]
	Props.boiler(f, at(-2, FY, -18, 0))
	Props.boiler(f, at(7.5, FY, -18, 0))
	for _, x in { -6, 14 } do
		Props.pipe(f, Vector3.new(x, FY, -26), Vector3.new(x, CEIL, -26), 0.45, C.MetalRust)
	end
	Props.pipe(f, Vector3.new(-7.5, -3, -26), Vector3.new(15.5, -3, -26), 0.45, C.MetalRust)
	Props.cagedBulb(f, at(6, CEIL, -10), zone, { brightness = 0.85, range = 14 })
	Props.boxes(f, at(-5, FY, -7, 20), 2, 17)
	Common.emitter(f, "BasementDrone", at(6, -6, -16), zone)
end

function Basement.Generator(root: any)
	local zone = "GeneratorRoom"
	local f = B.folder(zone, root) -- X[16,56] Z[-28,-4]
	Props.generator(f, at(36, FY, -18, 0))
	B.part({
		parent = f,
		name = "FuelTank",
		size = Vector3.new(6, 4, 3),
		cf = at(51, FY + 2, -24),
		color = Color3.fromRGB(120, 110, 60),
		material = Enum.Material.Metal,
	})
	local warn = B.part({
		parent = f,
		name = "Warning",
		role = "Detail",
		size = Vector3.new(3, 1.4, 0.05),
		cf = at(36, FY + 7, -27.45),
		color = C.SafetyYellow,
	})
	B.label(warn, Enum.NormalId.Front, "STANDBY GENERATOR\nAUTO START", { font = Enum.Font.Arcade })
	Props.emergencyLight(f, at(24, CEIL - 0.4, -27.4, Y.South), zone)
	Props.emergencyLight(f, at(48, CEIL - 0.4, -27.4, Y.South), zone)
	Props.cagedBulb(f, at(30, CEIL, -8), zone, { brightness = 0.8, range = 16 })
	Props.cagedBulb(f, at(46, CEIL, -8), zone, { brightness = 0.8, range = 16 })
	Common.emitter(f, "Generator", at(36, FY + 3, -18), zone)
end

function Basement.Electrical(root: any)
	local zone = "Electrical"
	local f = B.folder(zone, root) -- X[28,56] Z[4,24]
	local _, panel = Props.breakerPanel(f, at(55.1, FY, 14, Y.West), "B")
	local _p = panel
	Common.device(
		f,
		at(54.2, FY + 4.2, 14),
		Vector3.new(1.4, 4.4, 3),
		"BreakerPanel",
		"PanelB",
		zone,
		"prompt.panel",
		"Open",
		{ distance = 6 }
	)
	for i = 0, 3 do
		B.part({
			parent = f,
			name = "Switchgear",
			size = Vector3.new(3, 7.5, 2.6),
			cf = at(32 + i * 3.2, FY + 3.75, 22.6),
			color = Color3.fromRGB(110, 120, 116),
			material = Enum.Material.Metal,
		})
	end
	B.part({
		parent = f,
		name = "Transformer",
		size = Vector3.new(4.4, 5, 4),
		cf = at(31, FY + 2.5, 8),
		color = C.MetalDark,
		material = Enum.Material.Metal,
	})
	local sign = B.part({
		parent = f,
		name = "Danger",
		role = "Detail",
		size = Vector3.new(2.6, 1.6, 0.05),
		cf = at(31, FY + 6.4, 5.95, Y.South),
		color = Color3.fromRGB(240, 240, 230),
	})
	B.label(
		sign,
		Enum.NormalId.Front,
		"DANGER\n480 VOLTS",
		{ color = Color3.fromRGB(170, 20, 20), font = Enum.Font.Arcade }
	)
	Props.cagedBulb(f, at(44, CEIL, 14), zone, { brightness = 0.9, range = 16 })
end

function Basement.StudioB(root: any)
	local zone = "StudioB"
	local f = B.folder(zone, root) -- X[-8,16] Z[4,24]
	-- The 1987 set, burned. Same desk shape as Studio A, charred.
	local desk = Props.newsDesk(
		f,
		at(4, FY + 0.6, 16, Y.North),
		{ color = C.Charred, accent = Color3.fromRGB(70, 60, 40), logo = "N GHT D SK" }
	)
	local _d = desk
	B.part({
		parent = f,
		name = "Riser",
		size = Vector3.new(16, 0.6, 8),
		cf = at(4, FY + 0.3, 18.5),
		color = Color3.fromRGB(18, 16, 15),
		material = Enum.Material.Carpet,
	})
	Props.backdrop(
		f,
		at(4, FY, 23.2, Y.North),
		16,
		9,
		"N  HT DE  ",
		{ color = Color3.fromRGB(16, 14, 14), textColor = Color3.fromRGB(80, 70, 50) }
	)
	Common.tapeSlot(f, "Slot_StudioB_Desk", zone, at(4, FY + 3.8, 15.2, 180))
	-- Collapsed lighting grid and scorch marks.
	B.part({
		parent = f,
		name = "FallenTruss",
		size = Vector3.new(11, 0.6, 0.6),
		cf = at(-2, FY + 1.08, 11) * CFrame.Angles(0, math.rad(20), math.rad(8)),
		color = C.Charred,
		material = Enum.Material.CorrodedMetal,
	})
	Props.studioLight(f, at(10, CEIL, 10, 200), zone, { on = false, tilt = -40, color = Color3.fromRGB(255, 220, 180) })
	for i, pos in { { -4, 12 }, { 8, 8 }, { 12, 20 } } do
		B.part({
			parent = f,
			name = "Scorch" .. i,
			role = "Detail",
			size = Vector3.new(5, 0.03, 4),
			cf = at(pos[1], FY + 0.02, pos[2], i * 40),
			color = Color3.fromRGB(12, 10, 10),
			material = Enum.Material.Slate,
			collide = false,
		})
	end
	Props.studioCamera(f, at(4, FY, 7, 180), "2")
	-- A single bare bulb that barely works. Studio B is the darkest room on purpose.
	Props.cagedBulb(f, at(-4, CEIL, 6), zone, { brightness = 0.45, range = 11 })
	Common.securityCamera(f, 7, "CAM 07 — STUDIO B", zone, Vector3.new(-7, -2, 4.8), Vector3.new(4, FY + 3, 18))
	Common.marker(f, "AnchorStage_StudioB", at(4, FY + 0.6, 17.8, 180), "AnchorStage", { Stage = "StudioB" })
	Common.emitter(f, "StudioRoomTone", at(4, -6, 14), zone)
end

function Basement.build(root: any)
	Basement.Hall(root)
	Basement.Boiler(root)
	Basement.Generator(root)
	Basement.Electrical(root)
	Basement.StudioB(root)
end

return Basement
