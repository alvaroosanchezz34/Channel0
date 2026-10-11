--!strict
--[[
	The broadcast model. The transmitter exciter is tuned with the same dial used to listen to
	other frequencies: exploring the dial costs broadcast quality. That trade-off is deliberate.
]]

local SignalConfig = {}

SignalConfig.CarrierFrequency = 55.25
SignalConfig.TunerMin = 40.0
SignalConfig.TunerMax = 130.0
SignalConfig.FineStep = 0.05
SignalConfig.CoarseStep = 1.0
-- A frequency counts as "tuned" within this tolerance (MHz).
SignalConfig.LockTolerance = 0.051
-- Beyond this distance from the carrier the tuning factor reaches its floor.
SignalConfig.DetuneFalloff = 1.5
SignalConfig.DetuneFloor = 0.25

SignalConfig.Penalty = {
	PanelDown = 32,
	VTREmpty = 38,
	CameraOffline = 4,
	Interference = 30, -- multiplied by interference 0..1
}

SignalConfig.QualitySmoothing = 1.6 -- higher = faster response
SignalConfig.DeadAirThreshold = 22
SignalConfig.DeadAirGrace = 16

SignalConfig.Slate = {
	Duration = 9,
	Cooldown = 70,
}

-- Interference contributed while Channel 0 is on air.
SignalConfig.Channel0Interference = 0.28

-- How often the server publishes the signal snapshot to clients.
SignalConfig.PublishInterval = 0.25

return SignalConfig
