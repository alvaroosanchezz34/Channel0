--[[
	Building shell from StationLayout: floor slabs, ceilings, wall skins, openings (doors, windows),
	door frames, door leaves, stairs and the exterior envelope.
]]

local B = require("./B")
local Layout = require("../../../src/shared/Content/StationLayout")

local Vector3, CFrame, Color3, Enum = B.Vector3, B.CFrame, B.Color3, B.Enum
local C = B.Colors

local Shell = {}

local CELL = Layout.CellSize
local HALF_T = Layout.WallThickness / 2
local DOOR_H = 8
local OPEN_H = 9.5
local SILL_H = 3
local WIN_TOP = 7.6

local materialOf = {
	Concrete = Enum.Material.Concrete,
	SmoothPlastic = Enum.Material.SmoothPlastic,
	Marble = Enum.Material.Marble,
	Fabric = Enum.Material.Fabric,
	Carpet = Enum.Material.Carpet,
	WoodPlanks = Enum.Material.WoodPlanks,
	Wood = Enum.Material.Wood,
	DiamondPlate = Enum.Material.DiamondPlate,
	Brick = Enum.Material.Brick,
	Slate = Enum.Material.Slate,
}

-- Per-zone wall colour gives each room an identity even under the VHS grade.
local wallColorOf = {
	Lobby = C.WoodPanel,
	Security = C.WallBeige,
	MainHall = C.WallBeige,
	WestCorridor = C.WallGreen,
	EastCorridor = C.WallGreen,
	CableCorridor = C.ConcreteDark,
	StudioA = C.Fabric,
	MasterControl = C.WallBlue,
	Editing = C.WoodPanel,
	TapeArchive = C.Concrete,
	Offices = C.WallBeige,
	Lockers = C.WallGreen,
	Stairwell = C.Concrete,
	Workshop = C.Brick,
	Transmitter = C.ConcreteDark,
	AntennaAccess = C.Brick,
	BasementHall = C.ConcreteDark,
	BoilerRoom = C.Brick,
	GeneratorRoom = C.Concrete,
	Electrical = C.Concrete,
	StudioB = C.Charred,
}

local floorColorOf = {
	Concrete = C.Concrete,
	Marble = C.Marble,
	Carpet = C.Carpet,
	DiamondPlate = C.Metal,
	Slate = C.Tile,
	WoodPlanks = C.Charred,
}

local function room(floorId: string, key: string?): any
	if not key then
		return nil
	end
	return Layout.Floors[floorId].rooms[key]
end

-- Greedy merge of a floor's cells into rectangles per room key.
function Shell.rects(
	floorId: string,
	accept: ((key: string, cx: number, cz: number) -> boolean)?
): { { key: string, x0: number, z0: number, x1: number, z1: number } }
	local floor = Layout.Floors[floorId]
	local used = {}
	local rects = {}
	for cz = 0, Layout.Depth - 1 do
		for cx = 0, Layout.Width - 1 do
			local key = Layout.roomKeyAt(floorId, cx, cz)
			local id = cz * 100 + cx
			if key and not used[id] and (not accept or accept(key, cx, cz)) then
				-- Grow right, then down.
				local x1 = cx
				while
					x1 + 1 < Layout.Width
					and Layout.roomKeyAt(floorId, x1 + 1, cz) == key
					and not used[cz * 100 + x1 + 1]
					and (not accept or accept(key, x1 + 1, cz))
				do
					x1 += 1
				end
				local z1 = cz
				local canGrow = true
				while canGrow and z1 + 1 < Layout.Depth do
					for x = cx, x1 do
						if
							Layout.roomKeyAt(floorId, x, z1 + 1) ~= key
							or used[(z1 + 1) * 100 + x]
							or (accept and not accept(key, x, z1 + 1))
						then
							canGrow = false
							break
						end
					end
					if canGrow then
						z1 += 1
					end
				end
				for z = cz, z1 do
					for x = cx, x1 do
						used[z * 100 + x] = true
					end
				end
				table.insert(rects, { key = key, x0 = cx, z0 = cz, x1 = x1 + 1, z1 = z1 + 1 })
			end
		end
	end
	local _ = floor
	return rects
end

