--!strict
--[[
	Horror event catalogue for the Event Director. Data only: selection rules live in
	Logic/EventSelector, execution in server/Services/EventDirector handlers keyed by id.

	Fields
		tier          Subtle | Intermediate | Critical | Fault
		weight        relative chance among eligible events
		minPhase/maxPhase
		cooldown      seconds before this event may run again
		maxRepeats    per session (nil = unlimited)
		duration      expected seconds the event keeps resources busy
		intensity     0..1, feeds the tension budget and the VHS pulse
		requires      facts that must be true ("!fact" = must be false)
		anchorStates  if set, THE ANCHOR must be in one of these states
		needsIsolated if true, only runs when some player is away from the group
]]

export type EventDef = {
	id: string,
	tier: "Subtle" | "Intermediate" | "Critical" | "Fault",
	weight: number,
	minPhase: string,
	maxPhase: string,
	cooldown: number,
	maxRepeats: number?,
	duration: number,
	intensity: number,
	requires: { string }?,
	anchorStates: { string }?,
	needsIsolated: boolean?,
	descriptionKey: string,
}

local Events = {}

Events.Defs = {
	-- Subtle: most of the night is made of these. Many leave doubt rather than a scare.
	{
		id = "distant_light_failure",
		tier = "Subtle",
		weight = 5,
		minPhase = "Maintenance",
		maxPhase = "Crisis",
		cooldown = 28,
		duration = 26,
		intensity = 0.15,
		descriptionKey = "evt.distant_light_failure",
	},
	{
		id = "monitor_blink",
		tier = "Subtle",
		weight = 6,
		minPhase = "Anomaly",
		maxPhase = "Crisis",
		cooldown = 20,
		duration = 1,
		intensity = 0.2,
		descriptionKey = "evt.monitor_blink",
	},
	{
		id = "whisper_empty_room",
		tier = "Subtle",
		weight = 4,
		minPhase = "Maintenance",
		maxPhase = "Crisis",
		cooldown = 34,
		duration = 4,
		intensity = 0.15,
		descriptionKey = "evt.whisper_empty_room",
	},
	{
		id = "door_changed",
		tier = "Subtle",
		weight = 4,
		minPhase = "Maintenance",
		maxPhase = "Crisis",
		cooldown = 30,
		duration = 1,
		intensity = 0.1,
		descriptionKey = "evt.door_changed",
	},
	{
		id = "footsteps_empty",
		tier = "Subtle",
		weight = 4,
		minPhase = "Escalation",
		maxPhase = "Crisis",
		cooldown = 26,
		duration = 5,
		intensity = 0.2,
		descriptionKey = "evt.footsteps_empty",
	},
	{
		id = "phone_rings",
		tier = "Subtle",
		weight = 3,
		minPhase = "Maintenance",
		maxPhase = "Crisis",
		cooldown = 110,
		maxRepeats = 3,
		duration = 20,
		intensity = 0.2,
		requires = { "!phoneRinging" },
		descriptionKey = "evt.phone_rings",
	},

	-- Intermediate: the station contradicts what the crew believes.
	{
		id = "impossible_broadcast",
		tier = "Intermediate",
		weight = 3,
		minPhase = "Escalation",
		maxPhase = "Crisis",
		cooldown = 75,
		maxRepeats = 3,
		duration = 7,
		intensity = 0.5,
		descriptionKey = "evt.impossible_broadcast",
	},
	{
		id = "figure_hall_end",
		tier = "Intermediate",
		weight = 3,
		minPhase = "Escalation",
		maxPhase = "Crisis",
		cooldown = 65,
		duration = 5,
		intensity = 0.6,
		anchorStates = { "Observing", "Displacement", "Withdrawal" },
		descriptionKey = "evt.figure_hall_end",
	},
	{
		id = "personal_broadcast",
		tier = "Intermediate",
		weight = 2,
		minPhase = "Escalation",
		maxPhase = "Crisis",
		cooldown = 85,
		maxRepeats = 3,
		duration = 6,
		intensity = 0.45,
		needsIsolated = true,
		descriptionKey = "evt.personal_broadcast",
	},
	{
		id = "radio_future",
		tier = "Intermediate",
		weight = 3,
		minPhase = "Escalation",
		maxPhase = "Crisis",
		cooldown = 80,
		duration = 10,
		intensity = 0.35,
		descriptionKey = "evt.radio_future",
	},
	{
		id = "tape_extra_voice",
		tier = "Intermediate",
		weight = 3,
		minPhase = "Escalation",
		maxPhase = "Crisis",
		cooldown = 90,
		maxRepeats = 2,
		duration = 4,
		intensity = 0.4,
		requires = { "tapePlaying" },
		descriptionKey = "evt.tape_extra_voice",
	},

	-- Critical: changes the plan.
	{
		id = "studio_b_unsealed",
		tier = "Critical",
		weight = 100,
		minPhase = "Escalation",
		maxPhase = "Escalation",
		cooldown = 9999,
		maxRepeats = 1,
		duration = 12,
		intensity = 0.7,
		requires = { "studioBReady", "!studioBOpen" },
		descriptionKey = "evt.studio_b_unsealed",
	},
	{
		id = "blackout_wing",
		tier = "Critical",
		weight = 2,
		minPhase = "Escalation",
		maxPhase = "Crisis",
		cooldown = 140,
		maxRepeats = 2,
		duration = 30,
		intensity = 0.75,
		requires = { "panelAUp", "panelBUp" },
		descriptionKey = "evt.blackout_wing",
	},

	-- Faults: maintenance pressure. Announced on the Night Desk frequency before they happen.
	{
		id = "fault_panel_a",
		tier = "Fault",
		weight = 3,
		minPhase = "Escalation",
		maxPhase = "Crisis",
		cooldown = 70,
		duration = 1,
		intensity = 0.1,
		requires = { "panelAUp" },
		descriptionKey = "evt.fault_panel_a",
	},
	{
		id = "fault_panel_b",
		tier = "Fault",
		weight = 3,
		minPhase = "Escalation",
		maxPhase = "Crisis",
		cooldown = 80,
		duration = 1,
		intensity = 0.1,
		requires = { "panelBUp" },
		descriptionKey = "evt.fault_panel_b",
	},
	{
		id = "fault_tuning_drift",
		tier = "Fault",
		weight = 3,
		minPhase = "Escalation",
		maxPhase = "Crisis",
		cooldown = 75,
		duration = 1,
		intensity = 0.1,
		requires = { "carrierHeld" },
		descriptionKey = "evt.fault_tuning_drift",
	},
	{
		id = "fault_vtr_jam",
		tier = "Fault",
		weight = 2,
		minPhase = "Escalation",
		maxPhase = "Crisis",
		cooldown = 90,
		duration = 1,
		intensity = 0.1,
		requires = { "fillerInMCR" },
		descriptionKey = "evt.fault_vtr_jam",
	},
	{
		id = "fault_camera_offline",
		tier = "Fault",
		weight = 2,
		minPhase = "Maintenance",
		maxPhase = "Crisis",
		cooldown = 60,
		duration = 1,
		intensity = 0.05,
		descriptionKey = "evt.fault_camera_offline",
	},
} :: { EventDef }

-- Minimum gap between events of each tier (seconds), and the calm enforced after a Critical.
Events.TierGap = { Subtle = 9, Intermediate = 32, Critical = 80, Fault = 24 }
Events.CalmAfterCritical = 22
-- Lead time between a fault being scheduled (and prophesied on the radio) and it happening.
Events.FaultLead = { 14, 26 }
-- Tension budget: each event spends `intensity`; the budget refills over time, faster in later phases.
Events.TensionBudgetMax = 1.2
Events.TensionRefill = { Arrival = 0, Maintenance = 0.012, Anomaly = 0, Escalation = 0.022, Crisis = 0.03, Finale = 0 }
Events.DirectorTick = 3

return Events
