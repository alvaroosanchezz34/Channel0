--!strict
--[[
	THE ANCHOR tuning. The state machine logic lives in Logic/AnchorMachine; the server brain in
	server/Anchor. Durations are seconds.
]]

local AnchorConfig = {}

AnchorConfig.BroadcastMinDuration = 20
AnchorConfig.ObserveDuration = { 26, 44 }
-- Displacement: the future feed shows where he will appear `PreEchoLead` seconds ahead.
AnchorConfig.PreEchoLead = { 18, 30 }
AnchorConfig.DisplacementAppearance = 4.5
AnchorConfig.DisplacementCycles = { 1, 2 }
AnchorConfig.ManifestMinDuration = 12
AnchorConfig.ManifestMaxDuration = 40
AnchorConfig.HuntTelegraph = 6.5
AnchorConfig.HuntDuration = { 20, 28 }
AnchorConfig.HuntCooldown = 55
AnchorConfig.WithdrawalDuration = { 18, 34 }
AnchorConfig.LoseTargetAfter = 5.5

-- Pressure thresholds (0..1) that unlock stronger states.
AnchorConfig.ManifestPressure = 0.32
AnchorConfig.HuntPressure = 0.72

AnchorConfig.Movement = {
	-- Manifestation: slow walk interrupted by stillness.
	WalkSpeed = 4.6,
	-- Hunt: frame-skipping advance (studs per step, steps per second).
	HuntStepLength = { 2.4, 3.6 },
	HuntStepsPerSecond = 5.2,
	WalkStepsPerSecond = 3,
	PauseChance = 0.18,
	PauseDuration = { 0.6, 2.2 },
	DoorOpenPause = 1.4,
	MaxStepUp = 1.6,
}

AnchorConfig.CatchRadius = 3.6
AnchorConfig.CatchGrace = 0.35 -- seconds within radius before a catch registers
AnchorConfig.StareDistance = 38
AnchorConfig.ProximityInterferenceRadius = 46
AnchorConfig.Height = 7.6

return AnchorConfig
