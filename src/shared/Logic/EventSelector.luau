--!strict
--[[
	Chooses the next horror event. Pure: given the catalogue, the selector's memory, a context and
	a seeded RNG, it returns an event definition (or nil when the night should stay quiet).

	Rules: phase window, per-event cooldown, per-tier gap, max repeats, required facts, Anchor
	state, isolation, a calm period after Critical events, no immediate repeats, and a tension
	budget that refills over time so intensity is paced rather than random.
]]

local Events = require(script.Parent.Parent.Content.Events)
local PhaseOrder = require(script.Parent.PhaseOrder)
local SeededRandom = require(script.Parent.Parent.Util.SeededRandom)

type EventDef = Events.EventDef

export type Context = {
	now: number,
	phase: string,
	facts: { [string]: boolean },
	anchorState: string,
	hasIsolated: boolean,
	blocked: boolean, -- cinematic/ending in progress
}

export type Selector = {
	lastRunAt: { [string]: number },
	repeats: { [string]: number },
	lastTierAt: { [string]: number },
	history: { string },
	budget: number,
	calmUntil: number,
	defs: { EventDef },
}

local EventSelector = {}

function EventSelector.new(defs: { EventDef }?): Selector
	return {
		lastRunAt = {},
		repeats = {},
		lastTierAt = {},
		history = {},
		budget = 0.4,
		calmUntil = 0,
		defs = defs or Events.Defs,
	}
end

local function factsSatisfied(requires: { string }?, facts: { [string]: boolean }): boolean
	if not requires then
		return true
	end
	for _, requirement in requires do
		if string.sub(requirement, 1, 1) == "!" then
			if facts[string.sub(requirement, 2)] then
				return false
			end
		elseif not facts[requirement] then
			return false
		end
	end
	return true
end

function EventSelector.refill(selector: Selector, phase: string, dt: number)
	local rate = Events.TensionRefill[phase] or 0
	selector.budget = math.min(Events.TensionBudgetMax, selector.budget + rate * dt)
end

-- Returns whether `def` may run now, and a reason when it may not (for the debug panel).
function EventSelector.eligible(selector: Selector, def: EventDef, ctx: Context): (boolean, string?)
	if ctx.blocked then
		return false, "blocked"
	end
	if not PhaseOrder.within(ctx.phase, def.minPhase, def.maxPhase) then
		return false, "phase"
	end
	local last = selector.lastRunAt[def.id]
	if last and ctx.now - last < def.cooldown then
		return false, "cooldown"
	end
	local tierLast = selector.lastTierAt[def.tier]
	local gap = Events.TierGap[def.tier] or 0
	if tierLast and ctx.now - tierLast < gap then
		return false, "tierGap"
	end
	if def.maxRepeats and (selector.repeats[def.id] or 0) >= def.maxRepeats then
		return false, "maxRepeats"
	end
	if not factsSatisfied(def.requires, ctx.facts) then
		return false, "facts"
	end
	if def.anchorStates and not table.find(def.anchorStates, ctx.anchorState) then
		return false, "anchorState"
	end
	if def.needsIsolated and not ctx.hasIsolated then
		return false, "isolation"
	end
	if def.tier ~= "Fault" and def.tier ~= "Subtle" and ctx.now < selector.calmUntil then
		return false, "calm"
	end
	if def.tier ~= "Fault" and def.intensity > selector.budget then
		return false, "budget"
	end
	local n = #selector.history
	if n >= 1 and selector.history[n] == def.id then
		return false, "repeat"
	end
	if n >= 2 and selector.history[n - 1] == def.id and def.tier ~= "Fault" then
		return false, "repeat"
	end
	return true, nil
end

-- Picks among eligible events of the given tiers (all tiers when nil).
function EventSelector.choose(
	selector: Selector,
	ctx: Context,
	rng: SeededRandom.SeededRandom,
	tiers: { string }?
): EventDef?
	local candidates: { EventDef } = {}
	for _, def in selector.defs do
		if (not tiers or table.find(tiers, def.tier)) and EventSelector.eligible(selector, def, ctx) then
			table.insert(candidates, def)
		end
	end
	if #candidates == 0 then
		return nil
	end
	return rng:WeightedPick(candidates, function(def: EventDef)
		return def.weight
	end)
end

function EventSelector.record(selector: Selector, def: EventDef, now: number)
	selector.lastRunAt[def.id] = now
	selector.lastTierAt[def.tier] = now
	selector.repeats[def.id] = (selector.repeats[def.id] or 0) + 1
	table.insert(selector.history, def.id)
	if #selector.history > 16 then
		table.remove(selector.history, 1)
	end
	if def.tier ~= "Fault" then
		selector.budget = math.max(0, selector.budget - def.intensity)
	end
	if def.tier == "Critical" then
		selector.calmUntil = now + Events.CalmAfterCritical
	end
end

function EventSelector.find(selector: Selector, id: string): EventDef?
	for _, def in selector.defs do
		if def.id == id then
			return def
		end
	end
	return nil
end

return EventSelector
