--!strict
--[[
	Network contract. The server creates every remote under ReplicatedStorage.Net at startup; the
	client waits for them. Low-frequency shared state is published as attributes on
	ReplicatedStorage.SessionState (they replicate on their own and late joiners get them for free).

	Server -> client (RemoteEvent):
		Cue          { kind = ..., ... }   sounds, subtitles, notices, VHS pulses, scripted moments
		Signal       SignalSnapshot        every SignalConfig.PublishInterval while running
		Objectives   { ObjectiveView }     on change
		Crew         { CrewEntry }         on change
		Device       { op = "open" | "update" | "close" | "message", ... }
		Inventory    { tapes = { string }, key = boolean }
		Feeds        { [camId] = FeedDirective }
		Decks        { [deckId] = DeckState }
		Ending       EndingPayload
		Profile      { settings, endings }
		DebugState   (only when the player is authorized)

	Client -> server (RemoteEvent, rate-limited per player by NetConfig.Limits):
		Ready(boolean)
		DeviceAction(deviceId: string, action: string, arg: any)
		DeviceClose(deviceId: string)
		Flashlight(boolean)
		Sprint(boolean)
		Settings(table)
		Debug(command: string, arg: any)   (exists only where debug tools may be enabled)
]]

local Net = {}

Net.FolderName = "Net"
Net.StateFolderName = "SessionState"

Net.ServerToClient = {
	"Cue",
	"Signal",
	"Objectives",
	"Crew",
	"Device",
	"Inventory",
	"Feeds",
	"Decks",
	"Ending",
	"Profile",
	"DebugState",
}

Net.ClientToServer = {
	"Ready",
	"DeviceAction",
	"DeviceClose",
	"Flashlight",
	"Sprint",
	"Settings",
}

Net.DebugRemote = "Debug"

-- Attribute names on ReplicatedStorage.SessionState.
Net.Attr = {
	Session = "Session", -- SessionState
	Phase = "Phase",
	Clock = "Clock", -- fictional minutes after midnight
	Stalled = "Stalled", -- clock waiting on objectives
	Seed = "Seed",
	Countdown = "Countdown",
	AnchorState = "AnchorState",
	AnchorTelegraph = "AnchorTelegraph",
	Tension = "Tension", -- 0..1 for client-side presentation (VHS, audio)
	ProgramSource = "ProgramSource",
	AnomalyActive = "AnomalyActive",
	DebugEnabled = "DebugEnabled",
	PlayerCount = "PlayerCount",
}

return Net