function Shell.floorsAndCeilings(parent: any)
	for floorId, floor in Layout.Floors do
		local y = floor.y
		local isStairShaft = function(key: string): boolean
			return floorId == "Ground" and key == "D"
		end
		for _, r in Shell.rects(floorId) do
			local def = room(floorId, r.key)
			local wx0, wz0 = Layout.cellToWorld(r.x0, r.z0)
			local wx1, wz1 = Layout.cellToWorld(r.x1, r.z1)
			if not isStairShaft(r.key) then
				B.box(Vector3.new(wx0, y - 1, wz0), Vector3.new(wx1, y, wz1), {
					parent = parent,
					name = "Floor_" .. def.zone,
					role = "Structure",
					material = materialOf[def.floorMaterial] or Enum.Material.Concrete,
					color = floorColorOf[def.floorMaterial] or C.Concrete,
					tags = { "Floor" },
				})
			end
			if def.ceiling then
				B.box(Vector3.new(wx0, y + def.height, wz0), Vector3.new(wx1, y + def.height + 1, wz1), {
					parent = parent,
					name = "Ceiling_" .. def.zone,
					role = "Structure",
					material = if def.zone == "StudioA" then Enum.Material.Metal else Enum.Material.SmoothPlastic,
					color = if def.zone == "StudioA" then C.CeilingDark else C.Ceiling,
					tags = { "Ceiling" },
				})
			end
		end
	end
end

-- Opening lookup: which unit wall segments are doors/windows.
-- Key: floor|axis|lineIndex|cellIndex  (axis "X" = wall runs along X at z line; "Z" = along Z at x line)
local function openingKey(floorId: string, axis: string, line: number, index: number): string
	return `{floorId}|{axis}|{line}|{index}`
end

function Shell.openingIndex(): { [string]: any }
	local index = {}
	for _, opening in Layout.Openings do
		local ax, az = opening.a[1], opening.a[2]
		local bx, bz = opening.b[1], opening.b[2]
		for i = 0, opening.width - 1 do
			if az == bz then
				-- Neighbours along X: wall runs along Z at x line = max(ax,bx)
				local line = math.max(ax, bx)
				index[openingKey(opening.floor, "Z", line, az + i)] = { opening = opening, part = i }
			else
				local line = math.max(az, bz)
				index[openingKey(opening.floor, "X", line, ax + i)] = { opening = opening, part = i }
			end
		end
	end
	return index
end

local exteriorMaterial = Enum.Material.Brick

-- Builds a wall run (one side skin) between two world points along an axis.
local function skin(
	parent: any,
	axis: string,
	line: number,
	from: number,
	to: number,
	side: number,
	y0: number,
	y1: number,
	material: any,
	color: any,
	name: string
)
	if to - from <= 0.01 or y1 - y0 <= 0.01 then
		return
	end
	-- side = -1 (the low side of the line) or +1
	local center = line + side * HALF_T / 2
	local size, pos
	if axis == "X" then
		size = Vector3.new(to - from, y1 - y0, HALF_T)
		pos = Vector3.new((from + to) / 2, (y0 + y1) / 2, center)
	else
		size = Vector3.new(HALF_T, y1 - y0, to - from)
		pos = Vector3.new(center, (y0 + y1) / 2, (from + to) / 2)
	end
	B.part({
		parent = parent,
		name = name,
		size = size,
		cf = CFrame.new(pos),
		material = material,
		color = color,
		role = "Structure",
		tags = { "Wall" },
	})
end

