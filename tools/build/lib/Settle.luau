--[[
	Settling pass: dressing is authored on a 4-stud plan, so a prop placed "against the wall" can
	end up a few tenths of a stud inside the wall skin. Before validation, every prop model under
	Station/Zones that penetrates a Wall part is pushed out along that wall's normal. Prop/prop
	overlaps and door clearances are NOT resolved here; the validator still reports those.
]]

local roblox = require("@lune/roblox")
local Geometry = require("../../validate/Geometry")

local Settle = {}

local MARGIN = 0.03

local function ownerUnder(part: any, root: any): any?
	local node = part
	while node.Parent and node.Parent ~= root do
		if node.Parent.ClassName == "Folder" and node.ClassName ~= "Folder" then
			return node
		end
		node = node.Parent
	end
	return nil
end

local function thinAxis(box: Geometry.Box): any
	local best, bestHalf = 1, box.half[1]
	for i = 2, 3 do
		if box.half[i] < bestHalf then
			best, bestHalf = i, box.half[i]
		end
	end
	return box.axes[best]
end

local function move(owner: any, delta: any)
	local list = if owner:IsA("BasePart") then { owner } else {}
	for _, d in owner:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(list, d)
		end
	end
	for _, p in list do
		p.CFrame = p.CFrame + delta
	end
end

function Settle.run(zonesFolder: any, registry: { { part: any, role: string } }): number
	local walls = {}
	local props = {}
	for _, entry in registry do
		local part = entry.part
		if part.CanCollide and part:HasTag("Wall") then
			table.insert(walls, { part = part, box = Geometry.fromPart(part) })
		elseif part.CanCollide and entry.role == "Prop" and part:IsDescendantOf(zonesFolder) then
			table.insert(props, part)
		end
	end
	local wallGrid = Geometry.hash(walls, 8)

	local moved = 0
	for _ = 1, 3 do
		-- Gather per-owner push vectors (largest push per direction wins).
		local pushes: { [string]: { owner: any, delta: any } } = {}
		for _, part in props do
			local owner = ownerUnder(part, zonesFolder) or part
			local box = Geometry.fromPart(part)
			local seen = {}
			for gx = math.floor(box.min.X / 8), math.floor(box.max.X / 8) do
				for gz = math.floor(box.min.Z / 8), math.floor(box.max.Z / 8) do
					for _, index in wallGrid[gx .. ":" .. gz] or {} do
						if not seen[index] then
							seen[index] = true
							local wall = walls[index]
							if Geometry.aabbOverlap(box, wall.box, 0.01) then
								local depth = Geometry.penetration(box, wall.box)
								if depth > 0.01 then
									local axis = thinAxis(wall.box)
									local side = if (box.center - wall.box.center):Dot(axis) >= 0 then 1 else -1
									local delta = axis * side * (depth + MARGIN)
									local key = owner:GetAttribute("__uid") and tostring(owner:GetAttribute("__uid"))
										or owner:GetFullName() .. tostring(owner.CFrame.Position)
									local current = pushes[key]
									if not current then
										pushes[key] = { owner = owner, delta = delta }
									else
										-- Combine per axis, keeping the larger magnitude component.
										local c = current.delta
										local function pick(a: number, b: number): number
											return if math.abs(b) > math.abs(a) then b else a
										end
										current.delta = roblox.Vector3.new(
											pick(c.X, delta.X),
											pick(c.Y, delta.Y),
											pick(c.Z, delta.Z)
										)
									end
								end
							end
						end
					end
				end
			end
		end
		local any = false
		for _, push in pushes do
			move(push.owner, push.delta)
			moved += 1
			any = true
		end
		if not any then
			break
		end
	end
	return moved
end

-- Closed door leaves that run into a perpendicular wall skin at a corner are trimmed on that side.
function Settle.trimLeaves(doorsFolder: any, registry: { { part: any, role: string } }): number
	local walls = {}
	for _, entry in registry do
		if entry.part.CanCollide and entry.part:HasTag("Wall") then
			table.insert(walls, Geometry.fromPart(entry.part))
		end
	end
	local trimmed = 0
	for _, leaf in doorsFolder:GetDescendants() do
		if leaf:IsA("BasePart") and leaf:HasTag("DoorLeaf") then
			for _, wall in walls do
				local box = Geometry.fromPart(leaf)
				if Geometry.aabbOverlap(box, wall, 0.01) then
					local depth = Geometry.penetration(box, wall)
					if depth > 0.01 then
						local cut = depth + MARGIN
						local right = leaf.CFrame.RightVector
						local side = if (box.center - wall.center):Dot(right) >= 0 then 1 else -1
						leaf.Size = roblox.Vector3.new(leaf.Size.X - cut, leaf.Size.Y, leaf.Size.Z)
						leaf.CFrame = leaf.CFrame + right * side * (cut / 2)
						trimmed += 1
					end
				end
			end
		end
	end
	return trimmed
end

return Settle
