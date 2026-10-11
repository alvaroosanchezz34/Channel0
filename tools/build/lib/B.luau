--[[
	Builder primitives for the offline map generator (Lune). Every part goes through `B.part` so
	the generator can track bounds for the placement validator and keep conventions uniform:
	anchored, smooth surfaces, no unintended collisions.
]]

local roblox = require("@lune/roblox")

local Instance = roblox.Instance
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Color3 = roblox.Color3
local Enum = roblox.Enum

local B = {}

B.Vector3 = Vector3
B.CFrame = CFrame
B.Color3 = Color3
B.Enum = Enum
B.Instance = Instance

-- Palette: aged, desaturated 90s institutional colours. Kept in one place for coherence.
B.Colors = {
	Concrete = Color3.fromRGB(120, 118, 112),
	ConcreteDark = Color3.fromRGB(78, 77, 74),
	WallBeige = Color3.fromRGB(196, 186, 160),
	WallGreen = Color3.fromRGB(139, 152, 128),
	WallGrey = Color3.fromRGB(150, 150, 146),
	WallBlue = Color3.fromRGB(108, 122, 138),
	WoodPanel = Color3.fromRGB(110, 78, 50),
	WoodLight = Color3.fromRGB(160, 120, 78),
	Carpet = Color3.fromRGB(70, 66, 84),
	CarpetRed = Color3.fromRGB(96, 46, 44),
	Marble = Color3.fromRGB(176, 170, 158),
	Tile = Color3.fromRGB(184, 182, 170),
	Ceiling = Color3.fromRGB(200, 198, 186),
	CeilingDark = Color3.fromRGB(30, 30, 32),
	Metal = Color3.fromRGB(122, 126, 128),
	MetalDark = Color3.fromRGB(58, 60, 62),
	MetalRust = Color3.fromRGB(110, 76, 54),
	PlasticBeige = Color3.fromRGB(198, 190, 168),
	PlasticGrey = Color3.fromRGB(96, 96, 98),
	PlasticBlack = Color3.fromRGB(28, 28, 30),
	Fabric = Color3.fromRGB(40, 40, 44),
	FabricBlue = Color3.fromRGB(44, 58, 92),
	Brick = Color3.fromRGB(122, 74, 58),
	Asphalt = Color3.fromRGB(42, 42, 44),
	Grass = Color3.fromRGB(52, 62, 40),
	Glass = Color3.fromRGB(70, 90, 96),
	Screen = Color3.fromRGB(20, 26, 24),
	Red = Color3.fromRGB(150, 30, 28),
	SafetyYellow = Color3.fromRGB(190, 156, 40),
	Paper = Color3.fromRGB(226, 220, 200),
	Fluor = Color3.fromRGB(236, 244, 255),
	Warm = Color3.fromRGB(255, 214, 160),
	Sodium = Color3.fromRGB(255, 170, 90),
	Skin = Color3.fromRGB(208, 196, 182),
	Charred = Color3.fromRGB(24, 22, 20),
}

-- Registry of every created BasePart with its role, for the validator.
B.registry = {} :: { { part: any, role: string } }

local function applyProps(instance: any, props: { [string]: any }?)
	if not props then
		return
	end
	for key, value in props do
		if key ~= "Parent" and key ~= "Role" and key ~= "Tags" and key ~= "Attributes" then
			instance[key] = value
		end
	end
	if props.Tags then
		for _, tag in props.Tags do
			instance:AddTag(tag)
		end
	end
	if props.Attributes then
		for k, v in props.Attributes do
			instance:SetAttribute(k, v)
		end
	end
	if props.Parent then
		instance.Parent = props.Parent
	end
end

function B.inst(className: string, props: { [string]: any }?): any
	local instance = Instance.new(className)
	applyProps(instance, props)
	return instance
end

function B.folder(name: string, parent: any?): any
	return B.inst("Folder", { Name = name, Parent = parent })
end

local nextUid = 0
function B.model(name: string, parent: any?): any
	nextUid += 1
	-- Temporary identity for the validator (Lune hands out fresh userdata per access, so instances
	-- cannot be used as table keys). Stripped before serialisation.
	return B.inst("Model", { Name = name, Parent = parent, Attributes = { __uid = nextUid } })
end

function B.stripUids(root: any)
	for _, d in root:GetDescendants() do
		if d:GetAttribute("__uid") ~= nil then
			d:SetAttribute("__uid", nil)
		end
	end
end

--[[
	B.part{ size, cf, color, material, parent, name, role, ... }
	role classifies the part for validation: "Structure" (floors/walls/ceilings), "Trim",
	"Prop", "Detail" (decorative, non-colliding), "Glass", "Marker", "Dynamic", "Light".
]]
function B.part(spec: { [string]: any }): any
	local className = spec.class or "Part"
	local part = Instance.new(className)
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Size = spec.size
	part.CFrame = spec.cf
	part.Color = spec.color or B.Colors.WallGrey
	part.Material = spec.material or Enum.Material.SmoothPlastic
	part.Name = spec.name or "Part"
	if spec.transparency then
		part.Transparency = spec.transparency
	end
	if spec.reflectance then
		part.Reflectance = spec.reflectance
	end
	local role = spec.role or "Prop"
	if spec.collide == false or role == "Detail" or role == "Marker" or role == "Light" then
		part.CanCollide = false
		part.CanTouch = false
		if role == "Marker" then
			part.CanQuery = false
			part.Transparency = 1
		end
	end
	if spec.castShadow == false or role == "Marker" then
		part.CastShadow = false
	end
	if spec.shape then
		part.Shape = spec.shape
	end
	applyProps(part, spec.props)
	if spec.tags then
		for _, tag in spec.tags do
			part:AddTag(tag)
		end
	end
	if spec.attributes then
		for k, v in spec.attributes do
			part:SetAttribute(k, v)
		end
	end
	part.Parent = spec.parent
	table.insert(B.registry, { part = part, role = role })
	return part
