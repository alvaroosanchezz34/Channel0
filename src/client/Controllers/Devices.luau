--!strict
--[[
	Full-screen device panels (switcher, security cameras, tuner, breaker panels, VTR decks, the
	carrier keyswitch and the anchor desk). The server opens a panel for one player with the
	device's state, the client draws it and sends intents (DeviceAction); every answer comes back
	as a fresh state. Nothing here decides an outcome.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Make = require(script.Parent.Parent.UI.Make)
local Net = require(script.Parent.Net)
local Screens = require(script.Parent.Parent.UI.Screens)
local Store = require(script.Parent.Store)
local Theme = require(script.Parent.Parent.UI.Theme)

local Devices = {}

type Open = { id: string, kind: string, state: { [string]: any } }

local gui: ScreenGui
local window: Frame
local titleLabel: TextLabel
local body: Frame
local current: Open? = nil
local renderer: Screens.Renderer? = nil
local feed: Screens.FeedRenderer? = nil
local feedCam: number? = nil
local feedScreen: Frame? = nil
local cameraIndex = 1
local pendingConfirm: string? = nil

-- Tuner: the dial moves locally and the server hears about it at a gentle rate.
local localFrequency: number? = nil
local lastTuneSent = 0
local tuneDirty = false
local dragging = false

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function t(key: string, vars: { [string]: any }?): string
	return Store.t(key, vars)
end

local function action(name: string, arg: any?)
	if current then
		Net.send("DeviceAction", current.id, name, arg)
	end
end

local function closeRequest()
	if current then
		Net.send("DeviceClose", current.id)
	end
end

local function clearBody()
	if renderer then
		renderer.destroy()
		renderer = nil
	end
	for _, child in body:GetChildren() do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
end

local function dropFeed()
	if feed then
		feed.destroy()
		feed = nil
		feedCam = nil
	end
	if feedScreen then
		feedScreen:Destroy()
		feedScreen = nil
	end
end

local order = 0
local function nextOrder(): number
	order += 1
	return order
end

local function row(height: number?): Frame
	return Make.new("Frame", {
		Size = UDim2.new(1, 0, 0, height or 44),
		BackgroundTransparency = 1,
		LayoutOrder = nextOrder(),
		Parent = body,
	}, { Make.list(Enum.FillDirection.Horizontal, 8) })
end

local function label(text: string, color: Color3?, size: number?): TextLabel
	return Make.text({
		Text = text,
		TextColor3 = color or Theme.Colors.Text,
		TextSize = size or 18,
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = nextOrder(),
		Parent = body,
	})
end

local function button(
	parent: Instance,
	text: string,
	width: number,
	onActivate: () -> (),
	lit: boolean?,
	enabled: boolean?
): TextButton
	local b = Make.button({
		Text = text,
		Size = UDim2.new(0, width, 1, 0),
		BackgroundColor3 = if lit then Theme.Colors.AmberDim else Theme.Colors.PanelLight,
		TextColor3 = if enabled == false
			then Theme.Colors.TextDim
			else if lit then Theme.Colors.Panel else Theme.Colors.Amber,
		AutoButtonColor = enabled ~= false,
		Parent = parent,
	}, function()
		if enabled ~= false then
			onActivate()
		end
	end)
	return b
end

local function missingList(missing: { string }?)
	if not missing or #missing == 0 then
		return
	end
	for _, key in missing do
		label("○ " .. t(key), Theme.Colors.TextDim, 16)
	end
end

-- Two-step confirmation for anything that ends the night.
local function confirmButton(key: string, actionName: string, canConfirm: boolean, missing: { string }?)
	if pendingConfirm == actionName and canConfirm then
		label(t("dev.confirm.warning"), Theme.Colors.Red)
		local r = row()
		button(r, t(key), 280, function()
			pendingConfirm = nil
			action(actionName)
		end, true)
		button(r, t("ui.back"), 140, function()
			pendingConfirm = nil
			if current then
				Devices.render()
			end
		end)
	else
		local r = row()
		button(r, t(key), 300, function()
			pendingConfirm = actionName
			Devices.render()
		end, false, canConfirm)
		missingList(missing)
	end
end

------------------------------------------------------------------ panels

local function renderSwitcher(state: { [string]: any })
	if not state.powered then
		label(t("dev.switcher.title"), Theme.Colors.TextDim)
		local r = row(54)
		button(r, t("dev.switcher.power"), 300, function()
			action("power")
		end, true)
		return
	end
	local onAir = state.onAir or "Bars"
	local r = row(56)
	for _, source in { "Bars", "Studio", "VTR", "Slate", "Channel0" } do
		local text = t("dev.switcher." .. source)
		local enabled = true
		if source == "Channel0" and not state.zeroOpen then
			text = t("dev.switcher.ch0Locked")
			enabled = false
		elseif source == "Slate" and (state.slateCooldown or 0) > 0 and onAir ~= "Slate" then
			text = t("dev.switcher.slateCooldown", { seconds = state.slateCooldown })
			enabled = false
		end
		button(r, text, 132, function()
			action("source", source)
		end, onAir == source, enabled)
	end
	local vtr = state.vtr or {}
	label(
		if vtr.tape
			then t("dev.switcher.vtrTape", { tape = t("tape." .. vtr.tape .. ".label") })
			else t("dev.switcher.vtrEmpty"),
		Theme.Colors.Green
	)
	if state.crisis then
		confirmButton("dev.switcher.finish", "finish", state.canFinish == true, state.missing)
	end
end

local function renderCameras(state: { [string]: any })
	local cameras = state.cameras or {}
	if #cameras == 0 then
		dropFeed()
		label(t("dev.cameras.offline"), Theme.Colors.Red)
		return
	end
	cameraIndex = math.clamp(cameraIndex, 1, #cameras)
	local cam = cameras[cameraIndex]
	-- The feed renderer is expensive (geometry clone): keep it and its screen while the camera stays.
	if feedCam ~= cam.id or cam.offline then
		dropFeed()
	end
	if cam.offline then
		local screen = Make.new("Frame", {
			Size = UDim2.new(1, 0, 0, 300),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BorderSizePixel = 0,
			LayoutOrder = nextOrder(),
			Parent = body,
		})
		renderer = Screens.static(screen, 1)
		Make.text({
			Text = t("dev.cameras.offline"),
			Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = Theme.Colors.Red,
			TextSize = 28,
			ZIndex = 5,
			Parent = screen,
		})
	else
		if not feed or not feedScreen then
			local screen = Make.new("Frame", {
				Size = UDim2.new(1, 0, 0, 300),
				BackgroundColor3 = Color3.new(0, 0, 0),
				BorderSizePixel = 0,
			})
			feedScreen = screen
			feed = Screens.feed(screen, cam.id, function()
				return (Net.state(Net.Attr.Clock) or 0) :: number, (Net.state(Net.Attr.Phase) or "Arrival") :: string
			end)
			feedCam = cam.id
			action("view", cam.id)
		end
		local screen = feedScreen :: Frame
		screen.LayoutOrder = nextOrder()
		screen.Parent = body;
		(feed :: Screens.FeedRenderer).setDirective(Store.feeds[tostring(cam.id)])
	end
	label(string.format("CAM %02d  ·  %s", cam.id, tostring(cam.label or cam.zone or "")), Theme.Colors.Green)
	local r = row()
	button(r, "◀ " .. t("dev.cameras.prev"), 140, function()
		cameraIndex = if cameraIndex <= 1 then #cameras else cameraIndex - 1
		Devices.render()
	end)
	button(r, t("dev.cameras.next") .. " ▶", 140, function()
		cameraIndex = if cameraIndex >= #cameras then 1 else cameraIndex + 1
		Devices.render()
	end)
	if cam.offline then
		button(r, "RESET", 140, function()
			action("reset", cam.id)
		end, true)
	end
end

local tunerReadout: TextLabel? = nil
local tunerNeedle: Frame? = nil

local function tunerFraction(state: { [string]: any }, f: number): number
	local min, max = state.min or 40, state.max or 130
	return math.clamp((f - min) / (max - min), 0, 1)
end

local function refreshTuner()
	local open = current
	if not open or open.kind ~= "Tuner" then
		return
	end
	local f = localFrequency or open.state.frequency or 0
	if tunerReadout then
		tunerReadout.Text = string.format(
			"%06.2f MHz%s",
			f,
			if open.state.locked and not tuneDirty then "   [" .. t("dev.tuner.locked") .. "]" else ""
		)
	end
	if tunerNeedle then
		tunerNeedle.Position = UDim2.fromScale(tunerFraction(open.state, f), 0)
	end
end

local function nudge(delta: number)
	local open = current
	if not open then
		return
	end
	local state = open.state
	local f = (localFrequency or state.frequency or 0) + delta
	localFrequency = math.clamp(math.floor(f * 100 + 0.5) / 100, state.min or 40, state.max or 130)
	tuneDirty = true
	refreshTuner()
end

local function renderTuner(state: { [string]: any })
	if not dragging and not tuneDirty then
		localFrequency = state.frequency
	end
	tunerReadout = Make.text({
		Text = "",
		TextSize = 44,
		Size = UDim2.new(1, 0, 0, 54),
		TextColor3 = Theme.Colors.Green,
		TextXAlignment = Enum.TextXAlignment.Center,
		LayoutOrder = nextOrder(),
		Parent = body,
	})
	label(t("dev.tuner.carrierHint"), Theme.Colors.TextDim, 15)
	local scale = Make.new("TextButton", {
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.new(1, 0, 0, 46),
		BackgroundColor3 = Theme.Colors.PanelLight,
		BorderSizePixel = 0,
		LayoutOrder = nextOrder(),
		Parent = body,
	}, { Make.stroke(Theme.Colors.Edge, 1) })
	for mhz = 40, 130, 10 do
		Make.new("Frame", {
			Size = UDim2.new(0, 1, 0.4, 0),
			Position = UDim2.fromScale(tunerFraction(state, mhz), 0.6),
			BackgroundColor3 = Theme.Colors.AmberDim,
			BorderSizePixel = 0,
			Parent = scale,
		})
	end
	tunerNeedle = Make.new("Frame", {
		Size = UDim2.new(0, 3, 1, 0),
		BackgroundColor3 = Theme.Colors.Red,
		BorderSizePixel = 0,
		Parent = scale,
	})
	local function fromX(x: number)
		local fraction = math.clamp((x - scale.AbsolutePosition.X) / math.max(1, scale.AbsoluteSize.X), 0, 1)
		local min, max = state.min or 40, state.max or 130
		local target = min + fraction * (max - min)
		local base = localFrequency or state.frequency or min
		-- The server only accepts small moves per message; the needle follows at that pace.
		nudge(math.clamp(target - base, -5, 5))
	end
	scale.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragging = true
			fromX(input.Position.X)
		end
	end)
	scale.InputChanged:Connect(function(input)
		if
			dragging
			and (
				input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch
			)
		then
			fromX(input.Position.X)
		end
	end)
	scale.InputEnded:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragging = false
		end
	end)
	local r = row(50)
	local coarse, fine = state.coarse or 1, state.fine or 0.05
	button(r, "◀◀", 80, function()
		nudge(-coarse)
	end)
	button(r, "◀", 80, function()
		nudge(-fine)
	end)
	button(r, "▶", 80, function()
		nudge(fine)
	end)
	button(r, "▶▶", 80, function()
		nudge(coarse)
	end)
	button(r, if state.locked and not tuneDirty then t("dev.tuner.locked") else t("dev.tuner.lock"), 150, function()
		if tuneDirty and localFrequency then
			action("tune", localFrequency)
			tuneDirty = false
		end
		action("lock")
	end, state.locked and not tuneDirty)
	refreshTuner()
end

local function renderPanel(state: { [string]: any })
	label(t("dev.panel.order", { order = state.order or "?" }), Theme.Colors.TextDim, 16)
	if state.up then
		label(t("dev.panel.ok"), Theme.Colors.Green, 22)
	end
	local r = row(120)
	for i = 1, 5 do
		local tripped = state.tripped and state.tripped[i]
		local b = button(r, string.format("%d\n%s", i, if tripped then t("dev.panel.tripped") else "ON"), 96, function()
			action("flip", i)
		end, not tripped, tripped == true and not state.up)
		b.TextColor3 = if tripped then Theme.Colors.Red else Theme.Colors.Panel
	end
end

local function renderVTR(state: { [string]: any })
	local screen = Make.new("Frame", {
		Size = UDim2.new(1, 0, 0, 200),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BorderSizePixel = 0,
		LayoutOrder = nextOrder(),
		Parent = body,
	})
	if state.tape then
		label(t("tape." .. state.tape .. ".label"), Theme.Colors.Green)
		if state.playing then
			local deckId = state.deck
			renderer = Screens.tape(screen, state.tape, function()
				local deck = Store.decks[deckId]
				if deck and deck.startedAt and deck.playing then
					return serverNow() - deck.startedAt
				end
				return nil
			end, t, Store.clueVars)
		else
			renderer = Screens.bars(screen)
		end
		local r = row()
		button(r, if state.playing then t("ui.stop") else t("ui.play"), 140, function()
			action(if state.playing then "stop" else "play")
		end, state.playing)
		button(r, t("ui.eject"), 140, function()
			action("eject")
		end)
	else
		renderer = Screens.static(screen, 0.6)
		label(t("dev.vtr.empty"), Theme.Colors.TextDim)
		if state.ejected then
			local r = row()
			button(r, t("ui.insert") .. ": " .. t("tape." .. state.ejected .. ".label"), 380, function()
				action("insert", "tray")
			end)
		end
		local carried = state.carried or {}
		if #carried > 0 then
			label(t("dev.vtr.selectTape"), Theme.Colors.Text, 16)
			for _, tapeId in carried do
				local r = row(40)
				button(r, t("tape." .. tapeId .. ".label"), 380, function()
					action("insert", tapeId)
				end)
			end
		elseif not state.ejected then
			label(t("ui.noTapes"), Theme.Colors.TextDim, 16)
		end
	end
end

local function renderKeyswitch(state: { [string]: any })
	local r = row(54)
	button(r, if state.hasKey then "⚿  TURN" else "⚿", 200, function()
		action("turn")
	end, state.hasKey)
	if state.hasKey and state.crisis then
		confirmButton("dev.keyswitch.confirm", "confirm", state.canConfirm == true, state.missing)
	end
end

local function renderDesk(state: { [string]: any })
	local r = row(54)
	button(r, "SIT", 160, function()
		action("sit")
	end)
	confirmButton("dev.desk.confirm", "confirm", state.canConfirm == true, state.missing)
end

local TITLES: { [string]: (state: { [string]: any }) -> string } = {
	Switcher = function()
		return t("dev.switcher.title")
	end,
	CameraConsole = function()
		return t("dev.cameras.title")
	end,
	Tuner = function()
		return t("dev.tuner.title")
	end,
	BreakerPanel = function(state)
		return t("dev.panel.title", { panel = state.panel or "" })
	end,
	VTR = function(state)
		return t("dev.vtr.title", { deck = string.gsub(tostring(state.deck or ""), "VTR_", "") })
	end,
	Keyswitch = function()
		return "CARRIER KILL"
	end,
	AnchorDesk = function()
		return "NIGHT DESK"
	end,
}

local RENDER: { [string]: (state: { [string]: any }) -> () } = {
	Switcher = renderSwitcher,
	CameraConsole = renderCameras,
	Tuner = renderTuner,
	BreakerPanel = renderPanel,
	VTR = renderVTR,
	Keyswitch = renderKeyswitch,
	AnchorDesk = renderDesk,
}

------------------------------------------------------------------ lifecycle

function Devices.render()
	local open = current
	if not open then
		return
	end
	-- Keep the live camera feed's screen out of the rebuild.
	if feedScreen then
		feedScreen.Parent = nil
	end
	clearBody()
	order = 0
	tunerReadout, tunerNeedle = nil, nil
	local title = TITLES[open.kind]
	titleLabel.Text = if title then title(open.state) else open.kind
	local render = RENDER[open.kind]
	if render then
		render(open.state)
	end
	if open.kind ~= "CameraConsole" then
		dropFeed()
	end
end

function Devices.isOpen(): boolean
	return current ~= nil
end

local function onDevice(message: { [string]: any })
	if type(message) ~= "table" then
		return
	end
	if message.op == "open" then
		if not current or current.id ~= message.id then
			pendingConfirm = nil
			cameraIndex = 1
			tuneDirty = false
			localFrequency = nil
		end
		current = { id = message.id, kind = message.kind, state = message.state or {} }
		window.Visible = true
		Devices.render()
	elseif message.op == "update" and current and current.id == message.id then
		current.state = message.state or {}
		-- Live refreshes of the tuner only move the readout, so dragging is not interrupted.
		if current.kind == "Tuner" and (dragging or tuneDirty) then
			refreshTuner()
		else
			Devices.render()
		end
	elseif message.op == "close" and current and current.id == message.id then
		current = nil
		window.Visible = false
		dropFeed()
		clearBody()
	end
end

local function build()
	gui = Make.screen("DevicePanel", 30, Players.LocalPlayer:WaitForChild("PlayerGui"))
	window = Make.new("Frame", {
		Size = UDim2.new(0.92, 0, 0.86, 0),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Theme.Colors.Panel,
		BackgroundTransparency = 0.04,
		BorderSizePixel = 0,
		Visible = false,
		Parent = gui,
	}, {
		Make.stroke(Theme.Colors.Edge, 2),
		Make.corner(4),
		Make.new("UISizeConstraint", { MaxSize = Vector2.new(780, 620) }),
	})
	titleLabel = Make.text({
		Text = "",
		Font = Theme.Font,
		TextSize = 22,
		TextColor3 = Theme.Colors.Amber,
		Size = UDim2.new(1, -170, 0, 44),
		Position = UDim2.fromOffset(16, 6),
		Parent = window,
	})
	Make.button({
		Text = t("ui.exitDevice"),
		Size = UDim2.fromOffset(150, 38),
		Position = UDim2.new(1, -10, 0, 8),
		AnchorPoint = Vector2.new(1, 0),
		Parent = window,
	}, closeRequest)
	body = Make.new("ScrollingFrame", {
		Size = UDim2.new(1, -24, 1, -64),
		Position = UDim2.fromOffset(12, 56),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Parent = window,
	}, { Make.list(Enum.FillDirection.Vertical, 8) })
end

function Devices.init()
	build()
	Store.Changed:Connect(function(kind, payload)
		if kind == "device" then
			onDevice(payload)
		elseif kind == "feeds" and current and current.kind == "CameraConsole" and feed and feedCam then
			feed.setDirective(Store.feeds[tostring(feedCam)])
		elseif kind == "settings" and current then
			Devices.render()
		elseif kind == "session" and current and (payload :: any) ~= "Running" then
			onDevice({ op = "close", id = current.id })
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not current then
			return
		end
		if
			input.KeyCode == Enum.KeyCode.Escape
			or input.KeyCode == Enum.KeyCode.Backspace
			or input.KeyCode == Enum.KeyCode.ButtonB
		then
			closeRequest()
		elseif current.kind == "Tuner" then
			if input.KeyCode == Enum.KeyCode.Left or input.KeyCode == Enum.KeyCode.A then
				nudge(-(current.state.fine or 0.05))
			elseif input.KeyCode == Enum.KeyCode.Right or input.KeyCode == Enum.KeyCode.D then
				nudge(current.state.fine or 0.05)
			elseif input.KeyCode == Enum.KeyCode.Q then
				nudge(-(current.state.coarse or 1))
			elseif input.KeyCode == Enum.KeyCode.E then
				nudge(current.state.coarse or 1)
			end
		end
	end)
	RunService.RenderStepped:Connect(function(dt)
		if renderer then
			renderer.update(dt)
		end
		if feed then
			feed.update(dt)
		end
		-- Tuner: send the dial position at most ~6 times a second (server bucket is 8/s).
		if
			current
			and current.kind == "Tuner"
			and tuneDirty
			and localFrequency
			and os.clock() - lastTuneSent > 0.16
		then
			lastTuneSent = os.clock()
			action("tune", localFrequency)
			if not dragging then
				tuneDirty = false
			end
		end
	end)
end

return Devices
