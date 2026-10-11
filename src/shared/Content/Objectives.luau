--!strict
--[[
	Objectives are team-wide, so nobody's disconnection can strand progress. The server marks
	progress from validated facts only (never from client claims).

	`goal` may scale with player count via `goalByPlayers` (index = player count).
	`blocking = false` objectives are shown but never hold up the phase.
	`condition` objectives are standing instructions (e.g. "keep the station on air").
]]

export type ObjectiveDef = {
	id: string,
	phase: string,
	textKey: string,
	hintKey: string?,
	goal: number,
	goalByPlayers: { number }?,
	blocking: boolean,
	condition: boolean?,
	fact: string?, -- completes when this fact becomes true
	counter: string?, -- progresses with this counter
}

local Objectives = {}

Objectives.Defs = {
	-- Arrival
	{ id = "signin", phase = "Arrival", textKey = "obj.signin", hintKey = "hint.signin", goal = 1, blocking = true, fact = "signedIn" },
	{ id = "reach_mcr", phase = "Arrival", textKey = "obj.reach_mcr", hintKey = "hint.reach_mcr", goal = 1, blocking = true, fact = "reachedMCR" },
	{ id = "power_console", phase = "Arrival", textKey = "obj.power_console", hintKey = "hint.power_console", goal = 1, blocking = true, fact = "consolePowered" },
	{ id = "watch_orientation", phase = "Arrival", textKey = "obj.watch_orientation", goal = 1, blocking = false, fact = "orientationViewed" },

	-- Maintenance
	{ id = "tune_carrier", phase = "Maintenance", textKey = "obj.tune_carrier", hintKey = "hint.tune_carrier", goal = 1, blocking = true, fact = "carrierTuned" },
	{ id = "panel_a", phase = "Maintenance", textKey = "obj.panel_a", hintKey = "hint.panel_a", goal = 1, blocking = true, fact = "panelAReset" },
	{ id = "panel_b", phase = "Maintenance", textKey = "obj.panel_b", hintKey = "hint.panel_b", goal = 1, blocking = true, fact = "panelBReset" },
	{ id = "load_filler", phase = "Maintenance", textKey = "obj.load_filler", hintKey = "hint.load_filler", goal = 1, blocking = true, fact = "fillerOnAir" },
	{
		id = "check_cameras",
		phase = "Maintenance",
		textKey = "obj.check_cameras",
		hintKey = "hint.check_cameras",
		goal = 4,
		goalByPlayers = { 4, 5, 6, 6 },
		blocking = true,
		counter = "camerasChecked",
	},

	-- Anomaly (scripted; completes itself when the 02:17 broadcast ends)
	{ id = "witness", phase = "Anomaly", textKey = "obj.witness", goal = 1, blocking = true, fact = "anomalyWitnessed" },

	-- Escalation
	{ id = "keep_air", phase = "Escalation", textKey = "obj.keep_air", goal = 1, blocking = false, condition = true },
	{ id = "find_source", phase = "Escalation", textKey = "obj.find_source", hintKey = "hint.find_source", goal = 3, blocking = true, counter = "clueTapesViewed" },
	{ id = "studio_b", phase = "Escalation", textKey = "obj.studio_b", hintKey = "hint.studio_b", goal = 1, blocking = true, fact = "studioBEntered" },

	-- Crisis
	{ id = "keep_air_crisis", phase = "Crisis", textKey = "obj.keep_air", goal = 1, blocking = false, condition = true },
	{ id = "decide", phase = "Crisis", textKey = "obj.decide", hintKey = "hint.decide", goal = 1, blocking = true, fact = "endingChosen" },
} :: { ObjectiveDef }

return Objectives