-- Walls with openings. Returns opening placements for frames/doors.
function Shell.walls(parent: any): { any }
	local openings = Shell.openingIndex()
	local placements = {}
	local placed = {}

	for floorId, floor in Layout.Floors do
		local y = floor.y
		local function groupOf(key: string?): string?
			local def = room(floorId, key)
			return if def then def.group else nil
		end
		local function heightOf(key: string?): number
			local def = room(floorId, key)
			return if def then def.height else 0
		end

		-- Collect unit segments for both axes.
		for _, axis in { "X", "Z" } do
			local lines = if axis == "X" then Layout.Depth else Layout.Width
			local cells = if axis == "X" then Layout.Width else Layout.Depth
			for line = 0, lines do
				-- Runs are accumulated per side while properties stay equal.
				local runs = {}
				for index = 0, cells - 1 do
					local ka, kb
					if axis == "X" then
						ka = Layout.roomKeyAt(floorId, index, line - 1)
						kb = Layout.roomKeyAt(floorId, index, line)
					else
						ka = Layout.roomKeyAt(floorId, line - 1, index)
						kb = Layout.roomKeyAt(floorId, line, index)
					end
					local ga, gb = groupOf(ka), groupOf(kb)
					if (ga or gb) and ga ~= gb then
						local h = math.max(heightOf(ka), heightOf(kb))
						local o = openings[openingKey(floorId, axis, line, index)]
						table.insert(runs, { index = index, ka = ka, kb = kb, height = h, opening = o })
						if o and not placed[o.opening.id] then
							placed[o.opening.id] = true
							table.insert(placements, {
								opening = o.opening,
								axis = axis,
								line = line,
								index = index,
								floorId = floorId,
								height = h,
								ka = ka,
								kb = kb,
							})
						end
					end
				end

				-- Emit merged skins per side; openings split runs vertically.
				local function emitSide(side: number)
					local i = 1
					while i <= #runs do
						local first = runs[i]
						local key = if side < 0 then first.ka else first.kb
						local def = room(floorId, key)
						local j = i
						while j + 1 <= #runs do
							local nxt = runs[j + 1]
							local nkey = if side < 0 then nxt.ka else nxt.kb
							if
								nxt.index ~= runs[j].index + 1
								or nkey ~= key
								or nxt.height ~= first.height
								or (nxt.opening ~= nil) ~= (first.opening ~= nil)
							then
								break
							end
							if nxt.opening and first.opening and nxt.opening.opening ~= first.opening.opening then
								break
							end
							j += 1
						end
						local from = (if axis == "X" then Layout.Origin.x else Layout.Origin.z) + first.index * CELL
						local to = (if axis == "X" then Layout.Origin.x else Layout.Origin.z)
							+ (runs[j].index + 1) * CELL
						local lineWorld = (if axis == "X" then Layout.Origin.z else Layout.Origin.x) + line * CELL
						local material, color, label
						if def then
							material = materialOf[def.wallMaterial] or Enum.Material.SmoothPlastic
							color = wallColorOf[def.zone] or C.WallGrey
							label = "Wall_" .. def.zone
						else
							material = exteriorMaterial
							color = C.Brick
							label = "Wall_Exterior"
						end
						-- Extend X runs over junction columns so outer corners have no notch, but never
						-- into a doorway or window next to the run.
						if axis == "X" and not first.opening then
							local before = runs[i - 1]
							local after = runs[j + 1]
							local openBefore = before ~= nil
								and before.index == first.index - 1
								and before.opening ~= nil
							local openAfter = after ~= nil and after.index == runs[j].index + 1 and after.opening ~= nil
							if not openBefore then
								from -= HALF_T
							end
							if not openAfter then
								to += HALF_T
							end
						end
						local h = first.height
						if first.opening then
							local kind = first.opening.opening.kind
							local top = if kind == "Window" then WIN_TOP elseif kind == "Open" then OPEN_H else DOOR_H
							skin(
								parent,
								axis,
								lineWorld,
								from,
								to,
								side,
								y + top,
								y + h,
								material,
								color,
								label .. "_Lintel"
							)
							if kind == "Window" then
								skin(
									parent,
									axis,
									lineWorld,
									from,
									to,
									side,
									y,
									y + SILL_H,
									material,
									color,
									label .. "_Sill"
								)
							end
						else
							skin(parent, axis, lineWorld, from, to, side, y, y + h, material, color, label)
						end
						i = j + 1
					end
				end
				emitSide(-1)
				emitSide(1)
			end
		end
	end
	return placements
end

