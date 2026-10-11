--!strict
--[[
	Verifies ending requirements against session facts. The server is the only caller that can
	trigger an ending; the debug panel uses `report` to show what is missing.
]]

local Endings = require(script.Parent.Parent.Content.Endings)

local EndingEvaluator = {}

export type Report = { id: string, met: boolean, missing: { string } }

function EndingEvaluator.check(endingId: string, facts: { [string]: boolean }): (boolean, { string })
	local def = Endings.Defs[endingId]
	if not def then
		return false, { "unknown ending" }
	end
	local missing = {}
	for _, requirement in def.requirements do
		if not facts[requirement.fact] then
			table.insert(missing, requirement.textKey)
		end
	end
	return #missing == 0, missing
end

function EndingEvaluator.report(facts: { [string]: boolean }): { Report }
	local reports = {}
	for _, id in Endings.Order do
		local met, missing = EndingEvaluator.check(id, facts)
		table.insert(reports, { id = id, met = met, missing = missing })
	end
	return reports
end

return EndingEvaluator
