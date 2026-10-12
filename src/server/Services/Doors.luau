--!strict
--[[
	Doors: prompts, swinging leaves around their hinge markers, Studio B's seal, the chained fire
	exit and the main entrance (locked while a shift is running). Leaves carry a
	PathfindingModifier with PassThrough so THE ANCHOR can route through closed doors and open them
	when he arrives, which players hear and see.
]]

local RunService = game:GetService("RunService")

local Registry = require(script.Parent.Registry)
local World = require(script.Parent.World)

local Doors = {}

type Leaf = {
	hinge: BasePart,
	swing: number,
	parts: { { part: BasePart, offset: CFrame } }, -- offset relative to the hinge
	hingeCF: CFrame,
}

type Door = {
	id: string,
	model: Model,
	kind: string,
	leaves: { Leaf },
	open: boolean,
	angle: number,
	target: number,
	direction: number,
	prompt: ProximityPrompt?,
	boards: Instance?,
	sealed: boolean,
	zoneA: string,
	zoneB: string,
	center: Vector3,
	lastToggle: number,
}

Doors.list = {} :: { [string]: Door }
local OPEN_ANGLE = math.rad(92)
local SWING_SPEED = math.rad(240) -- degrees per second

local function promptKeyFor(door: Door): string
	if door.sealed then
		return "prompt.sealed"
	elseif door.kind == "Locked" or (door.id == "LobbyEntrance" and Registry.State.session == "Running") then
		return "prompt.locked"
	end
	return "prompt.door"
end

local function refreshPrompt(door: Door)
	if door.prompt then
		door.prompt:SetAttribute("PromptKey", promptKeyFor(door))
		door.prompt:SetAttribute("Open", door.open)
	end
end

local function setPassThrough(door: Door, enabled: boolean)
	for _, leaf in door.leaves do
		for _, entry in leaf.parts do
			if entry.part:HasTag("DoorLeaf") then
				local modifier = entry.part:FindFirstChildOfClass("PathfindingModifier")
				if enabled and not modifier then
					local m = Instance.new("PathfindingModifier")
					m.PassThrough = true
					m.Parent = entry.part
				elseif not enabled and modifier then
					modifier:Destroy()
				end
			end
		end
	end
end

local function pose(door: Door)
	for _, leaf in door.leaves do
		local rotation = CFrame.Angles(0, leaf.swing * door.direction * door.angle, 0)
		local pivot = leaf.hingeCF * rotation
		for _, entry in leaf.parts do
			entry.part.CFrame = pivot * entry.offset
		end
	end
end

local function build(model: Model)
	local id = model:GetAttribute("DoorId") :: string
	local kind = (model:GetAttribute("Kind") :: string?) or "Door"
	local hinges: { BasePart } = {}
	local leaves: { [number]: BasePart } = {}
	local details: { BasePart } = {}
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") then
			local leafIndex = child:GetAttribute("Leaf")
			if string.match(child.Name, "^Hinge") then
				table.insert(hinges, child)
				child.Transparency = 1
				child.CanCollide = false
				child.CanQuery = false
			elseif child:HasTag("DoorLeaf") and type(leafIndex) == "number" then
				leaves[leafIndex] = child
			else
				table.insert(details, child)
			end
		end
	end
	local door: Door = {
		id = id,
		model = model,
		kind = kind,
		leaves = {},
		open = false,
		angle = 0,
		target = 0,
		direction = 1,
		prompt = nil,
		boards = model:FindFirstChild("Boards"),
		sealed = kind == "Sealed",
		zoneA = (model:GetAttribute("ZoneA") :: string?) or "Exterior",
		zoneB = (model:GetAttribute("ZoneB") :: string?) or "Exterior",
		center = Vector3.zero,
		lastToggle = 0,
	}
	local sum = Vector3.zero
	for _, hinge in hinges do
		local index = hinge:GetAttribute("Leaf") :: number
		local leafPart = leaves[index]
		if leafPart then
			local hingeCF = hinge.CFrame
			local leaf: Leaf = {
				hinge = hinge,
				swing = (hinge:GetAttribute("Swing") :: number?) or 1,
				parts = { { part = leafPart, offset = hingeCF:Inverse() * leafPart.CFrame } },
				hingeCF = hingeCF,
			}
			-- Handles and portholes ride with the nearest leaf.
			for _, detail in details do
				local local_ = leafPart.CFrame:PointToObjectSpace(detail.Position)
				if math.abs(local_.X) <= leafPart.Size.X / 2 + 0.1 and math.abs(local_.Z) <= 0.6 then
					table.insert(leaf.parts, { part = detail, offset = hingeCF:Inverse() * detail.CFrame })
				end
			end
			table.insert(door.leaves, leaf)
			sum += leafPart.Position
		end
	end
	if #door.leaves == 0 then
		return
	end
	door.center = sum / #door.leaves
	local first = door.leaves[1].parts[1].part
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "DoorPrompt"
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt.ActionText = "Door"
	prompt.MaxActivationDistance = 7
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	prompt.Parent = first
	door.prompt = prompt
	prompt.Triggered:Connect(function(player)
		Doors.interact(player, door)
	end)
	if not door.sealed and kind ~= "Locked" then
		setPassThrough(door, true)
	end
	refreshPrompt(door)
	Doors.list[id] = door