-- Frames, glass and door leaves for each opening.
function Shell.openings(parent: any, doorsFolder: any, placements: { any })
	for _, p in placements do
		local o = p.opening
		local floorY = Layout.Floors[p.floorId].y
		local width = o.width * CELL
		local lineWorld = (if p.axis == "X" then Layout.Origin.z else Layout.Origin.x) + p.line * CELL
		local startWorld = (if p.axis == "X" then Layout.Origin.x else Layout.Origin.z) + p.index * CELL
		local centerAlong = startWorld + width / 2
		-- Frame orientation: local X along the wall, local Z across it.
		local yaw = if p.axis == "X" then 0 else 90
		local cx = if p.axis == "X" then centerAlong else lineWorld
		local cz = if p.axis == "X" then lineWorld else centerAlong
		local base = B.at(cx, floorY, cz, yaw)
		local top = if o.kind == "Window" then WIN_TOP elseif o.kind == "Open" then OPEN_H else DOOR_H
		local bottom = if o.kind == "Window" then SILL_H else 0
		local frameColor = if o.kind == "Window" then C.MetalDark else C.WoodPanel
		local frameMat = if o.kind == "Window" then Enum.Material.Metal else Enum.Material.Wood
		local depth = Layout.WallThickness + 0.3

		local frame = B.model("Frame_" .. o.id, parent)
		-- Jambs and head.
		B.part({
			parent = frame,
			name = "JambL",
			role = "Trim",
			size = Vector3.new(0.35, top - bottom, depth),
			cf = B.off(base, -width / 2 + 0.175, bottom + (top - bottom) / 2, 0),
			color = frameColor,
			material = frameMat,
		})
		B.part({
			parent = frame,
			name = "JambR",
			role = "Trim",
			size = Vector3.new(0.35, top - bottom, depth),
			cf = B.off(base, width / 2 - 0.175, bottom + (top - bottom) / 2, 0),
			color = frameColor,
			material = frameMat,
		})
		B.part({
			parent = frame,
			name = "Head",
			role = "Trim",
			size = Vector3.new(width, 0.35, depth),
			cf = B.off(base, 0, top - 0.175, 0),
			color = frameColor,
			material = frameMat,
		})
		if o.kind == "Window" then
			B.part({
				parent = frame,
				name = "SillBoard",
				role = "Trim",
				size = Vector3.new(width, 0.2, depth + 0.3),
				cf = B.off(base, 0, bottom + 0.1, 0),
				color = frameColor,
				material = frameMat,
			})
			B.part({
				parent = frame,
				name = "Glass",
				role = "Glass",
				size = Vector3.new(width - 0.7, top - bottom - 0.55, 0.12),
				cf = B.off(base, 0, bottom + 0.2 + (top - bottom - 0.55) / 2, 0),
				color = C.Glass,
				material = Enum.Material.Glass,
				transparency = 0.55,
				reflectance = 0.08,
			})
			-- Mullions on wide windows.
			for m = 1, o.width - 1 do
				B.part({
					parent = frame,
					name = "Mullion",
					role = "Trim",
					size = Vector3.new(0.18, top - bottom - 0.5, 0.25),
					cf = B.off(base, -width / 2 + m * CELL, bottom + (top - bottom) / 2, 0),
					color = frameColor,
					material = frameMat,
				})
			end
		end

		if o.label then
			local sign = B.part({
				parent = frame,
				name = "Sign",
				role = "Detail",
				size = Vector3.new(math.min(width, 3.6), 0.6, 0.08),
				cf = B.off(base, 0, top + 0.7, -(depth / 2 + 0.05)),
				color = C.PlasticBlack,
				material = Enum.Material.SmoothPlastic,
			})
			B.label(
				sign,
				Enum.NormalId.Front,
				o.label,
				{ color = Color3.fromRGB(230, 226, 210), font = Enum.Font.Arcade, ppu = 60 }
			)
			local sign2 = B.part({
				parent = frame,
				name = "Sign",
				role = "Detail",
				size = Vector3.new(math.min(width, 3.6), 0.6, 0.08),
				cf = B.off(base, 0, top + 0.7, depth / 2 + 0.05, 180),
				color = C.PlasticBlack,
				material = Enum.Material.SmoothPlastic,
			})
			B.label(
				sign2,
				Enum.NormalId.Front,
				o.label,
				{ color = Color3.fromRGB(230, 226, 210), font = Enum.Font.Arcade, ppu = 60 }
			)
		end

		if o.kind ~= "Window" and o.kind ~= "Open" then
			Shell.doorLeaves(doorsFolder, o, base, width, p)
		end
	end
end

