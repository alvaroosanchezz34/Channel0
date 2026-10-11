--!strict
--[[
	Endings and their verifiable requirements. Logic/EndingEvaluator checks these against session
	facts; the server is the only one who evaluates them.
]]

export type Requirement = { fact: string, textKey: string }

export type EndingDef = {
	id: string,
	titleKey: string,
	summaryKey: string,
	kind: "Choice" | "Automatic",
	requirements: { Requirement },
	-- Choice endings are triggered from a device; this names it.
	device: string?,
	tone: "Bittersweet" | "Release" | "Dark" | "Neutral" | "Defeat",
}

local Endings = {}

Endings.Defs = {
	CutSignal = {
		id = "CutSignal",
		titleKey = "end.CutSignal.title",
		summaryKey = "end.CutSignal.summary",
		kind = "Choice",
		device = "CarrierKeyswitch",
		tone = "Bittersweet",
		requirements = {
			{ fact = "phaseCrisis", textKey = "req.phaseCrisis" },
			{ fact = "hasKillKey", textKey = "req.hasKillKey" },
		},
	},
	FullBroadcast = {
		id = "FullBroadcast",
		titleKey = "end.FullBroadcast.title",
		summaryKey = "end.FullBroadcast.summary",
		kind = "Choice",
		device = "Switcher",
		tone = "Release",
		requirements = {
			{ fact = "phaseCrisis", textKey = "req.phaseCrisis" },
			{ fact = "allClueTapesViewed", textKey = "req.allClueTapesViewed" },
			{ fact = "lostFrequencyLocked", textKey = "req.lostFrequencyLocked" },
			{ fact = "masterInMCR", textKey = "req.masterInMCR" },
			{ fact = "channel0OnAir", textKey = "req.channel0OnAir" },
		},
	},
	NewAnchor = {
		id = "NewAnchor",
		titleKey = "end.NewAnchor.title",
		summaryKey = "end.NewAnchor.summary",
		kind = "Choice",
		device = "AnchorDesk",
		tone = "Dark",
		requirements = {
			{ fact = "phaseCrisis", textKey = "req.phaseCrisis" },
			{ fact = "contractViewed", textKey = "req.contractViewed" },
			{ fact = "channel0OnAir", textKey = "req.channel0OnAir" },
		},
	},
	Dawn = {
		id = "Dawn",
		titleKey = "end.Dawn.title",
		summaryKey = "end.Dawn.summary",
		kind = "Automatic",
		tone = "Neutral",
		requirements = { { fact = "dawnReached", textKey = "req.dawnReached" } },
	},
	SignalLost = {
		id = "SignalLost",
		titleKey = "end.SignalLost.title",
		summaryKey = "end.SignalLost.summary",
		kind = "Automatic",
		tone = "Defeat",
		requirements = { { fact = "allTaken", textKey = "req.allTaken" } },
	},
} :: { [string]: EndingDef }

Endings.Order = { "FullBroadcast", "NewAnchor", "CutSignal", "Dawn", "SignalLost" }

return Endings
