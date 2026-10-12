--!strict
--[[
	Screen renderers shared by in-world monitors and full-screen device panels.

	Every renderer draws into a parent GuiObject and returns { update(dt), destroy() }.
	  * bars / card / static / black   cheap 2D screens
	  * scene                          a tape set from Assets.Scenes in a ViewportFrame
	  * feed                           a security camera: real station geometry near the camera,
	                                   cloned once per camera into a ViewportFrame, plus proxies
	                                   for the crew, phantoms and THE ANCHOR from the server's
	                                   FeedDirective
	  * tape                           a deck's timeline (shots, lower thirds, burned-in time code)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local TapeContent = require(Shared.Content.Tapes)

local Make = require(script.Parent.Make)
local Theme = require(script.Parent.Theme)

export type Renderer = { update: (dt: number) -> (), destroy: () -> () }

local Screens = {}

local rng = Random.new()
local noop = function() end

local function base(parent: Instance, color: Color3?): Frame
	return Make.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = color or Color3.new(0, 0, 0),
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Parent = parent,
	})
end

function Screens.black(parent: Instance): Renderer
	local frame = base(parent)
	return {
		update = noop,
		destroy = function()
			frame:Destroy()
		end,
	}
end

function Screens.bars(parent: Instance): Renderer
	local frame = base(parent)
	Make.bars(frame)
	return {
		update = noop,
		destroy = function()
			frame:Destroy()
		end,
	}
end

-- Snow: a handful of stretched strips re-rolled several times a second.
function Screens.static(parent: Instance, strength: number?): Renderer
	local frame = base(parent, Color3.fromRGB(70, 70, 72))
	local strips = {}
	for i = 1, 14 do
		table.insert(
			strips,
			Make.new("Frame", {
				Size = UDim2.new(1, 0, 1 / 14, 1),
				Position = UDim2.fromScale(0, (i - 1) / 14),
				BorderSizePixel = 0,
				Parent = frame,
			})
		)
	end
	local timer = 0
	local s = strength or 1
	return {
		update = function(dt: number)
			timer += dt
			if timer < 0.06 then
				return
			end
			timer = 0
			for _, strip in strips do
				local v = rng:NextNumber(0.2, 0.9)
				strip.BackgroundColor3 = Color3.new(v, v, v)
				strip.BackgroundTransparency = 1 - s * rng:NextNumber(0.3, 0.9)
			end
		end,
		destroy = function()
			frame:Destroy()
		end,
	}
end

function Screens.card(parent: Instance, style: string?, title: string, body: string?): Renderer
	local styleName = style or "StationID"
	local background = if styleName == "Document"
		then Color3.fromRGB(226, 220, 200)
		elseif styleName == "Clue" or styleName == "Time" then Color3.new(0, 0, 0)
		elseif styleName == "Slate" then Theme.Colors.Blue
		else Color3.fromRGB(16, 22, 60)
	local textColor = if styleName == "Document" then Color3.fromRGB(30, 26, 20) else Color3.fromRGB(240, 236, 220)
	local frame = base(parent, background)
	Make.text({
		Text = title,
		Size = UDim2.fromScale(0.9, if body then 0.25 else 0.6),
		Position = UDim2.fromScale(0.05, if body then 0.06 else 0.2),
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = if styleName == "Document" then Enum.Font.Garamond else Theme.FontTitle,
		TextColor3 = textColor,
		Parent = frame,
	})
	if body then
		Make.text({
			Text = body,
			Size = UDim2.fromScale(0.86, 0.6),
			Position = UDim2.fromScale(0.07, 0.34),
			TextScaled = true,
			TextYAlignment = Enum.TextYAlignment.Top,
			Font = if styleName == "Document" then Enum.Font.Garamond else Theme.Font,
			TextColor3 = textColor,
			Parent = frame,
		})
	end
	return {
		update = noop,
		destroy = function()
			frame:Destroy()
		end,
	}
end

local function lowerThird(parent: Instance, text: string)
	local band = Make.new("Frame", {
		Size = UDim2.fromScale(0.62, 0.11),
		Position = UDim2.fromScale(0.06, 0.78),
		BackgroundColor3 = Color3.fromRGB(20, 30, 90),
		BorderSizePixel = 0,
		ZIndex = 5,
		Parent = parent,
	})
	Make.text({
		Text = text,
		Size = UDim2.fromScale(0.94, 0.9),
		Position = UDim2.fromScale(0.03, 0.05),
		TextScaled = true,
		Font = Enum.Font.Arial,
		TextColor3 = Color3.fromRGB(250, 246, 230),
		ZIndex = 6,
		Parent = band,
	})
end

