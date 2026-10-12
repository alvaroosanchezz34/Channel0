--!strict
--[[
	The permanent analog filter. Always on, never fully off: the accessibility profiles
	(Reduced, MinimalNoise) and "reduce motion" only scale it down.

	Layers (all built from GUI objects and post-processing, no uploaded assets required):
	  * ColorCorrection + Bloom: washed-out saturation, warm tint, contrast, luminance flicker
	  * scanlines: UIGradient triangle waves (20 keypoints = 10 lines per frame), rebuilt on resize
	  * grain: an EditableImage noise tile re-rolled StaticFrequency times per second; falls back
	    to sparse "dust" frames where EditableImage is unavailable
	  * chromatic fringe: red/cyan gradients on the left/right edges
	  * vignette: four edge gradients
	  * tracking band and head-switch band (VHS tape artefacts)
	  * OSD: PLAY, tape counter and the station date/time burned in like a camcorder

	Dynamic intensity = profile base x (1 + tension + pulses + THE ANCHOR's proximity + dead air),
	capped by VHSConfig.MaxAnomalyMultiplier. Dropouts are rate-limited and never fully black
	(photosensitivity guard).
]]

local AssetService = game:GetService("AssetService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local MathUtil = require(Shared.Util.MathUtil)
local VHSConfig = require(Shared.Config.VHSConfig)

local Make = require(script.Parent.Parent.UI.Make)
local Net = require(script.Parent.Net)
local Store = require(script.Parent.Store)

local VHS = {}

type Profile = typeof(VHSConfig.Profiles.Default)

local profile: Profile = VHSConfig.Profiles.Default
local reduceMotion = false
local gui: ScreenGui
local color: ColorCorrectionEffect
local bloom: BloomEffect
local blur: BlurEffect
local scanFolder: Frame
local grainLabel: ImageLabel
local dust: { Frame } = {}
local fringeL: Frame
local fringeR: Frame
local vignette: { Frame } = {}
local tracking: Frame
local headSwitch: Frame
local dropoutFrame: Frame
local osdTime: TextLabel
local osdDate: TextLabel
local osdPlay: TextLabel

local editable: any = nil
local grainBuffer: buffer? = nil
local GRAIN = VHSConfig.GrainTextureSize

type Pulse = { amount: number, duration: number, t: number }
local pulses: { Pulse } = {}
local dropoutTimes: { number } = {}
local trackingY = -1
local trackingSpeed = 0
local grainTimer = 0
local level = 0
local lastSize = Vector2.zero
local rng = Random.new()

------------------------------------------------------------------ construction

local function buildScanlines()
	for _, child in scanFolder:GetChildren() do
		child:Destroy()
	end
	local viewport = Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
	local period = math.max(2, profile.ScanlinePeriod)
	local linesPerFrame = 10
	local frameHeight = period * linesPerFrame
	local count = math.ceil(viewport.Y / frameHeight) + 1
	local keypoints = {}
	for i = 0, linesPerFrame - 1 do
		local t0 = i / linesPerFrame
		local t1 = (i + 0.5) / linesPerFrame
		table.insert(keypoints, NumberSequenceKeypoint.new(t0, 0))
		table.insert(keypoints, NumberSequenceKeypoint.new(math.min(t1, 1), 1))
	end
	keypoints[#keypoints] = NumberSequenceKeypoint.new(1, 1)
	keypoints[1] = NumberSequenceKeypoint.new(0, 0)
	local sequence = NumberSequence.new(keypoints)
	for i = 0, count - 1 do
		local frame = Make.new("Frame", {
			Size = UDim2.new(1, 0, 0, frameHeight),
			Position = UDim2.fromOffset(0, i * frameHeight),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BorderSizePixel = 0,
			BackgroundTransparency = 0,
			Parent = scanFolder,
		})
		Make.new("UIGradient", { Rotation = 90, Transparency = sequence, Parent = frame })
	end
end

local function edgeGradient(parent: Instance, rotation: number, size: UDim2, position: UDim2, tint: Color3): Frame
	local frame = Make.new("Frame", {
		Size = size,
		Position = position,
		BackgroundColor3 = tint,
		BorderSizePixel = 0,
		Parent = parent,
	})
	Make.new("UIGradient", {
		Rotation = rotation,
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }),
		Parent = frame,
	})
	return frame
end

local function tryEditableGrain(): boolean
	local ok = pcall(function()
		local image = (AssetService :: any):CreateEditableImage({ Size = Vector2.new(GRAIN, GRAIN) })
		local label: any = grainLabel
		label.ImageContent = Content.fromObject(image)
		editable = image
		grainBuffer = buffer.create(GRAIN * GRAIN * 4)
	end)
	return ok and editable ~= nil
end

local function buildDust()
	for _ = 1, 70 do
		local size = rng:NextInteger(1, 3)
		table.insert(
			dust,
			Make.new("Frame", {
				Size = UDim2.fromOffset(size, size),
				BackgroundColor3 = Color3.new(1, 1, 1),
				BorderSizePixel = 0,
				Parent = gui,
			})
		)
	end
end

local function build()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = Make.screen("VHS", 20, playerGui)

	color = Make.new("ColorCorrectionEffect", { Name = "VHSColor", Parent = Lighting })
	bloom = Make.new("BloomEffect", { Name = "VHSBloom", Threshold = 0.85, Size = 28, Parent = Lighting })
	blur = Make.new("BlurEffect", { Name = "VHSBlur", Size = 0, Parent = Lighting })

	grainLabel = Make.new("ImageLabel", {
		Name = "Grain",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Tile,
		TileSize = UDim2.fromOffset(GRAIN * VHSConfig.GrainTileScale, GRAIN * VHSConfig.GrainTileScale),
		ResampleMode = Enum.ResamplerMode.Pixelated,
		ImageTransparency = 1,
		Parent = gui,
	})
	if VHSConfig.GrainTextureId ~= "" then
		grainLabel.Image = VHSConfig.GrainTextureId
	elseif not tryEditableGrain() then
		buildDust()
	end

	scanFolder = Make.new(
		"Frame",
		{ Name = "Scanlines", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = gui }
	)
	buildScanlines()

	fringeL = edgeGradient(gui, 0, UDim2.new(0.035, 0, 1, 0), UDim2.fromScale(0, 0), Color3.fromRGB(255, 30, 40))
	fringeR = edgeGradient(gui, 180, UDim2.new(0.035, 0, 1, 0), UDim2.fromScale(0.965, 0), Color3.fromRGB(30, 230, 255))

	vignette = {
		edgeGradient(gui, 90, UDim2.new(1, 0, 0.22, 0), UDim2.fromScale(0, 0), Color3.new(0, 0, 0)),
		edgeGradient(gui, 270, UDim2.new(1, 0, 0.22, 0), UDim2.fromScale(0, 0.78), Color3.new(0, 0, 0)),
		edgeGradient(gui, 0, UDim2.new(0.16, 0, 1, 0), UDim2.fromScale(0, 0), Color3.new(0, 0, 0)),
		edgeGradient(gui, 180, UDim2.new(0.16, 0, 1, 0), UDim2.fromScale(0.84, 0), Color3.new(0, 0, 0)),
	}

	tracking = Make.new("Frame", {
		Name = "Tracking",
		Size = UDim2.new(1, 0, 0.07, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Visible = false,
		Parent = gui,
	})
	for i = 1, 6 do
		Make.new("Frame", {
			Size = UDim2.new(rng:NextNumber(0.2, 0.9), 0, 0, rng:NextInteger(1, 3)),
			Position = UDim2.new(rng:NextNumber(0, 0.5), 0, i / 7, 0),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0.35,
			BorderSizePixel = 0,
			Parent = tracking,
		})
	end
	Make.new("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0.55),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = tracking,
	})

	headSwitch = Make.new("Frame", {
		Name = "HeadSwitch",
		Size = UDim2.new(1.04, 0, 0.022, 0),
		Position = UDim2.fromScale(-0.02, 0.978),
		BackgroundColor3 = Color3.fromRGB(220, 220, 230),
		BackgroundTransparency = 0.85,
		BorderSizePixel = 0,
		Parent = gui,
	})

	dropoutFrame = Make.new("Frame", {
		Name = "Dropout",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = gui,
	})

	local osd =
		Make.new("Frame", { Name = "OSD", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = gui })
	local function osdLabel(position: UDim2, anchor: Vector2, align: Enum.TextXAlignment): TextLabel
		return Make.text({
			Position = position,
			AnchorPoint = anchor,
			Size = UDim2.fromOffset(320, 28),
			TextSize = 24,
			TextXAlignment = align,
			TextColor3 = Color3.fromRGB(245, 245, 235),
			TextStrokeTransparency = 0.55,
			Font = Enum.Font.Code,
			Parent = osd,
		})
	end
	osdPlay = osdLabel(UDim2.new(0, 34, 0, 26), Vector2.new(0, 0), Enum.TextXAlignment.Left)
	osdPlay.Text = "PLAY ▶"
	osdTime = osdLabel(UDim2.new(0, 34, 1, -34), Vector2.new(0, 1), Enum.TextXAlignment.Left)
	osdDate = osdLabel(UDim2.new(1, -34, 1, -34), Vector2.new(1, 1), Enum.TextXAlignment.Right)
end

------------------------------------------------------------------ public API

function VHS.setProfile(name: string, motionReduced: boolean)
	local chosen = (VHSConfig.Profiles :: any)[name] or VHSConfig.Profiles.Default
	local changedPeriod = chosen.ScanlinePeriod ~= profile.ScanlinePeriod
	profile = chosen
	reduceMotion = motionReduced
	if gui and changedPeriod then
		buildScanlines()
	end
end

-- Momentary intensity boost (events, the Anchor, dead air). Amount ~0.3 subtle .. 1.6 violent.
function VHS.pulse(amount: number, duration: number)
	table.insert(pulses, { amount = math.clamp(amount, 0, 2), duration = math.max(0.1, duration), t = 0 })
	if #pulses > 8 then
		table.remove(pulses, 1)
	end
	-- Strong pulses may cause a dropout, within the photosensitivity budget.
	if amount >= 0.9 then
		VHS.dropout(math.clamp(amount * 0.4, 0.2, VHSConfig.DropoutMaxDarkness))
	end
end

function VHS.dropout(darkness: number)
	local now = os.clock()
	for i = #dropoutTimes, 1, -1 do
		if now - dropoutTimes[i] > VHSConfig.DropoutWindowSeconds then
			table.remove(dropoutTimes, i)
		end
	end
	if #dropoutTimes >= VHSConfig.MaxDropoutsPerWindow then
		return
	end
	table.insert(dropoutTimes, now)
	local d = math.min(darkness, VHSConfig.DropoutMaxDarkness)
	if reduceMotion then
		d *= 0.5
	end
	dropoutFrame.BackgroundTransparency = 1 - d
	if not reduceMotion then
		trackingY = 0
		trackingSpeed = 1.6
	end
end

function VHS.level(): number
	return level
end

------------------------------------------------------------------ frame update

local function anchorProximity(): number
	local model = Workspace:FindFirstChild("TheAnchor")
	local camera = Workspace.CurrentCamera
	if not model or not camera or model:GetAttribute("Visible") ~= true then
		return 0
	end
	local pivot = (model :: Model):GetPivot().Position
	local distance = (pivot - camera.CFrame.Position).Magnitude
	return MathUtil.clamp01(1 - distance / 46)
end

local function writeGrain(strength: number)
	if editable and grainBuffer then
		local b = grainBuffer :: buffer
		for i = 0, GRAIN * GRAIN - 1 do
			local v = rng:NextInteger(0, 255)
			local offset = i * 4
			buffer.writeu8(b, offset, v)
			buffer.writeu8(b, offset + 1, v)
			buffer.writeu8(b, offset + 2, v)
			buffer.writeu8(b, offset + 3, math.floor(255 * strength * (v / 255)))
		end
		pcall(function()
			editable:WritePixelsBuffer(Vector2.zero, Vector2.new(GRAIN, GRAIN), b)
		end)
	elseif #dust > 0 then
		for _, frame in dust do
			frame.Position = UDim2.fromScale(rng:NextNumber(), rng:NextNumber())
			frame.BackgroundTransparency = 1 - strength * rng:NextNumber(0.3, 1)
		end
	else
		grainLabel.Position = UDim2.fromOffset(rng:NextInteger(-GRAIN, 0), rng:NextInteger(-GRAIN, 0))
	end
end

local function osdText()
	local clock = Net.state(Net.Attr.Clock)
	local session = Net.state(Net.Attr.Session)
	if type(clock) ~= "number" or session ~= "Running" then
		osdTime.Text = ""
		osdDate.Text = ""
		osdPlay.Text = if session == "Lobby" then "STOP ■" else "PLAY ▶"
		return
	end
	local minutes = clock % (24 * 60)
	local h24 = math.floor(minutes / 60)
	local m = math.floor(minutes % 60)
	local s = math.floor((minutes * 60) % 60)
	local suffix = if h24 >= 12 then "PM" else "AM"
	local h12 = h24 % 12
	if h12 == 0 then
		h12 = 12
	end
	osdTime.Text = string.format("%s %2d:%02d:%02d", suffix, h12, m, s)
	local date = if clock < 0 then GameConfig.Station.NightDate else GameConfig.Station.MorningDate
	local months = { "JAN.", "FEB.", "MAR.", "APR.", "MAY", "JUN.", "JUL.", "AUG.", "SEP.", "OCT.", "NOV.", "DEC." }
	osdDate.Text = string.format("%s %d %d", months[date.month], date.day, date.year)
	osdPlay.Text = if Store.signal.deadAir then "TRACKING" else "PLAY ▶"
end

local function update(dt: number)
	local camera = Workspace.CurrentCamera
	if camera and camera.ViewportSize ~= lastSize then
		lastSize = camera.ViewportSize
		buildScanlines()
	end

	-- Intensity sources.
	local pulse = 0
	for i = #pulses, 1, -1 do
		local p = pulses[i]
		p.t += dt
		if p.t >= p.duration then
			table.remove(pulses, i)
		else
			local envelope = 1 - p.t / p.duration
			pulse += p.amount * envelope * envelope
		end
	end
	local tension = (Net.state(Net.Attr.Tension) or 0) :: number
	local deadAir = if Store.signal.deadAir then 0.6 else 0
	local anomaly = if Net.state(Net.Attr.AnomalyActive) then 0.5 else 0
	local proximity = anchorProximity() * 1.4
	local target = math.min(VHSConfig.MaxAnomalyMultiplier, 1 + tension * 0.6 + pulse + deadAir + anomaly + proximity)
	level = MathUtil.approach(level, target, 3, dt)
	local k = level

	-- Post-processing.
	local flicker = if reduceMotion then 0 else profile.LuminanceFlicker * k * rng:NextNumber(-1, 1)
	color.Saturation = math.clamp(profile.Saturation - 0.06 * (k - 1), -0.7, 0)
	color.Contrast = profile.Contrast + 0.04 * (k - 1)
	color.Brightness = flicker - 0.02 * (k - 1)
	color.TintColor = Color3.new(profile.Tint[1], profile.Tint[2], profile.Tint[3])
	bloom.Intensity = profile.Bloom
	blur.Size = if reduceMotion then 0 else math.clamp((k - 1.8) * 3, 0, 6)

	-- Grain.
	local grainStrength = math.clamp(profile.BaseNoiseIntensity * k, 0, 0.45)
	grainTimer += dt
	if grainTimer >= 1 / math.max(1, profile.StaticFrequency * math.min(k, 2)) then
		grainTimer = 0
		writeGrain(grainStrength)
	end
	if editable then
		grainLabel.ImageTransparency = 0
	elseif VHSConfig.GrainTextureId ~= "" then
		grainLabel.ImageTransparency = 1 - grainStrength
	end

	-- Scanlines, fringe, vignette.
	local scan = math.clamp(profile.ScanlineOpacity * (0.85 + 0.15 * k), 0, 0.5)
	for _, frame in scanFolder:GetChildren() do
		(frame :: Frame).BackgroundTransparency = 1 - scan
	end
	local fringe = math.clamp(profile.ChromaticIntensity * 0.35 * k, 0, 0.6)
	fringeL.BackgroundTransparency = 1 - fringe
	fringeR.BackgroundTransparency = 1 - fringe
	if not reduceMotion and k > 1.4 then
		local jitter = (k - 1.4) * 0.006
		fringeL.Position = UDim2.fromScale(rng:NextNumber(-jitter, jitter), 0)
		fringeR.Position = UDim2.fromScale(0.965 + rng:NextNumber(-jitter, jitter), 0)
	end
	local vig = math.clamp(profile.VignetteIntensity * (0.9 + 0.1 * k), 0, 0.85)
	for _, frame in vignette do
		frame.BackgroundTransparency = 1 - vig
	end

	-- Tracking band: idle chance, forced by pulses.
	local distortion = profile.DistortionIntensity * k
	if trackingY < 0 and not reduceMotion and rng:NextNumber() < profile.TrackingBandChance * dt * k then
		trackingY = rng:NextNumber(0, 0.6)
		trackingSpeed = rng:NextNumber(0.15, 0.5)
	end
	if trackingY >= 0 then
		trackingY += trackingSpeed * dt
		tracking.Visible = true
		tracking.Position = UDim2.fromScale(0, trackingY)
		tracking.BackgroundTransparency = 1 - math.clamp(0.08 + distortion * 0.12, 0, 0.35)
		if trackingY > 1.05 then
			trackingY = -1
			tracking.Visible = false
		end
	end
	headSwitch.BackgroundTransparency = 1 - math.clamp(0.06 + distortion * 0.1, 0, 0.3)
	if not reduceMotion then
		headSwitch.Position = UDim2.new(-0.02, rng:NextInteger(-6, 6) * distortion, 0.978, 0)
	end

	-- Dropout recovers quickly.
	dropoutFrame.BackgroundTransparency = math.min(1, dropoutFrame.BackgroundTransparency + dt * 2.6)

	osdText()
end

function VHS.init()
	build()
	local function applySettings()
		VHS.setProfile(Store.settings.vhsProfile, Store.settings.reduceMotion)
	end
	applySettings()
	Store.Changed:Connect(function(kind, payload)
		if kind == "settings" then
			applySettings()
		elseif kind == "cue" and payload.kind == "Pulse" then
			VHS.pulse(payload.amount or 0.5, payload.duration or 1)
		end
	end)
	RunService.RenderStepped:Connect(update)
end

return VHS
