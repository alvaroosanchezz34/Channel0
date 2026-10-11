--!strict
--[[
	Broadcast state machine (pure). The server owns one instance and feeds it validated inputs;
	clients only ever receive snapshots.
]]

local SignalConfig = require(script.Parent.Parent.Config.SignalConfig)

local SignalModel = {}

export type ProgramSource = "Bars" | "Studio" | "VTR" | "Slate" | "Channel0"

export type State = {
	carrierOn: boolean,
	consolePowered: boolean,
	frequency: number,
	quality: number,
	interference: number,
	externalInterference: number,
	onAir: ProgramSource,
	resumeSource: ProgramSource,
	panelA: boolean,
	panelB: boolean,
	vtrLoaded: boolean,
	camerasOffline: number,
	lostFrequency: number,
	zeroChannelOpen: boolean,
	tuningLocked: boolean,
	deadAirArmed: boolean,
	deadAir: boolean,
	deadAirTimer: number,
	carrierDropFired: boolean,
	slateRemaining: number,
	slateCooldown: number,
}

export type SignalEvent = "DeadAirStarted" | "DeadAirEnded" | "CarrierDropped" | "SlateEnded"

function SignalModel.new(lostFrequency: number): State
	return {
		carrierOn = true,
		consolePowered = false,
		frequency = 47.8,
		quality = 0,
		interference = 0,
		externalInterference = 0,
		onAir = "Bars",
		resumeSource = "Bars",
		panelA = false,
		panelB = false,
		vtrLoaded = false,
		camerasOffline = 0,
		lostFrequency = lostFrequency,
		zeroChannelOpen = false,
		tuningLocked = false,
		deadAirArmed = false,
		deadAir = false,
		deadAirTimer = 0,
		carrierDropFired = false,
		slateRemaining = 0,
		slateCooldown = 0,
	}
end

function SignalModel.isNear(frequency: number, target: number): boolean
	return math.abs(frequency - target) <= SignalConfig.LockTolerance
end

function SignalModel.isCarrierHeld(state: State): boolean
	return SignalModel.isNear(state.frequency, SignalConfig.CarrierFrequency)
end

function SignalModel.tuningFactor(state: State): number
	if state.zeroChannelOpen and SignalModel.isNear(state.frequency, state.lostFrequency) then
		return 1
	end
	local distance = math.abs(state.frequency - SignalConfig.CarrierFrequency)
	if distance <= SignalConfig.LockTolerance then
		return 1
	end
	local t = math.clamp((distance - SignalConfig.LockTolerance) / SignalConfig.DetuneFalloff, 0, 1)
	return 1 - t * (1 - SignalConfig.DetuneFloor)
end

function SignalModel.targetQuality(state: State): number
	if not state.carrierOn then
		return 0
	end
	local value = 100 * SignalModel.tuningFactor(state)
	if not state.panelA then
		value -= SignalConfig.Penalty.PanelDown
	end
	if not state.panelB then
		value -= SignalConfig.Penalty.PanelDown
	end
	if state.onAir == "VTR" and not state.vtrLoaded then
		value -= SignalConfig.Penalty.VTREmpty
	end
	value -= state.camerasOffline * SignalConfig.Penalty.CameraOffline
	value -= state.interference * SignalConfig.Penalty.Interference
	return math.clamp(value, 0, 100)
end

-- Validated program change. Returns ok + reason for UI feedback.
function SignalModel.setOnAir(state: State, source: ProgramSource): (boolean, string?)
	if not state.consolePowered then
		return false, "ConsoleOff"
	end
	if state.onAir == source then
		return true, nil
	end
	if source == "Slate" then
		if state.slateCooldown > 0 then
			return false, "SlateCooldown"
		end
		state.resumeSource = if state.onAir == "Slate" then state.resumeSource else state.onAir
		state.onAir = "Slate"
		state.slateRemaining = SignalConfig.Slate.Duration
		return true, nil
	end
	if source == "Channel0" and not state.zeroChannelOpen then
		return false, "NoZeroChannel"
	end
	if state.onAir == "Slate" then
		-- Leaving the slate early still starts its cooldown.
		state.slateRemaining = 0
		state.slateCooldown = SignalConfig.Slate.Cooldown
	end
	state.onAir = source
	return true, nil
end

function SignalModel.step(state: State, dt: number): { SignalEvent }
	local events: { SignalEvent } = {}

	if state.slateCooldown > 0 then
		state.slateCooldown = math.max(0, state.slateCooldown - dt)
	end
	if state.onAir == "Slate" then
		state.slateRemaining -= dt
		if state.slateRemaining <= 0 then
			state.slateRemaining = 0
			state.slateCooldown = SignalConfig.Slate.Cooldown
			state.onAir = state.resumeSource
			table.insert(events, "SlateEnded")
		end
	end

	local channelNoise = if state.onAir == "Channel0" then SignalConfig.Channel0Interference else 0
	state.interference = math.clamp(math.max(state.externalInterference, channelNoise), 0, 1)

	local target = SignalModel.targetQuality(state)
	local alpha = 1 - math.exp(-SignalConfig.QualitySmoothing * dt)
	state.quality += (target - state.quality) * alpha

	local threshold = SignalConfig.DeadAirThreshold
	if not state.deadAir and state.quality < threshold then
		state.deadAir = true
		state.deadAirTimer = 0
		state.carrierDropFired = false
		table.insert(events, "DeadAirStarted")
	elseif state.deadAir and state.quality >= threshold + 6 then
		state.deadAir = false
		state.deadAirTimer = 0
		table.insert(events, "DeadAirEnded")
	end

	if state.deadAir and state.deadAirArmed then
		state.deadAirTimer += dt
		if not state.carrierDropFired and state.deadAirTimer >= SignalConfig.DeadAirGrace then
			state.carrierDropFired = true
			table.insert(events, "CarrierDropped")
		end
	end

	return events
end

function SignalModel.snapshot(state: State): { [string]: any }
	return {
		carrierOn = state.carrierOn,
		consolePowered = state.consolePowered,
		frequency = math.floor(state.frequency * 100 + 0.5) / 100,
		quality = math.floor(state.quality + 0.5),
		interference = math.floor(state.interference * 100 + 0.5) / 100,
		onAir = state.onAir,
		deadAir = state.deadAir and state.deadAirArmed,
		deadAirTimer = state.deadAirTimer,
		slateCooldown = math.ceil(state.slateCooldown),
		panelA = state.panelA,
		panelB = state.panelB,
		vtrLoaded = state.vtrLoaded,
		tuningLocked = state.tuningLocked,
		zeroChannelOpen = state.zeroChannelOpen,
	}
end

return SignalModel
