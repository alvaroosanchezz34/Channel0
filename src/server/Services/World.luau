--!strict
--[[
	Index of the generated station: devices, tape slots, cameras, monitors, doors, markers and
	anchor nodes, plus zone queries. Built once from tags/attributes written by tools/build, so
	the server never depends on instance paths that a level designer might rearrange.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Layout = require(Shared.Content.StationLayout)

local World = {}

World.station = nil :: Model?
World.devices = {} :: { [string]: BasePart }
World.slots = {} :: { [string]: BasePart }
World.cameras = {} :: { [number]: BasePart }
World.monitors = {} :: { Model }
World.doors = {} :: { [string]: Model }
World.markers = {} :: { [string]: BasePart }
World.nodes = {} :: { BasePart }
World.nodesByZone = {} :: { [string]: { BasePart } }
World.zoneFolders = {} :: { [string]: Instance }
World.emitters = {} :: { BasePart }

local function tagged(tag: string): { Instance }
	local list = {}
	for _, instance in CollectionService:GetTagged(tag) do
		if World.station and instance:IsDescendantOf(World.station) then
			table.insert(list, instance)
		end
	end
	return list
end

function World.init()
	local station = Workspace:WaitForChild("Station", 30) :: Model?
	assert(station, "Workspace.Station is missing: build assets/Station.rbxm with tools/build")
	World.station = station

	for _, instance in tagged("Device") do
		local id = instance:GetAttribute("DeviceId")
		if type(id) == "string" and instance:IsA("BasePart") then
			World.devices[id] = instance
		end
	end
	for _, instance in tagged("TapeSlot") do
		local id = instance:GetAttribute("SlotId")
		if type(id) == "string" and instance:IsA("BasePart") then
			World.slots[id] = instance
		end
	end
	for _, instance in tagged("SecurityCamera") do
		local id = instance:GetAttribute("CamId")
		if type(id) == "number" and instance:IsA("BasePart") then
			World.cameras[id] = instance
		end
	end
	for _, instance in tagged("Monitor") do
		if instance:IsA("Model") then
			table.insert(World.monitors, instance)
		end
	end
	for _, instance in tagged("Door") do
		local id = instance:GetAttribute("DoorId")
		if type(id) == "string" and instance:IsA("Model") then
			World.doors[id] = instance
		end
	end
	for _, instance in tagged("AnchorNode") do
		if instance:IsA("BasePart") then
			table.insert(World.nodes, instance)
			local zone = Layout.zoneAt(instance.Position.X, instance.Position.Y, instance.Position.Z)
			World.nodesByZone[zone] = World.nodesByZone[zone] or {}
			table.insert(World.nodesByZone[zone], instance)
		end
	end
	for _, instance in tagged("AmbientEmitter") do
		if instance:IsA("BasePart") then
			table.insert(World.emitters, instance)
		end
	end
	for _, instance in station:GetDescendants() do
		if
			instance:IsA("BasePart")
			and (
				string.match(instance.Name, "^Spawn_")
				or instance.Name == "TakenHoldPoint"
				or instance.Name == "RadioSpeaker"
				or string.match(instance.Name, "^AnchorStage_")
				or instance.Name == "TitleCamera"
				or instance.Name == "EndingCamera"
			)
		then
			World.markers[instance.Name] = instance
		end
	end
	local zones = station:FindFirstChild("Zones")
	if zones then
		for _, folder in zones:GetChildren() do
			World.zoneFolders[folder.Name] = folder
		end
	end
	-- Markers and nodes are invisible, non-colliding helpers.
	for _, list in { World.nodes, World.emitters } do
		for _, part in list do
			part.Transparency = 1
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
		end
	end
end

function World.zoneOf(position: Vector3): string
	return Layout.zoneAt(position.X, position.Y, position.Z)
end

function World.rootOf(player: Player): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

function World.positionOf(player: Player): Vector3?
	local root = World.rootOf(player)
	return if root then root.Position else nil
end

function World.teleport(player: Player, cf: CFrame)
	local character = player.Character
	if character then
		character:PivotTo(cf + Vector3.new(0, 2.6, 0))
	end
end

function World.marker(name: string): BasePart?
	return World.markers[name]
end

-- Spawn markers with the given prefix, ordered by name.
function World.spawns(prefix: string): { BasePart }
	local list = {}
	for name, part in World.markers do
		if string.sub(name, 1, #prefix) == prefix then
			table.insert(list, part)
		end
	end
	table.sort(list, function(a, b)
		return a.Name < b.Name
	end)
	return list
end

function World.playersNear(position: Vector3, radius: number): { Player }
	local list = {}
	for _, player in Players:GetPlayers() do
		local p = World.positionOf(player)
		if p and (p - position).Magnitude <= radius then
			table.insert(list, player)
		end
	end
	return list
end

function World.monitorsInZone(zone: string): { Model }
	local list = {}
	for _, monitor in World.monitors do
		if monitor:GetAttribute("Zone") == zone then
			table.insert(list, monitor)
		end
	end
	return list
end

-- Sets an attribute on a zone folder (the client mirrors light/monitor state from these).
function World.setZoneAttribute(zone: string, name: string, value: any)
	local folder = World.zoneFolders[zone]
	if folder and folder:GetAttribute(name) ~= value then
		folder:SetAttribute(name, value)
	end
end

function World.zoneAttribute(zone: string, name: string): any
	local folder = World.zoneFolders[zone]
	return if folder then folder:GetAttribute(name) else nil
end

local centers: { [string]: any } = {}
function World.zoneCenter(zone: string): Vector3?
	local cached = centers[zone]
	if cached == nil then
		local bounds = Layout.zoneBounds(zone)
		cached = if bounds ~= nil
			then Vector3.new((bounds.minX + bounds.maxX) / 2, bounds.y + 3, (bounds.minZ + bounds.maxZ) / 2)
			else false
		centers[zone] = cached
	end
	return if cached then cached else nil
end

-- True when a straight line between two points is not blocked by walls/doors/props.
function World.lineOfSight(from: Vector3, to: Vector3, ignore: { Instance }): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.IgnoreWater = true
	local result = Workspace:Raycast(from, to - from, params)
	return result == nil
end

return World