local function timecode(parent: Instance, text: string)
	Make.text({
		Text = text,
		Size = UDim2.fromScale(0.5, 0.08),
		Position = UDim2.fromScale(0.47, 0.06),
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Right,
		Font = Enum.Font.Code,
		TextColor3 = Color3.fromRGB(250, 250, 240),
		TextStrokeTransparency = 0.4,
		ZIndex = 6,
		Parent = parent,
	})
end

local function viewport(
	parent: Instance,
	ambient: Color3,
	lightColor: Color3,
	lightDirection: Vector3
): (ViewportFrame, Camera)
	local frame = Make.new("ViewportFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BorderSizePixel = 0,
		Ambient = ambient,
		LightColor = lightColor,
		LightDirection = lightDirection,
		Parent = parent,
	})
	local camera = Instance.new("Camera")
	camera.FieldOfView = 55
	camera.Parent = frame
	frame.CurrentCamera = camera
	return frame, camera
end

local function anchorClone(): Model?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local template = assets and assets:FindFirstChild("Anchor")
	if not template then
		return nil
	end
	local clone = (template :: Model):Clone()
	for _, d in clone:GetDescendants() do
		if d:IsA("Light") or d:IsA("JointInstance") or d:IsA("WeldConstraint") then
			d:Destroy()
		end
	end
	return clone
end

-- A tape set. `anchor`: "Composed" | "Stare" | "Absent"; `turn` rotates the technician figure.
function Screens.scene(parent: Instance, sceneName: string, anchor: string?, turn: boolean?): Renderer
	local frame = base(parent)
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local scenes = assets and assets:FindFirstChild("Scenes")
	local template = scenes and scenes:FindFirstChild(sceneName)
	if not template then
		frame.BackgroundColor3 = Color3.fromRGB(10, 10, 40)
		return {
			update = noop,
			destroy = function()
				frame:Destroy()
			end,
		}
	end
	local vp, camera = viewport(
		frame,
		(template:GetAttribute("Ambient") :: Color3?) or Color3.fromRGB(120, 110, 100),
		(template:GetAttribute("LightColor") :: Color3?) or Color3.fromRGB(255, 240, 220),
		(template:GetAttribute("LightDirection") :: Vector3?) or Vector3.new(-0.3, -1, 0.6)
	)
	local set = template:Clone()
	local cam = set:FindFirstChild("Cam")
	if cam and cam:IsA("BasePart") then
		camera.CFrame = cam.CFrame
	end
	if turn then
		local figure = set:FindFirstChild("Figure")
		if figure and figure:IsA("Model") then
			figure:PivotTo(figure:GetPivot() * CFrame.Angles(0, math.pi, 0))
		end
	end
	local mark = set:FindFirstChild("AnchorMark")
	if mark and mark:IsA("BasePart") and anchor and anchor ~= "Absent" then
		local him = anchorClone()
		if him then
			local pivot = mark.CFrame
			if anchor == "Stare" and cam and cam:IsA("BasePart") then
				local look = Vector3.new(cam.Position.X, pivot.Position.Y, cam.Position.Z)
				pivot = CFrame.lookAt(pivot.Position, look)
			end
			him:PivotTo(pivot * CFrame.new(0, 3.9, 0))
			him.Parent = set
		end
	end
	set.Parent = vp
	local t = 0
	return {
		update = function(dt: number)
			-- A barely perceptible handheld drift so footage never looks like a still.
			t += dt
			if cam and cam:IsA("BasePart") then
				camera.CFrame = cam.CFrame * CFrame.Angles(math.sin(t * 0.7) * 0.003, math.sin(t * 0.5) * 0.004, 0)
			end
		end,
		destroy = function()
			frame:Destroy()
		end,
	}
end

------------------------------------------------------------------ security feeds

local geometryCache: { [number]: Model } = {}

local function buildGeometry(camId: number, camPart: BasePart): Model
	local cached = geometryCache[camId]
	if cached then
		return cached
	end
	local model = Instance.new("Model")
	model.Name = "Feed" .. camId
	local station = Workspace:FindFirstChild("Station")
	local origin = camPart.Position
	local look = camPart.CFrame.LookVector
	local count = 0
	if station then
		for _, d in station:GetDescendants() do
			if count > 500 then
				break
			end
			if d:IsA("BasePart") and d.Transparency < 0.95 then
				local offset = d.Position - origin
				local distance = offset.Magnitude
				if distance < 46 and (distance < 6 or offset.Unit:Dot(look) > -0.1) then
					local ok, clone = pcall(function()
						return d:Clone()
					end)
					if ok and clone then
						for _, child in clone:GetChildren() do
							if not child:IsA("DataModelMesh") then
								child:Destroy()
							end
						end
						clone.Anchored = true
						clone.Parent = model
						count += 1
					end
				end
			end
		end
	end
	geometryCache[camId] = model
	return model
end

