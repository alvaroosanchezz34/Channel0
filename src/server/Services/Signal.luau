--!strict
--[[
	LA SEÑAL. Owns the broadcast model and turns its events into consequences. Every input arrives
	from a validated device action; clients only receive snapshots.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local PhaseOrder = require(Shared.Logic.PhaseOrder)
local SignalConfig = require(Shared.Config.SignalConfig)
local SignalModel = require(Shared.Logic.SignalModel)

local Registry = require(script.Parent.Registry)
local Remotes = require(script.Parent.Remotes)
local State = require(script.Parent.State)

local Signal = {}

Signal.model = SignalModel.new(70)
local publishTimer = 0
local lastSnapshot: { [string]: any }? = nil

local function shallowEqual(a: { [string]: any }?, b: { [string]: any }): boolean
	if not a then
		return false
	end
	for k, v in b do
		if a[k] ~= v then
			return false
		end
	end
	return true
end

function Signal.reset()
	Signal.model = SignalModel.new(State.lostFrequency)
	lastSnapshot = nil
	Signal.syncFacts()
end

function Signal.syncFacts()
	local m = Signal.model
	State.setFact("consolePowered", m.consolePowered)
	State.setFact("carrierHeld", SignalModel.isCarrierHeld(m))
	State.setFact("panelAUp", m.panelA)
	State.setFact("panelBUp", m.panelB)
	State.setFact("panelAReset", State.fact("panelAReset") or m.panelA)
	State.setFact("panelBReset", State.fact("panelBReset") or m.panelB)
	State.setFact("channel0OnAir", m.onAir == "Channel0")
	State.setFact(
		"lostFrequencyLocked",
		m.zeroChannelOpen and m.tuningLocked and SignalModel.isNear(m.frequency, m.lostFrequency)
	)
	State.setFact("fillerOnAir", State.fact("fillerOnAir") or (m.onAir == "VTR" and State.fact("fillerInMCR")))
	Remotes.setState(Net.Attr.ProgramSource, m.onAir)
end

-- Device entry points. Each returns ok + optional reason (a Strings key suffix for UI feedback).
function Signal.powerConsole(): boolean
	Signal.model.consolePowered = true
	Signal.syncFacts()
	return true
end

function Signal.setSource(source: string): (boolean, string?)
	local valid = { Bars = true, Studio = true, VTR = true, Slate = true, Channel0 = true }
	if not valid[source] then
		return false, "invalid"
	end
	local ok, reason = SignalModel.setOnAir(Signal.model, source :: any)
	if ok and source == "Slate" then
		Registry.Session.cueAll({ kind = "Subtitle", key = "sub.slate", speaker = "Caption", duration = 4 })
		Registry.Session.cueAll({ kind = "Pulse", amount = 0.6, duration = 1.2 })
	end
	Signal.syncFacts()
	return ok, reason
end

function Signal.tune(frequency: number)
	local m = Signal.model
	m.frequency = math.clamp(frequency, SignalConfig.TunerMin, SignalConfig.TunerMax)
	-- Moving the dial always unlocks it.
	m.tuningLocked = false
	Signal.syncFacts()
end

-- Locks the exciter. Returns what was locked: "Carrier", "Lost", "Taken", or nil for nothing.
function Signal.lock(): string?
	local m = Signal.model
	if SignalModel.isCarrierHeld(m) then
		m.tuningLocked = true
		State.setFact("carrierTuned", true)
		Signal.syncFacts()
		return "Carrier"
	end
	if m.zeroChannelOpen and SignalModel.isNear(m.frequency, m.lostFrequency) then
		m.tuningLocked = true
		Signal.syncFacts()
		return "Lost"
	end
	if Registry.Crew.recoverByFrequency(m.frequency) then
		return "Taken"
	end
	return nil
end

function Signal.setPanel(panel: string, up: boolean)
	if panel == "A" then
		Signal.model.panelA = up
	else
		Signal.model.panelB = up
	end
	Registry.Lighting.refreshPower()
	Signal.syncFacts()
end

function Signal.setVtrLoaded(loaded: boolean)
	Signal.model.vtrLoaded = loaded
	Signal.syncFacts()
end

function Signal.setCamerasOffline(count: number)
	Signal.model.camerasOffline = count
end

function Signal.openZeroChannel()
	Signal.model.zeroChannelOpen = true
	Signal.syncFacts()
end

-- Tuning drift fault: nudges the exciter off the carrier.
function Signal.drift(amount: number)
	local m = Signal.model
	m.frequency = math.clamp(m.frequency + amount, SignalConfig.TunerMin, SignalConfig.TunerMax)
	m.tuningLocked = false
	Signal.syncFacts()
end

function Signal.slateActive(): boolean
	return Signal.model.onAir == "Slate"
end

function Signal.deadAir(): boolean
	return Signal.model.deadAir and Signal.model.deadAirArmed
end

function Signal.snapshot(): { [string]: any }
	return SignalModel.snapshot(Signal.model)
end

function Signal.step(dt: number)
	local m = Signal.model
	m.deadAirArmed = PhaseOrder.atLeast(State.phase, "Escalation") and State.phase ~= "Finale"
	m.externalInterference = Registry.Anchor.interference()
	local events = SignalModel.step(m, dt)
	for _, event in events do
		if event == "DeadAirStarted" and m.deadAirArmed then
			Registry.Session.cueAll({ kind = "Notice", key = "notice.deadAir", style = "Alert" })
			Registry.Session.cueAll({ kind = "Sound", sound = "Dropout" })
		elseif event == "CarrierDropped" then
			State.addCounter("carrierDrops")
			Registry.Session.cueAll({ kind = "Subtitle", key = "sub.carrierDrop", speaker = "Caption", duration = 5 })
			Registry.Session.cueAll({ kind = "Pulse", amount = 1.4, duration = 3 })
			Registry.Lighting.flickerAll(4)
		elseif event == "SlateEnded" then
			Registry.Session.cueAll({ kind = "Sound", sound = "UISwitch" })
		end
	end
	Signal.syncFacts()

	publishTimer += dt
	if publishTimer >= SignalConfig.PublishInterval then
		publishTimer = 0
		local snapshot = Signal.snapshot()
		if not shallowEqual(lastSnapshot, snapshot) then
			lastSnapshot = snapshot
			Remotes.fireAll("Signal", snapshot)
		end
	end
end

return Signal
