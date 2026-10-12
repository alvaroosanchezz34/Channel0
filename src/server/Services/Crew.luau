--!strict
--[[
	The night crew: zone tracking, sprint stamina (server-authoritative), the flashlight other
	players see, isolation, and what happens when THE ANCHOR takes someone.

	Taken players are not killed. They are moved "into the broadcast" (a sealed room far below
	the map), watch the station through its cameras, and get a frequency their crew can tune and
	lock on the exciter to bring them back. Solo players get one automatic second chance.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Frequencies = require(Shared.Content.Frequencies)
local GameConfig = require(Shared.Config.GameConfig)
local SignalConfig = require(Shared.Config.SignalConfig)

local Registry = require(script.Parent.Registry)
local Remotes = require(script.Parent.Remotes)
local State = require(script.Parent.State)
local World = require(script.Parent.World)

local Crew = {}

local SECOND_CHANCE_DELAY = 9
local ISOLATION_DISTANCE = 42

local function publish()
	local list = {}
	for _, member in State.members() do
		table.insert(list, {
			userId = member.userId,
			name = member.name,
			status = member.status,
			ready = member.ready,
			zone = member.zone,
			frequency = member.takenFrequency,
		})
	end
	Remotes.fireAll("Crew", list)
	Remotes.setState("PlayerCount", #list)
end
Crew.publish = publish

function Crew.init()
	State.Changed:Connect(function(kind)
		if kind == "crew" then
			publish()
		end
	end)
	Remotes.on("Sprint", function(player, wants)
		local member = State.member(player)
		if member and type(wants) == "boolean" then
			member.sprinting = wants and member.status == "Active"
		end
	end)
	Remotes.on("Flashlight", function(player, on)
		if type(on) ~= "boolean" then
			return
		end
		local root = World.rootOf(player)
		local light = root and root:FindFirstChild("CrewFlashlight")
		if light and light:IsA("SpotLight") then
			light.Enabled = on
		end
	end)
end

-- Character setup common to every spawn.
function Crew.prepareCharacter(player: Player)
	local character = player.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = GameConfig.Player.WalkSpeed
		humanoid.UseJumpPower = true
		humanoid.JumpPower = 0
		humanoid.BreakJointsOnDeath = false
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and not root:FindFirstChild("CrewFlashlight") then
		-- What OTHER players see of your flashlight (your own is rendered locally from the camera).
		local light = Instance.new("SpotLight")
		light.Name = "CrewFlashlight"
		light.Brightness = GameConfig.Player.FlashlightBrightness * 0.8
		light.Range = GameConfig.Player.FlashlightRange * 0.8
		light.Angle = GameConfig.Player.FlashlightAngle
		light.Face = Enum.NormalId.Front
		light.Shadows = true
		light.Color = Color3.fromRGB(255, 236, 205)
		light.Enabled = false
		light.Parent = root
	end
end

local function freeFrequency(): number
	local used: { [number]: boolean } = {}
	for _, member in State.crew do
		if member.takenFrequency then
			used[member.takenFrequency] = true
		end
	end
	local options = {}
	for _, mhz in Frequencies.TakenPool do
		if not used[mhz] and math.abs(mhz - State.lostFrequency) > 1 then
			table.insert(options, mhz)
		end
	end
	if #options == 0 then
		return Frequencies.TakenPool[1]
	end
	return State.rng:Pick(options)
end

function Crew.take(member: State.CrewMember)
	if member.status ~= "Active" then
		return
	end
	member.timesTaken += 1
	member.sprinting = false
	member.takenAt = os.clock()
	local solo = State.shiftCount() == 1
	member.takenFrequency = if solo then nil else freeFrequency()
	State.setStatus(member, "Taken")
	Registry.Devices.releaseAll(member.player)
	local hold = World.marker("TakenHoldPoint")
	if hold then
		World.teleport(member.player, hold.CFrame)
	end
	local root = World.rootOf(member.player)
	if root then
		root.Anchored = true
	end
	Registry.Session.cueAll({
		kind = "Subtitle",
		key = "sub.taken",
		vars = { name = member.name },
		speaker = "Caption",
		duration = 5,
	})
	Registry.Session.cueAll({ kind = "Pulse", amount = 1.6, duration = 2.5 })
	Remotes.fire(member.player, "Cue", {
		kind = "Taken",
		frequency = member.takenFrequency,
		solo = solo,
	})
	Crew.checkAllTaken()
end

function Crew.recover(member: State.CrewMember, reasonKey: string)
	if member.status ~= "Taken" then
		return
	end
	member.takenFrequency = nil
	member.takenAt = nil
	local spawn = World.marker("Spawn_Recover")
	local root = World.rootOf(member.player)
	if root then
		root.Anchored = false
	end
	if spawn then
		World.teleport(member.player, spawn.CFrame)
	end
	State.setStatus(member, "Active")
	Remotes.fire(member.player, "Cue", { kind = "Recovered" })
	Registry.Session.cueAll({
		kind = "Subtitle",
		key = reasonKey,
		vars = { name = member.name },
		speaker = "Caption",
		duration = 5,
	})
end

-- Called when the exciter is locked: brings back the taken teammate on that frequency.
function Crew.recoverByFrequency(mhz: number): boolean
	for _, member in State.members({ "Taken" }) do
		if member.takenFrequency and math.abs(member.takenFrequency - mhz) <= SignalConfig.LockTolerance then
			Crew.recover(member, "sub.recovered")
			Registry.Session.cueAll({ kind = "Sound", sound = "CarrierLock" })
			return true
		end
	end
	return false
end

function Crew.checkAllTaken()
	if State.session ~= "Running" then
		return
	end
	if State.activeCount() > 0 then
		return
	end
	-- A solo player with a second chance left is not "all taken" yet.
	for _, member in State.members({ "Taken" }) do
		if member.takenFrequency == nil and member.secondChances > 0 then
			return
		end
	end
	if State.shiftCount() > 0 then
		State.setFact("allTaken", true)
		Registry.Endings.automatic("SignalLost")
	end
end

-- Which taken frequencies are live (for the radio).
function Crew.takenFrequencies(): { { mhz: number, name: string } }
	local list = {}
	for _, member in State.members({ "Taken" }) do
		if member.takenFrequency then
			table.insert(list, { mhz = member.takenFrequency, name = member.name })
		end
	end
	return list
end

-- 0..1: how split up the crew is (the Anchor and director prefer isolated players).
function Crew.isolation(): number
	local active = State.members({ "Active" })
	if #active <= 1 then
		return if #active == 1 then 0.5 else 0
	end
	local isolated = 0
	for _, member in active do
		if Crew.isIsolated(member) then
			isolated += 1
		end
	end
	return isolated / #active
end

function Crew.isIsolated(member: State.CrewMember): boolean
	local position = World.positionOf(member.player)
	if not position then
		return false
	end
	local nearest = math.huge
	for _, other in State.members({ "Active" }) do
		if other ~= member then
			local p = World.positionOf(other.player)
			if p then
				nearest = math.min(nearest, (p - position).Magnitude)
			end
		end
	end
	return nearest > ISOLATION_DISTANCE and nearest < math.huge
end

function Crew.isolatedMember(): State.CrewMember?
	for _, member in State.members({ "Active" }) do
		if Crew.isIsolated(member) then
			return member
		end
	end
	return nil
end

function Crew.step(dt: number)
	for _, member in State.members({ "Active" }) do
		local character = member.player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local position = World.positionOf(member.player)
		if position then
			local zone = World.zoneOf(position)
			if zone ~= member.zone then
				member.zone = zone
				member.zoneSince = os.clock()
				Registry.Session.onZoneEntered(member, zone)
			end
		end
		if humanoid then
			local moving = humanoid.MoveDirection.Magnitude > 0.1
			if member.sprinting and moving and member.stamina > 0 then
				member.stamina = math.max(0, member.stamina - dt / GameConfig.Player.StaminaSeconds)
				humanoid.WalkSpeed = GameConfig.Player.SprintSpeed
				if member.stamina <= 0 then
					member.sprinting = false
				end
			else
				member.stamina = math.min(
					1,
					member.stamina + dt * GameConfig.Player.StaminaRegenPerSecond / GameConfig.Player.StaminaSeconds * 2
				)
				humanoid.WalkSpeed = GameConfig.Player.WalkSpeed
			end
			if character then
				character:SetAttribute("Stamina", math.floor(member.stamina * 100) / 100)
			end
		end
	end
	-- Solo second chance.
	for _, member in State.members({ "Taken" }) do
		if member.takenFrequency == nil and member.takenAt and os.clock() - member.takenAt >= SECOND_CHANCE_DELAY then
			if member.secondChances > 0 then
				member.secondChances -= 1
				Crew.recover(member, "sub.secondChance")
			else
				Crew.checkAllTaken()
			end
		end
	end
end

function Crew.reset()
	for _, member in State.crew do
		member.takenFrequency = nil
		member.takenAt = nil
		member.stamina = 1
		member.sprinting = false
		member.timesTaken = 0
		member.secondChances = GameConfig.Scaling.SoloSecondChances
		local root = World.rootOf(member.player)
		if root then
			root.Anchored = false
		end
	end
	publish()
end

local _ = Players
return Crew
