--[[
	THE ANCHOR: an original rig built from primitives and built-in mesh shapes (no external assets).

	Design notes
	  * Silhouette first: too tall (7.8 studs), broad padded 90s shoulders, narrow waist, long arms
	    that hang perfectly still, a head held a little too high on a long neck.
	  * The face is almost nothing: a smooth pale head, slicked hair, two shallow sockets and a mouth
	    line slightly too wide. A dark horizontal "tracking tear" crosses the face like a bad VHS
	    frame, and two faint red/cyan shells offset from the head read as chroma misregistration.
	  * He carries his own key light: a warm studio spot that lights him like he is on air, even in a
	    dark corridor. The presentation code turns it on when he is physical.

	Joints are Motor6Ds so the server can snap poses by changing C0 (cheap to replicate). The Root is
	anchored; everything else is massless and non-colliding.
]]

local B = require("./B")
local roblox = require("@lune/roblox")

local Vector3, CFrame, Color3, Enum = B.Vector3, B.CFrame, B.Color3, B.Enum

local AnchorRig = {}

local SUIT = Color3.fromRGB(34, 34, 40)
local SUIT_LIGHT = Color3.fromRGB(46, 46, 54)
local SHIRT = Color3.fromRGB(226, 224, 216)
local TIE = Color3.fromRGB(118, 16, 20)
local SKIN = Color3.fromRGB(200, 192, 180)
local HAIR = Color3.fromRGB(26, 22, 20)

local function part(model: any, name: string, size: any, cf: any, color: any, material: any?, extra: { [string]: any }?)
	local p = roblox.Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = false
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if extra then
		for k, v in extra do
			p[k] = v
		end
	end
	p.Parent = model
	return p
end

local function wedge(model: any, name: string, size: any, cf: any, color: any, material: any?)
	local w = roblox.Instance.new("WedgePart")
	w.Name = name
	w.Size = size
	w.CFrame = cf
	w.Color = color
	w.Material = material or Enum.Material.Fabric
	w.Anchored = false
	w.CanCollide = false
	w.CanTouch = false
	w.CanQuery = false
	w.Massless = true
	w.Parent = model
	return w
end

local function sphereMesh(p: any, scale: any?)
	local mesh = roblox.Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = scale or Vector3.new(1, 1, 1)
	mesh.Parent = p
	return mesh
end

local function weld(a: any, b: any)
	local w = roblox.Instance.new("WeldConstraint")
	w.Part0 = a
	w.Part1 = b
	w.Parent = b
	return w
end

local function motor(name: string, part0: any, part1: any, jointWorld: any)
	local m = roblox.Instance.new("Motor6D")
	m.Name = name
	m.Part0 = part0
	m.Part1 = part1
	m.C0 = part0.CFrame:Inverse() * jointWorld
	m.C1 = part1.CFrame:Inverse() * jointWorld
	m.Parent = part0
	return m
end

