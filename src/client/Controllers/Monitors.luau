--!strict
--[[
	Every CRT in the station. Each monitor's role (Program, Wall, CCTV, Preview, Waveform, ...)
	decides what it shows from replicated state: the program output chosen on the switcher, the
	decks' timelines, the camera feed directives, the anomaly, and director cues.

	Only monitors near the local camera render rich content (ViewportFrames); distant screens are
	switched off locally. Tape subtitles are shown to players who can actually see/hear a deck.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local TapeContent = require(Shared.Content.Tapes)

local Make = require(script.Parent.Parent.UI.Make)
local Net = require(script.Parent.Net)
local Screens = require(script.Parent.Parent.UI.Screens)
local Store = require(script.Parent.Store)

local Monitors = {}

type Monitor = {
	model: Model,
	id: string,
	role: string,
	zone: string,
	screen: BasePart,
	gui: SurfaceGui,
	holder: Frame,
	renderer: Screens.Renderer?,
	key: string,
	index: number,
}

local monitors: { Monitor } = {}
local RICH_RANGE = 48
local blinkUntil = 0
local impossibleUntil = 0
local personal: { name: string, untilTime: number }? = nil
local anomalyStage = ""
local spokenLines: { [string]: boolean } = {}
-- Security feeds are the expensive screens: only the nearest few render live geometry.
local MAX_LIVE_FEEDS = 3
local feedAllowed: { [Monitor]: boolean } = {}

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function deckTime(deckId: string): number?
	local deck = Store.decks[deckId]
	if not deck or not deck.tape or not deck.playing then
		return nil
	end
	return serverNow() - (deck.startedAt or 0)
end

local function clockAndPhase(): (number, string)
	return (Net.state(Net.Attr.Clock) or 0) :: number, (Net.state(Net.Attr.Phase) or "Arrival") :: string
end

-- Decides a monitor's content: returns a cache key and a builder.
local function contentFor(m: Monitor): (string, (Frame) -> Screens.Renderer)
	local session = Net.state(Net.Attr.Session)
	local now = os.clock()
	if session ~= "Running" and session ~= "Ending" then
		if m.role == "Lobby" or m.role == "Program" then
			return "bars", Screens.bars
		end
		return "black", Screens.black
	end
	if now < blinkUntil then
		return "black", Screens.black
	end
	local anomaly = Net.state(Net.Attr.AnomalyActive) == true
	local role: string = m.role
	-- A plain boolean (not a refinement on role) keeps the checks below typed as string.
	local showsAnomaly = anomaly and role ~= "Waveform"
	if showsAnomaly then
		local stage = anomalyStage
		return "anomaly:" .. stage,
			function(f)
				return Screens.scene(
					f,
					"MasterControlNight",
					if stage == "Presence" then "Stare" else "Absent",
					stage ~= "Start"
				)
			end
	end
	local zoneFolder = Workspace:FindFirstChild("Station")
		and Workspace.Station:FindFirstChild("Zones")
		and Workspace.Station.Zones:FindFirstChild(m.zone)
	if zoneFolder and zoneFolder:GetAttribute("MonitorsOn") == false then
		return "off", Screens.black
	end
	if now < impossibleUntil and (role == "Program" or role == "Wall" or role == "Lobby" or role == "Office") then
		return "impossible", function(f)
			return Screens.scene(f, "HallwaySecurity", "Stare", false)
		end
	end
	if personal and now < personal.untilTime and (role == "Office" or role == "Program" or role == "Studio") then
		local name = personal.name
		return "personal:" .. name,
			function(f)
				return Screens.card(
					f,
					"StationID",
					Store.t("end.newAnchor.billing", { name = string.upper(name) }),
					nil
				)
			end
	end

	local signal = Store.signal
	local anchorState = Net.state(Net.Attr.AnchorState)
	local function program(): (string, (Frame) -> Screens.Renderer)
		if signal.deadAir then
			return "static", Screens.static
		end
		local source = Net.state(Net.Attr.ProgramSource) or "Bars"
		if source == "Studio" then
			local pose = if anchorState == "Broadcast" or anchorState == "Observing" then "Composed" else "Absent"
			return "studio:" .. pose, function(f)
				return Screens.scene(f, "StudioADesk", pose, false)
			end
		elseif source == "VTR" then
			local deck = Store.decks.VTR_MCR
			local tape = deck and deck.tape
			if not tape then
				return "static", Screens.static
			end
			return "vtr:" .. tape .. ":" .. tostring(deck.startedAt),
				function(f)
					return Screens.tape(f, tape, function()
						return deckTime("VTR_MCR")
					end, Store.t, Store.clueVars)
				end
		elseif source == "Slate" then
			return "slate", function(f)
				return Screens.card(f, "Slate", Store.t("sub.slate"), nil)
			end
		elseif source == "Channel0" then
			return "ch0", function(f)
				return Screens.scene(f, "StudioBMemory", "Stare", false)
			end
		end
		-- Bars, but THE ANCHOR sometimes broadcasts over them.
		if anchorState == "Broadcast" and (m.index % 3 == 0) then
			return "studio:Composed", function(f)
				return Screens.scene(f, "StudioADesk", "Composed", false)
			end
		end
		return "bars", Screens.bars
	end

	if role == "Program" or role == "Lobby" or role == "Studio" or role == "Office" then
		return program()
	elseif role == "CCTV" or (role == "Wall" and m.index % 4 == 1) then
		local count = 8
		local camId = ((m.index + math.floor(os.clock() / 7)) % count) + 1
		local directive = Store.feeds[tostring(camId)]
		local mode = directive and directive.mode or "Live"
		if not feedAllowed[m] then
			local label = "CAM " .. string.format("%02d", camId)
			return "camcard:" .. camId .. ":" .. mode,
				function(f)
					if mode == "Offline" then
						return Screens.static(f)
					end
					return Screens.card(f, "Clue", label, nil)
				end
		end
		return "cam:" .. camId .. ":" .. mode,
			function(f)
				local feed = Screens.feed(f, camId, clockAndPhase)
				feed.setDirective(Store.feeds[tostring(camId)])
				return feed
			end
	elseif role == "Wall" then
		if m.index % 4 == 2 then
			return program()
		end
		return "bars", Screens.bars
	elseif role == "Preview" then
		local deck = Store.decks.VTR_Editing
		local tape = deck and deck.tape
		if (m.id == "Editing_1" or m.id == "Editing_2") and tape then
			return "edit:" .. tape .. ":" .. tostring(deck.startedAt),
				function(f)
					return Screens.tape(f, tape, function()
						return deckTime("VTR_Editing")
					end, Store.t, Store.clueVars)
				end
		end
		return "blue", function(f)
			return Screens.card(f, "Slate", "VTR-B", nil)
		end
	elseif role == "Waveform" then
		return "wave",
			function(f)
				local frame = Make.new("Frame", {
					Size = UDim2.fromScale(1, 1),
					BackgroundColor3 = Color3.fromRGB(4, 16, 8),
					BorderSizePixel = 0,
					Parent = f,
				})
				local bars = {}
				for i = 1, 24 do
					table.insert(
						bars,
						Make.new("Frame", {
							Size = UDim2.new(1 / 24, -1, 0.5, 0),
							Position = UDim2.new((i - 1) / 24, 0, 0.5, 0),
							AnchorPoint = Vector2.new(0, 0.5),
							BackgroundColor3 = Color3.fromRGB(110, 255, 140),
							BorderSizePixel = 0,
							Parent = frame,
						})
					)
				end
				local t = 0
				return {
					update = function(dt: number)
						t += dt
						local q = (Store.signal.quality or 0) / 100
						local noise = Store.signal.interference or 0
						for i, bar in bars do
							local h = 0.15 + 0.6 * q * math.abs(math.sin(t * 3 + i * 0.5)) + noise * math.random() * 0.5
							bar.Size = UDim2.new(1 / 24, -1, math.clamp(h, 0.02, 0.95), 0)
						end
					end,
					destroy = function()
						frame:Destroy()
					end,
				}
			end
	end
	return "black", Screens.black
end

local function collect()
	local index = 0
	-- The screens live in PlayerGui and are adorned to the monitor parts: a SurfaceGui parented
	-- under Workspace would put every ViewportFrame's cloned geometry into the physical world.
	local folder = Instance.new("Folder")
	folder.Name = "CH0Monitors"
	folder.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	for _, model in CollectionService:GetTagged("Monitor") do
		if model:IsA("Model") then
			local screen = model:FindFirstChild("Screen")
			if screen and screen:IsA("BasePart") then
				index += 1
				local gui = Make.new("SurfaceGui", {
					Name = "CH0Screen",
					Face = Enum.NormalId.Front,
					SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
					PixelsPerStud = 60,
					LightInfluence = 0,
					Brightness = 1.4,
					Adornee = screen,
					Enabled = false,
					Parent = folder,
				})
				local holder = Make.new("Frame", {
					Size = UDim2.fromScale(1, 1),
					BackgroundColor3 = Color3.new(0, 0, 0),
					BorderSizePixel = 0,
					Parent = gui,
				})
				table.insert(monitors, {
					model = model,
					id = (model:GetAttribute("MonitorId") :: string?) or model.Name,
					role = (model:GetAttribute("Role") :: string?) or "General",
					zone = (model:GetAttribute("Zone") :: string?) or "Exterior",
					screen = screen,
					gui = gui,
					holder = holder,
					renderer = nil,
					key = "",
					index = index,
				})
			end
		end
	end
end

-- Subtitles for tape lines, delivered to players near a deck or a screen showing it.
local function tapeSubtitles()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local position = camera.CFrame.Position
	local station = Workspace:FindFirstChild("Station")
	for deckId, deck in Store.decks do
		if deck.tape and deck.playing then
			local def = TapeContent.Defs[deck.tape]
			local near = false
			if station then
				for _, d in CollectionService:GetTagged("Device") do
					if
						d:GetAttribute("DeviceId") == deckId
						and d:IsA("BasePart")
						and (d.Position - position).Magnitude < 28
					then
						near = true
					end
				end
			end
			if not near and deckId == "VTR_MCR" and Net.state(Net.Attr.ProgramSource) == "VTR" then
				for _, m in monitors do
					if
						(m.role == "Program" or m.role == "Lobby" or m.role == "Office")
						and m.gui.Enabled
						and (m.screen.Position - position).Magnitude < 22
					then
						near = true
					end
				end
			end
			local elapsed = deckTime(deckId)
			if near and def and elapsed then
				local length = TapeContent.duration(def)
				local tt = if def.loop and length > 0 then elapsed % length else elapsed
				for i, line in def.lines do
					local key = deckId .. ":" .. tostring(deck.startedAt) .. ":" .. i
					if tt >= line.at and tt < line.at + 1.5 and not spokenLines[key] then
						spokenLines[key] = true
						Store.Changed:Fire("cue", {
							kind = "Subtitle",
							key = line.key,
							vars = Store.clueVars,
							speaker = line.speaker,
							duration = line.duration or 5,
						})
					end
				end
			end
		end
	end
end

local timer = 0
local subtitleTimer = 0

local function update(dt: number)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local position = camera.CFrame.Position
	timer += dt
	local refresh = timer >= 0.4
	if refresh then
		timer = 0
	end
	if refresh then
		table.clear(feedAllowed)
		local candidates = {}
		for _, m in monitors do
			if m.role == "CCTV" or (m.role == "Wall" and m.index % 4 == 1) then
				table.insert(candidates, m)
			end
		end
		table.sort(candidates, function(a, b)
			return (a.screen.Position - position).Magnitude < (b.screen.Position - position).Magnitude
		end)
		for i = 1, math.min(MAX_LIVE_FEEDS, #candidates) do
			feedAllowed[candidates[i]] = true
		end
	end
	for _, m in monitors do
		local distance = (m.screen.Position - position).Magnitude
		local rich = distance <= RICH_RANGE
		if not rich then
			if m.gui.Enabled then
				m.gui.Enabled = false
				if m.renderer then
					m.renderer.destroy()
					m.renderer = nil
				end
				m.key = ""
			end
		else
			if refresh or m.key == "" then
				local key, builder = contentFor(m)
				if key ~= m.key then
					if m.renderer then
						m.renderer.destroy()
					end
					m.key = key
					m.renderer = builder(m.holder)
				elseif string.sub(key, 1, 4) == "cam:" and m.renderer then
					local camId = tonumber(string.match(key, "^cam:(%d+)")) or 1;
					((m.renderer :: any).setDirective)(Store.feeds[tostring(camId)])
				end
				m.gui.Enabled = true
			end
			if m.renderer then
				m.renderer.update(dt)
			end
		end
	end
	subtitleTimer += dt
	if subtitleTimer > 0.25 then
		subtitleTimer = 0
		tapeSubtitles()
	end
end

function Monitors.init()
	local station = Workspace:WaitForChild("Station", 60)
	if not station then
		return
	end
	collect()
	Store.Changed:Connect(function(kind, cue)
		if kind == "cue" then
			if cue.kind == "MonitorBlink" then
				blinkUntil = os.clock() + 0.35
			elseif cue.kind == "ImpossibleBroadcast" then
				impossibleUntil = os.clock() + (cue.duration or 6)
			elseif cue.kind == "PersonalBroadcast" then
				personal = { name = cue.name or "", untilTime = os.clock() + (cue.duration or 6) }
			elseif cue.kind == "Anomaly" then
				anomalyStage = cue.stage or ""
			end
		elseif kind == "session" then
			table.clear(spokenLines)
		end
	end)
	RunService.RenderStepped:Connect(update)
end

return Monitors