local function proxy(color: Color3): Model
	local m = Instance.new("Model")
	local body = Make.new("Part", { Size = Vector3.new(1.8, 3.6, 1), Color = color, Anchored = true, Parent = m })
	Make.new("Part", {
		Name = "Head",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(1.2, 1.2, 1.2),
		Color = color,
		Anchored = true,
		CFrame = CFrame.new(0, 2.5, 0),
		Parent = m,
	})
	body.CFrame = CFrame.new()
	m.PrimaryPart = body
	return m
end

export type FeedRenderer = Renderer & { setDirective: (directive: { [string]: any }?) -> () }

local function formatClock(minutes: number): string
	local m = minutes % (24 * 60)
	local h = math.floor(m / 60)
	local mm = math.floor(m % 60)
	local ss = math.floor((m * 60) % 60)
	return string.format("%02d:%02d:%02d", h, mm, ss)
end

function Screens.feed(parent: Instance, camId: number, getClock: () -> (number, string)): FeedRenderer
	local frame = base(parent)
	local station = Workspace:FindFirstChild("Station")
	local camPart: BasePart? = nil
	if station then
		for _, d in station:GetDescendants() do
			if d:IsA("BasePart") and d:GetAttribute("CamId") == camId then
				camPart = d
				break
			end
		end
	end
	if not camPart then
		local fallback = Screens.static(frame)
		return {
			update = fallback.update,
			destroy = function()
				frame:Destroy()
			end,
			setDirective = function() end,
		}
	end
	local cp = camPart :: BasePart
	local vp, camera =
		viewport(frame, Color3.fromRGB(150, 160, 150), Color3.fromRGB(200, 220, 200), Vector3.new(-0.2, -1, 0.3))
	vp.ImageColor3 = Color3.fromRGB(190, 215, 190)
	camera.FieldOfView = (cp:GetAttribute("FOV") :: number?) or 72
	camera.CFrame = cp.CFrame
	local geometry = buildGeometry(camId, cp):Clone()
	geometry.Parent = vp
	local dynamic = Instance.new("Folder")
	dynamic.Parent = vp
	local label = Make.text({
		Text = (cp:GetAttribute("Label") :: string?) or ("CAM " .. camId),
		Size = UDim2.fromScale(0.6, 0.08),
		Position = UDim2.fromScale(0.03, 0.04),
		TextScaled = true,
		Font = Enum.Font.Code,
		TextColor3 = Color3.fromRGB(240, 240, 230),
		TextStrokeTransparency = 0.4,
		ZIndex = 4,
		Parent = frame,
	})
	local stamp = Make.text({
		Text = "",
		Size = UDim2.fromScale(0.5, 0.08),
		Position = UDim2.fromScale(0.47, 0.88),
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Right,
		Font = Enum.Font.Code,
		TextColor3 = Color3.fromRGB(240, 240, 230),
		TextStrokeTransparency = 0.4,
		ZIndex = 4,
		Parent = frame,
	})
	local offline = Screens.static(frame)
	local offlineFrame = frame:FindFirstChildWhichIsA("Frame", false)
	local offlineText = Make.text({
		Text = "NO SIGNAL",
		Size = UDim2.fromScale(1, 0.2),
		Position = UDim2.fromScale(0, 0.4),
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Theme.FontTitle,
		ZIndex = 5,
		Visible = false,
		Parent = frame,
	})
	local directive: { [string]: any } = { mode = "Live", leadSeconds = 0 }
	local anchorModel: Model? = nil
	local crewProxies: { [number]: Model } = {}
	local phantomProxies: { Model } = {}

	local function clearPhantoms()
		for _, p in phantomProxies do
			p:Destroy()
		end
		table.clear(phantomProxies)
	end

	local function applyDirective()
		local mode = directive.mode
		local isOffline = mode == "Offline"
		if offlineFrame then
			offlineFrame.Visible = isOffline
		end
		offlineText.Visible = isOffline
		vp.Visible = not isOffline
		label.Visible = true
		local at = directive.anchorAt
		if at and not anchorModel then
			anchorModel = anchorClone()
			if anchorModel then
				anchorModel.Parent = dynamic
			end
		end
		if anchorModel then
			if at then
				anchorModel:PivotTo(CFrame.new(at.x, at.y + 3.9, at.z) * CFrame.Angles(0, at.yaw or 0, 0))
			else
				anchorModel:Destroy()
				anchorModel = nil
			end
		end
		clearPhantoms()
		if directive.phantoms then
			for i, _ in directive.phantoms do
				local p = proxy(Color3.fromRGB(60, 60, 64))
				local spot = cp.Position
					+ cp.CFrame.LookVector * (10 + i * 2.5)
					+ cp.CFrame.RightVector * ((i % 2) * 2 - 1) * 2
				p:PivotTo(
					CFrame.lookAt(
						Vector3.new(spot.X, cp.Position.Y - 8, spot.Z),
						Vector3.new(cp.Position.X, cp.Position.Y - 8, cp.Position.Z)
					) * CFrame.new(0, 0, 0)
				)
				p.Parent = dynamic
				table.insert(phantomProxies, p)
			end
		end
		vp.ImageColor3 = if mode == "Memory" then Color3.fromRGB(230, 190, 150) else Color3.fromRGB(190, 215, 190)
	end

	applyDirective()
	local timer = 0
	return {
		update = function(dt: number)
			if directive.mode == "Offline" then
				offline.update(dt)
				return
			end
			timer += dt
			if timer < 0.12 then
				return
			end
			timer = 0
			-- Live crew proxies (cheap boxes where the real players stand).
			local seen: { [number]: boolean } = {}
			if directive.mode ~= "Memory" then
				for _, player in Players:GetPlayers() do
					local character = player.Character
					local root = character and character:FindFirstChild("HumanoidRootPart")
					if root and root:IsA("BasePart") and (root.Position - cp.Position).Magnitude < 50 then
						seen[player.UserId] = true
						local p: Model? = crewProxies[player.UserId]
						if not p then
							local made = proxy(Color3.fromRGB(85, 85, 90))
							made.Parent = dynamic
							crewProxies[player.UserId] = made
							p = made
						end
						(p :: Model):PivotTo(root.CFrame * CFrame.new(0, -0.6, 0))
					end
				end
			end
			for userId, p in crewProxies do
				if not seen[userId] then
					p:Destroy()
					crewProxies[userId] = nil
				end
			end
			local clock, phase = getClock()
			local rate = (GameConfig.Phases :: any)[phase] and (GameConfig.Phases :: any)[phase].rate or 0.3
			local shown = clock + (directive.leadSeconds or 0) * rate
			if directive.mode == "Memory" then
				stamp.Text = "10/17/87 02:17:00"
			else
				local date = if shown < 0 then "10/16/98" else "10/17/98"
				stamp.Text = date .. " " .. formatClock(shown)
			end
		end,
		destroy = function()
			frame:Destroy()
		end,
		setDirective = function(d: { [string]: any }?)
			directive = d or { mode = "Live", leadSeconds = 0 }
			applyDirective()
		end,
	}