function AnchorRig.build(parent: any): any
	local model = roblox.Instance.new("Model")
	model.Name = "Anchor"
	model:AddTag("AnchorRig")
	-- Built facing -Z with feet at y = 0, centred on x = z = 0.
	local root = roblox.Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(2, 2, 1)
	root.CFrame = CFrame.new(0, 3.9, 0)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanTouch = false
	root.CanQuery = false
	root.Parent = model
	model.PrimaryPart = root

	-- Torso and jacket
	local torso = part(model, "Torso", Vector3.new(1.9, 2.5, 0.95), CFrame.new(0, 5.25, 0), SUIT, Enum.Material.Fabric)
	local hem = part(model, "JacketHem", Vector3.new(2.0, 0.7, 1.0), CFrame.new(0, 3.95, 0), SUIT, Enum.Material.Fabric)
	weld(torso, hem)
	for _, side in { -1, 1 } do
		local pad = part(
			model,
			"ShoulderPad",
			Vector3.new(0.7, 0.38, 1.05),
			CFrame.new(side * 1.12, 6.36, 0),
			SUIT,
			Enum.Material.Fabric
		)
		weld(torso, pad)
		local lapel = wedge(
			model,
			"Lapel",
			Vector3.new(0.08, 1.3, 0.42),
			CFrame.new(side * 0.32, 5.8, -0.5)
				* CFrame.Angles(0, 0, math.rad(side * -14))
				* CFrame.Angles(0, math.rad(180), 0),
			SUIT_LIGHT
		)
		weld(torso, lapel)
	end
	local shirt = wedge(
		model,
		"Shirt",
		Vector3.new(0.05, 1.1, 0.5),
		CFrame.new(0, 6.0, -0.48) * CFrame.Angles(0, math.rad(90), math.rad(180)),
		SHIRT,
		Enum.Material.SmoothPlastic
	)
	weld(torso, shirt)
	local collar = part(model, "Collar", Vector3.new(0.75, 0.25, 0.8), CFrame.new(0, 6.55, -0.05), SHIRT)
	weld(torso, collar)
	local knot = part(model, "TieKnot", Vector3.new(0.2, 0.2, 0.08), CFrame.new(0, 6.32, -0.52), TIE)
	weld(torso, knot)
	local tie = part(model, "Tie", Vector3.new(0.2, 1.55, 0.05), CFrame.new(0, 5.4, -0.5), TIE, Enum.Material.Fabric)
	weld(torso, tie)
	local pocket = part(model, "PocketSquare", Vector3.new(0.28, 0.1, 0.04), CFrame.new(-0.55, 5.9, -0.49), SHIRT)
	weld(torso, pocket)
	local pin = part(
		model,
		"LapelPin",
		Vector3.new(0.09, 0.09, 0.04),
		CFrame.new(0.42, 6.0, -0.53),
		Color3.fromRGB(200, 170, 90),
		Enum.Material.Metal
	)
	weld(torso, pin)
	local mic = part(
		model,
		"LavalierMic",
		Vector3.new(0.07, 0.14, 0.06),
		CFrame.new(0.06, 5.95, -0.54),
		Color3.fromRGB(10, 10, 10)
	)
	weld(torso, mic)
	for i = 0, 1 do
		local button = part(
			model,
			"Button",
			Vector3.new(0.09, 0.09, 0.03),
			CFrame.new(0.18, 4.95 - i * 0.45, -0.49),
			Color3.fromRGB(18, 18, 20)
		)
		weld(torso, button)
	end

	-- Neck and head
	local neck = part(model, "Neck", Vector3.new(0.42, 0.62, 0.42), CFrame.new(0, 6.78, 0), SKIN)
	weld(torso, neck)
	local headCenter = CFrame.new(0, 7.32, -0.02)
	local head = part(model, "Head", Vector3.new(0.96, 1.18, 1.04), headCenter, SKIN)
	sphereMesh(head)
	local hair = part(
		model,
		"Hair",
		Vector3.new(1.0, 0.62, 1.1),
		headCenter * CFrame.new(0, 0.36, 0.06),
		HAIR,
		Enum.Material.SmoothPlastic,
		{ Reflectance = 0.12 }
	)
	sphereMesh(hair)
	weld(head, hair)
	for _, side in { -1, 1 } do
		local socket = part(
			model,
			"Socket",
			Vector3.new(0.2, 0.11, 0.05),
			headCenter * CFrame.new(side * 0.21, 0.08, -0.5),
			Color3.fromRGB(40, 36, 34)
		)
		sphereMesh(socket)
		weld(head, socket)
		local ear =
			part(model, "Ear", Vector3.new(0.08, 0.26, 0.16), headCenter * CFrame.new(side * 0.49, 0.02, 0.02), SKIN)
		sphereMesh(ear)
		weld(head, ear)
	end
	local mouth = part(
		model,
		"Mouth",
		Vector3.new(0.6, 0.032, 0.05),
		headCenter * CFrame.new(0, -0.27, -0.49),
		Color3.fromRGB(34, 22, 22)
	)
	weld(head, mouth)
	for _, side in { -1, 1 } do
		local corner = part(
			model,
			"MouthCorner",
			Vector3.new(0.14, 0.03, 0.05),
			headCenter * CFrame.new(side * 0.35, -0.245, -0.47) * CFrame.Angles(0, 0, math.rad(side * 24)),
			Color3.fromRGB(34, 22, 22)
		)
		weld(head, corner)
	end
	-- Tracking tear: a dark band that slices the face horizontally.
	local tear = part(
		model,
		"TrackingTear",
		Vector3.new(1.0, 0.035, 1.08),
		headCenter * CFrame.new(0.05, -0.06, 0),
		Color3.fromRGB(14, 14, 16),
		Enum.Material.Neon
	)
	weld(head, tear)
	tear:AddTag("AnchorGlitch")
	-- Chroma ghosts.
	for i, info in
		{ { -0.075, Color3.fromRGB(255, 40, 40), "GhostR" }, { 0.075, Color3.fromRGB(40, 240, 255), "GhostC" } }
	do
		local ghost = part(
			model,
			info[3],
			Vector3.new(0.98, 1.2, 1.06),
			headCenter * CFrame.new(info[1], 0, 0),
			info[2],
			Enum.Material.Neon,
			{ Transparency = 0.88, CastShadow = false }
		)
		sphereMesh(ghost)
		weld(head, ghost)
		ghost:AddTag("AnchorGhost")
		ghost:SetAttribute("Offset", info[1])
		local _ = i
	end

	-- Arms
	local arms = {}
	for _, side in { -1, 1 } do
		local tag = if side < 0 then "L" else "R"
		local upper = part(
			model,
			"UpperArm" .. tag,
			Vector3.new(0.55, 1.75, 0.6),
			CFrame.new(side * 1.2, 5.45, 0),
			SUIT,
			Enum.Material.Fabric
		)
		local lower = part(
			model,
			"LowerArm" .. tag,
			Vector3.new(0.48, 1.65, 0.52),
			CFrame.new(side * 1.22, 3.78, 0),
			SUIT,
			Enum.Material.Fabric
		)
		local cuff = part(model, "Cuff" .. tag, Vector3.new(0.42, 0.16, 0.46), CFrame.new(side * 1.22, 2.98, 0), SHIRT)
		weld(lower, cuff)
		local hand = part(model, "Hand" .. tag, Vector3.new(0.18, 0.55, 0.36), CFrame.new(side * 1.22, 2.62, 0), SKIN)
		-- Fingers: a little too long.
		for f = 0, 3 do
			local finger = part(
				model,
				"Finger",
				Vector3.new(0.07, 0.7, 0.075),
				CFrame.new(side * 1.22, 2.0, -0.13 + f * 0.088),
				SKIN
			)
			weld(hand, finger)
		end
		local thumb = part(
			model,
			"Thumb",
			Vector3.new(0.08, 0.4, 0.08),
			CFrame.new(side * 1.17, 2.38, -0.2) * CFrame.Angles(math.rad(14), 0, 0),
			SKIN
		)
		weld(hand, thumb)
		motor("Shoulder" .. tag, torso, upper, CFrame.new(side * 1.2, 6.25, 0))
		motor("Elbow" .. tag, upper, lower, CFrame.new(side * 1.21, 4.6, 0))
		motor("Wrist" .. tag, lower, hand, CFrame.new(side * 1.22, 2.92, 0))
		arms[tag] = upper
	end

	-- Legs
	for _, side in { -1, 1 } do
		local tag = if side < 0 then "L" else "R"
		local upper = part(
			model,
			"UpperLeg" .. tag,
			Vector3.new(0.72, 1.95, 0.76),
			CFrame.new(side * 0.46, 2.85, 0),
			SUIT,
			Enum.Material.Fabric
		)
		local lower = part(
			model,
			"LowerLeg" .. tag,
			Vector3.new(0.62, 1.75, 0.66),
			CFrame.new(side * 0.46, 1.12, 0),
			SUIT,
			Enum.Material.Fabric
		)
		local shoe = part(
			model,
			"Shoe" .. tag,
			Vector3.new(0.6, 0.32, 1.1),
			CFrame.new(side * 0.46, 0.16, -0.18),
			Color3.fromRGB(12, 12, 12),
			Enum.Material.SmoothPlastic,
			{ Reflectance = 0.1 }
		)
		weld(lower, shoe)
		motor("Hip" .. tag, root, upper, CFrame.new(side * 0.46, 3.82, 0))
		motor("Knee" .. tag, upper, lower, CFrame.new(side * 0.46, 1.95, 0))
	end

	motor("Waist", root, torso, CFrame.new(0, 4.1, 0))
	motor("Neck", torso, head, CFrame.new(0, 6.6, 0))

	-- His own studio key light, in front and above, aimed at the face.
	local keyPos = Vector3.new(0.8, 9.6, -5.5)
	local key = part(
		model,
		"KeyLight",
		Vector3.new(0.4, 0.4, 0.4),
		B.lookAt(keyPos, Vector3.new(0, 6.4, 0)),
		Color3.new(1, 1, 1),
		Enum.Material.SmoothPlastic,
		{ Transparency = 1, CastShadow = false }
	)
	local spot = roblox.Instance.new("SpotLight")
	spot.Name = "Key"
	spot.Face = Enum.NormalId.Front
	spot.Angle = 46
	spot.Brightness = 3.2
	spot.Range = 16
	spot.Color = Color3.fromRGB(255, 228, 190)
	spot.Shadows = true
	spot.Enabled = false
	spot.Parent = key
	local rim = roblox.Instance.new("PointLight")
	rim.Name = "Rim"
	rim.Brightness = 0.6
	rim.Range = 7
	rim.Color = Color3.fromRGB(150, 180, 255)
	rim.Enabled = false
	rim.Parent = torso
	-- The key light rides on the root so it moves with him.
	local keyWeld = roblox.Instance.new("WeldConstraint")
	keyWeld.Part0 = root
	keyWeld.Part1 = key
	keyWeld.Parent = key

	model:SetAttribute("Height", 7.85)
	model.Parent = parent
	return model
end

return AnchorRig
