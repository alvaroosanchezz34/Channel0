--!strict
--[[
	Explicit session states and the only legal transitions between them. SessionService is the
	single owner; any other system asks it to transition.
]]

local SessionMachine = {}

SessionMachine.Transitions = {
	Lobby = { Intro = true, Resetting = true },
	Intro = { Running = true, Resetting = true },
	Running = { Ending = true, Resetting = true },
	Ending = { Results = true, Resetting = true },
	Results = { Resetting = true },
	Resetting = { Lobby = true },
} :: { [string]: { [string]: boolean } }

function SessionMachine.canTransition(from: string, to: string): boolean
	local allowed = SessionMachine.Transitions[from]
	return allowed ~= nil and allowed[to] == true
end

return SessionMachine