end

function Doors.init()
	for _, model in World.doors do
		build(model)
	end
	RunService.Heartbeat:Connect(function(dt)
		for _, door in Doors.list do
			if door.angle ~= door.target then
				local step = SWING_SPEED * dt
				if door.target > door.angle then
					door.angle = math.min(door.target, door.angle + step)
				else
					door.angle = math.max(door.target, door.angle - step)
				end
				pose(door)
			end
		end
	end)
end

local function blocked(door: Door): boolean
	return door.sealed or door.kind == "Locked" or (door.id == "LobbyEntrance" and Registry.State.session == "Running")
end

-- Opens away from `from` (a world position), so a door never swings into the person opening it.
function Doors.setOpen(door: Door, open: boolean, from: Vector3?, silent: boolean?)
	if blocked(door) or door.open == open then
		return
	end
	if open and from and #door.leaves > 0 then
		local leaf = door.leaves[1]
		local localFrom = leaf.hingeCF:PointToObjectSpace(from)
		-- Leaves swing toward -Z for direction 1 (see Shell.doorLeaves); flip to swing away.
		door.direction = if localFrom.Z * leaf.swing < 0 then -1 else 1
	end
	door.open = open
	door.target = if open then OPEN_ANGLE else 0
	door.lastToggle = os.clock()
	refreshPrompt(door)
	if not silent then
		Registry.Session.cueNear(
			door.center,
			70,
			{ kind = "Sound", sound = if open then "DoorOpen" else "DoorClose", position = door.center }
		)
	end
end

function Doors.interact(player: Player, door: Door)
	local member = Registry.State.member(player)
	if not member or (member.status ~= "Active" and member.status ~= "Lobby") then
		return
	end
	local position = World.positionOf(player)
	if not position or (position - door.center).Magnitude > 10 then
		return
	end
	if os.clock() - door.lastToggle < 0.4 then
		return
	end
	if door.sealed then
		Registry.Devices.message(player, "dev.sealed")
		return
	elseif blocked(door) then
		Registry.Devices.message(player, "prompt.locked")
		return
	end
	Doors.setOpen(door, not door.open, position)
end

function Doors.unseal(id: string)
	local door = Doors.list[id]
	if not door or not door.sealed then
		return
	end
	door.sealed = false
	if door.boards then
		door.boards.Parent = nil
	end
	setPassThrough(door, true)
	Doors.setOpen(door, true, nil, true)
	refreshPrompt(door)
end

function Doors.isOpen(id: string): boolean
	local door = Doors.list[id]
	return door ~= nil and door.open
end

-- The Anchor opens closed doors he walks into. Returns true when a door started opening.
function Doors.openNear(position: Vector3, radius: number): boolean
	for _, door in Doors.list do
		if not door.open and not blocked(door) and (door.center - position).Magnitude <= radius then
			Doors.setOpen(door, true, position)
			return true
		end
	end
	return false
end

-- A door nobody is looking at, for the "door changed" subtle event.
function Doors.unobserved(minDistance: number, rng: any): Door?
	local candidates = {}
	for _, door in Doors.list do
		if not blocked(door) and door.id ~= "LobbyEntrance" then
			local near = World.playersNear(door.center, minDistance)
			if #near == 0 then
				table.insert(candidates, door)
			end
		end
	end
	table.sort(candidates, function(a, b)
		return a.id < b.id
	end)
	if #candidates == 0 then
		return nil
	end
	return rng:Pick(candidates)
end

function Doors.refreshPrompts()
	for _, door in Doors.list do
		refreshPrompt(door)
	end
end

function Doors.reset()
	for _, door in Doors.list do
		door.open = false
		door.target = 0
		door.angle = 0
		door.direction = 1
		pose(door)
		if door.kind == "Sealed" then
			door.sealed = true
			if door.boards then
				door.boards.Parent = door.model
			end
			setPassThrough(door, false)
		end
		refreshPrompt(door)
	end
end

return Doors
