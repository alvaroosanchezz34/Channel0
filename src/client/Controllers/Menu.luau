--!strict
--[[
	Everything outside the shift itself:
	  * title card (camera on the TitleCamera marker) and the lobby panel (crew, ready, countdown)
	  * settings (volume, VHS profile, reduce motion, subtitles, language), saved by the server
	  * the intro cinematic while the session is in Intro
	  * the "taken" screen: you watch the station through its cameras and read your frequency
	  * the ending card and the results / credits
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EndingDefs = require(Shared.Content.Endings)
local GameConfig = require(Shared.Config.GameConfig)
local SettingsConfig = require(Shared.Config.Settings)

local Make = require(script.Parent.Parent.UI.Make)
local Net = require(script.Parent.Net)
local Screens = require(script.Parent.Parent.UI.Screens)
local Store = require(script.Parent.Store)
local Theme = require(script.Parent.Parent.UI.Theme)

local Menu = {}

local player = Players.LocalPlayer
local gui: ScreenGui
local titleFrame: Frame
local lobbyFrame: Frame
local lobbyCrew: Frame
local lobbyCountdown: TextLabel
local readyButton: TextButton
local settingsFrame: Frame
local settingsBody: Frame
local introFrame: Frame
local introLine: TextLabel
local takenFrame: Frame
local takenScreen: Frame
local takenText: TextLabel
local takenCam: TextLabel
local endingFrame: Frame
local endingTitle: TextLabel
local endingSummary: TextLabel
local endingDetails: TextLabel

local titleDismissed = false
local ready = false
local cameraHeld = false
local cameraTime = 0
local introStart = 0
local takenFeed: Screens.FeedRenderer? = nil
local takenCamIndex = 1
local takenCams: { number } = {}
local resultsStart = 0

local function t(key: string, vars: { [string]: any }?): string
	return Store.t(key, vars)
end

local function session(): string
	return (Net.state(Net.Attr.Session) or "Lobby") :: string
end

local function marker(name: string): BasePart?
	local station = Workspace:FindFirstChild("Station")
	local found = station and station:FindFirstChild(name, true)
	return if found and found:IsA("BasePart") then found else nil
end

local function holdCamera(name: string, drift: boolean)
	local camera = Workspace.CurrentCamera
	local m = marker(name)
	if not camera or not m then
		return
	end
	cameraHeld = true
	camera.CameraType = Enum.CameraType.Scriptable
	local sway = if drift and not Store.settings.reduceMotion
		then CFrame.new(math.sin(cameraTime * 0.2) * 0.8, math.sin(cameraTime * 0.13) * 0.3, -cameraTime * 0.15 % 6)
		else CFrame.identity
	camera.CFrame = m.CFrame * sway
end

local function releaseCamera()
	local camera = Workspace.CurrentCamera
	-- Nothing else in the game scripts the camera, so a Scriptable camera outside the title and
	-- ending shots is always stale: hand it back to the player.
	if not cameraHeld and not (camera and camera.CameraType == Enum.CameraType.Scriptable) then
		return
	end
	cameraHeld = false
	if camera then
		camera.CameraType = Enum.CameraType.Custom
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			camera.CameraSubject = humanoid
		end
	end
end

------------------------------------------------------------------ settings

local function settingRow(name: string, value: string, options: { { label: string, apply: () -> () } }?)
	local r = Make.new("Frame", {
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundTransparency = 1,
		Parent = settingsBody,
	})
	Make.text({ Text = name, Size = UDim2.new(0.45, 0, 1, 0), TextSize = 17, Parent = r })
	local holder = Make.new("Frame", {
		Size = UDim2.new(0.55, 0, 1, 0),
		Position = UDim2.fromScale(0.45, 0),
		BackgroundTransparency = 1,
		Parent = r,
	}, { Make.list(Enum.FillDirection.Horizontal, 6) })
	for _, option in (options or {}) :: { { label: string, apply: () -> () } } do
		Make.button({
			Text = option.label,
			Size = UDim2.new(0, math.max(54, #option.label * 10), 1, -4),
			TextSize = 15,
			BackgroundColor3 = if option.label == value then Theme.Colors.AmberDim else Theme.Colors.PanelLight,
			TextColor3 = if option.label == value then Theme.Colors.Panel else Theme.Colors.Amber,
			Parent = holder,
		}, option.apply)
	end
end

local function volumeOptions(key: string): { { label: string, apply: () -> () } }
	local list = {}
	for _, v in { 0, 0.25, 0.5, 0.75, 1 } do
		table.insert(list, {
			label = tostring(math.floor(v * 100)),
			apply = function()
				Store.setSettings({ [key] = v })
			end,
		})
	end
	return list
end

local function renderSettings()
	for _, child in settingsBody:GetChildren() do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
	local s = Store.settings :: any
	settingRow(t("set.master"), tostring(math.floor(s.masterVolume * 100)), volumeOptions("masterVolume"))
	settingRow(t("set.ambience"), tostring(math.floor(s.ambienceVolume * 100)), volumeOptions("ambienceVolume"))
	local vhs = {}
	for _, profile in SettingsConfig.Choices.vhsProfile do
		table.insert(vhs, {
			label = t("set.vhs." .. profile),
			apply = function()
				Store.setSettings({ vhsProfile = profile })
			end,
		})
	end
	settingRow(t("set.vhs"), t("set.vhs." .. s.vhsProfile), vhs)
	local function onOff(key: string): { { label: string, apply: () -> () } }
		return {
			{
				label = t("set.on"),
				apply = function()
					Store.setSettings({ [key] = true })
				end,
			},
			{
				label = t("set.off"),
				apply = function()
					Store.setSettings({ [key] = false })
				end,
			},
		}
	end
	settingRow(t("set.motion"), if s.reduceMotion then t("set.on") else t("set.off"), onOff("reduceMotion"))
	settingRow(t("set.subtitles"), if s.subtitles then t("set.on") else t("set.off"), onOff("subtitles"))
	local sizes = {}
	for _, size in { "small", "medium", "large" } do
		table.insert(sizes, {
			label = t("set." .. size),
			apply = function()
				Store.setSettings({ subtitleSize = size })
			end,
		})
	end
	settingRow(t("set.subtitleSize"), t("set." .. s.subtitleSize), sizes)
	settingRow("Language / Idioma", if s.language == "es" then "ES" elseif s.language == "en" then "EN" else "AUTO", {
		{
			label = "AUTO",
			apply = function()
				Store.setSettings({ language = "auto" })
			end,
		},
		{
			label = "EN",
			apply = function()
				Store.setSettings({ language = "en" })
			end,
		},
		{
			label = "ES",
			apply = function()
				Store.setSettings({ language = "es" })
			end,
		},
	})
	Make.text({
		Text = t("set.note"),
		TextColor3 = Theme.Colors.TextDim,
		TextSize = 15,
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = settingsBody,
	})
end

function Menu.openSettings()
	renderSettings()
	settingsFrame.Visible = true
end

------------------------------------------------------------------ lobby

local function renderLobby()
	for _, child in lobbyCrew:GetChildren() do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
	local title = lobbyFrame:FindFirstChild("CrewTitle") :: TextLabel?
	if title then
		title.Text = t("ui.crew", { count = #Store.crew, max = GameConfig.MaxPlayers })
	end
	for _, entry in Store.crew do
		Make.text({
			Text = string.format("%s  %s", if entry.ready then "■" else "□", tostring(entry.name)),
			TextColor3 = if entry.ready then Theme.Colors.Green else Theme.Colors.TextDim,
			TextSize = 17,
			Parent = lobbyCrew,
		})
	end
	local me = Store.me()
	ready = me ~= nil and me.ready == true
	readyButton.Text = if ready then t("ui.cancelReady") else t("ui.ready")
	readyButton.BackgroundColor3 = if ready then Theme.Colors.PanelLight else Theme.Colors.AmberDim
	readyButton.TextColor3 = if ready then Theme.Colors.Amber else Theme.Colors.Panel
end

------------------------------------------------------------------ taken

local function collectCams()
	takenCams = {}
	local station = Workspace:FindFirstChild("Station")
	if not station then
		return
	end
	for _, d in station:GetDescendants() do
		local id = d:GetAttribute("CamId")
		if type(id) == "number" and not table.find(takenCams, id) then
			table.insert(takenCams, id)
		end
	end
	table.sort(takenCams)
end

local function showTakenCam()
	if takenFeed then
		takenFeed.destroy()
		takenFeed = nil
	end
	if #takenCams == 0 then
		return
	end
	takenCamIndex = (takenCamIndex - 1) % #takenCams + 1
	local camId = takenCams[takenCamIndex]
	takenFeed = Screens.feed(takenScreen, camId, function()
		return (Net.state(Net.Attr.Clock) or 0) :: number, (Net.state(Net.Attr.Phase) or "Arrival") :: string
	end)
	local feed = takenFeed :: Screens.FeedRenderer
	feed.setDirective(Store.feeds[tostring(camId)])
	takenCam.Text = string.format("CAM %02d", camId)
end

local function renderTaken()
	local taken = Store.taken
	takenFrame.Visible = taken ~= nil and session() == "Running"
	if not takenFrame.Visible then
		if takenFeed then
			takenFeed.destroy()
			takenFeed = nil
		end
		return
	end
	local info = taken :: { [string]: any }
	if info.solo or not info.frequency then
		takenText.Text = t("ui.taken.solo")
	else
		takenText.Text = t("ui.taken.body") .. "\n" .. string.format("%06.2f MHz", info.frequency)
	end
	if not takenFeed then
		if #takenCams == 0 then
			collectCams()
		end
		showTakenCam()
	end
end

------------------------------------------------------------------ ending / results

local function formatDuration(seconds: number): string
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

local function renderEnding()
	local ending = Store.ending
	local state = session()
	endingFrame.Visible = ending ~= nil and (state == "Ending" or state == "Results")
	if not endingFrame.Visible then
		return
	end
	local e = ending :: { [string]: any }
	local def = EndingDefs.Defs[e.id]
	endingTitle.Text = if def then t(def.titleKey) else tostring(e.id)
	endingSummary.Text = if def then t(def.summaryKey) else ""
	if state == "Results" then
		local lines = {
			t("ui.results"),
			"",
			t("ui.endingsFound", { count = e.endingsFound or 0, total = #EndingDefs.Order }),
			t("ui.duration", { time = formatDuration(tonumber(e.duration) or 0) }),
			t("ui.seed", { seed = tostring(e.seed or "?") }),
			"",
			t("end.credits.tonight", { names = table.concat(e.crew or {}, " · ") }),
			t("end.credits.crew87"),
		}
		if e.id == "NewAnchor" and e.actor then
			table.insert(lines, 2, t("end.newAnchor.billing", { name = e.actor }))
		end
		local left = math.max(0, GameConfig.ResultsDuration - math.floor(os.clock() - resultsStart))
		table.insert(lines, "")
		table.insert(lines, t("ui.returnLobby", { seconds = left }))
		endingDetails.Text = table.concat(lines, "\n")
	else
		endingDetails.Text = ""
	end
end

------------------------------------------------------------------ build

local function panel(props: { [string]: any }): Frame
	local base = {
		BackgroundColor3 = Theme.Colors.Panel,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		Visible = false,
		Parent = gui,
	}
	for k, v in props do
		base[k] = v
	end
	return Make.new("Frame", base, { Make.stroke(Theme.Colors.Edge, 1), Make.corner(3) })
end

local function build()
	gui = Make.screen("Menu", 20, player:WaitForChild("PlayerGui"))

	-- Title card.
	titleFrame =
		Make.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, Parent = gui })
	Make.modal(titleFrame)
	Make.text({
		Text = t("ui.title"),
		Font = Theme.FontTitle,
		TextSize = 72,
		TextColor3 = Theme.Colors.Text,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 90),
		Position = UDim2.fromScale(0, 0.22),
		Parent = titleFrame,
	})
	Make.text({
		Name = "Sub",
		Text = t("ui.subtitle"),
		TextSize = 18,
		TextColor3 = Theme.Colors.Amber,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 24),
		Position = UDim2.new(0, 0, 0.22, 96),
		Parent = titleFrame,
	})
	local titleButtons = Make.new("Frame", {
		Size = UDim2.fromOffset(320, 100),
		Position = UDim2.fromScale(0.5, 0.62),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		Parent = titleFrame,
	}, { Make.list(Enum.FillDirection.Vertical, 10, Enum.HorizontalAlignment.Center) })
	Make.button(
		{ Name = "Start", Text = t("ui.start"), Size = UDim2.fromOffset(320, 46), Parent = titleButtons },
		function()
			titleDismissed = true
		end
	)
	Make.button(
		{ Name = "Settings", Text = t("ui.settings"), Size = UDim2.fromOffset(320, 40), Parent = titleButtons },
		Menu.openSettings
	)

	-- Lobby panel (bottom-left, the player walks around the parking lot meanwhile).
	lobbyFrame = panel({
		Size = UDim2.fromOffset(300, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Position = UDim2.new(0, 20, 1, -20),
		AnchorPoint = Vector2.new(0, 1),
	})
	Make.modal(lobbyFrame)
	Make.padding(10).Parent = lobbyFrame
	Make.list(Enum.FillDirection.Vertical, 6).Parent = lobbyFrame
	Make.text({ Name = "CrewTitle", Text = "", TextColor3 = Theme.Colors.Amber, LayoutOrder = 1, Parent = lobbyFrame })
	lobbyCrew = Make.new("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 2,
		Parent = lobbyFrame,
	}, { Make.list(Enum.FillDirection.Vertical, 2) })
	lobbyCountdown = Make.text({ Text = "", TextColor3 = Theme.Colors.Green, LayoutOrder = 3, Parent = lobbyFrame })
	Make.text({
		Name = "Hint",
		Text = t("ui.lobbyHint") .. "\n" .. t("ui.keyHints"),
		TextSize = 14,
		TextColor3 = Theme.Colors.TextDim,
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 4,
		Parent = lobbyFrame,
	})
	local lobbyButtons = Make.new("Frame", {
		Size = UDim2.new(1, 0, 0, 42),
		BackgroundTransparency = 1,
		LayoutOrder = 5,
		Parent = lobbyFrame,
	}, { Make.list(Enum.FillDirection.Horizontal, 8) })
	readyButton = Make.button(
		{ Text = t("ui.ready"), Size = UDim2.new(0.6, -4, 1, 0), Parent = lobbyButtons },
		function()
			Net.send("Ready", not ready)
		end
	)
	Make.button({ Text = "⚙", Size = UDim2.new(0.4, -4, 1, 0), Parent = lobbyButtons }, Menu.openSettings)

	-- Settings.
	settingsFrame = panel({
		Size = UDim2.new(0.9, 0, 0.8, 0),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = 5,
	})
	Make.modal(settingsFrame)
	Make.new("UISizeConstraint", { MaxSize = Vector2.new(640, 560) }).Parent = settingsFrame
	Make.text({
		Name = "Title",
		Text = t("set.title"),
		TextColor3 = Theme.Colors.Amber,
		TextSize = 22,
		Position = UDim2.fromOffset(14, 10),
		Size = UDim2.new(1, -150, 0, 30),
		Parent = settingsFrame,
	})
	Make.button({
		Name = "Close",
		Text = t("ui.close"),
		Size = UDim2.fromOffset(120, 34),
		Position = UDim2.new(1, -10, 0, 8),
		AnchorPoint = Vector2.new(1, 0),
		Parent = settingsFrame,
	}, function()
		settingsFrame.Visible = false
	end)
	settingsBody = Make.new("ScrollingFrame", {
		Size = UDim2.new(1, -24, 1, -60),
		Position = UDim2.fromOffset(12, 50),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Parent = settingsFrame,
	}, { Make.list(Enum.FillDirection.Vertical, 6) })

	-- Intro cinematic.
	introFrame = Make.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		Visible = false,
		Parent = gui,
	})
	introLine = Make.text({
		Text = "",
		TextSize = 26,
		TextColor3 = Theme.Colors.Text,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(0.8, 0, 0, 80),
		Position = UDim2.fromScale(0.1, 0.7),
		Parent = introFrame,
	})

	-- Taken.
	takenFrame = Make.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BorderSizePixel = 0,
		Visible = false,
		Parent = gui,
	})
	takenScreen = Make.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = takenFrame })
	Make.text({
		Text = t("ui.taken.title"),
		Font = Theme.FontTitle,
		TextSize = 40,
		TextColor3 = Theme.Colors.Red,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 50),
		Position = UDim2.fromScale(0, 0.08),
		ZIndex = 10,
		Parent = takenFrame,
	})
	takenText = Make.text({
		Text = "",
		TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(0.9, 0, 0, 70),
		Position = UDim2.fromScale(0.05, 0.78),
		ZIndex = 10,
		Parent = takenFrame,
	})
	takenCam = Make.text({
		Text = "",
		TextColor3 = Theme.Colors.Green,
		Position = UDim2.fromOffset(24, 24),
		ZIndex = 10,
		Parent = takenFrame,
	})
	Make.button({
		Text = t("ui.taken.cameras") .. " ▶",
		Size = UDim2.fromOffset(220, 44),
		Position = UDim2.new(0.5, 0, 1, -30),
		AnchorPoint = Vector2.new(0.5, 1),
		ZIndex = 10,
		Parent = takenFrame,
	}, function()
		takenCamIndex += 1
		showTakenCam()
	end)

	-- Ending / results.
	endingFrame = Make.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		Visible = false,
		Parent = gui,
	})
	Make.modal(endingFrame)
	endingTitle = Make.text({
		Text = "",
		Font = Theme.FontTitle,
		TextSize = 52,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 64),
		Position = UDim2.fromScale(0, 0.14),
		Parent = endingFrame,
	})
	endingSummary = Make.text({
		Text = "",
		TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(0.7, 0, 0, 90),
		Position = UDim2.new(0.15, 0, 0.14, 80),
		Parent = endingFrame,
	})
	endingDetails = Make.text({
		Text = "",
		TextSize = 18,
		TextColor3 = Theme.Colors.Amber,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Top,
		Size = UDim2.new(0.8, 0, 0.45, 0),
		Position = UDim2.fromScale(0.1, 0.45),
		Parent = endingFrame,
	})
