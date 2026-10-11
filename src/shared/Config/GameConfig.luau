--!strict
--[[
	Session, pacing and player tuning. Every number a designer may want to tweak lives here
	or in the sibling config modules; systems read them instead of hardcoding values.
]]

local GameConfig = {}

GameConfig.MaxPlayers = 4
GameConfig.MinPlayersToStart = 1

GameConfig.Lobby = {
	-- Countdown once every present player is ready.
	AllReadyCountdown = 6,
	-- Countdown once at least one player is ready (lets a full lobby start without waiting forever).
	AnyReadyCountdown = 25,
}

GameConfig.IntroDuration = 10
GameConfig.ResultsDuration = 22

--[[
	The fictional night runs from 23:40 to 06:00. Clock values are minutes after midnight
	(negative = the previous evening). Each phase advances the clock at `rate` fictional minutes
	per real second and stalls at `cap` until the phase's objectives are met: the clock is a
	consequence of progression, never the other way round. Crisis is the exception: reaching
	06:00 ends the night (Dawn ending).
]]
GameConfig.Phases = {
	Arrival = { startClock = -20, cap = 30, rate = 0.34 },
	Maintenance = { startClock = 30, cap = 136, rate = 0.33 },
	Anomaly = { startClock = 137, cap = 139, rate = 0.035 },
	Escalation = { startClock = 139, cap = 239, rate = 0.29 },
	Crisis = { startClock = 240, cap = 360, rate = 0.29 },
	Finale = { startClock = 360, cap = 360, rate = 0 },
}
GameConfig.PhaseOrder = { "Arrival", "Maintenance", "Anomaly", "Escalation", "Crisis", "Finale" }

-- 02:17. The scripted first anomaly fires when the clock reaches this during Anomaly.
GameConfig.AnomalyClock = 137
GameConfig.AnomalyDuration = 48
GameConfig.DawnClock = 360

GameConfig.Player = {
	WalkSpeed = 11,
	SprintSpeed = 17,
	StaminaSeconds = 6,
	StaminaRegenPerSecond = 0.6,
	-- Interaction range enforced server-side (ProximityPrompt range is only a hint).
	InteractRange = 10,
	MaxTapes = 3,
	FlashlightBrightness = 1.6,
	FlashlightRange = 42,
	FlashlightAngle = 52,
}

-- How player count scales pressure (index = player count).
GameConfig.Scaling = {
	FaultRateMultiplier = { 0.65, 0.85, 1.0, 1.15 },
	AnchorAggression = { 0.7, 0.85, 1.0, 1.1 },
	-- Solo players get one "second chance" when taken instead of ending the run.
	SoloSecondChances = 1,
}

-- Station identity used across signage, OSD and narrative.
GameConfig.Station = {
	CallSign = "KZRO",
	Town = "Marrow Falls, MT",
	NightDate = { month = 10, day = 16, year = 1998 },
	MorningDate = { month = 10, day = 17, year = 1998 },
}

return GameConfig
