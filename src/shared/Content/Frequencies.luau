--!strict
--[[
	What lives on the dial. Every non-static frequency carries information that matters:
	a rule, a warning, a prediction, or a clue. Lines are Strings keys.

	kinds:
		Carrier   the station's own carrier (maintenance target)
		Loop      a fixed message that repeats
		Dynamic   composed by the server from what is ABOUT to happen (Night Desk prophecy)
		Lost      the zero channel; its value is chosen per session (see Tapes.LostFrequencies)
		Taken     a taken teammate; value assigned when it happens
]]

export type FrequencyDef = {
	id: string,
	mhz: number?,
	kind: "Carrier" | "Loop" | "Dynamic" | "Lost" | "Taken",
	lines: { string },
	minPhase: string,
	nameKey: string,
}

local Frequencies = {}

Frequencies.Defs = {
	{
		id = "Carrier",
		mhz = 55.25,
		kind = "Carrier",
		lines = { "freq.Carrier.l1" },
		minPhase = "Arrival",
		nameKey = "freq.Carrier.name",
	},
	{
		id = "Emergency",
		mhz = 121.5,
		kind = "Loop",
		lines = { "freq.Emergency.l1", "freq.Emergency.l2", "freq.Emergency.l3", "freq.Emergency.l4" },
		minPhase = "Maintenance",
		nameKey = "freq.Emergency.name",
	},
	{
		id = "Dispatch",
		mhz = 88.1,
		kind = "Loop",
		lines = { "freq.Dispatch.l1", "freq.Dispatch.l2", "freq.Dispatch.l3" },
		minPhase = "Maintenance",
		nameKey = "freq.Dispatch.name",
	},
	{
		id = "NightDesk",
		mhz = 98.7,
		kind = "Dynamic",
		lines = { "freq.NightDesk.intro" },
		minPhase = "Anomaly",
		nameKey = "freq.NightDesk.name",
	},
	{
		id = "RollCall",
		mhz = 72.4,
		kind = "Loop",
		lines = { "freq.RollCall.l1", "freq.RollCall.l2", "freq.RollCall.l3" },
		minPhase = "Escalation",
		nameKey = "freq.RollCall.name",
	},
	{
		id = "Lost",
		kind = "Lost",
		lines = { "freq.Lost.l1", "freq.Lost.l2" },
		minPhase = "Escalation",
		nameKey = "freq.Lost.name",
	},
} :: { FrequencyDef }

-- Values handed out to taken players (a teammate tunes it to bring them back).
Frequencies.TakenPool = { 63.4, 77.85, 84.1, 91.65, 108.3, 112.75 }

-- Seconds between lines of a looping message.
Frequencies.LineInterval = 5.5
-- MHz window in which a station starts to fade in through the static.
Frequencies.AudibleWindow = 0.6

return Frequencies
