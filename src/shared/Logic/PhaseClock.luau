--!strict
--[[
	Fictional clock. Advances at the phase rate and stalls at the phase cap until the phase's
	blocking objectives are complete. Crisis caps at dawn, which ends the night.
]]

local PhaseClock = {}

export type PhaseTiming = { startClock: number, cap: number, rate: number }

-- Returns the new clock and whether the phase cap has been reached.
function PhaseClock.advance(clock: number, timing: PhaseTiming, dt: number, objectivesComplete: boolean): (number, boolean)
	local nextClock = clock + timing.rate * dt
	if nextClock >= timing.cap then
		if objectivesComplete then
			return timing.cap, true
		end
		-- Stall a few fictional seconds before the cap: the clocks sit at 02:16 until you're done.
		return math.min(nextClock, timing.cap - 1 / 60), false
	end
	return nextClock, false
end

return PhaseClock
