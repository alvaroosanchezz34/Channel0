--!strict
--[[
	Team objectives evaluated from facts and counters. Completion latches: an objective that was
	done stays done even if its fact later flips (e.g. the panel trips again in Escalation).
]]

local Objectives = require(script.Parent.Parent.Content.Objectives)

type ObjectiveDef = Objectives.ObjectiveDef

export type Tracker = {
	defs: { ObjectiveDef },
	playerCount: number,
	done: { [string]: boolean },
	progress: { [string]: number },
}

export type View = {
	id: string,
	textKey: string,
	hintKey: string?,
	done: boolean,
	progress: number,
	goal: number,
	optional: boolean,
	condition: boolean,
}

local ObjectiveTracker = {}

function ObjectiveTracker.new(playerCount: number, defs: { ObjectiveDef }?): Tracker
	return {
		defs = defs or Objectives.Defs,
		playerCount = math.max(1, playerCount),
		done = {},
		progress = {},
	}
end

function ObjectiveTracker.goalOf(tracker: Tracker, def: ObjectiveDef): number
	if def.goalByPlayers then
		local index = math.clamp(tracker.playerCount, 1, #def.goalByPlayers)
		return def.goalByPlayers[index]
	end
	return def.goal
end

function ObjectiveTracker.setPlayerCount(tracker: Tracker, count: number)
	tracker.playerCount = math.max(1, count)
end

-- Re-evaluates every objective. Returns ids that became complete during this call.
function ObjectiveTracker.evaluate(tracker: Tracker, facts: { [string]: boolean }, counters: { [string]: number }): { string }
	local completed = {}
	for _, def in tracker.defs do
		if not def.condition and not tracker.done[def.id] then
			local goal = ObjectiveTracker.goalOf(tracker, def)
			local progress = 0
			if def.fact then
				progress = if facts[def.fact] then goal else 0
			elseif def.counter then
				progress = math.min(goal, counters[def.counter] or 0)
			end
			tracker.progress[def.id] = progress
			if progress >= goal then
				tracker.done[def.id] = true
				table.insert(completed, def.id)
			end
		end
	end
	return completed
end

function ObjectiveTracker.phaseComplete(tracker: Tracker, phase: string): boolean
	for _, def in tracker.defs do
		if def.phase == phase and def.blocking and not def.condition and not tracker.done[def.id] then
			return false
		end
	end
	return true
end

function ObjectiveTracker.view(tracker: Tracker, phase: string): { View }
	local list = {}
	for _, def in tracker.defs do
		if def.phase == phase then
			table.insert(list, {
				id = def.id,
				textKey = def.textKey,
				hintKey = def.hintKey,
				done = tracker.done[def.id] == true,
				progress = tracker.progress[def.id] or 0,
				goal = ObjectiveTracker.goalOf(tracker, def),
				optional = not def.blocking,
				condition = def.condition == true,
			})
		end
	end
	return list
end

return ObjectiveTracker
