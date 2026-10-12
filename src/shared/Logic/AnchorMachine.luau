--!strict
--[[
	THE ANCHOR's state machine (pure, deterministic given a SeededRandom).

	The machine owns every timer and every transition. The server brain (server/Anchor) only:
	  * supplies context (phase, pressure, slate, target info),
	  * reacts to the returned events (choose a location, move, appear, vanish).
	Clients never influence transitions except through validated game actions (e.g. the slate).

	Displacement runs "pre-echo" cycles: a future feed shows him somewhere, `lead` seconds later he
	physically appears there for a few seconds, then vanishes. That is the rule players can learn
	from the orientation tape: the feed is early, not wrong.
]]

local AnchorConfig = require(script.Parent.Parent.Config.AnchorConfig)
local PhaseOrder = require(script.Parent.PhaseOrder)
local SeededRandom = require(script.Parent.Parent.Util.SeededRandom)

export type AnchorState = "Dormant" | "Broadcast" | "Observing" | "Displacement" | "Manifestation" | "Hunt" | "Withdrawal"

export type Context = {
	phase: string,
	pressure: number,
	slateActive: boolean,
	deadAir: boolean,
	hasTarget: boolean,
	targetLostFor: number,
	caught: boolean,
	aggression: number, -- player-count scaling (0.7..1.1)
}

export type MachineEvent = {
	kind: "Entered" | "PreEcho" | "Appear" | "Vanish" | "TelegraphEnded",
	state: AnchorState?,
	from: AnchorState?,
	reason: string?,
	lead: number?,
}

export type Machine = {
	state: AnchorState,
	timeInState: number,
	stateDuration: number,
	huntCooldown: number,
	telegraphing: boolean,
	cyclesLeft: number,
	cyclePhase: "Lead" | "Appear" | "Idle",
	cycleTimer: number,
	rng: SeededRandom.SeededRandom,
	history: { { from: AnchorState, to: AnchorState, reason: string } },
}

local AnchorMachine = {}

AnchorMachine.Allowed = {
	Dormant = { Broadcast = true },
	Broadcast = { Observing = true, Withdrawal = true },
	Observing = { Displacement = true, Withdrawal = true },
	Displacement = { Manifestation = true, Observing = true, Withdrawal = true },
	Manifestation = { Hunt = true, Withdrawal = true },
	Hunt = { Withdrawal = true },
	Withdrawal = { Observing = true, Broadcast = true },
} :: { [string]: { [string]: boolean } }

local function roll(rng: SeededRandom.SeededRandom, range: { number }): number
	return rng:NextNumber(range[1], range[2])
end

function AnchorMachine.new(rng: SeededRandom.SeededRandom): Machine
	return {
		state = "Dormant",
		timeInState = 0,
		stateDuration = math.huge,
		huntCooldown = 0,
		telegraphing = false,
		cyclesLeft = 0,
		cyclePhase = "Idle",
		cycleTimer = 0,
		rng = rng,
		history = {},
	}
end

function AnchorMachine.canTransition(from: string, to: string): boolean
	local allowed = AnchorMachine.Allowed[from]
	return allowed ~= nil and allowed[to] == true
end

local function startCycle(machine: Machine, events: { MachineEvent })
	local lead = roll(machine.rng, AnchorConfig.PreEchoLead)
	machine.cyclePhase = "Lead"
	machine.cycleTimer = lead
	table.insert(events, { kind = "PreEcho", lead = lead })
end

local function enter(machine: Machine, to: AnchorState, reason: string, ctx: Context, events: { MachineEvent })
	local from: AnchorState = machine.state
	assert(AnchorMachine.canTransition(from, to), `illegal anchor transition {from} -> {to}`)
	machine.state = to
	machine.timeInState = 0
	machine.telegraphing = false
	machine.cyclePhase = "Idle"
	table.insert(machine.history, { from = from, to = to, reason = reason })
	if #machine.history > 64 then
		table.remove(machine.history, 1)
	end

	local scale = 1 - 0.4 * math.clamp(ctx.pressure, 0, 1)
	if to == "Observing" then
		machine.stateDuration = roll(machine.rng, AnchorConfig.ObserveDuration) * scale / math.max(0.5, ctx.aggression)
	elseif to == "Displacement" then
		machine.cyclesLeft =
			machine.rng:NextInteger(AnchorConfig.DisplacementCycles[1], AnchorConfig.DisplacementCycles[2])
		machine.stateDuration = math.huge
	elseif to == "Manifestation" then
		machine.stateDuration = AnchorConfig.ManifestMaxDuration
	elseif to == "Hunt" then
		machine.telegraphing = true
		machine.stateDuration = AnchorConfig.HuntTelegraph
			+ roll(machine.rng, AnchorConfig.HuntDuration) * ctx.aggression
	elseif to == "Withdrawal" then
		local crisis = ctx.phase == "Crisis"
		machine.stateDuration = roll(machine.rng, AnchorConfig.WithdrawalDuration) * (if crisis then 0.6 else 1)
		if from == "Hunt" then
			machine.huntCooldown = AnchorConfig.HuntCooldown * (if crisis then 0.7 else 1)
		end
	else
		machine.stateDuration = math.huge
	end

	table.insert(events, { kind = "Entered", state = to, from = from, reason = reason })
	if to == "Displacement" then
		startCycle(machine, events)
	end
end

