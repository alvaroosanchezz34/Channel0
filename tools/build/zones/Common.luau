-- Shared helpers for zone dressing.
local B = require("../lib/B")
local Layout = require("../../../src/shared/Content/StationLayout")

local Vector3, CFrame, Enum = B.Vector3, B.CFrame, B.Enum

local Common = {}

Common.YAW = { North = 0, West = 90, South = 180, East = -90 }

function Common.bounds(zone: string)
	local b = Layout.zoneBounds(zone)
	assert(b, "zone without bounds: " .. zone)
	return b
end

function Common.device(
	parent: any,
	cf: any,
	size: any,
	kind: string,
	id: string,
	zone: string,
	promptKey: string,
	action: string,
	opts: { [string]: any }?
)
	local o = opts or {}
	local part = B.part({
		parent = parent,
		name = "Device_" .. id,
		size = size,
		cf = cf,
		role = "Marker",
		tags = { "Device" },
		attributes = { Device = kind, DeviceId = id, Zone = zone },
	})
	B.prompt(part, { action = action, key = promptKey, distance = o.distance or 7, object = o.object or "" })
	return part
end

function Common.marker(parent: any, name: string, cf: any, tag: string?, attributes: { [string]: any }?)
	return B.part({
		parent = parent,
		name = name,
		size = Vector3.new(1, 1, 1),
		cf = cf,
		role = "Marker",
		tags = if tag then { tag } else nil,
		attributes = attributes,
	})
end

-- Wall-mounted security camera. `pos` is the mount point, `target` where it looks.
function Common.securityCamera(
	parent: any,
	id: number,
	label: string,
	zone: string,
	pos: any,
	target: any,
	fov: number?
)
	local m = B.model(string.format("CAM%02d", id), parent)
	local look = B.lookAt(pos, target)
	B.part({
		parent = m,
		name = "Bracket",
		role = "Detail",
		size = Vector3.new(0.3, 0.3, 0.9),
		cf = look * CFrame.new(0, 0.25, 0.55),
		color = B.Colors.PlasticBeige,
	})
	B.part({
		parent = m,
		name = "Housing",
		role = "Detail",
		size = Vector3.new(0.7, 0.6, 1.4),
		cf = look,
		color = B.Colors.PlasticBeige,
	})
	B.part({
		parent = m,
		name = "Lens",
		role = "Detail",
		size = Vector3.new(0.45, 0.45, 0.1),
		cf = look * CFrame.new(0, 0, -0.72),
		color = B.Colors.PlasticBlack,
		material = Enum.Material.Glass,
	})
	local led = B.part({
		parent = m,
		name = "LED",
		role = "Detail",
		size = Vector3.new(0.1, 0.1, 0.05),
		cf = look * CFrame.new(0.25, 0.22, -0.71),
		color = B.Color3.fromRGB(255, 30, 20),
		material = Enum.Material.Neon,
	})
	led:SetAttribute("BaseColor", led.Color)
	led:AddTag("CameraLED")
	local point = B.part({
		parent = m,
		name = "CamPoint",
		role = "Marker",
		size = Vector3.new(0.2, 0.2, 0.2),
		cf = look * CFrame.new(0, 0, -0.9),
		tags = { "SecurityCamera" },
		attributes = { CamId = id, Label = label, Zone = zone, FOV = fov or 72 },
	})
	return m, point
end

function Common.monitorSwitch(parent: any, zone: string, cf: any)
	local plate = B.part({
		parent = parent,
		name = "MonitorSwitchPlate",
		role = "Detail",
		size = Vector3.new(0.8, 1.2, 0.1),
		cf = cf,
		color = B.Colors.PlasticBeige,
	})
	B.label(plate, Enum.NormalId.Front, "MONITORS\nON / OFF", { font = Enum.Font.Code, padding = 0.12 })
	return Common.device(
		parent,
		cf * CFrame.new(0, 0, -0.4),
		Vector3.new(1, 1.4, 0.6),
		"MonitorSwitch",
		"MonSwitch_" .. zone,
		zone,
		"prompt.monitors",
		"Switch",
		{ distance = 6 }
	)
end

function Common.tapeSlot(parent: any, slotId: string, zone: string, cf: any)
	return Common.marker(parent, slotId, cf, "TapeSlot", { SlotId = slotId, Zone = zone })
end

function Common.emitter(parent: any, sound: string, cf: any, zone: string)
	return Common.marker(parent, "Emitter_" .. sound, cf, "AmbientEmitter", { Sound = sound, Zone = zone })
end

return Common
