--!strict
local PhaseOrder = {}

PhaseOrder.List = { "Arrival", "Maintenance", "Anomaly", "Escalation", "Crisis", "Finale" }

local indexOf: { [string]: number } = {}
for index, name in PhaseOrder.List do
	indexOf[name] = index
end

function PhaseOrder.index(phase: string): number
	return indexOf[phase] or 0
end

function PhaseOrder.atLeast(phase: string, minimum: string): boolean
	return PhaseOrder.index(phase) >= PhaseOrder.index(minimum)
end

function PhaseOrder.within(phase: string, minimum: string, maximum: string): boolean
	local i = PhaseOrder.index(phase)
	return i >= PhaseOrder.index(minimum) and i <= PhaseOrder.index(maximum)
end

function PhaseOrder.next(phase: string): string?
	local i = PhaseOrder.index(phase)
	return PhaseOrder.List[i + 1]
end

return PhaseOrder
