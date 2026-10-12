--!strict
--[[
	Endings. Choice endings are requested from a device by a real player and verified against the
	session facts (the carrier key must be on THAT player for Cut the Signal). Automatic endings
	come from the clock (Dawn) or the crew (Signal Lost). Only this module ends a night.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EndingContent = require(Shared.Content.Endings)
local EndingEvaluator = require(Shared.Logic.EndingEvaluator)

local Registry = require(script.Parent.Registry)
local State = require(script.Parent.State)

local Endings = {}

local function finish(endingId: string, actor: State.CrewMember?)
	if State.session ~= "Running" or State.ending then
		return
	end
	State.ending = endingId
	if EndingContent.Defs[endingId].kind == "Choice" then
		State.setFact("endingChosen", true)
	end
	Registry.Session.beginEnding(endingId, actor)
end

function Endings.choice(player: Player, endingId: string): (boolean, { string }?)
	local member = State.member(player)
	local def = EndingContent.Defs[endingId]
	if not member or member.status ~= "Active" or not def or def.kind ~= "Choice" then
		return false, nil
	end
	local facts = table.clone(State.facts)
	if endingId == "CutSignal" then
		facts.hasKillKey = member.hasKey
	end
	local ok, missing = EndingEvaluator.check(endingId, facts)
	if not ok then
		Registry.Devices.message(player, "dev.confirm.warning")
		return false, missing
	end
	finish(endingId, member)
	return true, nil
end

function Endings.automatic(endingId: string)
	local def = EndingContent.Defs[endingId]
	if not def or def.kind ~= "Automatic" then
		return
	end
	local ok = EndingEvaluator.check(endingId, State.facts)
	if ok then
		finish(endingId, nil)
	end
end

-- Debug: report what each ending still needs.
function Endings.report(): { EndingEvaluator.Report }
	return EndingEvaluator.report(table.clone(State.facts))
end

return Endings
