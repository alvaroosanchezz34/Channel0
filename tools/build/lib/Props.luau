--[[
	Prop library. Every prop is built in local space: origin on the floor at its footprint centre,
	front facing local -Z. Props favour a few well-proportioned parts plus SurfaceGui detail over
	hundreds of tiny parts (cheap to render, cheap to stream).
]]

local roblox = require("@lune/roblox")
local B = require("./B")

local Vector3, CFrame, Color3, Enum = B.Vector3, B.CFrame, B.Color3, B.Enum
local UDim2 = roblox.UDim2
local C = B.Colors

local Props = {}

local function v(x: number, y: number, z: number)
	return Vector3.new(x, y, z)
end

local function p(parent: any, name: string, size: any, cf: any, color: any, material: any?, extra: { [string]: any }?)
	local spec = {
		parent = parent,
		name = name,
		size = size,
		cf = cf,
		color = color,
		material = material or Enum.Material.SmoothPlastic,
	}
	if extra then
		for k, val in extra do
			spec[k] = val
		end
	end
	return B.part(spec)
end

-- A SurfaceGui panel of coloured cells (button banks, LED rows, tape spines).
local function cellPanel(part: any, face: any, cols: number, rows: number, colors: { any }, opts: { [string]: any }?)
	local o = opts or {}
	local gui = B.Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = o.ppu or 30
	gui.LightInfluence = o.lightInfluence or 0.6
	gui.Name = o.name or "Panel"
	local frame = B.Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = o.background or C.PlasticBlack
	frame.BorderSizePixel = 0
	frame.Parent = gui
	local grid = B.Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromScale(1 / cols * 0.78, 1 / rows * 0.7)
	grid.CellPadding = UDim2.fromScale(1 / cols * 0.22, 1 / rows * 0.3)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = frame
	local pad = B.Instance.new("UIPadding")
	pad.PaddingLeft = roblox.UDim.new(1 / cols * 0.11, 0)
	pad.PaddingTop = roblox.UDim.new(1 / rows * 0.15, 0)
	pad.Parent = frame
	local seed = o.seed or 1
	for i = 1, cols * rows do
		local cell = B.Instance.new("Frame")
		seed = (seed * 1103515245 + 12345) % 2147483648
		cell.BackgroundColor3 = colors[(seed % #colors) + 1]
		cell.BorderSizePixel = 0
		cell.LayoutOrder = i
		cell.Parent = frame
	end
	gui.Parent = part
	return gui
end
Props.cellPanel = cellPanel

---------------------------------------------------------------- Lighting fixtures

function Props.fluorescent(parent: any, cf: any, zone: string, opts: { [string]: any }?)
	local o = opts or {}
	local m = B.model("Fluorescent", parent)
	m:AddTag("Fixture")
	m:SetAttribute("Zone", zone)
	m:SetAttribute("Kind", "Fluorescent")
	local len = o.length or 4
	p(m, "Housing", v(len, 0.25, 1.6), B.off(cf, 0, -0.125, 0), C.Metal, Enum.Material.Metal, { role = "Detail" })
	local tube = p(
		m,
		"Diffuser",
		v(len - 0.3, 0.08, 1.3),
		B.off(cf, 0, -0.29, 0),
		o.color or Color3.fromRGB(226, 236, 230),
		Enum.Material.Neon,
		{ role = "Light", transparency = 0.15 }
	)
	tube:SetAttribute("BaseColor", o.color or Color3.fromRGB(226, 236, 230))
	local light = B.surfaceLight(tube, {
		face = Enum.NormalId.Bottom,
		brightness = o.brightness or 1.15,
		range = o.range or 16,
		angle = 120,
		color = o.lightColor or C.Fluor,
		shadows = o.shadows or false,
	})
	light:SetAttribute("BaseBrightness", light.Brightness)
	return m
end

function Props.cagedBulb(parent: any, cf: any, zone: string, opts: { [string]: any }?)
	local o = opts or {}
	local m = B.model("CagedBulb", parent)
	m:AddTag("Fixture")
	m:SetAttribute("Zone", zone)
	m:SetAttribute("Kind", "Bulb")
	p(m, "Base", v(0.6, 0.3, 0.6), B.off(cf, 0, -0.15, 0), C.MetalDark, Enum.Material.Metal, { role = "Detail" })
	local bulb = p(
		m,
		"Bulb",
		v(0.45, 0.6, 0.45),
		B.off(cf, 0, -0.6, 0),
		o.color or Color3.fromRGB(255, 205, 140),
		Enum.Material.Neon,
		{ role = "Light", shape = Enum.PartType.Ball }
	)
	bulb.Size = v(0.5, 0.5, 0.5)
	bulb:SetAttribute("BaseColor", bulb.Color)
	for i = 0, 3 do
		local a = math.rad(i * 90)
		p(
			m,
			"Cage",
			v(0.05, 0.8, 0.05),
			B.off(cf, math.cos(a) * 0.32, -0.6, math.sin(a) * 0.32),
			C.MetalDark,
			Enum.Material.Metal,
			{ role = "Detail" }
		)
	end
	local light = B.pointLight(bulb, {
		brightness = o.brightness or 1.1,
		range = o.range or 18,
		color = o.lightColor or C.Warm,
		shadows = o.shadows or false,
	})
	light:SetAttribute("BaseBrightness", light.Brightness)
	return m
end

function Props.emergencyLight(parent: any, cf: any, zone: string)
	local m = B.model("EmergencyLight", parent)
	m:AddTag("Fixture")
	m:SetAttribute("Zone", zone)
	m:SetAttribute("Kind", "Emergency")
	p(m, "Box", v(1.4, 0.6, 0.5), cf, C.PlasticBeige, nil, { role = "Detail" })
	local lamp = p(
		m,
		"Lamp",
		v(1.1, 0.2, 0.3),
		B.off(cf, 0, -0.38, -0.05),
		Color3.fromRGB(255, 80, 60),
		Enum.Material.Neon,
		{ role = "Light", transparency = 0.2 }
	)
	lamp:SetAttribute("BaseColor", lamp.Color)
	local light = B.surfaceLight(
		lamp,
		{ face = Enum.NormalId.Bottom, brightness = 0.6, range = 14, angle = 140, color = Color3.fromRGB(255, 70, 50) }
	)
	light:SetAttribute("BaseBrightness", light.Brightness)
	light.Enabled = false
	return m
end

function Props.studioLight(parent: any, cf: any, zone: string, opts: { [string]: any }?)
	-- Fresnel hung from the grid; cf = hanging point, aims along its local -Z tilted down.
	local o = opts or {}
	local m = B.model("StudioLight", parent)
	m:AddTag("Fixture")
	m:SetAttribute("Zone", zone)
	m:SetAttribute("Kind", "Studio")
	p(m, "Clamp", v(0.3, 1.2, 0.3), B.off(cf, 0, -0.6, 0), C.MetalDark, Enum.Material.Metal, { role = "Detail" })
	local aim = B.off(cf, 0, -1.6, 0) * CFrame.Angles(math.rad(o.tilt or -35), 0, 0)
	p(m, "Yoke", v(1.5, 0.15, 0.15), aim * CFrame.new(0, 0.6, 0), C.MetalDark, Enum.Material.Metal, { role = "Detail" })
	p(m, "Body", v(1.1, 1.1, 1.5), aim, C.PlasticBlack, Enum.Material.Metal, { role = "Detail" })
	local lens = p(
		m,
		"Lens",
		v(0.9, 0.9, 0.1),
		aim * CFrame.new(0, 0, -0.8),
		o.color or Color3.fromRGB(255, 236, 200),
		Enum.Material.Neon,
		{ role = "Light", transparency = if o.on then 0 else 0.6 }
	)
	lens:SetAttribute("BaseColor", lens.Color)
	for _, side in { -1, 1 } do
		p(
			m,
			"BarnDoor",
			v(0.05, 1, 0.6),
			aim * CFrame.new(side * 0.6, 0, -1.05) * CFrame.Angles(0, math.rad(side * 25), 0),
			C.PlasticBlack,
			Enum.Material.Metal,
			{ role = "Detail" }
		)
	end
	local light = B.spotLight(lens, {
		face = Enum.NormalId.Front,
		brightness = o.brightness or 2.2,
		range = o.range or 30,
		angle = o.angle or 40,
		color = o.lightColor or Color3.fromRGB(255, 226, 190),
		shadows = o.shadows or false,
	})
	light:SetAttribute("BaseBrightness", light.Brightness)
	light.Enabled = o.on or false
	m:SetAttribute("StartsOn", o.on or false)
	return m
end

function Props.sodiumLamp(parent: any, cf: any, zone: string)
	local m = B.model("LampPost", parent)
	m:AddTag("Fixture")
	m:SetAttribute("Zone", zone)
	m:SetAttribute("Kind", "Sodium")
	p(m, "Pole", v(0.5, 18, 0.5), B.off(cf, 0, 9, 0), C.MetalDark, Enum.Material.Metal)
	p(m, "Arm", v(0.3, 0.3, 4), B.off(cf, 0, 17.8, -2), C.MetalDark, Enum.Material.Metal, { role = "Detail" })
	p(m, "Head", v(1.4, 0.6, 2.2), B.off(cf, 0, 17.6, -4), C.MetalDark, Enum.Material.Metal, { role = "Detail" })
	local lamp =
		p(m, "Lamp", v(1.1, 0.12, 1.8), B.off(cf, 0, 17.25, -4), C.Sodium, Enum.Material.Neon, { role = "Light" })
	lamp:SetAttribute("BaseColor", lamp.Color)
	local light = B.surfaceLight(
		lamp,
		{ face = Enum.NormalId.Bottom, brightness = 1.8, range = 40, angle = 120, color = C.Sodium, shadows = true }
	)
	light:SetAttribute("BaseBrightness", light.Brightness)
	return m
end

---------------------------------------------------------------- Furniture

function Props.desk(parent: any, cf: any, w: number?, d: number?, color: any?)
	local width, depth = w or 5, d or 2.6
	local m = B.model("Desk", parent)
	local col = color or C.WoodPanel
	p(m, "Top", v(width, 0.2, depth), B.off(cf, 0, 2.6, 0), col, Enum.Material.Wood)
	p(m, "SideL", v(0.15, 2.5, depth - 0.1), B.off(cf, -width / 2 + 0.1, 1.25, 0), col, Enum.Material.Wood)
	p(m, "Drawers", v(1.6, 2.5, depth - 0.1), B.off(cf, width / 2 - 0.85, 1.25, 0), col, Enum.Material.Wood)
	p(m, "Modesty", v(width - 0.3, 1.5, 0.1), B.off(cf, 0, 1.75, depth / 2 - 0.15), col, Enum.Material.Wood)
	for i = 0, 2 do
		p(
			m,
			"Pull",
			v(0.6, 0.08, 0.08),
			B.off(cf, width / 2 - 0.85, 2.15 - i * 0.75, -depth / 2 + 0.02),
			C.Metal,
			Enum.Material.Metal,
			{ role = "Detail" }
		)
	end
	return m
end

function Props.chair(parent: any, cf: any, color: any?)
	local m = B.model("Chair", parent)
	local col = color or C.FabricBlue
	p(m, "Seat", v(1.6, 0.35, 1.6), B.off(cf, 0, 1.6, 0), col, Enum.Material.Fabric)
	p(
		m,
		"Back",
		v(1.5, 1.8, 0.3),
		B.off(cf, 0, 2.7, 0.75) * CFrame.Angles(math.rad(-8), 0, 0),
		col,
		Enum.Material.Fabric
	)
	p(m, "Post", v(0.25, 1.3, 0.25), B.off(cf, 0, 0.8, 0), C.MetalDark, Enum.Material.Metal, { role = "Detail" })
	p(m, "BaseA", v(1.8, 0.15, 0.25), B.off(cf, 0, 0.15, 0), C.PlasticBlack, nil, { role = "Detail" })
	p(m, "BaseB", v(0.25, 0.15, 1.8), B.off(cf, 0, 0.15, 0), C.PlasticBlack, nil, { role = "Detail" })
	return m
end

function Props.stool(parent: any, cf: any)
	local m = B.model("Stool", parent)
	p(
		m,
		"Seat",
		v(1.3, 0.25, 1.3),
		B.off(cf, 0, 2.4, 0),
		C.PlasticBlack,
		Enum.Material.Fabric,
		{ shape = Enum.PartType.Cylinder, props = { Size = v(0.25, 1.3, 1.3) } }
	)
	local seat = m:FindFirstChild("Seat")
	seat.CFrame = B.off(cf, 0, 2.4, 0) * CFrame.Angles(0, 0, math.rad(90))
	p(m, "Leg", v(0.2, 2.3, 0.2), B.off(cf, 0, 1.15, 0), C.Metal, Enum.Material.Metal, { role = "Detail" })
	return m
end

function Props.sofa(parent: any, cf: any, w: number?, color: any?)
	local width = w or 6
	local m = B.model("Sofa", parent)
	local col = color or Color3.fromRGB(96, 70, 52)
	p(m, "Base", v(width, 1.2, 2.6), B.off(cf, 0, 0.6, 0), col, Enum.Material.Fabric)
	p(m, "Cushion", v(width - 1, 0.5, 2), B.off(cf, 0, 1.45, -0.2), col, Enum.Material.Fabric)
	p(m, "Back", v(width, 1.8, 0.6), B.off(cf, 0, 2.1, 1), col, Enum.Material.Fabric)
	p(m, "ArmL", v(0.6, 1.9, 2.6), B.off(cf, -width / 2 + 0.3, 0.95, 0), col, Enum.Material.Fabric)
	p(m, "ArmR", v(0.6, 1.9, 2.6), B.off(cf, width / 2 - 0.3, 0.95, 0), col, Enum.Material.Fabric)
	return m
end

function Props.table(parent: any, cf: any, w: number, d: number, h: number?, color: any?)
	local height = h or 2.6
	local m = B.model("Table", parent)
	local col = color or C.WoodLight
	p(m, "Top", v(w, 0.2, d), B.off(cf, 0, height, 0), col, Enum.Material.Wood)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			p(
				m,
				"Leg",
				v(0.2, height - 0.1, 0.2),
				B.off(cf, sx * (w / 2 - 0.25), (height - 0.1) / 2, sz * (d / 2 - 0.25)),
				C.MetalDark,
				Enum.Material.Metal,
				{ role = "Detail" }
			)
		end
	end
	return m
end

function Props.plant(parent: any, cf: any)
	local m = B.model("Plant", parent)
	p(m, "Pot", v(1.3, 1.4, 1.3), B.off(cf, 0, 0.7, 0), Color3.fromRGB(120, 70, 50), Enum.Material.Slate)
	local leaves = p(
		m,
		"Leaves",
		v(2.2, 2.2, 2.2),
		B.off(cf, 0, 2.6, 0),
		Color3.fromRGB(58, 78, 46),
		Enum.Material.Grass,
		{ shape = Enum.PartType.Ball, role = "Detail" }
	)
	leaves.Size = v(2.4, 2.4, 2.4)
	-- A dead plant: a few brown leaves on top. Nobody has watered it in a long time.
	p(
		m,
		"Dead",
		v(1.2, 0.6, 1.2),
		B.off(cf, 0.3, 3.7, -0.2),
		Color3.fromRGB(110, 90, 50),
		Enum.Material.Grass,
		{ role = "Detail", shape = Enum.PartType.Ball }
	)
	return m
end

function Props.filingCabinet(parent: any, cf: any, drawers: number?)
	local n = drawers or 4
	local m = B.model("FilingCabinet", parent)
	local h = n * 1.15
	p(m, "Body", v(1.6, h, 2.2), B.off(cf, 0, h / 2, 0), C.Metal, Enum.Material.Metal)
	for i = 1, n do
		p(
			m,
			"Handle",
			v(0.6, 0.1, 0.1),
			B.off(cf, 0, i * 1.15 - 0.5, -1.13),
			C.MetalDark,
			Enum.Material.Metal,
			{ role = "Detail" }
		)
	end
	return m
end

function Props.bookshelf(parent: any, cf: any, w: number?, h: number?)
	local width, height = w or 4, h or 7
	local m = B.model("Bookshelf", parent)
	p(m, "SideL", v(0.2, height, 1.4), B.off(cf, -width / 2 + 0.1, height / 2, 0), C.WoodPanel, Enum.Material.Wood)
	p(m, "SideR", v(0.2, height, 1.4), B.off(cf, width / 2 - 0.1, height / 2, 0), C.WoodPanel, Enum.Material.Wood)
	p(m, "Back", v(width, height, 0.1), B.off(cf, 0, height / 2, 0.65), C.WoodPanel, Enum.Material.Wood)
	for i = 0, 4 do
		local y = 0.2 + i * (height - 0.4) / 4
		p(m, "Shelf", v(width - 0.4, 0.15, 1.3), B.off(cf, 0, y, 0), C.WoodPanel, Enum.Material.Wood)
		if i < 4 then
			local binders = p(
				m,
				"Binders",
				v(width - 0.6, 1.1, 1),
				B.off(cf, 0, y + 0.65, 0.05),
				C.PlasticBlack,
				nil,
				{ role = "Detail" }
			)
			cellPanel(
				binders,
				Enum.NormalId.Front,
				14,
				1,
				{ C.FabricBlue, C.Red, C.PlasticGrey, C.Paper, C.SafetyYellow },
				{ seed = i + width }
			)
		end
	end
	return m
end

function Props.boxes(parent: any, cf: any, count: number?, seed: number?)
	local m = B.model("Boxes", parent)
	local s = seed or 1
	local y = 0
	for _ = 1, count or 3 do
		s = (s * 16807) % 2147483647
		local size = 1.4 + (s % 7) / 10
		local offset = ((s % 5) - 2) / 10
		p(
			m,
			"Box",
			v(size, size * 0.8, size),
			B.off(cf, offset, y + size * 0.4, -offset, (s % 30) - 15),
			Color3.fromRGB(150, 120, 80),
			Enum.Material.Cardboard
		)
		y += size * 0.8
	end
	return m
end

function Props.trashCan(parent: any, cf: any)
	local m = B.model("TrashCan", parent)
	local can = p(
		m,
		"Can",
		v(2, 1.2, 1.2),
		B.off(cf, 0, 1, 0) * CFrame.Angles(0, 0, math.rad(90)),
		C.PlasticGrey,
		nil,
		{ shape = Enum.PartType.Cylinder }
	)
	can.Size = v(2, 1.2, 1.2)
	return m
end

function Props.waterCooler(parent: any, cf: any)
	local m = B.model("WaterCooler", parent)
	p(m, "Body", v(1.3, 3.4, 1.3), B.off(cf, 0, 1.7, 0), C.PlasticBeige)
	local jug = p(
		m,
		"Jug",
		v(1.6, 1, 1),
		B.off(cf, 0, 4.2, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(120, 160, 190),
		Enum.Material.Glass,
		{ shape = Enum.PartType.Cylinder, transparency = 0.4 }
	)
	jug.Size = v(1.6, 1, 1)
	return m
end

function Props.vendingMachine(parent: any, cf: any)
	local m = B.model("VendingMachine", parent)
	p(m, "Body", v(3.2, 6.6, 2.6), B.off(cf, 0, 3.3, 0), Color3.fromRGB(150, 30, 34))
	local front = p(
		m,
		"Front",
		v(2, 4.4, 0.1),
		B.off(cf, -0.4, 4, -1.32),
		Color3.fromRGB(30, 30, 30),
		Enum.Material.Glass,
		{ role = "Detail" }
	)
	cellPanel(front, Enum.NormalId.Front, 5, 6, {
		Color3.fromRGB(200, 60, 40),
		Color3.fromRGB(220, 200, 80),
		Color3.fromRGB(40, 90, 160),
		Color3.fromRGB(230, 230, 230),
	}, { lightInfluence = 0.2, background = Color3.fromRGB(20, 20, 20) })
	local glow = p(
		m,
		"Glow",
		v(1.9, 0.1, 0.1),
		B.off(cf, -0.4, 6.2, -1.32),
		Color3.fromRGB(230, 236, 255),
		Enum.Material.Neon,
		{ role = "Light" }
	)
	B.pointLight(glow, { color = Color3.fromRGB(220, 230, 255), brightness = 0.5, range = 8 })
	return m
end

---------------------------------------------------------------- Broadcast equipment

-- CRT monitor. size: "Small" (13"), "Medium" (19"), "Large" (27"). Screen faces local -Z.
function Props.crt(parent: any, cf: any, zone: string, id: string, opts: { [string]: any }?)
	local o = opts or {}
	local sizes = { Small = v(1.6, 1.4, 1.6), Medium = v(2.2, 1.9, 2.1), Large = v(3.2, 2.6, 2.8) }
	local dims = sizes[o.size or "Medium"]
	local m = B.model("Monitor_" .. id, parent)
	m:AddTag("Monitor")
	m:SetAttribute("Zone", zone)
	m:SetAttribute("MonitorId", id)
	m:SetAttribute("Role", o.role or "General")
	local casing = o.casing or (if o.size == "Small" then C.PlasticBeige else C.PlasticGrey)
	p(m, "Bezel", v(dims.X, dims.Y, 0.35), B.off(cf, 0, dims.Y / 2, -dims.Z / 2 + 0.175), casing)
	p(
		m,
		"Tube",
		v(dims.X * 0.8, dims.Y * 0.8, dims.Z - 0.35),
		B.off(cf, 0, dims.Y / 2, 0.175),
		casing,
		nil,
		{ role = "Detail" }
	)
	local screen = p(
		m,
		"Screen",
		v(dims.X * 0.82, dims.Y * 0.76, 0.06),
		B.off(cf, -dims.X * 0.03, dims.Y / 2 + dims.Y * 0.02, -dims.Z / 2 - 0.02),
		C.Screen,
		Enum.Material.Glass,
		{ role = "Detail", reflectance = 0.06 }
	)
	screen:AddTag("MonitorScreen")
	local glow = B.surfaceLight(screen, {
		face = Enum.NormalId.Front,
		brightness = 0.55,
		range = o.lightRange or 9,
		angle = 120,
		color = Color3.fromRGB(150, 170, 200),
	})
	glow:SetAttribute("BaseBrightness", glow.Brightness)
	glow.Name = "ScreenGlow"
	-- Control strip and power LED.
	local led = p(
		m,
		"PowerLED",
		v(0.08, 0.08, 0.05),
		B.off(cf, dims.X / 2 - 0.25, 0.18, -dims.Z / 2 - 0.02),
		Color3.fromRGB(60, 220, 80),
		Enum.Material.Neon,
		{ role = "Detail" }
	)
	led:SetAttribute("BaseColor", led.Color)
	m.PrimaryPart = screen
	return m
end

function Props.monitorWall(parent: any, cf: any, zone: string, prefix: string, cols: number, rows: number)
	-- Rack frame holding a grid of Medium monitors; the centre-top one is larger (Program).
	local m = B.model("MonitorWall", parent)
	local cellW, cellH = 2.5, 2.2
	local width = cols * cellW + 0.6
	local height = rows * cellH + 0.6
	p(m, "Frame", v(width, height, 0.4), B.off(cf, 0, 2.6 + height / 2, 1.2), C.PlasticBlack, Enum.Material.Metal)
	p(m, "Shelf", v(width, 2.6, 2.6), B.off(cf, 0, 1.3, 0.2), C.PlasticBlack, Enum.Material.Metal)
	local index = 0
	for r = 0, rows - 1 do
		for c = 0, cols - 1 do
			index += 1
			local x = -width / 2 + 0.3 + cellW * (c + 0.5)
			local y = 2.6 + 0.3 + cellH * r
			local role = if r == rows - 1 and c == math.floor(cols / 2) then "Program" else "Wall"
			Props.crt(
				m,
				B.off(cf, x, y, 0),
				zone,
				`{prefix}_{index}`,
				{ size = "Medium", role = role, casing = C.PlasticBlack, lightRange = 7 }
			)
		end
	end
	return m
end

function Props.switcherConsole(parent: any, cf: any, width: number)
	local m = B.model("SwitcherConsole", parent)
	p(m, "Base", v(width, 2.5, 2.6), B.off(cf, 0, 1.25, 0), C.PlasticGrey)
	local top =
		p(m, "Panel", v(width, 0.25, 2.8), B.off(cf, 0, 2.75, -0.1) * CFrame.Angles(math.rad(12), 0, 0), C.PlasticBlack)
	cellPanel(top, Enum.NormalId.Top, math.floor(width * 4), 7, {
		Color3.fromRGB(60, 60, 64),
		Color3.fromRGB(60, 60, 64),
		Color3.fromRGB(180, 40, 30),
		Color3.fromRGB(40, 150, 60),
		Color3.fromRGB(210, 190, 70),
		Color3.fromRGB(200, 200, 196),
	}, { ppu = 24, lightInfluence = 0.3 })
	p(m, "Riser", v(width, 1.2, 0.5), B.off(cf, 0, 3.3, 1.1), C.PlasticGrey)
	local meters =
		p(m, "Meters", v(width - 0.4, 0.8, 0.06), B.off(cf, 0, 3.35, 0.83), C.PlasticBlack, nil, { role = "Detail" })
	cellPanel(
		meters,
		Enum.NormalId.Front,
		math.floor(width * 2),
		2,
		{ Color3.fromRGB(30, 200, 80), Color3.fromRGB(30, 200, 80), Color3.fromRGB(220, 180, 40) },
		{ lightInfluence = 0 }
	)
	return m
end

function Props.rack(parent: any, cf: any, seed: number?, opts: { [string]: any }?)
	local o = opts or {}
	local m = B.model("Rack", parent)
	local h = o.height or 7
	p(m, "Cabinet", v(2.2, h, 3), B.off(cf, 0, h / 2, 0), C.PlasticBlack, Enum.Material.Metal)
	local s = seed or 3
	local y = 0.6
	while y < h - 0.8 do
		s = (s * 48271) % 2147483647
		local units = 0.45 + (s % 4) * 0.35
		local unit = p(
			m,
			"Unit",
			v(1.9, units - 0.05, 0.08),
			B.off(cf, 0, y + units / 2, -1.52),
			if s % 3 == 0 then C.PlasticGrey else C.MetalDark,
			Enum.Material.Metal,
			{ role = "Detail" }
		)
		if s % 2 == 0 then
			cellPanel(unit, Enum.NormalId.Front, 10, 1, {
				Color3.fromRGB(30, 30, 30),
				Color3.fromRGB(40, 200, 80),
				Color3.fromRGB(220, 160, 40),
				Color3.fromRGB(30, 30, 30),
			}, { seed = s, lightInfluence = 0, ppu = 30 })
		end
		y += units
	end
	return m
end

function Props.vtrDeck(parent: any, cf: any, label: string)
	local m = B.model("VTR", parent)
	local body = p(m, "Body", v(2.4, 0.8, 2), B.off(cf, 0, 0.4, 0), C.PlasticGrey, Enum.Material.Metal)
	p(m, "Slot", v(1.4, 0.12, 0.05), B.off(cf, -0.3, 0.55, -1.01), C.PlasticBlack, nil, { role = "Detail" })
	local lcd = p(
		m,
		"Counter",
		v(0.7, 0.25, 0.05),
		B.off(cf, 0.7, 0.55, -1.01),
		Color3.fromRGB(20, 40, 30),
		nil,
		{ role = "Detail" }
	)
	B.label(
		lcd,
		Enum.NormalId.Front,
		"00:00:00",
		{ color = Color3.fromRGB(80, 255, 140), font = Enum.Font.Code, lightInfluence = 0, name = "CounterText" }
	)
	local tag = p(m, "Tag", v(1.2, 0.18, 0.04), B.off(cf, -0.3, 0.25, -1.01), C.Paper, nil, { role = "Detail" })
	B.label(tag, Enum.NormalId.Front, label, { font = Enum.Font.Code })
	return m, body
end

-- Tape shelving: spines drawn on a surface, a few loose tapes as real parts.
function Props.tapeShelf(parent: any, cf: any, w: number?, seed: number?, labelText: string?)
	local width = w or 6
	local height = 7.4
	local m = B.model("TapeShelf", parent)
	p(m, "SideL", v(0.15, height, 1.6), B.off(cf, -width / 2 + 0.075, height / 2, 0), C.Metal, Enum.Material.Metal)
	p(m, "SideR", v(0.15, height, 1.6), B.off(cf, width / 2 - 0.075, height / 2, 0), C.Metal, Enum.Material.Metal)
	for i = 0, 5 do
		local y = 0.3 + i * 1.35
		p(m, "Shelf", v(width - 0.3, 0.1, 1.6), B.off(cf, 0, y, 0), C.Metal, Enum.Material.Metal)
		if i < 5 and ((seed or 1) + i) % 7 ~= 0 then
			local spines = p(
				m,
				"Spines",
				v(width - 0.5, 1, 1.1),
				B.off(cf, 0, y + 0.56, 0.1),
				C.PlasticBlack,
				nil,
				{ role = "Detail" }
			)
			cellPanel(spines, Enum.NormalId.Front, math.floor(width * 5.5), 1, {
				Color3.fromRGB(230, 226, 210),
				Color3.fromRGB(220, 214, 190),
				Color3.fromRGB(28, 28, 30),
				Color3.fromRGB(200, 60, 50),
				Color3.fromRGB(60, 90, 160),
			}, { seed = (seed or 1) * 13 + i, ppu = 26 })
		end
	end
	if labelText then
		local tag =
			p(m, "Label", v(2.2, 0.45, 0.04), B.off(cf, 0, height - 0.4, -0.82), C.Paper, nil, { role = "Detail" })
		B.label(tag, Enum.NormalId.Front, labelText, { font = Enum.Font.Code })
	end
	return m
end

function Props.breakerPanel(parent: any, cf: any, name: string)
	local m = B.model("BreakerPanel_" .. name, parent)
	local box = p(m, "Box", v(3, 4.4, 0.7), B.off(cf, 0, 4.2, 0), C.Metal, Enum.Material.Metal)
	local door =
		p(m, "Door", v(2.8, 4.2, 0.08), B.off(cf, 0, 4.2, -0.39), C.WallGrey, Enum.Material.Metal, { role = "Detail" })
	B.label(
		door,
		Enum.NormalId.Front,
		"PANEL " .. name .. "\n\nDANGER\n480V",
		{ color = Color3.fromRGB(150, 20, 20), font = Enum.Font.Arcade, padding = 0.18 }
	)
	local sticker =
		p(m, "OrderSticker", v(1.1, 0.7, 0.03), B.off(cf, 0.6, 2.6, -0.44), C.Paper, nil, { role = "Detail" })
	sticker:SetAttribute("OrderSticker", name)
	B.label(sticker, Enum.NormalId.Front, "RESTORE ORDER:\n—", { font = Enum.Font.Code, name = "OrderText" })
	p(m, "Conduit", v(0.5, 8, 0.5), B.off(cf, -1, 10.4, 0.1), C.Metal, Enum.Material.Metal, { role = "Detail" })
	return m, box
end

function Props.tunerCabinet(parent: any, cf: any)
	local m = B.model("ExciterTuner", parent)
	local body = p(m, "Body", v(3.4, 5, 2.4), B.off(cf, 0, 2.5, 0), Color3.fromRGB(90, 100, 96), Enum.Material.Metal)
	local face = p(m, "Face", v(3.1, 2.2, 0.06), B.off(cf, 0, 3.6, -1.22), C.PlasticBlack, nil, { role = "Detail" })
	B.label(face, Enum.NormalId.Front, "EXCITER  55.25 MHz", {
		color = Color3.fromRGB(255, 170, 60),
		font = Enum.Font.Code,
		lightInfluence = 0,
		name = "FreqReadout",
		alignY = Enum.TextYAlignment.Top,
	})
	local dial = p(
		m,
		"Dial",
		v(0.35, 1.3, 1.3),
		B.off(cf, 0, 1.8, -1.3) * CFrame.Angles(0, math.rad(90), 0),
		C.PlasticBlack,
		nil,
		{ shape = Enum.PartType.Cylinder, role = "Detail" }
	)
	dial.Size = v(0.35, 1.3, 1.3)
	dial:AddTag("TunerDial")
	local sticker = p(m, "Sticker", v(1.6, 0.6, 0.03), B.off(cf, -0.6, 4.9, -1.23), C.Paper, nil, { role = "Detail" })
	B.label(sticker, Enum.NormalId.Front, "CARRIER 55.25\n— G.M.", { font = Enum.Font.Code })
	return m, body
end

function Props.transmitterCabinet(parent: any, cf: any, index: number)
	local m = B.model("Transmitter_" .. index, parent)
	p(m, "Cabinet", v(4, 8.5, 3.4), B.off(cf, 0, 4.25, 0), Color3.fromRGB(70, 80, 76), Enum.Material.Metal)
	local window = p(
		m,
		"TubeWindow",
		v(2.2, 1.6, 0.06),
		B.off(cf, 0, 5.6, -1.72),
		Color3.fromRGB(255, 140, 60),
		Enum.Material.Neon,
		{ role = "Light", transparency = 0.35 }
	)
	window:SetAttribute("BaseColor", window.Color)
	window:AddTag("TransmitterGlow")
	B.pointLight(window, { color = Color3.fromRGB(255, 150, 80), brightness = 0.7, range = 10 })
	local vents = p(
		m,
		"Vents",
		v(3.4, 1.6, 0.05),
		B.off(cf, 0, 1.4, -1.72),
		C.MetalDark,
		Enum.Material.Metal,
		{ role = "Detail" }
	)
	cellPanel(vents, Enum.NormalId.Front, 1, 8, { C.PlasticBlack }, { background = C.MetalDark })
	local warn = p(m, "Warning", v(1.6, 0.9, 0.04), B.off(cf, 0, 7.5, -1.72), C.SafetyYellow, nil, { role = "Detail" })
	B.label(warn, Enum.NormalId.Front, "⚠ HIGH VOLTAGE\nRF HAZARD", { font = Enum.Font.Arcade })
	local meters = p(m, "Meters", v(3, 0.8, 0.05), B.off(cf, 0, 3.6, -1.72), C.PlasticBlack, nil, { role = "Detail" })
	cellPanel(meters, Enum.NormalId.Front, 4, 1, { Color3.fromRGB(230, 220, 190) }, { lightInfluence = 0.2 })
	return m
end

function Props.studioCamera(parent: any, cf: any, label: string)
	local m = B.model("StudioCamera", parent)
	p(m, "Base", v(2.6, 0.5, 2.6), B.off(cf, 0, 0.25, 0), C.MetalDark, Enum.Material.Metal)
	for i = 0, 2 do
		local a = math.rad(i * 120)
		p(
			m,
			"Caster",
			v(0.4, 0.4, 0.4),
			B.off(cf, math.cos(a) * 1.1, 0.2, math.sin(a) * 1.1),
			C.PlasticBlack,
			nil,
			{ role = "Detail" }
		)
	end
	p(m, "Column", v(0.6, 3.7, 0.6), B.off(cf, 0, 2.35, 0), C.Metal, Enum.Material.Metal)
	p(m, "Head", v(1.6, 0.4, 1.6), B.off(cf, 0, 4.4, 0), C.MetalDark, Enum.Material.Metal)
	p(m, "Body", v(1.3, 1.5, 2.6), B.off(cf, 0, 5.35, 0), Color3.fromRGB(196, 196, 190))
	local lens = p(
		m,
		"Lens",
		v(1, 1, 1.4),
		B.off(cf, 0, 5.3, -1.9) * CFrame.Angles(math.rad(90), 0, 0),
		C.PlasticBlack,
		nil,
		{ shape = Enum.PartType.Cylinder }
	)
	lens.Size = v(1.4, 1, 1)
	lens.CFrame = B.off(cf, 0, 5.3, -1.9) * CFrame.Angles(0, math.rad(90), 0)
	p(m, "Viewfinder", v(1, 0.8, 0.8), B.off(cf, 0, 6.4, 0.7), C.PlasticBlack)
	local tally = p(
		m,
		"Tally",
		v(0.3, 0.2, 0.1),
		B.off(cf, 0, 6.15, -1.32),
		Color3.fromRGB(90, 10, 10),
		Enum.Material.Neon,
		{ role = "Detail" }
	)
	tally:AddTag("TallyLight")
	tally:SetAttribute("BaseColor", tally.Color)
	local tag = p(m, "Number", v(0.6, 0.6, 0.04), B.off(cf, 0.67, 5.4, 0, 90), C.PlasticBlack, nil, { role = "Detail" })
	B.label(tag, Enum.NormalId.Front, label, { color = Color3.fromRGB(240, 240, 230), font = Enum.Font.Arcade })
	p(
		m,
		"PanBar",
		v(0.15, 0.15, 2.4),
		B.off(cf, 0.5, 4.9, 1.8) * CFrame.Angles(math.rad(-15), 0, 0),
		C.Metal,
		Enum.Material.Metal,
		{ role = "Detail" }
	)
	return m
end

-- The Night Desk set: curved anchor desk built from angled segments, logo front.
function Props.newsDesk(parent: any, cf: any, opts: { [string]: any }?)
	local o = opts or {}
	local m = B.model("NewsDesk", parent)
	local wood = o.color or Color3.fromRGB(60, 42, 34)
	local accent = o.accent or Color3.fromRGB(150, 120, 70)
	local segments = 5
	local radius = 6
	for i = 0, segments - 1 do
		local a = math.rad(-40 + i * 20)
		local seg = B.off(cf, math.sin(a) * radius, 0, -math.cos(a) * radius + radius - 1.2) * CFrame.Angles(0, -a, 0)
		p(m, "Front", v(2.2, 3, 0.4), seg * CFrame.new(0, 1.5, 0), wood, Enum.Material.Wood)
		p(m, "Top", v(2.3, 0.2, 2.2), seg * CFrame.new(0, 3.1, 0.9), Color3.fromRGB(40, 36, 34), Enum.Material.Marble)
		p(
			m,
			"Stripe",
			v(2.2, 0.15, 0.05),
			seg * CFrame.new(0, 2.6, -0.23),
			accent,
			Enum.Material.Metal,
			{ role = "Detail" }
		)
	end
	local logo =
		p(m, "Logo", v(3, 1.2, 0.05), B.off(cf, 0, 1.6, -1.45), Color3.fromRGB(20, 20, 24), nil, { role = "Detail" })
	B.label(
		logo,
		Enum.NormalId.Front,
		o.logo or "NIGHT DESK",
		{ color = accent, font = Enum.Font.Antique, lightInfluence = 0.5 }
	)
	local chair = Props.chair(m, B.off(cf, 0, 0, 2.2, 180), Color3.fromRGB(30, 30, 34))
	chair.Name = "AnchorChair"
	-- Desk props: papers, mug, mic.
	p(m, "Papers", v(1.2, 0.04, 1.6), B.off(cf, -0.6, 3.22, 0.7, 8), C.Paper, nil, { role = "Detail" })
	p(m, "Mug", v(0.35, 0.45, 0.35), B.off(cf, 1.6, 3.42, 0.6), Color3.fromRGB(180, 40, 30), nil, { role = "Detail" })
	p(m, "MicBase", v(0.3, 0.6, 0.3), B.off(cf, 0.5, 3.5, 0.3), C.PlasticBlack, nil, { role = "Detail" })
	return m, chair
end

function Props.backdrop(parent: any, cf: any, width: number, height: number, title: string, opts: { [string]: any }?)
	local o = opts or {}
	local m = B.model("Backdrop", parent)
	local flat = p(
		m,
		"Flat",
		v(width, height, 0.3),
		B.off(cf, 0, height / 2, 0),
		o.color or Color3.fromRGB(20, 28, 54),
		Enum.Material.Fabric
	)
	-- City skyline at night painted on the flat.
	local gui = B.Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 16
	gui.LightInfluence = 0.8
	local bg = B.Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = o.color or Color3.fromRGB(20, 28, 54)
	bg.BorderSizePixel = 0
	bg.Parent = gui
	local grad = B.Instance.new("UIGradient")
	grad.Rotation = 90
	grad.Color = roblox.ColorSequence.new(Color3.fromRGB(40, 56, 100), Color3.fromRGB(10, 12, 24))
	grad.Parent = bg
	local s = 7
	local x = 0
	while x < 1 do
		s = (s * 48271) % 2147483647
		local w = 0.03 + (s % 5) / 100
		local h = 0.18 + (s % 17) / 60
		local b = B.Instance.new("Frame")
		b.BorderSizePixel = 0
		b.BackgroundColor3 = Color3.fromRGB(8, 10, 18)
		b.Position = UDim2.fromScale(x, 1 - h)
		b.Size = UDim2.fromScale(w, h)
		b.Parent = bg
		-- lit windows
		for k = 1, 3 do
			local wnd = B.Instance.new("Frame")
			wnd.BorderSizePixel = 0
			wnd.BackgroundColor3 = Color3.fromRGB(230, 200, 120)
			wnd.Size = UDim2.fromScale(0.18, 0.03)
			wnd.Position = UDim2.fromScale(0.2 + ((s + k * 31) % 50) / 100, 0.1 + ((s + k * 17) % 70) / 100)
			wnd.Parent = b
		end
		x += w + 0.004
	end
	local text = B.Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(0.8, 0.22)
	text.Position = UDim2.fromScale(0.1, 0.12)
	text.Text = title
	text.Font = Enum.Font.Antique
	text.TextScaled = true
	text.TextColor3 = o.textColor or Color3.fromRGB(220, 196, 130)
	text.Parent = bg
	gui.Parent = flat
	return m
end

function Props.wallClock(parent: any, cf: any, zone: string)
	local m = B.model("WallClock", parent)
	m:AddTag("WallClock")
	m:SetAttribute("Zone", zone)
	local face = p(
		m,
		"Face",
		v(0.2, 1.8, 1.8),
		cf * CFrame.Angles(0, math.rad(90), 0),
		C.Paper,
		nil,
		{ shape = Enum.PartType.Cylinder, role = "Detail" }
	)
	face.Size = v(0.2, 1.8, 1.8)
	local rim = p(
		m,
		"Rim",
		v(0.15, 2, 2),
		cf * CFrame.new(0, 0, 0.05) * CFrame.Angles(0, math.rad(90), 0),
		C.PlasticBlack,
		nil,
		{ shape = Enum.PartType.Cylinder, role = "Detail" }
	)
	rim.Size = v(0.15, 2, 2)
	-- Hands are thin parts the client rotates to show the station clock (stuck at 02:16 when stalled).
	local hour =
		p(m, "HourHand", v(0.08, 0.55, 0.04), cf * CFrame.new(0, 0.22, -0.13), C.PlasticBlack, nil, { role = "Detail" })
	local minute = p(
		m,
		"MinuteHand",
		v(0.06, 0.8, 0.04),
		cf * CFrame.new(0, 0.35, -0.15),
		C.PlasticBlack,
		nil,
		{ role = "Detail" }
	)
	hour:SetAttribute("Pivot", cf * CFrame.new(0, 0, -0.13))
	minute:SetAttribute("Pivot", cf * CFrame.new(0, 0, -0.15))
	return m
end

function Props.phone(parent: any, cf: any)
	local m = B.model("Phone", parent)
	local body = p(m, "Body", v(0.9, 0.3, 1), B.off(cf, 0, 0.15, 0), C.PlasticBeige)
	p(m, "Handset", v(1.1, 0.2, 0.3), B.off(cf, 0, 0.38, -0.2), C.PlasticBeige, nil, { role = "Detail" })
	local lamp = p(
		m,
		"RingLamp",
		v(0.12, 0.06, 0.12),
		B.off(cf, 0.32, 0.32, 0.3),
		Color3.fromRGB(80, 20, 20),
		Enum.Material.Neon,
		{ role = "Detail" }
	)
	lamp:SetAttribute("BaseColor", lamp.Color)
	return m, body
end

function Props.locker(parent: any, cf: any, name: string, color: any?)
	local m = B.model("Locker_" .. name, parent)
	local body =
		p(m, "Body", v(1.8, 6.6, 1.8), B.off(cf, 0, 3.3, 0), color or Color3.fromRGB(70, 96, 110), Enum.Material.Metal)
	local door = p(
		m,
		"Door",
		v(1.6, 6.2, 0.08),
		B.off(cf, 0, 3.4, -0.93),
		color or Color3.fromRGB(70, 96, 110),
		Enum.Material.Metal,
		{ role = "Detail" }
	)
	cellPanel(
		door,
		Enum.NormalId.Front,
		1,
		6,
		{ Color3.fromRGB(30, 30, 30) },
		{ background = color or Color3.fromRGB(70, 96, 110), name = "Vents" }
	)
	local tag = p(m, "NameTag", v(1, 0.3, 0.03), B.off(cf, 0, 5.6, -0.99), C.Paper, nil, { role = "Detail" })
	B.label(tag, Enum.NormalId.Front, name, { font = Enum.Font.Code })
	return m, body
end

function Props.workbench(parent: any, cf: any, w: number?)
	local width = w or 7
	local m = B.model("Workbench", parent)
	p(m, "Top", v(width, 0.4, 2.8), B.off(cf, 0, 3, 0), C.WoodLight, Enum.Material.WoodPlanks)
	for _, sx in { -1, 1 } do
		p(m, "Leg", v(0.4, 2.8, 2.4), B.off(cf, sx * (width / 2 - 0.4), 1.4, 0), C.MetalDark, Enum.Material.Metal)
	end
	p(m, "Shelf", v(width - 1, 0.2, 2.4), B.off(cf, 0, 0.8, 0), C.MetalDark, Enum.Material.Metal, { role = "Detail" })
	local board =
		p(m, "Pegboard", v(width, 3.5, 0.15), B.off(cf, 0, 5.2, 1.35), Color3.fromRGB(150, 120, 80), Enum.Material.Wood)
	cellPanel(
		board,
		Enum.NormalId.Front,
		9,
		4,
		{ Color3.fromRGB(150, 120, 80), C.Red, C.MetalDark, C.SafetyYellow, C.Metal },
		{ background = Color3.fromRGB(150, 120, 80), seed = 4 }
	)
	p(
		m,
		"Vise",
		v(0.8, 0.6, 0.6),
		B.off(cf, width / 2 - 1, 3.5, -0.8),
		C.FabricBlue,
		Enum.Material.Metal,
		{ role = "Detail" }
	)
	p(m, "SolderStation", v(1, 0.5, 0.8), B.off(cf, -1.2, 3.45, -0.3), C.PlasticGrey, nil, { role = "Detail" })
	return m
end

function Props.pipe(parent: any, from: any, to: any, radius: number, color: any?)
	local delta = to - from
	local length = delta.Magnitude
	local mid = from + delta / 2
	local part = B.part({
		parent = parent,
		name = "Pipe",
		role = "Detail",
		size = v(length, radius * 2, radius * 2),
		cf = B.lookAt(mid, to) * CFrame.Angles(0, math.rad(90), 0),
		color = color or C.Metal,
		material = Enum.Material.Metal,
		shape = Enum.PartType.Cylinder,
	})
	return part
end

function Props.cableTray(parent: any, from: any, to: any)
	local delta = to - from
	local length = delta.Magnitude
	local frame = B.lookAt(from + delta / 2, to)
	local m = B.model("CableTray", parent)
	p(m, "Tray", v(2, 0.1, length), frame, C.Metal, Enum.Material.Metal, { role = "Detail" })
	p(
		m,
		"LipL",
		v(0.08, 0.4, length),
		frame * CFrame.new(-0.96, 0.2, 0),
		C.Metal,
		Enum.Material.Metal,
		{ role = "Detail" }
	)
	p(
		m,
		"LipR",
		v(0.08, 0.4, length),
		frame * CFrame.new(0.96, 0.2, 0),
		C.Metal,
		Enum.Material.Metal,
		{ role = "Detail" }
	)
	p(
		m,
		"CablesA",
		v(0.9, 0.3, length),
		frame * CFrame.new(-0.35, 0.2, 0),
		C.PlasticBlack,
		Enum.Material.Rubber,
		{ role = "Detail" }
	)
	p(
		m,
		"CablesB",
		v(0.6, 0.25, length),
		frame * CFrame.new(0.45, 0.18, 0),
		Color3.fromRGB(70, 70, 120),
		Enum.Material.Rubber,
		{ role = "Detail" }
	)
	return m
end

function Props.poster(parent: any, cf: any, w: number, h: number, text: string, opts: { [string]: any }?)
	local o = opts or {}
	local part = B.part({
		parent = parent,
		name = o.name or "Poster",
		role = "Detail",
		size = v(w, h, 0.04),
		cf = cf,
		color = o.background or C.Paper,
		material = Enum.Material.SmoothPlastic,
	})
	B.label(part, Enum.NormalId.Front, text, {
		color = o.color,
		font = o.font or Enum.Font.Code,
		padding = o.padding or 0.1,
		background = o.background,
		alignY = o.alignY,
	})
	return part
end

function Props.framedPhoto(parent: any, cf: any, w: number, h: number, caption: string, tint: any?)
	local m = B.model("FramedPhoto", parent)
	p(m, "Frame", v(w, h, 0.12), cf, Color3.fromRGB(60, 44, 30), Enum.Material.Wood, { role = "Detail" })
	local photo = p(
		m,
		"Photo",
		v(w - 0.3, h - 0.5, 0.04),
		cf * CFrame.new(0, 0.1, -0.07),
		tint or Color3.fromRGB(110, 100, 86),
		nil,
		{ role = "Detail" }
	)
	-- Silhouettes of a crew in front of the building (just shapes; tinted sepia).
	local gui = B.Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	local bg = B.Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = tint or Color3.fromRGB(150, 132, 104)
	bg.BorderSizePixel = 0
	bg.Parent = gui
	for i = 0, 4 do
		local fig = B.Instance.new("Frame")
		fig.BorderSizePixel = 0
		fig.BackgroundColor3 = Color3.fromRGB(60, 50, 40)
		fig.Size = UDim2.fromScale(0.1, 0.45 + (i % 2) * 0.05)
		fig.Position = UDim2.fromScale(0.12 + i * 0.16, 0.5 - (i % 2) * 0.05)
		fig.Parent = bg
		local head = B.Instance.new("Frame")
		head.BorderSizePixel = 0
		head.BackgroundColor3 = Color3.fromRGB(60, 50, 40)
		head.Size = UDim2.fromScale(0.07, 0.1)
		head.Position = UDim2.fromScale(0.135 + i * 0.16, 0.37 - (i % 2) * 0.05)
		head.Parent = bg
	end
	gui.Parent = photo
	local cap = p(
		m,
		"Caption",
		v(w - 0.3, 0.3, 0.04),
		cf * CFrame.new(0, -h / 2 + 0.2, -0.07),
		C.Paper,
		nil,
		{ role = "Detail" }
	)
	B.label(cap, Enum.NormalId.Front, caption, { font = Enum.Font.Garamond })
	return m
end

function Props.extinguisher(parent: any, cf: any)
	local m = B.model("Extinguisher", parent)
	local body = p(
		m,
		"Body",
		v(1.6, 0.6, 0.6),
		B.off(cf, 0, 3.6, 0) * CFrame.Angles(0, 0, math.rad(90)),
		C.Red,
		Enum.Material.SmoothPlastic,
		{ shape = Enum.PartType.Cylinder }
	)
	body.Size = v(1.6, 0.6, 0.6)
	p(m, "Valve", v(0.25, 0.3, 0.25), B.off(cf, 0, 4.5, 0), C.PlasticBlack, nil, { role = "Detail" })
	return m
end

function Props.generator(parent: any, cf: any)
	local m = B.model("Generator", parent)
	p(m, "Skid", v(12, 0.6, 5), B.off(cf, 0, 0.3, 0), C.MetalDark, Enum.Material.DiamondPlate)
	p(m, "Engine", v(7, 4.5, 4), B.off(cf, -1.8, 2.85, 0), Color3.fromRGB(70, 100, 70), Enum.Material.Metal)
	p(m, "Alternator", v(3.4, 3.8, 3.6), B.off(cf, 3.6, 2.5, 0), Color3.fromRGB(70, 100, 70), Enum.Material.Metal)
	p(m, "Radiator", v(1, 4.6, 4.2), B.off(cf, -5.6, 2.9, 0), C.MetalDark, Enum.Material.Metal)
	local panel =
		p(m, "ControlPanel", v(1.8, 1.6, 0.3), B.off(cf, 3.6, 5.2, -1.4), C.PlasticGrey, nil, { role = "Detail" })
	cellPanel(
		panel,
		Enum.NormalId.Front,
		4,
		3,
		{ Color3.fromRGB(230, 220, 190), Color3.fromRGB(40, 200, 80), Color3.fromRGB(200, 40, 30) },
		{ lightInfluence = 0.2 }
	)
	Props.pipe(
		m,
		Vector3.new(0, 0, 0) + (cf * CFrame.new(-3, 5.1, 0)).Position,
		(cf * CFrame.new(-3, 10.5, 0)).Position,
		0.45,
		C.MetalRust
	)
	return m
end

function Props.boiler(parent: any, cf: any)
	local m = B.model("Boiler", parent)
	local tank = p(
		m,
		"Tank",
		v(8, 4.4, 4.4),
		B.off(cf, 0, 3, 0) * CFrame.Angles(0, math.rad(90), 0),
		C.MetalRust,
		Enum.Material.CorrodedMetal,
		{ shape = Enum.PartType.Cylinder }
	)
	tank.Size = v(8, 4.4, 4.4)
	tank.CFrame = B.off(cf, 0, 3, 0)
	p(m, "Base", v(3.4, 1, 8.4), B.off(cf, 0, 0.5, 0), C.Concrete, Enum.Material.Concrete)
	p(m, "Gauge", v(0.1, 0.8, 0.8), B.off(cf, -2.25, 4.3, -2), C.Paper, nil, { role = "Detail" })
	Props.pipe(m, (cf * CFrame.new(0, 5.2, 3)).Position, (cf * CFrame.new(0, 10.4, 3)).Position, 0.5, C.MetalRust)
	return m
end

function Props.sedan(parent: any, cf: any, color: any)
	local m = B.model("Sedan", parent)
	p(m, "Body", v(5.6, 1.6, 12), B.off(cf, 0, 1.6, 0), color, Enum.Material.SmoothPlastic, { reflectance = 0.05 })
	p(m, "Cabin", v(5, 1.5, 6), B.off(cf, 0, 3.15, 0.6), color, Enum.Material.SmoothPlastic)
	p(
		m,
		"Windshield",
		v(4.8, 1.4, 0.1),
		B.off(cf, 0, 3.1, -2.45) * CFrame.Angles(math.rad(-25), 0, 0),
		C.Glass,
		Enum.Material.Glass,
		{ role = "Detail", transparency = 0.3 }
	)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local wheel = p(
				m,
				"Wheel",
				v(0.8, 2, 2),
				B.off(cf, sx * 2.7, 0.9, sz * 3.8),
				C.PlasticBlack,
				Enum.Material.Rubber,
				{ shape = Enum.PartType.Cylinder }
			)
			wheel.Size = v(0.8, 1.9, 1.9)
		end
	end
	return m
end

function Props.van(parent: any, cf: any)
	local m = B.model("CrewVan", parent)
	local white = Color3.fromRGB(206, 204, 196)
	p(m, "Body", v(6.4, 5.4, 15), B.off(cf, 0, 3.6, 0.6), white)
	p(m, "Hood", v(6.2, 2.2, 3), B.off(cf, 0, 2.3, -8.3), white)
	p(
		m,
		"Windshield",
		v(6, 1.8, 0.1),
		B.off(cf, 0, 4.6, -7) * CFrame.Angles(math.rad(-20), 0, 0),
		C.Glass,
		Enum.Material.Glass,
		{ role = "Detail", transparency = 0.3 }
	)
	local livery = p(m, "Livery", v(0.05, 2, 9), B.off(cf, 3.23, 3.8, 1.5), white, nil, { role = "Detail" })
	B.label(
		livery,
		Enum.NormalId.Right,
		"KZRO  CHANNEL 0",
		{ color = Color3.fromRGB(150, 30, 30), font = Enum.Font.Antique }
	)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local wheel = p(
				m,
				"Wheel",
				v(0.9, 2.2, 2.2),
				B.off(cf, sx * 3.1, 1.1, sz * 5.2 - 1),
				C.PlasticBlack,
				Enum.Material.Rubber,
				{ shape = Enum.PartType.Cylinder }
			)
			wheel.Size = v(0.9, 2.2, 2.2)
		end
	end
	local headlight = p(
		m,
		"Headlight",
		v(1, 0.5, 0.1),
		B.off(cf, 2.2, 2.6, -9.82),
		Color3.fromRGB(255, 240, 200),
		Enum.Material.Neon,
		{ role = "Light" }
	)
	B.spotLight(
		headlight,
		{ face = Enum.NormalId.Front, brightness = 1.2, range = 28, angle = 50, color = Color3.fromRGB(255, 236, 200) }
	)
	return m
end

function Props.fence(parent: any, from: any, to: any)
	local m = B.model("Fence", parent)
	local delta = to - from
	local length = delta.Magnitude
	local frame = B.lookAt(from + delta / 2, to)
	local mesh = p(
		m,
		"Mesh",
		v(0.1, 7, length),
		frame * CFrame.new(0, 3.5, 0),
		C.Metal,
		Enum.Material.Metal,
		{ transparency = 0.55 }
	)
	mesh:AddTag("Boundary")
	local posts = math.floor(length / 8)
	for i = 0, posts do
		p(
			m,
			"Post",
			v(0.3, 7.6, 0.3),
			frame * CFrame.new(0, 3.8, -length / 2 + i * (length / math.max(1, posts))),
			C.MetalDark,
			Enum.Material.Metal,
			{ role = "Detail" }
		)
	end
	p(
		m,
		"Wire",
		v(0.15, 0.15, length),
		frame * CFrame.new(0, 7.4, 0),
		C.MetalDark,
		Enum.Material.Metal,
		{ role = "Detail" }
	)
	-- Invisible barrier above the fence so nobody walks out of the night.
	B.part({
		parent = m,
		name = "Barrier",
		role = "Structure",
		size = v(0.5, 40, length),
		cf = frame * CFrame.new(0, 20, 0),
		transparency = 1,
		castShadow = false,
		tags = { "Boundary" },
	})
	return m
end

function Props.mast(parent: any, cf: any, height: number)
	local m = B.model("AntennaMast", parent)
	local spread = 3
	for i = 0, 3 do
		local a = math.rad(45 + i * 90)
		local x, z = math.cos(a) * spread, math.sin(a) * spread
		p(m, "Leg", v(0.5, height, 0.5), B.off(cf, x, height / 2, z), Color3.fromRGB(150, 60, 50), Enum.Material.Metal)
	end
	local y = 6
	local flip = 1
	while y < height - 4 do
		for i = 0, 3 do
			local a = math.rad(i * 90)
			local x, z = math.cos(a) * spread * 0.7, math.sin(a) * spread * 0.7
			p(
				m,
				"Brace",
				v(0.2, 0.2, spread * 1.5),
				B.off(cf, x, y, z) * CFrame.Angles(0, -a + math.rad(90), 0) * CFrame.Angles(math.rad(flip * 35), 0, 0),
				if math.floor(y / 6) % 2 == 0 then Color3.fromRGB(150, 60, 50) else Color3.fromRGB(200, 196, 190),
				Enum.Material.Metal,
				{ role = "Detail" }
			)
		end
		flip = -flip
		y += 6
	end
	for _, h in { height * 0.5, height } do
		local beacon = p(
			m,
			"Beacon",
			v(0.9, 0.9, 0.9),
			B.off(cf, 0, h + 0.5, 0),
			Color3.fromRGB(255, 30, 20),
			Enum.Material.Neon,
			{ role = "Light", shape = Enum.PartType.Ball }
		)
		beacon:AddTag("Beacon")
		beacon:SetAttribute("BaseColor", beacon.Color)
		B.pointLight(beacon, { color = Color3.fromRGB(255, 40, 30), brightness = 2, range = 30 })
	end
	p(m, "Base", v(8, 1, 8), B.off(cf, 0, 0.5, 0), C.Concrete, Enum.Material.Concrete)
	return m
end

return Props