end

function B.wedge(spec: { [string]: any }): any
	spec.class = "WedgePart"
	return B.part(spec)
end

-- Box between two corner points (axis aligned).
function B.box(min: any, max: any, spec: { [string]: any }): any
	local size = max - min
	spec.size = Vector3.new(math.abs(size.X), math.abs(size.Y), math.abs(size.Z))
	spec.cf = CFrame.new((min + max) / 2)
	return B.part(spec)
end

function B.at(x: number, y: number, z: number, yawDegrees: number?): any
	return CFrame.new(x, y, z) * CFrame.Angles(0, math.rad(yawDegrees or 0), 0)
end

-- Local offset from a frame.
function B.off(frame: any, x: number, y: number, z: number, yawDegrees: number?): any
	return frame * CFrame.new(x, y, z) * CFrame.Angles(0, math.rad(yawDegrees or 0), 0)
end

-- CFrame looking from `from` toward `to`. (Lune's CFrame.lookAt mishandles the exact -Z case.)
function B.lookAt(from: any, to: any): any
	local look = (to - from).Unit
	local up = Vector3.new(0, 1, 0)
	if math.abs(look:Dot(up)) > 0.999 then
		up = Vector3.new(0, 0, 1)
	end
	local right = look:Cross(up).Unit
	local trueUp = right:Cross(look).Unit
	return CFrame.fromMatrix(from, right, trueUp, -look)
end

function B.surfaceLight(parent: any, props: { [string]: any }): any
	local light = Instance.new("SurfaceLight")
	light.Face = props.face or Enum.NormalId.Bottom
	light.Brightness = props.brightness or 1
	light.Range = props.range or 14
	light.Angle = props.angle or 100
	light.Color = props.color or B.Colors.Fluor
	light.Shadows = props.shadows or false
	light.Parent = parent
	return light
end

function B.pointLight(parent: any, props: { [string]: any }): any
	local light = Instance.new("PointLight")
	light.Brightness = props.brightness or 1
	light.Range = props.range or 12
	light.Color = props.color or B.Colors.Warm
	light.Shadows = props.shadows or false
	light.Parent = parent
	return light
end

function B.spotLight(parent: any, props: { [string]: any }): any
	local light = Instance.new("SpotLight")
	light.Face = props.face or Enum.NormalId.Front
	light.Brightness = props.brightness or 2
	light.Range = props.range or 20
	light.Angle = props.angle or 45
	light.Color = props.color or B.Colors.Warm
	light.Shadows = props.shadows or false
	light.Parent = parent
	return light
end

-- Text on a surface (signage, labels, tape spines). Pixel density keeps text crisp but cheap.
function B.label(part: any, face: any, text: string, props: { [string]: any }?): any
	local p = props or {}
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = p.ppu or 40
	gui.LightInfluence = p.lightInfluence or 1
	gui.Name = p.name or "Label"
	local label = Instance.new("TextLabel")
	label.Size = roblox.UDim2.fromScale(1, 1)
	label.BackgroundTransparency = if p.background then 0 else 1
	if p.background then
		label.BackgroundColor3 = p.background
	end
	label.BorderSizePixel = 0
	label.Text = text
	label.TextColor3 = p.color or Color3.fromRGB(20, 20, 20)
	label.Font = p.font or Enum.Font.Arial
	label.TextScaled = true
	label.TextWrapped = true
	label.TextXAlignment = p.alignX or Enum.TextXAlignment.Center
	label.TextYAlignment = p.alignY or Enum.TextYAlignment.Center
	label.Parent = gui
	local pad = Instance.new("UIPadding")
	local inset = roblox.UDim.new(p.padding or 0.08, 0)
	pad.PaddingLeft, pad.PaddingRight, pad.PaddingTop, pad.PaddingBottom = inset, inset, inset, inset
	pad.Parent = label
	gui.Parent = part
	return gui
end

function B.prompt(parent: any, props: { [string]: any }): any
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = props.action or "Use"
	prompt.ObjectText = props.object or ""
	prompt.HoldDuration = props.hold or 0
	prompt.MaxActivationDistance = props.distance or 8
	prompt.RequiresLineOfSight = props.lineOfSight or false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	prompt.Name = "Prompt"
	if props.key then
		prompt:SetAttribute("PromptKey", props.key)
	end
	prompt.Parent = parent
	return prompt
end

function B.weld(a: any, b: any): any
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = a
	weld.Part1 = b
	weld.Parent = a
	return weld
end

return B
