--[[
	CHANNEL 0 map + asset generator.

	    lune run tools/build/build            build assets/Station.rbxm and assets/Assets.rbxm, validate
	    lune run tools/build/build --check    validate only (non-zero exit on errors, nothing written)

	The station is generated from src/shared/Content/StationLayout.luau and the zone dressing
	modules, so the plan used by the server for zone lookup and the geometry can never drift apart.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local B = require("./lib/B")
local Shell = require("./lib/Shell")
local AnchorRig = require("./lib/AnchorRig")
local Scenes = require("./lib/Scenes")
local Ground = require("./zones/Ground")
local Basement = require("./zones/Basement")
local Exterior = require("./zones/Exterior")
local Common = require("./zones/Common")
local Settle = require("./lib/Settle")
local Validator = require("../validate/Validator")
local Tapes = require("../../src/shared/Content/Tapes")

local checkOnly = table.find(process.args, "--check") ~= nil

local station = B.model("Station")
station:SetAttribute("Generator", "tools/build/build.luau")
local shell = B.folder("Shell", station)
local doors = B.folder("Doors", station)
local frames = B.folder("Frames", station)
local zones = B.folder("Zones", station)
local markers = B.folder("Markers", station)

Shell.floorsAndCeilings(shell)
local placements = Shell.walls(shell)
Shell.openings(frames, doors, placements)
Shell.stairs(shell)
Ground.build(zones)
Basement.build(zones)
Exterior.build(zones)
print("settled " .. Settle.run(zones, B.registry) .. " prop push(es) out of walls")
print("trimmed " .. Settle.trimLeaves(doors, B.registry) .. " door leaf/leaves at wall corners")

-- Anchor nodes go in open floor space after everything else is placed.
local nodes = B.folder("AnchorNodes", markers)
Validator.placeAnchorNodes(station, B.registry, function(name, cf, attrs)
	Common.marker(nodes, name, cf, "AnchorNode", attrs)
end)

local assets = B.folder("Assets")
AnchorRig.build(assets)
Scenes.build(assets)

-- Pickup model for tapes (the server clones it into slots).
local tape = B.model("Tape", assets)
local body = roblox.Instance.new("Part")
body.Name = "Body"
body.Size = B.Vector3.new(1.3, 0.25, 0.75)
body.Color = B.Color3.fromRGB(22, 22, 24)
body.Material = B.Enum.Material.SmoothPlastic
body.Anchored = true
body.CanCollide = false
body.CFrame = B.CFrame.new(0, 0.125, 0)
body.Parent = tape
tape.PrimaryPart = body
local labelPart = roblox.Instance.new("Part")
labelPart.Name = "Label"
labelPart.Size = B.Vector3.new(1.1, 0.02, 0.45)
labelPart.Color = B.Color3.fromRGB(232, 228, 214)
labelPart.Anchored = true
labelPart.CanCollide = false
labelPart.CanQuery = false
labelPart.CFrame = B.CFrame.new(0, 0.26, 0)
labelPart.Parent = tape
B.label(labelPart, B.Enum.NormalId.Top, "TAPE", { font = B.Enum.Font.PermanentMarker, name = "LabelGui", ppu = 120 })
local window = roblox.Instance.new("Part")
window.Name = "Window"
window.Size = B.Vector3.new(0.6, 0.02, 0.18)
window.Color = B.Color3.fromRGB(60, 50, 40)
window.Material = B.Enum.Material.Glass
window.Transparency = 0.3
window.Anchored = true
window.CanCollide = false
window.CanQuery = false
window.CFrame = B.CFrame.new(0, 0.255, 0.22)
window.Parent = tape
local glow = roblox.Instance.new("PointLight")
glow.Name = "Glint"
glow.Range = 4
glow.Brightness = 0.35
glow.Color = B.Color3.fromRGB(255, 240, 210)
glow.Parent = body

local result = Validator.run(station, assets, B.registry, Tapes.Defs)
for _, warning in result.warnings do
	print("warning: " .. warning)
end
for _, err in result.errors do
	print("ERROR: " .. err)
end
local summary = {}
for k, v in result.stats do
	table.insert(summary, k .. "=" .. tostring(v))
end
table.sort(summary)
print("stats: " .. table.concat(summary, " "))

if not checkOnly then
	B.stripUids(station)
	B.stripUids(assets)
	fs.writeFile("assets/Station.rbxm", roblox.serializeModel({ station }))
	fs.writeFile("assets/Assets.rbxm", roblox.serializeModel({ assets }))
	print("wrote assets/Station.rbxm and assets/Assets.rbxm")
end

if #result.errors > 0 then
	print(string.format("%d validation error(s)", #result.errors))
	process.exit(1)
end
print("validation passed")