-- Advances the machine by dt. Returns the events that happened this step, in order.
function AnchorMachine.step(machine: Machine, dt: number, ctx: Context): { MachineEvent }
	local events: { MachineEvent } = {}
	machine.timeInState += dt
	if machine.huntCooldown > 0 then
		machine.huntCooldown = math.max(0, machine.huntCooldown - dt)
	end
	local state = machine.state
	local t = machine.timeInState

	if state == "Dormant" then
		if PhaseOrder.atLeast(ctx.phase, "Anomaly") then
			enter(machine, "Broadcast", "Anomaly", ctx, events)
		end
	elseif state == "Broadcast" then
		if PhaseOrder.atLeast(ctx.phase, "Escalation") and t >= AnchorConfig.BroadcastMinDuration then
			enter(machine, "Observing", "Escalation", ctx, events)
		end
	elseif state == "Observing" then
		if t >= machine.stateDuration then
			enter(machine, "Displacement", "ObserveTimeout", ctx, events)
		end
	elseif state == "Displacement" then
		if ctx.slateActive then
			enter(machine, "Withdrawal", "Slate", ctx, events)
			return events
		end
		machine.cycleTimer -= dt
		if machine.cyclePhase == "Lead" and machine.cycleTimer <= 0 then
			machine.cyclePhase = "Appear"
			machine.cycleTimer = AnchorConfig.DisplacementAppearance
			table.insert(events, { kind = "Appear" })
		elseif machine.cyclePhase == "Appear" and machine.cycleTimer <= 0 then
			table.insert(events, { kind = "Vanish" })
			machine.cyclesLeft -= 1
			if machine.cyclesLeft > 0 then
				startCycle(machine, events)
			elseif ctx.pressure >= AnchorConfig.ManifestPressure then
				enter(machine, "Manifestation", "Pressure", ctx, events)
			else
				enter(machine, "Observing", "LowPressure", ctx, events)
			end
		end
	elseif state == "Manifestation" then
		if ctx.slateActive then
			enter(machine, "Withdrawal", "Slate", ctx, events)
		elseif
			t >= AnchorConfig.ManifestMinDuration
			and machine.huntCooldown <= 0
			and ctx.hasTarget
			and (ctx.phase == "Crisis" or ctx.deadAir or ctx.pressure >= AnchorConfig.HuntPressure)
		then
			enter(machine, "Hunt", if ctx.deadAir then "DeadAir" else "Pressure", ctx, events)
		elseif t >= machine.stateDuration then
			enter(machine, "Withdrawal", "ManifestTimeout", ctx, events)
		end
	elseif state == "Hunt" then
		if machine.telegraphing then
			-- The warning always plays out in full: no catch is possible before it ends.
			if t >= AnchorConfig.HuntTelegraph then
				machine.telegraphing = false
				table.insert(events, { kind = "TelegraphEnded" })
			elseif ctx.slateActive then
				enter(machine, "Withdrawal", "Slate", ctx, events)
			end
		elseif ctx.caught then
			enter(machine, "Withdrawal", "Caught", ctx, events)
		elseif ctx.slateActive then
			enter(machine, "Withdrawal", "Slate", ctx, events)
		elseif ctx.targetLostFor >= AnchorConfig.LoseTargetAfter then
			enter(machine, "Withdrawal", "LostTarget", ctx, events)
		elseif t >= machine.stateDuration then
			enter(machine, "Withdrawal", "HuntTimeout", ctx, events)
		end
	elseif state == "Withdrawal" then
		if t >= machine.stateDuration then
			if PhaseOrder.atLeast(ctx.phase, "Escalation") then
				enter(machine, "Observing", "Return", ctx, events)
			else
				enter(machine, "Broadcast", "Return", ctx, events)
			end
		end
	end

	return events
end

-- Can a hunting Anchor catch someone right now? (never during the telegraph)
function AnchorMachine.canCatch(machine: Machine): boolean
	return machine.state == "Hunt" and not machine.telegraphing
end

-- Is he physically present in the world?
function AnchorMachine.isPhysical(machine: Machine): boolean
	return machine.state == "Manifestation"
		or machine.state == "Hunt"
		or (machine.state == "Displacement" and machine.cyclePhase == "Appear")
end

-- Debug/scripted transition along a legal edge only.
function AnchorMachine.force(
	machine: Machine,
	to: AnchorState,
	ctx: Context,
	reason: string
): ({ MachineEvent }?, string?)
	if not AnchorMachine.canTransition(machine.state, to) then
		return nil, `cannot go from {machine.state} to {to}`
	end
	local events: { MachineEvent } = {}
	enter(machine, to, reason, ctx, events)
	return events, nil
end

function AnchorMachine.reset(machine: Machine)
	machine.state = "Dormant"
	machine.timeInState = 0
	machine.stateDuration = math.huge
	machine.huntCooldown = 0
	machine.telegraphing = false
	machine.cyclesLeft = 0
	machine.cyclePhase = "Idle"
	machine.cycleTimer = 0
	table.clear(machine.history)
end

-- Pressure 0..1 from game context. Pure so it can be tuned and tested.
export type PressureInputs = {
	phase: string,
	phaseProgress: number,
	channel0OnAir: boolean,
	deadAir: boolean,
	carrierDrops: number,
	isolation: number, -- 0..1, how separated the crew is
	aggression: number,
}

function AnchorMachine.pressure(inputs: PressureInputs): number
	local p = 0
	local progress = math.clamp(inputs.phaseProgress, 0, 1)
	if inputs.phase == "Anomaly" then
		p = 0.1
	elseif inputs.phase == "Escalation" then
		p = 0.18 + 0.25 * progress
	elseif inputs.phase == "Crisis" or inputs.phase == "Finale" then
		p = 0.55 + 0.35 * progress
	end
	if inputs.channel0OnAir then
		p += 0.15
	end
	if inputs.deadAir then
		p += 0.25
	end
	p += 0.05 * math.min(inputs.carrierDrops, 3)
	p += 0.1 * math.clamp(inputs.isolation, 0, 1)
	return math.clamp(p * inputs.aggression, 0, 1)
end

return AnchorMachine
