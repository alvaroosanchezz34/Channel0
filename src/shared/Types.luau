--!strict
--[[
	Shared type contracts between server, client and the offline test runner.
]]

export type SessionState = "Lobby" | "Intro" | "Running" | "Ending" | "Results" | "Resetting"

-- Narrative phases while the session is Running. Only PhaseService changes these.
export type Phase = "Arrival" | "Maintenance" | "Anomaly" | "Escalation" | "Crisis" | "Finale"

export type AnchorState = "Dormant" | "Broadcast" | "Observing" | "Displacement" | "Manifestation" | "Hunt" | "Withdrawal"

-- What the master switcher puts on air.
export type ProgramSource = "Bars" | "Studio" | "VTR" | "Slate" | "Channel0"

export type EndingId = "CutSignal" | "FullBroadcast" | "NewAnchor" | "Dawn" | "SignalLost"

export type EventTier = "Subtle" | "Intermediate" | "Critical" | "Fault"

export type PlayerStatus = "Lobby" | "Active" | "Taken" | "Spectating"

export type SignalSnapshot = {
	carrierOn: boolean,
	frequency: number,
	quality: number,
	interference: number,
	onAir: ProgramSource,
	deadAir: boolean,
	deadAirTimer: number,
	slateCooldown: number,
	panelA: boolean,
	panelB: boolean,
	vtrLoaded: boolean,
	tuningLocked: boolean,
}

export type ObjectiveView = {
	id: string,
	textKey: string,
	done: boolean,
	progress: number,
	goal: number,
	optional: boolean,
}

-- One security camera's presentation instruction, decided by the server.
export type FeedDirective = {
	mode: "Live" | "Offline" | "Displaced" | "Memory",
	-- Seconds the feed's timestamp runs ahead of the station clock (Displaced feeds).
	leadSeconds: number,
	-- Where THE ANCHOR appears in this feed, if anywhere (world position + yaw).
	anchorAt: { x: number, y: number, z: number, yaw: number }?,
	-- Door ids drawn open in the feed regardless of their real state.
	doorsOpen: { string }?,
	-- UserIds of players drawn in the feed who are not physically there (taken players).
	phantoms: { number }?,
}

export type Cue = {
	kind: string,
	[string]: any,
}

return {}
