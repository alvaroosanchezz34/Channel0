--!strict
--[[
	The single source of truth for one night: facts, counters, crew records, seed and RNG streams.
	Services mutate it only through these functions so every change raises `Changed`, which is
	what objectives, endings and the director react to.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SeededRandom = require(Shared.Util.SeededRandom)
local Signal = require(Shared.Util.Signal)

export type CrewStatus = "Lobby" | "Active" | "Taken" | "Spectating"

export type CrewMember = {
	player: Player,
	userId: number,
	name: string,
	status: CrewStatus,
	ready: boolean,
	tapes: { string },
	hasKey: boolean,
	takenFrequency: number?,
	takenAt: number?,
	secondChances: number,
	zone: string,
	zoneSince: number,
	stamina: number,
	sprinting: boolean,
	joinedLate: boolean,
	timesTaken: number,
}

local State = {}

State.Changed = Signal.new() :: any -- (kind: "fact" | "counter" | "crew" | "reset", name: string?)
State.facts = {} :: { [string]: boolean }
State.counters = {} :: { [string]: number }
State.crew = {} :: { [number]: CrewMember }
State.seed = 0
State.rng = SeededRandom.new(1)
State.session = "Lobby"
State.phase = "Arrival"
State.clock = -20
State.runStartedAt = 0
State.phaseStartedAt = 0
State.ending = nil :: string?
State.lostFrequency = 0
State.cluePieces = {} :: { string }

function State.newNight(seed: number)
	State.seed = seed
	State.rng = SeededRandom.new(seed)
	table.clear(State.facts)
	table.clear(State.counters)
	State.phase = "Arrival"
	State.clock = -20
	State.ending = nil
	State.Changed:Fire("reset", nil)
end

-- Independent deterministic stream for a subsystem (so one system's draws never shift another's).
function State.stream(name: string): SeededRandom.SeededRandom
	return SeededRandom.new(State.seed):Fork(name)
end

function State.setFact(name: string, value: boolean)
	if (State.facts[name] == true) ~= value then
		State.facts[name] = value
		State.Changed:Fire("fact", name)
	end
end

function State.fact(name: string): boolean
	return State.facts[name] == true
end

function State.addCounter(name: string, amount: number?)
	State.counters[name] = (State.counters[name] or 0) + (amount or 1)
	State.Changed:Fire("counter", name)
end

function State.setCounter(name: string, value: number)
	if State.counters[name] ~= value then
		State.counters[name] = value
		State.Changed:Fire("counter", name)
	end
end

function State.counter(name: string): number
	return State.counters[name] or 0
end

function State.addCrew(player: Player): CrewMember
	local member: CrewMember = {
		player = player,
		userId = player.UserId,
		name = player.DisplayName,
		status = "Lobby",
		ready = false,
		tapes = {},
		hasKey = false,
		takenFrequency = nil,
		takenAt = nil,
		secondChances = 0,
		zone = "Exterior",
		zoneSince = os.clock(),
		stamina = 1,
		sprinting = false,
		joinedLate = false,
		timesTaken = 0,
	}
	State.crew[player.UserId] = member
	State.Changed:Fire("crew", nil)
	return member
end

function State.removeCrew(player: Player)
	State.crew[player.UserId] = nil
	State.Changed:Fire("crew", nil)
end

function State.member(player: Player): CrewMember?
	return State.crew[player.UserId]
end

function State.setStatus(member: CrewMember, status: CrewStatus)
	if member.status ~= status then
		member.status = status
		State.Changed:Fire("crew", nil)
	end
end

-- Members in the given statuses (all when nil), in stable join order.
function State.members(statuses: { string }?): { CrewMember }
	local list = {}
	for _, member in State.crew do
		if not statuses or table.find(statuses :: { string }, member.status) then
			table.insert(list, member)
		end
	end
	table.sort(list, function(a, b)
		return a.userId < b.userId
	end)
	return list
end

function State.activeCount(): number
	return #State.members({ "Active" })
end

-- Crew in the night (active or taken): used for objective scaling and endings.
function State.shiftCount(): number
	return #State.members({ "Active", "Taken" })
end

function State.anyCarries(tapeId: string): boolean
	for _, member in State.crew do
		if table.find(member.tapes, tapeId) then
			return true
		end
	end
	return false
end

return State
