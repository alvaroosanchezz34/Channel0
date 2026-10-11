--[[
	Oriented-box geometry for the offline placement validator: AABBs for broad phase, SAT for the
	exact overlap test with penetration depth (so flush contact is not reported as intersection).
]]

local roblox = require("@lune/roblox")
local Vector3 = roblox.Vector3

local Geometry = {}

export type Box = {
	center: any, -- Vector3
	axes: { any }, -- 3 unit Vector3 (right, up, look-back)
	half: { number }, -- half extents along axes
	min: any,
	max: any,
}

function Geometry.fromPart(part: any): Box
	local cf = part.CFrame
	local size = part.Size
	local right, up, back = cf.RightVector, cf.UpVector, -cf.LookVector
	local hx, hy, hz = size.X / 2, size.Y / 2, size.Z / 2
	local ex = math.abs(right.X) * hx + math.abs(up.X) * hy + math.abs(back.X) * hz
	local ey = math.abs(right.Y) * hx + math.abs(up.Y) * hy + math.abs(back.Y) * hz
	local ez = math.abs(right.Z) * hx + math.abs(up.Z) * hy + math.abs(back.Z) * hz
	local c = cf.Position
	return {
		center = c,
		axes = { right, up, back },
		half = { hx, hy, hz },
		min = Vector3.new(c.X - ex, c.Y - ey, c.Z - ez),
		max = Vector3.new(c.X + ex, c.Y + ey, c.Z + ez),
	}
end

function Geometry.aabbOverlap(a: Box, b: Box, eps: number?): boolean
	local e = eps or 0
	return a.min.X < b.max.X - e
		and a.max.X > b.min.X + e
		and a.min.Y < b.max.Y - e
		and a.max.Y > b.min.Y + e
		and a.min.Z < b.max.Z - e
		and a.max.Z > b.min.Z + e
end

local function project(box: Box, axis: any): number
	return box.half[1] * math.abs(box.axes[1]:Dot(axis))
		+ box.half[2] * math.abs(box.axes[2]:Dot(axis))
		+ box.half[3] * math.abs(box.axes[3]:Dot(axis))
end

-- Returns the minimum penetration depth (<= 0 means separated or touching).
function Geometry.penetration(a: Box, b: Box): number
	local d = b.center - a.center
	local minDepth = math.huge
	local axes = {}
	for i = 1, 3 do
		table.insert(axes, a.axes[i])
		table.insert(axes, b.axes[i])
	end
	for i = 1, 3 do
		for j = 1, 3 do
			local cross = a.axes[i]:Cross(b.axes[j])
			if cross.Magnitude > 1e-4 then
				table.insert(axes, cross.Unit)
			end
		end
	end
	for _, axis in axes do
		local distance = math.abs(d:Dot(axis))
		local depth = project(a, axis) + project(b, axis) - distance
		if depth <= 0 then
			return depth
		end
		if depth < minDepth then
			minDepth = depth
		end
	end
	return minDepth
end

-- Spatial hash of boxes for broad phase.
function Geometry.hash(items: { any }, cell: number): { [string]: { number } }
	local grid = {}
	for index, item in items do
		local b = item.box
		for gx = math.floor(b.min.X / cell), math.floor(b.max.X / cell) do
			for gz = math.floor(b.min.Z / cell), math.floor(b.max.Z / cell) do
				local key = gx .. ":" .. gz
				local bucket = grid[key]
				if not bucket then
					bucket = {}
					grid[key] = bucket
				end
				table.insert(bucket, index)
			end
		end
	end
	return grid
end

return Geometry