-- Door leaves. Each leaf is a Model with an invisible Hinge (PrimaryPart) the server rotates.
function Shell.doorLeaves(folder: any, o: any, base: any, width: number, placement: any)
	local leaves = if o.kind == "Double" then 2 else 1
	local leafWidth = (width - 0.7) / leaves
	local metal = o.kind == "Exit" or o.kind == "Locked" or o.id == "StudioHall" or o.id == "StairsHall"
	local color = if metal then C.MetalDark elseif o.kind == "Sealed" then C.WoodLight else C.WoodLight
	local material = if metal then Enum.Material.Metal else Enum.Material.Wood
	local doorModel = B.model("Door_" .. o.id, folder)
	doorModel:SetAttribute("DoorId", o.id)
	doorModel:SetAttribute("Kind", o.kind)
	doorModel:SetAttribute("Floor", placement.floorId)
	doorModel:AddTag("Door")
	local zoneA = room(placement.floorId, placement.ka)
	local zoneB = room(placement.floorId, placement.kb)
	doorModel:SetAttribute("ZoneA", if zoneA then zoneA.zone else "Exterior")
	doorModel:SetAttribute("ZoneB", if zoneB then zoneB.zone else "Exterior")

	for i = 1, leaves do
		local sideSign = if i == 1 then -1 else 1
		local hingeX = sideSign * (width / 2 - 0.35)
		local hinge = B.part({
			parent = doorModel,
			name = "Hinge" .. i,
			role = "Marker",
			size = Vector3.new(0.2, DOOR_H - 0.4, 0.2),
			cf = B.off(base, hingeX, (DOOR_H - 0.35) / 2, 0),
		})
		local leafCenter = hingeX - sideSign * leafWidth / 2
		B.part({
			parent = doorModel,
			name = "Leaf" .. i,
			role = "Dynamic",
			size = Vector3.new(leafWidth - 0.05, DOOR_H - 0.45, 0.28),
			cf = B.off(base, leafCenter, (DOOR_H - 0.35) / 2, 0),
			color = color,
			material = material,
			tags = { "DoorLeaf" },
			attributes = { DoorId = o.id, Leaf = i },
		})
		-- Handle on both faces.
		for _, face in { -1, 1 } do
			B.part({
				parent = doorModel,
				name = "Handle",
				role = "Detail",
				size = Vector3.new(0.5, 0.12, 0.12),
				cf = B.off(base, leafCenter - sideSign * (leafWidth / 2 - 0.45), 3.4, face * 0.22),
				color = C.Metal,
				material = Enum.Material.Metal,
				props = { Name = "Handle" },
			})
		end
		if o.id == "StudioHall" or o.id == "MCRStudio" then
			-- Studio doors: small wired-glass window and an ON AIR lamp above.
			B.part({
				parent = doorModel,
				name = "Porthole",
				role = "Detail",
				size = Vector3.new(0.9, 1.2, 0.3),
				cf = B.off(base, leafCenter, 5.2, 0),
				color = C.Glass,
				material = Enum.Material.Glass,
				transparency = 0.5,
			})
		end
		hinge:SetAttribute("Leaf", i)
		hinge:SetAttribute("Swing", sideSign)
	end

	if o.kind == "Sealed" then
		-- Boards nailed across the doorway; removed when Studio B is unsealed.
		local boards = B.model("Boards", doorModel)
		for k = 0, 4 do
			local tilt = (k % 2 == 0) and 7 or -6
			B.part({
				parent = boards,
				name = "Board",
				role = "Dynamic",
				size = Vector3.new(width + 0.6, 0.55, 0.18),
				cf = B.off(base, 0, 1.3 + k * 1.45, -0.75) * CFrame.Angles(0, 0, math.rad(tilt)),
				color = C.WoodLight,
				material = Enum.Material.WoodPlanks,
			})
		end
		local plaque = B.part({
			parent = boards,
			name = "Paint",
			role = "Detail",
			size = Vector3.new(3.4, 1.4, 0.05),
			cf = B.off(base, 0, 4.7, -0.87),
			color = C.WoodLight,
			material = Enum.Material.WoodPlanks,
			transparency = 1,
		})
		B.label(
			plaque,
			Enum.NormalId.Front,
			"STUDIO B — NO ENTRY — 10/87",
			{ color = Color3.fromRGB(150, 20, 20), font = Enum.Font.Fantasy }
		)
	elseif o.kind == "Locked" then
		-- Chained fire exit: a landmark, never opens.
		B.part({
			parent = doorModel,
			name = "Chain",
			role = "Detail",
			size = Vector3.new(width - 0.4, 0.2, 0.2),
			cf = B.off(base, 0, 3.6, -0.3),
			color = C.Metal,
			material = Enum.Material.Metal,
		})
		B.part({
			parent = doorModel,
			name = "Padlock",
			role = "Detail",
			size = Vector3.new(0.35, 0.45, 0.2),
			cf = B.off(base, 0, 3.3, -0.42),
			color = C.SafetyYellow,
			material = Enum.Material.Metal,
		})
		local exit = B.part({
			parent = doorModel,
			name = "ExitSign",
			role = "Detail",
			size = Vector3.new(2, 0.7, 0.2),
			cf = B.off(base, 0, DOOR_H + 1.1, -0.7),
			color = C.PlasticBlack,
			material = Enum.Material.SmoothPlastic,
		})
		B.label(
			exit,
			Enum.NormalId.Front,
			"EXIT",
			{ color = Color3.fromRGB(200, 40, 30), font = Enum.Font.Arcade, lightInfluence = 0 }
		)
		B.pointLight(exit, { color = Color3.fromRGB(255, 60, 40), brightness = 0.6, range = 7 })
	end
