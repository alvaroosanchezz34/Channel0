--!strict
--[[
	Every interactive device in the station. ProximityPrompt.Triggered gives the server a real
	Player; the server re-checks range, session state, crew status and device locks before doing
	anything. Devices with a panel UI are opened for ONE player at a time (others get "busy");
	the client only sends intents (DeviceAction) and the server answers with the new state.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EndingEvaluator = require(Shared.Logic.EndingEvaluator)
local GameConfig = require(Shared.Config.GameConfig)
local PhaseOrder = require(Shared.Logic.PhaseOrder)
local SignalConfig = require(Shared.Config.SignalConfig)

local Registry = require(script.Parent.Registry)
local Remotes = require(script.Parent.Remotes)
local State = require(script.Parent.State)
local World = require(script.Parent.World)

local Devices = {}

local UI_DEVICES = {
	Switcher = true,
	CameraConsole = true,
	Tuner = true,
	BreakerPanel = true,
	VTR = true,
	Keyswitch = true,
	AnchorDesk = true,
}

local locks: { [string]: Player } = {}
local openBy: { [number]: string } = {}
local cameraView: { [number]: { camId: number, since: number } } = {}
local camerasSeen: { [number]: boolean } = {}

type Panel = { order: { number }, progress: number, tripped: { boolean }, up: boolean }
Devices.panels = {} :: { [string]: Panel }

local function kindOf(deviceId: string): string?
	local part = World.devices[deviceId]
	return if part then part:GetAttribute("Device") :: string else nil
end

function Devices.message(player: Player, key: string, vars: { [string]: any }?)
	Remotes.fire(player, "Device", { op = "message", key = key, vars = vars })
end

local function inRange(player: Player, deviceId: string, extra: number?): boolean
	local part = World.devices[deviceId]
	local position = World.positionOf(player)
	if not part or not position then
		return false
	end
	return (position - part.Position).Magnitude <= GameConfig.Player.InteractRange + (extra or 0)
end

local function activeMember(player: Player): State.CrewMember?
	local member = State.member(player)
	if member and member.status == "Active" and State.session == "Running" then
		return member
	end
	return nil
end

------------------------------------------------------------------ breaker panels

local function stickerText(panel: Panel): string
	local parts = {}
	for _, n in panel.order do
		table.insert(parts, tostring(n))
	end
	return table.concat(parts, "-")
end

local function updateSticker(name: string)
	local panel = Devices.panels[name]
	if not World.station then
		return
	end
	for _, d in World.station:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("OrderSticker") == name then
			local gui = d:FindFirstChild("OrderText")
			local label = gui and gui:FindFirstChildOfClass("TextLabel")
			if label then
				label.Text = "RESTORE ORDER:\n" .. stickerText(panel)
			end
		end
	end
end

function Devices.planPanels()
	local rng = State.stream("panels")
	for _, name in { "A", "B" } do
		local breakers = rng:Shuffle({ 1, 2, 3, 4, 5 })
		local order = { breakers[1], breakers[2], breakers[3], breakers[4] }
		Devices.panels[name] = { order = order, progress = 0, tripped = { true, true, true, true, true }, up = false }
		updateSticker(name)
	end
end

function Devices.tripPanel(name: string)
	local panel = Devices.panels[name]
	if not panel or not panel.up then
		return
	end
	panel.up = false
	panel.progress = 0
	panel.tripped = { true, true, true, true, true }
	Registry.Signal.setPanel(name, false)
	local device = World.devices["Panel" .. name]
	if device then
		Registry.Session.cueNear(
			device.Position,
			60,
			{ kind = "Sound", sound = "BreakerSpark", position = device.Position }
		)
	end
	Registry.Session.cueAll({ kind = "Notice", key = "notice.panelTripped", vars = { panel = name }, style = "Fault" })
end

------------------------------------------------------------------ views

local function switcherView(): { [string]: any }
	local signal = Registry.Signal.model
	local facts = table.clone(State.facts)
	local canFinish, missing = EndingEvaluator.check("FullBroadcast", facts)
	return {
		powered = signal.consolePowered,
		onAir = signal.onAir,
		slateCooldown = math.ceil(signal.slateCooldown),
		zeroOpen = signal.zeroChannelOpen,
		vtr = Registry.Tapes.deckView("VTR_MCR", nil),
		crisis = State.fact("phaseCrisis"),
		canFinish = canFinish,
		missing = missing,
	}
end

local function cameraConsoleView(): { [string]: any }
	local list = {}
	for id, part in World.cameras do
		table.insert(list, {
			id = id,
			label = part:GetAttribute("Label"),
			zone = part:GetAttribute("Zone"),
			offline = Registry.Feeds.isOffline(id),
		})
	end
	table.sort(list, function(a, b)
		return a.id < b.id
	end)
	return { cameras = list }
end

local function tunerView(): { [string]: any }
	local signal = Registry.Signal.model
	return {
		frequency = signal.frequency,
		locked = signal.tuningLocked,
		min = SignalConfig.TunerMin,
		max = SignalConfig.TunerMax,
		fine = SignalConfig.FineStep,
		coarse = SignalConfig.CoarseStep,
	}
end

local function panelView(name: string): { [string]: any }
	local panel = Devices.panels[name]
	return { panel = name, tripped = table.clone(panel.tripped), order = stickerText(panel), up = panel.up }
end

local function keyswitchView(member: State.CrewMember): { [string]: any }
	local facts = table.clone(State.facts)
	facts.hasKillKey = member.hasKey
	local ok, missing = EndingEvaluator.check("CutSignal", facts)
	return { hasKey = member.hasKey, crisis = State.fact("phaseCrisis"), canConfirm = ok, missing = missing }
end

local function deskView(): { [string]: any }
	local ok, missing = EndingEvaluator.check("NewAnchor", table.clone(State.facts))
	return { canConfirm = ok, missing = missing }
end

local function viewFor(deviceId: string, member: State.CrewMember): { [string]: any }
	local kind = kindOf(deviceId)
	if kind == "Switcher" then
		return switcherView()
	elseif kind == "CameraConsole" then
		return cameraConsoleView()
	elseif kind == "Tuner" then
		return tunerView()
	elseif kind == "BreakerPanel" then
		return panelView(if deviceId == "PanelA" then "A" else "B")
	elseif kind == "VTR" then
		return Registry.Tapes.deckView(deviceId, member)
	elseif kind == "Keyswitch" then
		return keyswitchView(member)
	elseif kind == "AnchorDesk" then
		return deskView()
	end
	return {}
end

local function sendUpdate(deviceId: string)
	local player = locks[deviceId]
	local member = player and State.member(player)
	if player and member then
		Remotes.fire(
			player,
			"Device",
			{ op = "update", id = deviceId, kind = kindOf(deviceId), state = viewFor(deviceId, member) }
		)
	end
end
Devices.sendUpdate = sendUpdate

------------------------------------------------------------------ open / close

local function settleCameraView(userId: number)
	local view = cameraView[userId]
	if view and os.clock() - view.since >= 1.5 and not Registry.Feeds.isOffline(view.camId) then
		if not camerasSeen[view.camId] then
			camerasSeen[view.camId] = true
			local count = 0
			for _ in camerasSeen do
				count += 1
			end
			State.setCounter("camerasChecked", count)
		end
	end
	cameraView[userId] = nil
end

function Devices.close(player: Player, deviceId: string?)
	local id = deviceId or openBy[player.UserId]
	if not id or locks[id] ~= player then
		return
	end
	locks[id] = nil
	openBy[player.UserId] = nil
	settleCameraView(player.UserId)
	Remotes.fire(player, "Device", { op = "close", id = id })
end

function Devices.releaseAll(player: Player)
	Devices.close(player, nil)
end

local function open(player: Player, member: State.CrewMember, deviceId: string)
	local holder = locks[deviceId]
	if holder and holder ~= player then
		if holder.Parent and State.member(holder) and inRange(holder, deviceId, 4) then
			Devices.message(player, "dev.busy")
			return
		end
		Devices.close(holder, deviceId)
	end
	if openBy[player.UserId] and openBy[player.UserId] ~= deviceId then
		Devices.close(player, nil)
	end
	locks[deviceId] = player
	openBy[player.UserId] = deviceId
	Remotes.fire(
		player,
		"Device",
		{ op = "open", id = deviceId, kind = kindOf(deviceId), state = viewFor(deviceId, member) }
	)
end

------------------------------------------------------------------ immediate devices

local function useLocker(player: Player, member: State.CrewMember, deviceId: string)
	if deviceId == "Locker_MARSH" and not State.fact("keyTaken") then
		State.setFact("keyTaken", true)
		member.hasKey = true
		State.setFact("hasKillKey", true)
		Registry.Tapes.sendInventory(member)
		Devices.message(player, "dev.locker.key")
		Remotes.fire(player, "Cue", { kind = "Sound", sound = "TapePickup" })
	else
		Devices.message(player, "dev.locker.empty")
	end
end

local function useImmediate(player: Player, member: State.CrewMember, deviceId: string, kind: string)
	if kind == "SignIn" then
		State.setFact("signedIn", true)
		Devices.message(player, "dev.signin.done")
	elseif kind == "Phone" then
		Registry.Director.answerPhone(player)
	elseif kind == "Locker" then
		useLocker(player, member, deviceId)
	elseif kind == "Drawer" then
		if PhaseOrder.atLeast(State.phase, "Escalation") and Registry.Tapes.reveal("Contract1961") then
			Devices.message(player, "dev.drawer.found")
		else
			Devices.message(player, "dev.drawer.empty")
		end
	elseif kind == "MonitorSwitch" then
		local zone = World.devices[deviceId]:GetAttribute("Zone") :: string
		local on = World.zoneAttribute(zone, "MonitorsOn") ~= false
		World.setZoneAttribute(zone, "MonitorsOn", not on)
		Devices.message(player, if on then "dev.monitors.off" else "dev.monitors.on")
		Remotes.fire(player, "Cue", { kind = "Sound", sound = "UISwitch" })
	end
end

local function onTriggered(player: Player, deviceId: string)
	local member = activeMember(player)
	local kind = kindOf(deviceId)
	if not member or not kind or not inRange(player, deviceId) then
		return
	end
	if UI_DEVICES[kind] then
		open(player, member, deviceId)
	else
		useImmediate(player, member, deviceId, kind)
	end
end

------------------------------------------------------------------ actions

local ActionHandlers: { [string]: (player: Player, member: State.CrewMember, deviceId: string, action: string, arg: any) -> () } =
	{}

ActionHandlers.Switcher = function(player, _member, deviceId, action, arg)
	if action == "power" then
		Registry.Signal.powerConsole()
		Remotes.fire(player, "Cue", { kind = "Sound", sound = "UIConfirm" })
	elseif action == "source" and type(arg) == "string" then
		local ok, reason = Registry.Signal.setSource(arg)
		if not ok and reason then
			Devices.message(
				player,
				if reason == "SlateCooldown"
					then "dev.switcher.slateCooldown"
					elseif reason == "NoZeroChannel" then "dev.switcher.ch0Locked"
					else "dev.switcher.power",
				{ seconds = math.ceil(Registry.Signal.model.slateCooldown) }
			)
		else
			Remotes.fire(player, "Cue", { kind = "Sound", sound = "UISwitch" })
		end
	elseif action == "finish" then
		Registry.Endings.choice(player, "FullBroadcast")
	end
	sendUpdate(deviceId)
end

ActionHandlers.CameraConsole = function(player, _member, deviceId, action, arg)
	if action == "view" and type(arg) == "number" and World.cameras[arg] then
		settleCameraView(player.UserId)
		cameraView[player.UserId] = { camId = arg, since = os.clock() }
	elseif action == "reset" and type(arg) == "number" and World.cameras[arg] then
		if Registry.Feeds.restore(arg) then
			Remotes.fire(player, "Cue", { kind = "Sound", sound = "UIConfirm" })
		end
		sendUpdate(deviceId)
	end
end

ActionHandlers.Tuner = function(player, _member, deviceId, action, arg)
	if action == "tune" and Remotes.isFiniteNumber(arg) then
		local current = Registry.Signal.model.frequency
		-- A dial moves continuously: reject teleporting values.
		local target = math.clamp(arg, current - 6, current + 6)
		Registry.Signal.tune(math.floor(target * 100 + 0.5) / 100)
	elseif action == "lock" then
		local locked = Registry.Signal.lock()
		if locked == "Carrier" or locked == "Lost" then
			Remotes.fire(player, "Cue", { kind = "Sound", sound = "CarrierLock" })
		elseif locked == nil then
			Remotes.fire(player, "Cue", { kind = "Sound", sound = "UIClick" })
		end
	end
	sendUpdate(deviceId)
end

ActionHandlers.BreakerPanel = function(player, _member, deviceId, action, arg)
	local name = if deviceId == "PanelA" then "A" else "B"
	local panel = Devices.panels[name]
	if action ~= "flip" or type(arg) ~= "number" or arg ~= math.floor(arg) or arg < 1 or arg > 5 or panel.up then
		return
	end
	local device = World.devices[deviceId]
	if not panel.tripped[arg] then
		return
	end
	if panel.order[panel.progress + 1] == arg then
		panel.tripped[arg] = false
		panel.progress += 1
		Registry.Session.cueNear(
			device.Position,
			40,
			{ kind = "Sound", sound = "BreakerFlip", position = device.Position }
		)
		if panel.progress >= #panel.order then
			panel.up = true
			panel.tripped = { false, false, false, false, false }
			Registry.Signal.setPanel(name, true)
			Devices.message(player, "dev.panel.ok")
		end
	else
		panel.progress = 0
		panel.tripped = { true, true, true, true, true }
		Registry.Session.cueNear(
			device.Position,
			50,
			{ kind = "Sound", sound = "BreakerSpark", position = device.Position }
		)
		Devices.message(player, "dev.panel.retrip")
	end
	sendUpdate(deviceId)
end

ActionHandlers.VTR = function(player, member, deviceId, action, arg)
	local ok, reason = true, nil
	if action == "insert" and type(arg) == "string" and #arg <= 32 then
		ok, reason = Registry.Tapes.insert(member, deviceId, arg)
	elseif action == "eject" then
		ok, reason = Registry.Tapes.eject(member, deviceId)
	elseif action == "play" then
		Registry.Tapes.setPlaying(deviceId, true)
	elseif action == "stop" then
		Registry.Tapes.setPlaying(deviceId, false)
	end
	if not ok and reason == "full" then
		Devices.message(player, "dev.full")
	end
	sendUpdate(deviceId)
	-- The MCR switcher shows the deck too.
	if locks.Switcher then
		sendUpdate("Switcher")
	end
end

ActionHandlers.Keyswitch = function(player, member, deviceId, action, _arg)
	if action == "turn" then
		if not member.hasKey then
			Devices.message(player, "dev.keyswitch.noKey")
		elseif not State.fact("phaseCrisis") then
			Devices.message(player, "dev.keyswitch.early")
		end
		sendUpdate(deviceId)
	elseif action == "confirm" then
		Registry.Endings.choice(player, "CutSignal")
	end
end

ActionHandlers.AnchorDesk = function(player, _member, deviceId, action, _arg)
	if action == "sit" then
		local ok = EndingEvaluator.check("NewAnchor", table.clone(State.facts))
		if not ok then
			Devices.message(player, "dev.desk.cold")
		end
		sendUpdate(deviceId)
	elseif action == "confirm" then
		Registry.Endings.choice(player, "NewAnchor")
	end
end

local function onAction(player: Player, deviceId: any, action: any, arg: any)
	if not Remotes.isString(deviceId, 40) or not Remotes.isString(action, 16) then
		return
	end
	if locks[deviceId] ~= player then
		return
	end
	local member = activeMember(player)
	if not member or not inRange(player, deviceId, 4) then
		Devices.close(player, deviceId)
		return
	end
	local kind = kindOf(deviceId)
	local handler = kind and ActionHandlers[kind]
	if handler then
		handler(player, member, deviceId, action, arg)
	end
end

function Devices.init()
	for id, part in World.devices do
		local prompt = part:FindFirstChildOfClass("ProximityPrompt")
		if prompt then
			prompt.Triggered:Connect(function(player)
				onTriggered(player, id)
			end)
		end
	end
	Remotes.on("DeviceAction", onAction)
	Remotes.on("DeviceClose", function(player, deviceId)
		if Remotes.isString(deviceId, 40) then
			Devices.close(player, deviceId)
		end
	end)
end

-- Watchdog: closes panels for players who walked away, were taken or left.
function Devices.step()
	for deviceId, player in locks do
		local member = State.member(player)
		if not player.Parent or not member or member.status ~= "Active" or not inRange(player, deviceId, 4) then
			if player.Parent then
				Devices.close(player, deviceId)
			else
				locks[deviceId] = nil
				openBy[player.UserId] = nil
			end
		end
	end
	-- Keep live panels fresh (slate cooldown, tuner readout during drift).
	for deviceId in locks do
		local kind = kindOf(deviceId)
		if kind == "Switcher" or kind == "Tuner" or kind == "CameraConsole" then
			sendUpdate(deviceId)
		end
	end
end

-- Puts Marsh's key back in her locker (its carrier left the game).
function Devices.returnKey(member: State.CrewMember)
	if member.hasKey then
		member.hasKey = false
		State.setFact("keyTaken", false)
		State.setFact("hasKillKey", false)
	end
end

function Devices.reset()
	for deviceId, player in locks do
		if player.Parent then
			Remotes.fire(player, "Device", { op = "close", id = deviceId })
		end
	end
	table.clear(locks)
	table.clear(openBy)
	table.clear(cameraView)
	table.clear(camerasSeen)
end

return Devices
