--[[
	Prints the runtime contract of the generated station (devices, slots, cameras, monitors,
	markers, tag counts) so server code and docs can be checked against the real map.

	    lune run tools/inspect/inventory
]]
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")

local station = roblox.deserializeModel(fs.readFile("assets/Station.rbxm"))[1]
local tags = {}
local devices, slots, cams, monitors, markers = {}, {}, {}, {}, {}
for _, d in station:GetDescendants() do
	for _, tag in d:GetTags() do
		tags[tag] = (tags[tag] or 0) + 1
	end
	if d:HasTag("Device") then
		local prompt = d:FindFirstChildWhichIsA("ProximityPrompt")
		table.insert(
			devices,
			string.format(
				"%-18s %-22s %-14s %s",
				d:GetAttribute("Device"),
				d:GetAttribute("DeviceId"),
				d:GetAttribute("Zone"),
				prompt and prompt:GetAttribute("PromptKey") or "-"
			)
		)
	elseif d:HasTag("TapeSlot") then
		table.insert(slots, string.format("%-26s %s", d:GetAttribute("SlotId"), d:GetAttribute("Zone")))
	elseif d:HasTag("SecurityCamera") then
		table.insert(
			cams,
			string.format("%d %-28s %s", d:GetAttribute("CamId"), d:GetAttribute("Label"), d:GetAttribute("Zone"))
		)
	elseif d:HasTag("Monitor") then
		table.insert(
			monitors,
			string.format(
				"%-18s %-10s %s",
				tostring(d:GetAttribute("MonitorId")),
				tostring(d:GetAttribute("Role")),
				tostring(d:GetAttribute("Zone"))
			)
		)
	elseif
		d.Parent
		and (
			d.Parent.Name == "Markers"
			or string.find(d.Name, "^Spawn_")
			or string.find(d.Name, "Camera$")
			or string.find(d.Name, "^AnchorStage")
		)
	then
		table.insert(markers, d:GetFullName())
	end
end
local function dump(title, list)
	table.sort(list)
	print(string.format("== %s (%d)", title, #list))
	for _, line in list do
		print("  " .. line)
	end
end
dump("devices", devices)
dump("tape slots", slots)
dump("security cameras", cams)
dump("monitors", monitors)
dump("markers", markers)
local tagList = {}
for tag, n in tags do
	table.insert(tagList, string.format("%-18s %d", tag, n))
end
dump("tags", tagList)