end

local function relabel()
	local start = titleFrame:FindFirstChild("Start", true) :: TextButton?
	if start then
		start.Text = t("ui.start")
	end
	local settings = titleFrame:FindFirstChild("Settings", true) :: TextButton?
	if settings then
		settings.Text = t("ui.settings")
	end
	local sub = titleFrame:FindFirstChild("Sub") :: TextLabel?
	if sub then
		sub.Text = t("ui.subtitle")
	end
	local hint = lobbyFrame:FindFirstChild("Hint") :: TextLabel?
	if hint then
		hint.Text = t("ui.lobbyHint") .. "\n" .. t("ui.keyHints")
	end
	local title = settingsFrame:FindFirstChild("Title") :: TextLabel?
	if title then
		title.Text = t("set.title")
	end
	local close = settingsFrame:FindFirstChild("Close") :: TextButton?
	if close then
		close.Text = t("ui.close")
	end
end

------------------------------------------------------------------ frame loop

local function update(dt: number)
	cameraTime += dt
	local state = session()
	local me = Store.me()
	local inLobby = state == "Lobby" and (me == nil or me.status == "Lobby")

	titleFrame.Visible = inLobby and not titleDismissed
	lobbyFrame.Visible = inLobby and titleDismissed
	if inLobby and titleDismissed then
		local countdown = Net.state(Net.Attr.Countdown)
		lobbyCountdown.Text = if type(countdown) == "number" and countdown >= 0
			then t("ui.countdown", { seconds = math.ceil(countdown) })
			else ""
	end

	introFrame.Visible = state == "Intro"
	if state == "Intro" then
		local elapsed = os.clock() - introStart
		local step = math.clamp(math.floor(elapsed / (GameConfig.IntroDuration / 4)) + 1, 1, 4)
		introLine.Text = t("intro." .. step)
		local within = (elapsed % (GameConfig.IntroDuration / 4)) / (GameConfig.IntroDuration / 4)
		introLine.TextTransparency = if within < 0.15
			then 1 - within / 0.15
			elseif within > 0.85 then (within - 0.85) / 0.15
			else 0
	end

	renderTaken()
	if takenFeed then
		takenFeed.update(dt)
	end
	renderEnding()

	-- Camera: title shot in the lobby menu and intro, ending shot during the ending.
	if titleFrame.Visible or state == "Intro" then
		holdCamera("TitleCamera", true)
	elseif state == "Ending" or state == "Results" then
		holdCamera("EndingCamera", true)
	else
		releaseCamera()
	end
end

function Menu.init()
	build()
	relabel()
	renderLobby()
	Store.Changed:Connect(function(kind, payload)
		if kind == "crew" then
			renderLobby()
		elseif kind == "settings" then
			relabel()
			renderLobby()
			if settingsFrame.Visible then
				renderSettings()
			end
		elseif kind == "session" then
			if payload == "Intro" then
				introStart = os.clock()
				settingsFrame.Visible = false
			elseif payload == "Results" then
				resultsStart = os.clock()
			elseif payload == "Lobby" then
				takenCamIndex = 1
			end
		elseif kind == "feeds" and takenFeed and #takenCams > 0 then
			takenFeed.setDirective(Store.feeds[tostring(takenCams[takenCamIndex])])
		end
	end)
	-- A player joining mid-shift skips the title card.
	if session() ~= "Lobby" then
		titleDismissed = true
	end
	RunService.RenderStepped:Connect(update)
end

return Menu