end

------------------------------------------------------------------ tapes

-- Renders a deck's timeline. `getTime()` returns seconds since the tape started (nil = stopped).
function Screens.tape(
	parent: Instance,
	tapeId: string,
	getTime: () -> number?,
	t: (string, { [string]: any }?) -> string,
	vars: { [string]: any }
): Renderer
	local frame = base(parent)
	local def = TapeContent.Defs[tapeId]
	local current: Renderer? = nil
	local currentIndex = -1
	if not def then
		return Screens.static(parent)
	end
	local function showShot(index: number)
		if current then
			current.destroy()
			current = nil
		end
		local shot = def.shots[index]
		if not shot then
			current = Screens.black(frame)
			return
		end
		if shot.kind == "Bars" then
			current = Screens.bars(frame)
		elseif shot.kind == "Static" then
			current = Screens.static(frame)
		elseif shot.kind == "Black" then
			current = Screens.black(frame)
		elseif shot.kind == "Card" then
			current = Screens.card(
				frame,
				shot.style,
				if shot.titleKey then t(shot.titleKey, vars) else "",
				if shot.bodyKey then t(shot.bodyKey, vars) else nil
			)
		elseif shot.kind == "Scene" then
			local holder = base(frame)
			local scene = Screens.scene(holder, shot.scene or "StudioADesk", shot.anchor, false)
			if shot.lowerThirdKey then
				lowerThird(holder, t(shot.lowerThirdKey, vars))
			end
			if shot.timestamp then
				timecode(holder, shot.timestamp)
			end
			current = {
				update = scene.update,
				destroy = function()
					holder:Destroy()
				end,
			}
		end
	end
	return {
		update = function(dt: number)
			local elapsed = getTime()
			local index = 0
			if elapsed then
				local length = TapeContent.duration(def)
				local tt = if def.loop and length > 0 then elapsed % length else elapsed
				local cursor = 0
				index = #def.shots + 1
				for i, shot in def.shots do
					if tt < cursor + shot.duration then
						index = i
						break
					end
					cursor += shot.duration
				end
			end
			if index ~= currentIndex then
				currentIndex = index
				if index == 0 then
					if current then
						current.destroy()
					end
					current = Screens.card(frame, "Slate", "VTR  ■  STOP", nil)
				else
					showShot(index)
				end
			end
			if current then
				current.update(dt)
			end
		end,
		destroy = function()
			if current then
				current.destroy()
			end
			frame:Destroy()
		end,
	}
end

return Screens
