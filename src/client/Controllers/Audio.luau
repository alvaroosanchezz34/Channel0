--!strict
--[[
	Layered audio. Ambience beds crossfade by zone, positional emitters live where the map put
	them, the signal layer reacts to interference and dead air, and THE ANCHOR has a presence bed
	that rises with proximity. Silence is used on purpose (Studio B, after a withdrawal).

	Sound ids come from Shared/Config/AudioConfig. Empty ids are skipped silently, so the game is
	fully playable (with subtitles) before the generated audio files are uploaded. In Studio the
	controller lists the essential sounds that are still missing.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AudioConfig = require(Shared.Config.AudioConfig)
local Layout = require(Shared.Content.StationLayout)
local MathUtil = require(Shared.Util.MathUtil)

local Store = require(script.Parent.Store)

local Audio = {}

local groups: { [string]: SoundGroup } = {}
local beds: { [string]: Sound } = {}
local loops: { [string]: Sound } = {}
local pointFolder: Folder
local activeOneShots = 0
local silenceUntil = 0

local AMBIENCE: { [string]: { [string]: number } } = {
	Lobby = { StationHum = 0.8, Ventilation = 0.7 },
	Office = { StationHum = 0.8, Ventilation = 0.8 },
	Hall = { StationHum = 1, Ventilation = 1 },
	Service = { StationHum = 0.9, Ventilation = 0.6 },
	Studio = { StationHum = 0.5, StudioRoomTone = 1 },
	Control = { StationHum = 1, Ventilation = 0.8 },
	Archive = { StationHum = 0.5, Ventilation = 0.4, TapeHiss = 0.6 },
	Machine = { StationHum = 1, BasementDrone = 0.5 },
	Basement = { BasementDrone = 1, StationHum = 0.4 },
	Dead = { StudioRoomTone = 0.25 },
	Exterior = { ExteriorWind = 1 },
}

local function hasId(name: string): boolean
	local def = AudioConfig.Sounds[name]
	return def ~= nil and def.id ~= ""
end

local function makeSound(name: string, parent: Instance): Sound?
	local def = AudioConfig.Sounds[name]
	if not def or def.id == "" then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = def.id
	sound.Volume = def.volume
	sound.Looped = def.looped
	sound.SoundGroup = groups[def.group]
	if def.rolloffMin then
		sound.RollOffMinDistance = def.rolloffMin
		sound.RollOffMaxDistance = def.rolloffMax or 60
		sound.RollOffMode = Enum.RollOffMode.InverseTapered
	end
	if def.playbackSpeed then
		sound.PlaybackSpeed = def.playbackSpeed
	end
	sound.Parent = parent
	return sound
end

-- Plays a one-shot, 2D or at a world position. Returns silently when the id is not set.
function Audio.play(name: string, position: Vector3?, volumeScale: number?)
	if not hasId(name) or activeOneShots >= AudioConfig.MaxSimultaneousOneShots then
		return
	end
	local parent: Instance = SoundService
	local holder: Attachment? = nil
	if position then
		holder = Instance.new("Attachment")
		local h = holder :: Attachment
		h.WorldPosition = position
		h.Parent = Workspace.Terrain
		parent = h
	end
	local sound = makeSound(name, parent)
	if not sound then
		if holder then
			holder:Destroy()
		end
		return
	end
	local s = sound :: Sound
	s.Volume *= volumeScale or 1
	activeOneShots += 1
	s.Ended:Once(function()
		activeOneShots -= 1
		if holder then
			holder:Destroy()
		else
			s:Destroy()
		end
	end)
	s:Play()
	task.delay(30, function()
		if s.Parent then
			s:Stop()
			activeOneShots = math.max(0, activeOneShots - 1)
			if holder then
				holder:Destroy()
			else
				s:Destroy()
			end
		end
	end)
end

-- Named loop (e.g. the Anchor's hum) optionally attached to a world position.
function Audio.startLoop(key: string, name: string, position: Vector3?)
	Audio.stopLoop(key)
	local parent: Instance = SoundService
	if position then
		local holder = Instance.new("Attachment")
		holder.WorldPosition = position
		holder.Parent = Workspace.Terrain
		parent = holder
	end
	local sound = makeSound(name, parent)
	if sound then
		sound.Looped = true
		sound:Play()
		loops[key] = sound
	elseif parent ~= SoundService then
		parent:Destroy()
	end
end

function Audio.stopLoop(key: string)
	local sound = loops[key]
	if sound then
		loops[key] = nil
		local parent = sound.Parent
		sound:Destroy()
		if parent and parent:IsA("Attachment") then
			parent:Destroy()
		end
	end
end

-- Fades every ambience bed to silence for a while.
function Audio.silence(seconds: number)
	silenceUntil = os.clock() + seconds
end

local function applyGroupVolumes()
	local master = Store.settings.masterVolume
	for name, group in groups do
		local base = (AudioConfig.Groups :: any)[name] or 1
		group.Volume = base * master * (if name == "Ambience" then Store.settings.ambienceVolume else 1)
	end
end

local function myZone(): string
	local camera = Workspace.CurrentCamera
	if not camera then
		return "Exterior"
	end
	local p = camera.CFrame.Position
	return Layout.zoneAt(p.X, p.Y, p.Z)
end

local function update(dt: number)
	local zone = myZone()
	local zoneDef = (Layout.Zones :: any)[zone]
	local ambience: { [string]: number } = AMBIENCE[zoneDef and zoneDef.ambience or "Exterior"] or {}
	local silent = os.clock() < silenceUntil
	local session = Store.signal
	for name, sound in beds do
		local def = AudioConfig.Sounds[name]
		local target = (ambience[name] or 0) * def.volume
		if silent then
			target *= 0.15
		end
		local fade = if silent then AudioConfig.SilenceFade else AudioConfig.AmbienceFade
		sound.Volume = MathUtil.approach(sound.Volume, target, def.volume / fade, dt)
	end
	-- Signal layer: interference and dead air are audible in the control rooms.
	local interference = loops.__interference
	if interference then
		local inControl = zone == "MasterControl" or zone == "Transmitter"
		local target = if inControl
			then (session.interference or 0) * 0.6 + (if session.deadAir then 0.25 else 0)
			else 0
		interference.Volume = MathUtil.approach(interference.Volume, target, 0.5, dt)
	end
	-- Anchor presence: a 2D bed that grows as he gets close.
	local presence = loops.__presence
	local model = Workspace:FindFirstChild("TheAnchor")
	if presence then
		local target = 0
		if model and model:GetAttribute("Visible") == true then
			local camera = Workspace.CurrentCamera
			local distance = if camera
				then ((model :: Model):GetPivot().Position - camera.CFrame.Position).Magnitude
				else 999
			target = MathUtil.clamp01(1 - distance / 70) * AudioConfig.Sounds.AnchorPresence.volume
		end
		presence.Volume = MathUtil.approach(presence.Volume, target, 0.6, dt)
	end
	-- The hum follows his root.
	local hum = loops.anchor
	if hum and model and hum.Parent and hum.Parent:IsA("Attachment") then
		(hum.Parent :: Attachment).WorldPosition = (model :: Model):GetPivot().Position
	end
end

local function onCue(cue: { [string]: any })
	local kind = cue.kind
	if kind == "Sound" and type(cue.sound) == "string" then
		if cue.loop then
			Audio.startLoop(cue.loop, cue.sound, cue.position)
		else
			Audio.play(cue.sound, cue.position)
		end
	elseif kind == "StopLoop" and type(cue.loop) == "string" then
		Audio.stopLoop(cue.loop)
		Audio.silence(5)
	elseif kind == "Taken" then
		Audio.silence(8)
	end
end

function Audio.init()
	for name in AudioConfig.Groups do
		local group = Instance.new("SoundGroup")
		group.Name = "CH0_" .. name
		group.Parent = SoundService
		groups[name] = group
	end
	applyGroupVolumes()
	for name, def in AudioConfig.Sounds do
		if def.group == "Ambience" then
			local sound = makeSound(name, SoundService)
			if sound then
				sound.Volume = 0
				sound:Play()
				beds[name] = sound
			end
		end
	end
	local fixedLoops: { [string]: string } = { __interference = "Interference", __presence = "AnchorPresence" }
	for key, name in fixedLoops do
		local sound = makeSound(name, SoundService)
		if sound then
			sound.Looped = true
			sound.Volume = 0
			sound:Play()
			loops[key] = sound
		end
	end
	-- Positional emitters placed by the map generator.
	pointFolder = Instance.new("Folder")
	pointFolder.Name = "CH0_Emitters"
	pointFolder.Parent = Workspace
	local station = Workspace:WaitForChild("Station", 30)
	if station then
		for _, part in station:GetDescendants() do
			if part:IsA("BasePart") and part:GetAttribute("Sound") and part:HasTag("AmbientEmitter") then
				makeSound(part:GetAttribute("Sound") :: string, part)
				local sound = part:FindFirstChildOfClass("Sound")
				if sound then
					sound.Looped = true
					sound:Play()
				end
			end
		end
	end
	if RunService:IsStudio() then
		local missing = {}
		for name, def in AudioConfig.Sounds do
			if def.essential and def.id == "" then
				table.insert(missing, name .. " (" .. def.file .. ")")
			end
		end
		if #missing > 0 then
			table.sort(missing)
			warn(
				"[Channel0] Essential sounds without an uploaded id (see docs/ASSETS.md): "
					.. table.concat(missing, ", ")
			)
		end
	end
	Store.Changed:Connect(function(kind, payload)
		if kind == "settings" then
			applyGroupVolumes()
		elseif kind == "cue" then
			onCue(payload)
		end
	end)
	RunService.Heartbeat:Connect(update)
end

return Audio
