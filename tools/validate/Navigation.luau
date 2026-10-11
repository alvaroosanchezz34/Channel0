--[[
	Coarse walkability grid (1 stud) per floor, built from colliding geometry in the walking band.
	Used to verify every room is reachable from the entrance and to place THE ANCHOR's nodes in
	open floor space.
]]

local Geometry = require("./Geometry")
local Layout = require("../../src/shared/Content/StationLayout")

local Navigation = {}

local MIN_X, MAX_X = Layout.Origin.x, Layout.Origin.x + Layout.Width * Layout.CellSize
local MIN_Z, MAX_Z = Layout.Origin.z, Layout.Origin.z + Layout.Depth * Layout.CellSize

export type Grid = { floor: string, y: number, blocked: { [number]: boolean }, w: number, d: number }

local function index(x: number, z: number, w: number): number
	return z * w + x
end

local function inside(box: Geometry.Box, point: any): boolean
	local d = point - box.center
	for i = 1, 3 do
		if math.abs(d:Dot(box.axes[i])) > box.half[i] then
			return false
		end
	end
	return true
end

function Navigation.build(registry: { { part: any, role: string } }, floorId: string): Grid
	local roblox = require("@lune/roblox")
	local Vector3 = roblox.Vector3
	local floorY = Layout.Floors[floorId].y
	local w = MAX_X - MIN_X
	local d = MAX_Z - MIN_Z
	local blocked = {}
	for _, entry in registry do
		local part = entry.part
		local role = entry.role
		local blocking = (
			role == "Structure"
			or role == "Prop"
			or role == "Trim"
			or role == "Glass"
			or role == "Dynamic"
		)
			and part.CanCollide
			and not part:HasTag("Floor")
			and not part:HasTag("Ceiling")
			and not part:HasTag("Stair")
			and not part:HasTag("DoorLeaf")
		if blocking and part.Parent then
			local box = Geometry.fromPart(part)
			-- Only parts that intersect the walking band of this floor.
			if box.max.Y > floorY + 0.6 and box.min.Y < floorY + 5 then
				for x = math.max(0, math.floor(box.min.X - MIN_X)), math.min(w - 1, math.floor(box.max.X - MIN_X)) do
					for z = math.max(0, math.floor(box.min.Z - MIN_Z)), math.min(d - 1, math.floor(box.max.Z - MIN_Z)) do
						local px, pz = MIN_X + x + 0.5, MIN_Z + z + 0.5
						for _, hy in { 1.2, 2.6, 4.2 } do
							if inside(box, Vector3.new(px, floorY + hy, pz)) then
								blocked[index(x, z, w)] = true
								break
							end
						end
					end
				end
			end
		end
	end
	-- Cells outside any room on this floor are not walkable (except the ground-floor exterior apron,
	-- which BFS never needs: the entrance is inside the Lobby).
	for x = 0, w - 1 do
		for z = 0, d - 1 do
			local zone = Layout.zoneAt(MIN_X + x + 0.5, floorY + 1, MIN_Z + z + 0.5)
			if zone == "Exterior" then
				blocked[index(x, z, w)] = true
			end
		end
	end
	return { floor = floorId, y = floorY, blocked = blocked, w = w, d = d }
end

function Navigation.free(grid: Grid, x: number, z: number, radius: number): boolean
	for dx = -radius, radius do
		for dz = -radius, radius do
			local cx, cz = x + dx, z + dz
			if cx < 0 or cz < 0 or cx >= grid.w or cz >= grid.d or grid.blocked[index(cx, cz, grid.w)] then
				return false
			end
		end
	end
	return true
end

function Navigation.worldToGrid(x: number, z: number): (number, number)
	return math.floor(x - MIN_X), math.floor(z - MIN_Z)
end

function Navigation.gridToWorld(x: number, z: number): (number, number)
	return MIN_X + x + 0.5, MIN_Z + z + 0.5
end

-- Flood fill from a world point using an agent of the given radius (cells).
function Navigation.reach(grid: Grid, startX: number, startZ: number, radius: number): { [number]: boolean }
	local sx, sz = Navigation.worldToGrid(startX, startZ)
	local seen = {}
	if not Navigation.free(grid, sx, sz, radius) then
		return seen
	end
	local queue = { { sx, sz } }
	seen[index(sx, sz, grid.w)] = true
	local head = 1
	while head <= #queue do
		local cell = queue[head]
		head += 1
		for _, step in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
			local nx, nz = cell[1] + step[1], cell[2] + step[2]
			local key = index(nx, nz, grid.w)
			if not seen[key] and Navigation.free(grid, nx, nz, radius) then
				seen[key] = true
				table.insert(queue, { nx, nz })
			end
		end
	end
	return seen
end

function Navigation.index(grid: Grid, x: number, z: number): number
	return index(x, z, grid.w)
end

return Navigation
