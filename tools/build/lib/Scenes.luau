--[[
	Small sets rendered inside ViewportFrames for tape footage and impossible broadcasts.
	ViewportFrames do not render dynamic lights or SurfaceGuis, so these sets use emissive (Neon)
	parts for screens and lamps, and each scene declares its own viewport lighting as attributes.
	Every scene has a "Cam" marker (viewport camera) and optionally an "AnchorMark".
]]

local B = require("./B")
local roblox = require("@lune/roblox")

local Vector3, CFrame, Color3, Enum = B.Vector3, B.CFrame, B.Color3, B.Enum
local C = B.Colors

local Scenes = {}

local function p(parent: any, name: string, size: any, cf: any, color: any, material: any?)
	local part = roblox.Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cf
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function scene(parent: any, name: string, ambient: any, lightColor: any, lightDir: any)
	local m = roblox.Instance.new("Model")
	m.Name = name
	m:SetAttribute("Ambient", ambient)
	m:SetAttribute("LightColor", lightColor)
	m:SetAttribute("LightDirection", lightDir)
	m.Parent = parent
	return m
end

local function marker(parent: any, name: string, cf: any)
	local part = p(parent, name, Vector3.new(0.2, 0.2, 0.2), cf, Color3.new(1, 1, 1))
	part.Transparency = 1
	return part
end

-- A person in old footage: readable silhouette, no face.
local function figure(parent: any, cf: any, shirt: any, pose: string?)
	local m = roblox.Instance.new("Model")
	m.Name = "Figure"
	m.Parent = parent
	p(m, "Legs", Vector3.new(1.2, 2.6, 0.7), cf * CFrame.new(0, 1.3, 0), Color3.fromRGB(40, 40, 50))
	p(m, "Torso", Vector3.new(1.6, 2.1, 0.8), cf * CFrame.new(0, 3.65, 0), shirt)
	local head = p(m, "Head", Vector3.new(0.9, 1, 0.9), cf * CFrame.new(0, 5.25, 0), C.Skin)
	local mesh = roblox.Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Head
	mesh.Parent = head
	local armAngle = if pose == "Wave" then -150 else 0
	p(m, "ArmL", Vector3.new(0.45, 2, 0.5), cf * CFrame.new(-1.05, 3.6, 0), shirt)
	p(
		m,
		"ArmR",
		Vector3.new(0.45, 2, 0.5),
		cf * CFrame.new(1.05, 4.4, 0) * CFrame.Angles(math.rad(armAngle), 0, 0) * CFrame.new(0, -0.8, 0),
		shirt
	)
	return m
end

local function newsSet(m: any, deskColor: any, backdropColor: any, accent: any)
	p(m, "Floor", Vector3.new(30, 0.4, 22), CFrame.new(0, -0.2, 0), Color3.fromRGB(26, 24, 28), Enum.Material.Carpet)
	p(m, "Backdrop", Vector3.new(26, 12, 0.4), CFrame.new(0, 6, 7), backdropColor, Enum.Material.Fabric)
	p(m, "LogoBand", Vector3.new(12, 1.4, 0.2), CFrame.new(0, 8.6, 6.75), accent, Enum.Material.Neon)
	for i = 0, 5 do
		p(
			m,
			"Skyline",
			Vector3.new(1.6 + (i % 3) * 0.6, 2 + (i * 7 % 5), 0.2),
			CFrame.new(-10 + i * 4, 2 + (i * 7 % 5) / 2, 6.75),
			Color3.fromRGB(10, 12, 20)
		)
		p(
			m,
			"Window",
			Vector3.new(0.3, 0.3, 0.1),
			CFrame.new(-10 + i * 4, 2.5 + (i % 3), 6.6),
			Color3.fromRGB(230, 200, 120),
			Enum.Material.Neon
		)
	end
	-- Curved desk from segments.
	for i = 0, 4 do
		local a = math.rad(-40 + i * 20)
		local seg = CFrame.new(math.sin(a) * 6, 0, -math.cos(a) * 6 + 6.2 - 3) * CFrame.Angles(0, -a, 0)
		p(m, "DeskFront", Vector3.new(2.2, 3, 0.4), seg * CFrame.new(0, 1.5, 0), deskColor, Enum.Material.Wood)
		p(
			m,
			"DeskTop",
			Vector3.new(2.3, 0.2, 2),
			seg * CFrame.new(0, 3.1, 0.9),
			Color3.fromRGB(36, 32, 30),
			Enum.Material.Marble
		)
		p(m, "Stripe", Vector3.new(2.2, 0.15, 0.06), seg * CFrame.new(0, 2.6, -0.23), accent, Enum.Material.Neon)
	end
	p(m, "Papers", Vector3.new(1.2, 0.04, 1.6), CFrame.new(-0.6, 3.25, 1.1) * CFrame.Angles(0, math.rad(8), 0), C.Paper)
	p(m, "Mug", Vector3.new(0.35, 0.45, 0.35), CFrame.new(1.6, 3.43, 1.0), Color3.fromRGB(180, 40, 30))