end

-- Switchback stairs from the ground-floor Stairwell (D) down to the basement (d).
function Shell.stairs(parent: any)
	local b = Layout.zoneBounds("Stairwell")
	assert(b, "Stairwell zone missing")
	-- Ground-floor footprint of D (zoneBounds returns the first floor found; recompute explicitly).
	local x0, z0 = Layout.cellToWorld(20, 12)
	local x1, z1 = Layout.cellToWorld(23, 17)
	local mid = x0 + (x1 - x0) / 2
	local folder = B.model("Stairs", parent)
	local concrete = { material = Enum.Material.Concrete, color = C.Concrete, role = "Structure", parent = folder }
	local function block(minV: any, maxV: any, name: string)
		local spec = table.clone(concrete)
		spec.name = name
		spec.tags = { "Stair" }
		B.box(minV, maxV, spec)
	end
	-- Top landing (ground level) across the full width.
	block(Vector3.new(x0, -1, z0), Vector3.new(x1, 0, z0 + 4), "TopLanding")
	-- Flight 1: west half, descending south from y=0 to y=-6 (5 risers + landing).
	for i = 1, 5 do
		local zA = z0 + 4 + (i - 1) * 2
		block(Vector3.new(x0, -12, zA), Vector3.new(mid, -i, zA + 2), "Flight1_Step" .. i)
	end
	-- Mid landing across the full width at y=-6.
	block(Vector3.new(x0, -12, z1 - 6), Vector3.new(x1, -6, z1), "MidLanding")
	-- Flight 2: east half, descending north from -6 to -12.
	for j = 1, 5 do
		local zB = z1 - 6 - j * 2
		block(Vector3.new(mid, -12, zB), Vector3.new(x1, -6 - j, zB + 2), "Flight2_Step" .. j)
	end
	-- Divider between flights, rising to a rail height above the top landing.
	B.box(Vector3.new(mid - 0.25, -12, z0 + 4), Vector3.new(mid + 0.25, 3.5, z1 - 6), {
		parent = folder,
		name = "Divider",
		role = "Structure",
		material = Enum.Material.Concrete,
		color = C.ConcreteDark,
		tags = { "Wall" },
	})
	-- Rail along the top landing edge over the shaft.
	B.box(Vector3.new(mid, 0, z0 + 4 - 0.15), Vector3.new(x1 - 0.5, 3.4, z0 + 4 + 0.15), {
		parent = folder,
		name = "ShaftRail",
		role = "Trim",
		material = Enum.Material.Metal,
		color = C.SafetyYellow,
	})
	-- Handrail detail on the outer walls.
	B.box(
		Vector3.new(x0 + 0.5, -3, z0 + 4),
		Vector3.new(x0 + 0.7, -2.8, z1 - 6),
		{ parent = folder, name = "Handrail", role = "Detail", material = Enum.Material.Metal, color = C.Metal }
	)
	B.box(
		Vector3.new(x1 - 0.7, -9, z0 + 4),
		Vector3.new(x1 - 0.5, -8.8, z1 - 6),
		{ parent = folder, name = "Handrail", role = "Detail", material = Enum.Material.Metal, color = C.Metal }
	)
	-- Floor markings.
	local sign = B.part({
		parent = folder,
		name = "LevelSign",
		role = "Detail",
		size = Vector3.new(2.4, 1.2, 0.1),
		cf = B.at(x0 + 0.56, 5, z0 + 2, 90),
		color = C.SafetyYellow,
		material = Enum.Material.SmoothPlastic,
	})
	B.label(sign, Enum.NormalId.Front, "LEVEL 1  ▼ B1", { font = Enum.Font.Arcade })
	return folder
end

return Shell
