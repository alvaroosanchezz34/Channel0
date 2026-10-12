--!strict
--[[
	Narrative phases A–F, the fictional clock and team objectives.

	Arrival -> Maintenance -> Anomaly (the scripted 02:17 broadcast) -> Escalation -> Crisis -> Finale.
	The clock advances at each phase's rate and stalls just before the phase cap until the phase's
	blocking objectives are done, so progression drives time, never the reverse. Crisis is the
	exception: 06:00 arrives no matter what (Dawn ending).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Net = require(Shared.Net)
local ObjectiveTracker = require(Shared.Logic.ObjectiveTracker)
local PhaseClock = require(Shared.Logic.PhaseClock)
local PhaseOrder = require(Shared.Logic.PhaseOrder)

local Registry = require(script.Parent.Registry)
local Remotes = require(script.Parent.Remotes)
local State = require(script.Parent.State)
local World = require(script.Parent.World)

local Phase = {}

Phase.tracker = ObjectiveTracker.new(1)
local dirty = true
local anomaly: { startedAt: number, beats: { [number]: boolean } }? = nil
local studioBReadySince: number? = nil

local function publishObjectives()
	local view = ObjectiveTracker.view(Phase.tracker, State.phase)
	-- Crisis shows the ways out the crew has actually earned.
	if State.phase == "Crisis" then
		local hints = {}
		if State.fact("hasKillKey") then
			table.insert(hints, "hint.decide.cut")
		end
		if State.fact("allClueTapesViewed") then
			table.insert(hints, "hint.decide.full")
		end
		if State.fact("contractViewed") then
			table.insert(hints, "hint.decide.anchor")
		end
		for _, entry in view do
			if entry.id == "decide" then
				(entry :: any).extraHints = hints
			end
		end
	end
	Remotes.fireAll("Objectives", { phase = State.phase, list = view })
end
Phase.publishObjectives = publishObjectives

function Phase.sendObjectives(player: Player)
	Remotes.fire(
		player,
		"Objectives",
		{ phase = State.phase, list = ObjectiveTracker.view(Phase.tracker, State.phase) }
	)
end

function Phase.init()
	State.Changed:Connect(function(kind)
		if kind == "fact" or kind == "counter" or kind == "crew" then
			dirty = true
		end
	end)
end

local function setClock(value: number)
	State.clock = value
	Remotes.setState(Net.Attr.Clock, math.floor(value * 60) / 60)
end

function Phase.enter(phase: string)
	State.phase = phase
	State.phaseStartedAt = os.clock()
	local timing = GameConfig.Phases[phase]
	if timing and State.clock < timing.startClock then
		setClock(timing.startClock)
	end
	Remotes.setState(Net.Attr.Phase, phase)
	State.setFact("phaseCrisis", PhaseOrder.atLeast(phase, "Crisis"))
	Registry.Tapes.spawnForPhase(phase)
	if phase ~= "Arrival" then
		Registry.Session.cueAll({ kind = "PhaseNotice", phase = phase, key = "notice.phase." .. phase })
		Registry.Session.cueAll({ kind = "Sound", sound = "ObjectiveUpdate" })
	end
	if phase == "Anomaly" then
		anomaly = { startedAt = os.clock(), beats = {} }
		Remotes.setState(Net.Attr.AnomalyActive, true)
	elseif phase == "Escalation" then
		Registry.Radio.prophesy("freq.NightDesk.intro")
	elseif phase == "Crisis" then
		Registry.Radio.prophesy("freq.NightDesk.crisis")
		Registry.Lighting.flickerAll(2.5)
	end
	dirty = true
	publishObjectives()
end

-- The scripted first anomaly at 02:17: every monitor shows the same picture, a technician on
-- screen turns to the lens, a voice asks the crew to keep the signal on, and someone is seen at
-- the Studio A desk through the control room window.
local ANOMALY_BEATS = {
	{
		at = 0,
		run = function()
			Registry.Session.cueAll({ kind = "Anomaly", stage = "Start" })
			Registry.Session.cueAll({ kind = "Sound", sound = "EASAttention" })
			Registry.Session.cueAll({ kind = "Subtitle", key = "sub.anomaly.1", speaker = "Caption", duration = 6 })
			for zone in World.zoneFolders do
				World.setZoneAttribute(zone, "MonitorsOn", true)
			end
		end,
	},
	{
		at = 9,
		run = function()
			Registry.Session.cueAll({ kind = "Anomaly", stage = "Turn" })
			Registry.Session.cueAll({ kind = "Subtitle", key = "sub.anomaly.2", speaker = "Caption", duration = 6 })
			Registry.Session.cueAll({ kind = "Pulse", amount = 1.1, duration = 2 })
		end,
	},
	{
		at = 18,
		run = function()
			Registry.Session.cueAll({ kind = "Subtitle", key = "sub.anomaly.3", speaker = "Hale", duration = 7 })
		end,
	},
	{
		at = 28,
		run = function()
			Registry.Session.cueAll({ kind = "Anomaly", stage = "Presence" })
			Registry.Session.cueAll({ kind = "Subtitle", key = "sub.anomaly.4", speaker = "Caption", duration = 6 })
			Registry.Anchor.glimpseAtDesk(9)
			Registry.Lighting.override("StudioA", "Hunt", 9)
			Registry.Lighting.override("MasterControl", "Flicker", 4)
		end,
	},
	{
		at = GameConfig.AnomalyDuration,
		run = function()
			Registry.Session.cueAll({ kind = "Anomaly", stage = "End" })
			Remotes.setState(Net.Attr.AnomalyActive, false)
			State.setFact("anomalyWitnessed", true)
		end,
	},
}

local function stepAnomaly()
	if not anomaly then
		return
	end
	local elapsed = os.clock() - anomaly.startedAt
	for index, beat in ANOMALY_BEATS do
		if not anomaly.beats[index] and elapsed >= beat.at then
			anomaly.beats[index] = true
			beat.run()
		end
	end
	if anomaly.beats[#ANOMALY_BEATS] then
		anomaly = nil
	end
end

function Phase.step(dt: number)
	if State.session ~= "Running" then
		return
	end
	ObjectiveTracker.setPlayerCount(Phase.tracker, State.shiftCount())
	if dirty then
		dirty = false
		local completed = ObjectiveTracker.evaluate(Phase.tracker, State.facts, State.counters)
		if #completed > 0 then
			Registry.Session.cueAll({ kind = "Sound", sound = "ObjectiveUpdate" })
		end
		publishObjectives()
	end
	stepAnomaly()

	-- Studio B can only be opened once the crew has been looking for the source for a while.
	if State.phase == "Escalation" then
		local ready = State.counter("clueTapesViewed") >= 2 or os.clock() - State.phaseStartedAt >= 240
		if ready and not studioBReadySince then
			studioBReadySince = os.clock()
		end
		State.setFact("studioBReady", ready)
	end

	local timing = GameConfig.Phases[State.phase]
	if not timing or State.phase == "Finale" then
		return
	end
	local complete = ObjectiveTracker.phaseComplete(Phase.tracker, State.phase)
	if State.phase == "Crisis" then
		complete = true -- dawn comes regardless
	end
	local clock, reached = PhaseClock.advance(State.clock, timing, dt, complete)
	setClock(clock)
	Remotes.setState(Net.Attr.Stalled, not complete and clock >= timing.cap - 0.05)
	if reached then
		if State.phase == "Crisis" then
			State.setFact("dawnReached", true)
			Registry.Endings.automatic("Dawn")
			return
		end
		local nextPhase = PhaseOrder.next(State.phase)
		if nextPhase then
			Phase.enter(nextPhase)
		end
	end
end

function Phase.studioBReadyFor(): number
	return if studioBReadySince then os.clock() - studioBReadySince else 0
end

-- Debug: complete the current phase's objectives by forcing their facts/counters.
function Phase.skip()
	for _, def in Phase.tracker.defs do
		if def.phase == State.phase and not def.condition then
			if def.fact then
				State.setFact(def.fact, true)
			elseif def.counter then
				State.setCounter(
					def.counter,
					math.max(State.counter(def.counter), ObjectiveTracker.goalOf(Phase.tracker, def))
				)
			end
		end
	end
	if State.phase == "Anomaly" and anomaly then
		anomaly.startedAt -= GameConfig.AnomalyDuration
	end
	local timing = GameConfig.Phases[State.phase]
	if timing then
		setClock(math.max(State.clock, timing.cap - 0.02))
	end
end

function Phase.reset()
	Phase.tracker = ObjectiveTracker.new(math.max(1, State.shiftCount()))
	anomaly = nil
	studioBReadySince = nil
	dirty = true
	setClock(GameConfig.Phases.Arrival.startClock)
	State.phase = "Arrival"
	Remotes.setState(Net.Attr.Phase, "Arrival")
	Remotes.setState(Net.Attr.AnomalyActive, false)
	Remotes.setState(Net.Attr.Stalled, false)
end

return Phase