end

function Scenes.build(parent: any)
	local folder = roblox.Instance.new("Folder")
	folder.Name = "Scenes"
	folder.Parent = parent

	-- Night Desk on air (1979–1987). The anchor sits behind the desk facing camera (-Z).
	local studio = scene(
		folder,
		"StudioADesk",
		Color3.fromRGB(70, 66, 74),
		Color3.fromRGB(255, 226, 190),
		Vector3.new(-0.4, -0.8, 0.6)
	)
	newsSet(studio, Color3.fromRGB(60, 42, 34), Color3.fromRGB(26, 34, 64), Color3.fromRGB(200, 160, 90))
	marker(studio, "AnchorMark", CFrame.new(0, 0, 2.2))
	marker(studio, "Cam", B.lookAt(Vector3.new(0.4, 5.4, -10.5), Vector3.new(0, 4.6, 2)))

	-- Studio B as it was: the same set, warmer, the camera a little too close.
	local memory = scene(
		folder,
		"StudioBMemory",
		Color3.fromRGB(84, 70, 60),
		Color3.fromRGB(255, 214, 170),
		Vector3.new(0.3, -0.9, 0.5)
	)
	newsSet(memory, Color3.fromRGB(80, 50, 36), Color3.fromRGB(46, 30, 30), Color3.fromRGB(210, 150, 80))
	marker(memory, "AnchorMark", CFrame.new(0, 0, 2.2))
	marker(memory, "Cam", B.lookAt(Vector3.new(-0.2, 5.6, -7.5), Vector3.new(0, 5.4, 2)))

	-- Master control, day (orientation tape) and night (filler glitch frame).
	for _, info in
		{
			{ "MasterControlDay", Color3.fromRGB(120, 120, 116), Color3.fromRGB(255, 250, 235) },
			{ "MasterControlNight", Color3.fromRGB(40, 44, 56), Color3.fromRGB(140, 170, 220) },
		}
	do
		local mcr = scene(folder, info[1], info[2], info[3], Vector3.new(0.2, -1, 0.4))
		p(mcr, "Floor", Vector3.new(28, 0.4, 24), CFrame.new(0, -0.2, 0), C.Carpet, Enum.Material.Carpet)
		p(mcr, "WallBack", Vector3.new(28, 12, 0.4), CFrame.new(0, 6, 9), C.WallBlue)
		p(mcr, "WallSide", Vector3.new(0.4, 12, 24), CFrame.new(-12, 6, -1), C.WallBlue)
		p(mcr, "MonitorFrame", Vector3.new(14, 7.2, 0.6), CFrame.new(0, 6.2, 8.4), C.PlasticBlack)
		for r = 0, 2 do
			for c = 0, 4 do
				local glow = if info[1] == "MasterControlDay"
					then Color3.fromRGB(70, 90, 120)
					else Color3.fromRGB(30, 60, 50)
				if r == 2 and c == 2 then
					glow = Color3.fromRGB(180, 180, 170)
				end
				p(
					mcr,
					"Screen",
					Vector3.new(2.1, 1.7, 0.1),
					CFrame.new(-5 + c * 2.5, 3.9 + r * 2.2, 8.05),
					glow,
					Enum.Material.Neon
				)
			end
		end
		p(mcr, "Console", Vector3.new(12, 2.6, 2.6), CFrame.new(0, 1.3, 3), C.PlasticGrey)
		p(
			mcr,
			"ConsoleTop",
			Vector3.new(12, 0.25, 2.8),
			CFrame.new(0, 2.75, 2.9) * CFrame.Angles(math.rad(-12), 0, 0),
			C.PlasticBlack
		)
		p(mcr, "Chair", Vector3.new(1.6, 3, 1.6), CFrame.new(-2, 1.5, -0.4), C.FabricBlue, Enum.Material.Fabric)
		if info[1] == "MasterControlNight" then
			-- The glitch frame: someone standing where nobody should be.
			marker(mcr, "AnchorMark", CFrame.new(8, 0, -2) * CFrame.Angles(0, math.rad(200), 0))
			figure(mcr, CFrame.new(-2, 0, -0.4) * CFrame.Angles(0, math.rad(180), 0), Color3.fromRGB(70, 80, 70))
		end
		marker(mcr, "Cam", B.lookAt(Vector3.new(9, 9, -10), Vector3.new(-1, 3, 4)))
	end

	-- Christmas party, 1986.
	local party = scene(
		folder,
		"LobbyParty",
		Color3.fromRGB(110, 90, 80),
		Color3.fromRGB(255, 220, 180),
		Vector3.new(0.5, -0.8, 0.3)
	)
	p(party, "Floor", Vector3.new(30, 0.4, 24), CFrame.new(0, -0.2, 0), C.Marble, Enum.Material.Marble)
	p(party, "Wall", Vector3.new(30, 12, 0.4), CFrame.new(0, 6, 9), C.WoodPanel, Enum.Material.Wood)
	p(
		party,
		"StudioWindow",
		Vector3.new(8, 4, 0.2),
		CFrame.new(6, 6, 8.75),
		Color3.fromRGB(255, 230, 190),
		Enum.Material.Neon
	)
	p(party, "Table", Vector3.new(8, 0.3, 3), CFrame.new(-4, 2.8, 3), Color3.fromRGB(200, 40, 40))
	p(
		party,
		"Punch",
		Vector3.new(1.4, 0.8, 1.4),
		CFrame.new(-4, 3.4, 3),
		Color3.fromRGB(200, 60, 80),
		Enum.Material.Glass
	)
	for i = 0, 6 do
		p(
			party,
			"Streamer",
			Vector3.new(4, 0.15, 0.15),
			CFrame.new(-12 + i * 4, 10 - (i % 2) * 0.6, 8.6)
				* CFrame.Angles(0, 0, math.rad(if i % 2 == 0 then 8 else -8)),
			if i % 2 == 0 then Color3.fromRGB(40, 160, 70) else Color3.fromRGB(200, 40, 40),
			Enum.Material.Neon
		)
	end
	figure(party, CFrame.new(-7, 0, 0), Color3.fromRGB(150, 40, 40), "Wave")
	figure(party, CFrame.new(-2, 0, -1), Color3.fromRGB(60, 70, 120))
	figure(party, CFrame.new(1.5, 0, 1) * CFrame.Angles(0, math.rad(30), 0), Color3.fromRGB(90, 90, 80))
	-- Through the window: a silhouette at the desk.
	marker(party, "AnchorMark", CFrame.new(6, 3.4, 11) * CFrame.Angles(0, math.rad(180), 0))
	marker(party, "Cam", B.lookAt(Vector3.new(-3, 5.5, -12), Vector3.new(1, 4.5, 5)))

	-- Security camera 3, 1991: high angle down the main hall.
	local hall = scene(
		folder,
		"HallwaySecurity",
		Color3.fromRGB(60, 66, 60),
		Color3.fromRGB(200, 230, 210),
		Vector3.new(0, -1, 0.2)
	)
	p(hall, "Floor", Vector3.new(8, 0.4, 60), CFrame.new(0, -0.2, -20), C.Marble, Enum.Material.Marble)
	p(hall, "WallL", Vector3.new(0.4, 12, 60), CFrame.new(-4, 6, -20), C.WallBeige)
	p(hall, "WallR", Vector3.new(0.4, 12, 60), CFrame.new(4, 6, -20), C.WallBeige)
	for i = 0, 4 do
		p(
			hall,
			"Fixture",
			Vector3.new(1.4, 0.1, 4),
			CFrame.new(0, 11.8, -i * 12),
			Color3.fromRGB(220, 236, 226),
			Enum.Material.Neon
		)
	end
	p(
		hall,
		"StudioDoorGlow",
		Vector3.new(3.6, 7.6, 0.2),
		CFrame.new(-3.8, 3.8, -30) * CFrame.Angles(0, math.rad(90), 0),
		Color3.fromRGB(255, 226, 180),
		Enum.Material.Neon
	)
	figure(hall, CFrame.new(0.6, 0, -8) * CFrame.Angles(0, math.rad(180), 0), Color3.fromRGB(60, 70, 110))
	marker(hall, "Cam", B.lookAt(Vector3.new(2.8, 11, 8), Vector3.new(0, 2, -14)))

	return folder
end

return Scenes
