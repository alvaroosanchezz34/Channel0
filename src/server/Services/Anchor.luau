--!strict
--[[
	THE ANCHOR — server brain and presenter.

	The pure state machine (Shared/Logic/AnchorMachine) owns timers and transitions. This module
	supplies context (phase, pressure, slate, target), and turns machine events into presence:
	where he appears, how he moves (a stuttering, frame-skipping walk), what the feeds show, what
	the Night Desk frequency says before it happens.

	Fairness rules enforced here:
	  * a hunt is always telegraphed (studio lights coming up, sting, subtitle) and no catch is
	    possible during the telegraph;
	  * catches need sustained proximity (CatchGrace), never a single frame;
	  * the STAND BY slate always forces a withdrawal (with cooldown on the slate itself);
	  * being caught takes you into the broadcast, it does not kill you.
]]

local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AnchorConfig = require(Shared.Config.AnchorConfig)
local AnchorMachine = require(Shared.Logic.AnchorMachine)
local GameConfig = require(Shared.Config.GameConfig)
local Layout = require(Shared.Content.StationLayout)
local Net = require(Shared.Net)

local Registry = require(script.Parent.Registry)
local Remotes = require(script.Parent.Remotes)
local State = require(script.Parent.State)
local World = require(script.Parent.World)

local Anchor = {}

local HIDDEN = CFrame.new(0, -480, 0)
local ROOT_HEIGHT = 3.9

local machine: AnchorMachine.Machine = AnchorMachine.new(State.stream("anchor"))
local rng = State.stream("anchor-presence")
local model: Model? = nil
local root: BasePart? = nil
local keyLight: Light? = nil
local motors: { [string]: { motor: Motor6D, base: CFrame } } = {}

local visible = false
local position = HIDDEN.Position
local facing = Vector3.new(0, 0, -1)
local target: State.CrewMember? = nil
local targetLostFor = 0
local catchTimer = 0
local caughtFlag = false
local waypoints: { Vector3 } = {}
local waypointIndex = 1
local pathBusy = false
local pathAge = math.huge
local stepTimer = 0
local pauseTimer = 0
local stepParity = false
local pendingAppear: { zone: string, position: Vector3, yaw: number }? = nil
local glimpseUntil = 0
local godMode = false -- debug: no catches

-- Pose library: joint -> rotation (radians, applied on top of the bind pose).
local POSES: { [string]: { [string]: { number } } } = {
	Stand = {},
	Composed = {
		ShoulderL = { 0.35, 0, 0.12 },
		ShoulderR = { 0.35, 0, -0.12 },
		ElbowL = { 0.9, 0, 0 },
		ElbowR = { 0.9, 0, 0 },
	},
	Seated = {
		HipL = { 1.5, 0, 0 },
		HipR = { 1.5, 0, 0 },
		KneeL = { -1.5, 0, 0 },
		KneeR = { -1.5, 0, 0 },
		ShoulderL = { 0.5, 0, 0.1 },
		ShoulderR = { 0.5, 0, -0.1 },
		ElbowL = { 0.9, 0, 0 },
		ElbowR = { 0.9, 0, 0 },
	},
	Stare = { Neck = { 0, 0, 0.22 }, ShoulderL = { 0, 0, 0.04 }, ShoulderR = { 0, 0, -0.04 } },
	WalkA = {
		HipL = { 0.42, 0, 0 },
		HipR = { -0.36, 0, 0 },
		KneeR = { -0.3, 0, 0 },
		ShoulderL = { -0.2, 0, 0 },
		ShoulderR = { 0.25, 0, 0 },
	},
	WalkB = {
		HipL = { -0.36, 0, 0 },
		HipR = { 0.42, 0, 0 },
		KneeL = { -0.3, 0, 0 },
		ShoulderL = { 0.25, 0, 0 },
		ShoulderR = { -0.2, 0, 0 },
	},
	Reach = { ShoulderL = { 1.45, 0, 0.1 }, ShoulderR = { 1.45, 0, -0.1 }, Neck = { -0.15, 0, 0 } },
	Telegraph = { Neck = { 0, 1.35, 0.3 }, ShoulderL = { 0.2, 0, 0.7 }, ShoulderR = { 0.2, 0, -0.7 } },
}

local function setPose(name: string, headYaw: number?)
	local pose = POSES[name] or POSES.Stand
	for joint, entry in motors do
		local r = pose[joint]
		local cf = entry.base
		if r then
			cf = cf * CFrame.Angles(r[1], r[2], r[3])
		end
		if joint == "Neck" and headYaw then
			cf = cf * CFrame.Angles(0, headYaw, 0)
		end
		entry.motor.C0 = cf
	end
end

local function place(at: Vector3, look: Vector3?)
	position = at
	if look then
		local flat = Vector3.new(look.X - at.X, 0, look.Z - at.Z)
		if flat.Magnitude > 0.05 then
			facing = flat.Unit
		end
	end
	if model and root then
		model:PivotTo(CFrame.lookAt(at + Vector3.new(0, ROOT_HEIGHT, 0), at + Vector3.new(0, ROOT_HEIGHT, 0) + facing))
	end
end

local function show(at: Vector3, look: Vector3?, light: boolean)
	visible = true
	place(at, look)
	if keyLight then
		keyLight.Enabled = light
	end
	if model then
		model:SetAttribute("Visible", true)
	end
end

local function hide()
	visible = false
	waypoints = {}
	if model then
		model:PivotTo(HIDDEN)
		model:SetAttribute("Visible", false)
	end
	if keyLight then
		keyLight.Enabled = false
	end
	position = HIDDEN.Position
end

function Anchor.init()
	local assets = ReplicatedStorage:WaitForChild("Assets")
	local template = assets:FindFirstChild("Anchor")
	assert(template and template:IsA("Model"), "Assets.Anchor is missing: rebuild assets with tools/build")
	model = template:Clone()
	local m = model :: Model
	m.Name = "TheAnchor"
	root = m:FindFirstChild("Root") :: BasePart?
	keyLight = m:FindFirstChild("Key", true) :: Light?
	for _, d in m:GetDescendants() do
		if d:IsA("Motor6D") then
			motors[d.Name] = { motor = d, base = d.C0 }
		elseif d:IsA("BasePart") then
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = d == root
			d.CastShadow = true
		end
	end
	m:PivotTo(HIDDEN)
	m.Parent = Workspace
	setPose("Stand")
end

function Anchor.state(): string
	return machine.state
end

function Anchor.isVisible(): boolean
	return visible
end

function Anchor.physicalZone(): string?
	if not visible then
		return nil
	end
	return World.zoneOf(position + Vector3.new(0, 1, 0))
end

function Anchor.feedPose(): { x: number, y: number, z: number, yaw: number }?
	if not visible then
		return nil
	end
	return { x = position.X, y = position.Y, z = position.Z, yaw = math.atan2(-facing.X, -facing.Z) }
end

function Anchor.setGodMode(on: boolean)
	godMode = on
end

local function aggression(): number
	local list = GameConfig.Scaling.AnchorAggression
	return list[math.clamp(State.shiftCount(), 1, #list)]
end

function Anchor.pressure(): number
	local phaseDef = GameConfig.Phases[State.phase]
	local progress = 0
	if phaseDef and phaseDef.cap > phaseDef.startClock then
		progress = (State.clock - phaseDef.startClock) / (phaseDef.cap - phaseDef.startClock)
	end
	return AnchorMachine.pressure({
		phase = State.phase,
		phaseProgress = progress,
		channel0OnAir = State.fact("channel0OnAir"),
		deadAir = Registry.Signal.deadAir(),
		carrierDrops = State.counter("carrierDrops"),
		isolation = Registry.Crew.isolation(),
		aggression = aggression(),
	})
end

-- Interference he adds to the broadcast (0..1).
function Anchor.interference(): number
	local state = machine.state
	if state == "Hunt" then
		return 0.5
	elseif visible then
		local base = 0.18
		local tuner = World.devices.Tuner
		local switcher = World.devices.Switcher
		for _, device in { tuner, switcher } do
			if device and (device.Position - position).Magnitude <= AnchorConfig.ProximityInterferenceRadius then
				base += 0.18
			end
		end
		return math.min(base, 0.6)
	elseif state == "Broadcast" or state == "Observing" then
		return 0.04
	end
	return 0
end

local function chooseTarget(): State.CrewMember?
	local isolated = Registry.Crew.isolatedMember()
	if isolated then
		return isolated
	end
	local active = State.members({ "Active" })
	if #active == 0 then
		return nil
	end
	if visible then
		local best, bestDistance = nil, math.huge
		for _, member in active do
			local p = World.positionOf(member.player)
			if p and (p - position).Magnitude < bestDistance then
				best, bestDistance = member, (p - position).Magnitude
			end
		end
		return best
	end
	return rng:Pick(active)
end

-- A node at a comfortable distance from `from`, preferring zones with a camera when asked.
local function nodeNear(from: Vector3, minDistance: number, maxDistance: number, zones: { string }?): BasePart?
	local options = {}
	local floor = Layout.floorAtHeight(from.Y)
	for _, node in World.nodes do
		local p = node.Position
		local d = (Vector3.new(p.X, from.Y, p.Z) - from).Magnitude
		if d >= minDistance and d <= maxDistance and Layout.floorAtHeight(p.Y) == floor then
			if not zones or table.find(zones, World.zoneOf(p + Vector3.new(0, 1, 0))) then
				table.insert(options, node)
			end
		end
	end
	if #options == 0 then
		return nil
	end
	table.sort(options, function(a, b)
		return a.Name < b.Name or (a.Name == b.Name and a.Position.X < b.Position.X)
	end)
	return rng:Pick(options)
end

local function nobodySees(at: Vector3): boolean
	local ignore: { Instance } = {}
	if model then
		table.insert(ignore, model)
	end
	for _, member in State.members({ "Active" }) do
		if member.player.Character then
			table.insert(ignore, member.player.Character)
		end
	end
	for _, member in State.members({ "Active" }) do
		local p = World.positionOf(member.player)
		if
			p
			and (p - at).Magnitude < 70
			and World.lineOfSight(p + Vector3.new(0, 1.5, 0), at + Vector3.new(0, 5, 0), ignore)
		then
			return false
		end
	end
	return true
end

local function requestPath(to: Vector3)
	if pathBusy then
		return
	end
	pathBusy = true
	local from = position
	task.spawn(function()
		local path = PathfindingService:CreatePath({
			AgentRadius = 1.8,
			AgentHeight = 7.5,
			AgentCanJump = false,
			WaypointSpacing = 2.5,
		})
		local ok = pcall(function()
			path:ComputeAsync(from, to)
		end)
		if ok and path.Status == Enum.PathStatus.Success then
			local list = {}
			for _, waypoint in path:GetWaypoints() do
				table.insert(list, waypoint.Position)
			end
			waypoints = list
			waypointIndex = math.min(2, #list)
		end
		pathAge = 0
		pathBusy = false
	end)
end

local function zoneLabel(zone: string): string
	return "@zone." .. zone
end

local function ctx(): AnchorMachine.Context
	local hasTarget = target ~= nil and target.status == "Active"
	return {
		phase = State.phase,
		pressure = Anchor.pressure(),
		slateActive = Registry.Signal.slateActive(),
		deadAir = Registry.Signal.deadAir(),
		hasTarget = hasTarget,
		targetLostFor = targetLostFor,
		caught = caughtFlag,
		aggression = aggression(),
	}
end

local function cueNearHim(radius: number, cue: { [string]: any })
	Registry.Session.cueNear(position, radius, cue)
end

local function onEntered(state: string, reason: string?)
	Remotes.setState(Net.Attr.AnchorState, state)
	Remotes.setState(Net.Attr.AnchorTelegraph, state == "Hunt")
	if state == "Broadcast" or state == "Observing" or state == "Displacement" then
		hide()
	elseif state == "Manifestation" then
		target = chooseTarget()
		local origin = if target then World.positionOf(target.player) else nil
		-- He arrives where nobody is looking, then lets himself be found.
		local node: BasePart? = nil
		for _ = 1, 6 do
			local candidate = origin and nodeNear(origin, 22, 46, Registry.Feeds.coveredZones())
			candidate = candidate or (origin and nodeNear(origin, 18, 60, nil))
			if candidate and nobodySees(candidate.Position) then
				node = candidate
				break
			end
			node = node or candidate
		end
		if node and origin then
			show(node.Position, origin, true)
			setPose("Stare")
			local zone = World.zoneOf(node.Position + Vector3.new(0, 1, 0))
			Registry.Lighting.override(zone, "Flicker", 3)
			cueNearHim(90, { kind = "Sound", sound = "AnchorHum", position = position, loop = "anchor" })
			Registry.Session.cueAll({ kind = "Pulse", amount = 0.8, duration = 2 })
			if aggression() >= 0.85 then
				Registry.Radio.prophesy("freq.NightDesk.hunt")
			end
		else
			hide()
		end
	elseif state == "Hunt" then
		target = target or chooseTarget()
		targetLostFor = 0
		catchTimer = 0
		local zone = Anchor.physicalZone() or (target and target.zone) or "MainHall"
		Registry.Lighting.override(zone, "Hunt", AnchorConfig.HuntTelegraph + 2)
		Registry.Session.cueAll({ kind = "Sound", sound = "HuntSting" })
		Registry.Session.cueAll({ kind = "Subtitle", key = "sub.huntWarning", speaker = "Caption", duration = 4 })
		Registry.Session.cueAll({ kind = "Pulse", amount = 1.2, duration = AnchorConfig.HuntTelegraph })
		setPose("Telegraph")
		if keyLight then
			keyLight.Enabled = true
		end
	elseif state == "Withdrawal" then
		if visible then
			cueNearHim(80, { kind = "Subtitle", key = "sub.withdrawal", speaker = "Caption", duration = 4 })
			cueNearHim(80, { kind = "StopLoop", loop = "anchor" })
			Registry.Session.cueAll({ kind = "Pulse", amount = 1.0, duration = 1 })
		end
		hide()
		target = nil
		Registry.Feeds.clearPreEcho()
		if reason == "Slate" then
			Registry.Session.cueAll({ kind = "Sound", sound = "Dropout" })
		end
	end
end

local function onPreEcho(lead: number)
	-- Choose where he will appear: near the crew, in a zone a console can see.
	local member = chooseTarget()
	local origin = if member then World.positionOf(member.player) else nil
	local node = origin and nodeNear(origin, 14, 55, Registry.Feeds.coveredZones())
	if not node then
		local zones = Registry.Feeds.coveredZones()
		local zone = zones[rng:NextInteger(1, #zones)]
		local list = World.nodesByZone[zone]
		node = if list and #list > 0 then list[rng:NextInteger(1, #list)] else nil
	end
	if not node then
		pendingAppear = nil
		return
	end
	local zone = World.zoneOf(node.Position + Vector3.new(0, 1, 0))
	local yaw = rng:NextNumber(-math.pi, math.pi)
	pendingAppear = { zone = zone, position = node.Position, yaw = yaw }
	Registry.Feeds.setPreEcho(zone, node.Position, yaw, lead)
	Registry.Radio.prophesy("freq.NightDesk.manifest", { zone = zoneLabel(zone) })
end

local function onAppear()
	local appear = pendingAppear
	if not appear then
		return
	end
	local look = appear.position + Vector3.new(-math.sin(appear.yaw), 0, -math.cos(appear.yaw))
	show(appear.position, look, true)
	setPose("Composed")
	Registry.Lighting.override(appear.zone, "Flicker", AnchorConfig.DisplacementAppearance)
	cueNearHim(70, { kind = "Sound", sound = "AnchorSkip", position = position })
	cueNearHim(60, { kind = "Pulse", amount = 0.9, duration = AnchorConfig.DisplacementAppearance })
end

local function onVanish()
	hide()
	pendingAppear = nil
	Registry.Feeds.clearPreEcho()
end

-- A brief impossible presence used by events and the 02:17 anomaly. Never while he is physical.
function Anchor.glimpse(at: Vector3, look: Vector3, duration: number, pose: string?): boolean
	if visible or machine.state == "Hunt" or machine.state == "Manifestation" then
		return false
	end
	show(at, look, true)
	setPose(pose or "Stare")
	glimpseUntil = os.clock() + duration
	return true
end

function Anchor.glimpseAtDesk(duration: number): boolean
	local stage = World.marker("AnchorStage_Desk")
	if not stage then
		return false
	end
	if Anchor.glimpse(stage.Position, stage.Position + stage.CFrame.LookVector, duration, "Seated") then
		place(stage.Position + Vector3.new(0, -1.7, 0), stage.Position + stage.CFrame.LookVector)
		return true
	end
	return false
end

local function stepMovement(dt: number)
	if not visible then
		return
	end
	local state = machine.state
	local member = target
	local targetPos = member and World.positionOf(member.player)

	-- Head follows the target in every visible state (he is always looking at someone).
	if targetPos and state ~= "Hunt" then
		local toTarget = (targetPos - position)
		local localDir = CFrame.lookAt(Vector3.zero, facing):VectorToObjectSpace(toTarget)
		local yaw = math.clamp(math.atan2(-localDir.X, -localDir.Z), -1.2, 1.2)
		setPose(if state == "Manifestation" then "Stare" else "Composed", yaw)
	end

	if state == "Manifestation" and targetPos then
		-- Slow approach that stops short: he wants to be seen, not to touch (yet).
		pathAge += dt
		local distance = (targetPos - position).Magnitude
		if distance > 14 and pathAge > 2.5 then
			requestPath(targetPos)
		end
		if pauseTimer > 0 then
			pauseTimer -= dt
			return
		end
		stepTimer += dt
		local interval = 1 / AnchorConfig.Movement.WalkStepsPerSecond
		if stepTimer >= interval and distance > 12 and waypoints[waypointIndex] then
			stepTimer = 0
			local goal = waypoints[waypointIndex]
			local delta = goal - position
			local stepLength = AnchorConfig.Movement.WalkSpeed * interval
			if delta.Magnitude <= stepLength then
				place(goal, goal + facing)
				waypointIndex += 1
			else
				place(position + delta.Unit * stepLength, goal)
			end
			stepParity = not stepParity
			setPose(if stepParity then "WalkA" else "WalkB")
			if Registry.Doors.openNear(position, 4) then
				pauseTimer = AnchorConfig.Movement.DoorOpenPause
			elseif rng:Chance(AnchorConfig.Movement.PauseChance * interval) then
				pauseTimer =
					rng:NextNumber(AnchorConfig.Movement.PauseDuration[1], AnchorConfig.Movement.PauseDuration[2])
			end
		end
	elseif state == "Hunt" and not machine.telegraphing and targetPos then
		pathAge += dt
		if pathAge > 0.8 then
			requestPath(targetPos)
		end
		if pauseTimer > 0 then
			pauseTimer -= dt
		else
			stepTimer += dt
			local interval = 1 / AnchorConfig.Movement.HuntStepsPerSecond
			if stepTimer >= interval then
				stepTimer = 0
				local goal = waypoints[waypointIndex]
				local direct = (targetPos - position)
				if (not goal) and direct.Magnitude < 8 then
					goal = Vector3.new(targetPos.X, position.Y, targetPos.Z)
				end
				if goal then
					local delta = goal - position
					local stepLength =
						rng:NextNumber(AnchorConfig.Movement.HuntStepLength[1], AnchorConfig.Movement.HuntStepLength[2])
					if delta.Magnitude <= stepLength then
						place(goal, targetPos)
						waypointIndex += 1
					else
						place(position + delta.Unit * stepLength, goal)
					end
					stepParity = not stepParity
					setPose(if stepParity then "Reach" else "WalkA")
					if rng:Chance(0.25) then
						cueNearHim(80, { kind = "Sound", sound = "AnchorStep", position = position })
					end
					if Registry.Doors.openNear(position, 4) then
						pauseTimer = AnchorConfig.Movement.DoorOpenPause * 0.5
					end
				end
			end
		end

		-- Sight and catch checks.
		local ignore: { Instance } = {}
		if model then
			table.insert(ignore, model)
		end
		if member and member.player.Character then
			table.insert(ignore, member.player.Character)
		end
		local horizontal = Vector3.new(targetPos.X - position.X, 0, targetPos.Z - position.Z).Magnitude
		local sees = horizontal < 10 or World.lineOfSight(position + Vector3.new(0, 6.5, 0), targetPos, ignore)
		targetLostFor = if sees then 0 else targetLostFor + dt
		if
			AnchorMachine.canCatch(machine)
			and horizontal <= AnchorConfig.CatchRadius
			and math.abs(targetPos.Y - (position.Y + 3)) < 6
		then
			catchTimer += dt
			if catchTimer >= AnchorConfig.CatchGrace and member and not godMode then
				caughtFlag = true
				Registry.Crew.take(member)
			end
		else
			catchTimer = 0
		end
	end
end

function Anchor.step(dt: number)
	if State.session ~= "Running" then
		return
	end
	if target and target.status ~= "Active" then
		target = if machine.state == "Hunt" then nil else chooseTarget()
		if machine.state == "Hunt" then
			targetLostFor = math.huge
		end
	end
	if glimpseUntil > 0 and os.clock() >= glimpseUntil then
		glimpseUntil = 0
		if machine.state ~= "Manifestation" and machine.state ~= "Hunt" then
			hide()
		end
	end
	local events = AnchorMachine.step(machine, dt, ctx())
	caughtFlag = false
	for _, event in events do
		if event.kind == "Entered" then
			onEntered(event.state or machine.state, event.reason)
		elseif event.kind == "PreEcho" then
			onPreEcho(event.lead or 20)
		elseif event.kind == "Appear" then
			onAppear()
		elseif event.kind == "Vanish" then
			onVanish()
		elseif event.kind == "TelegraphEnded" then
			setPose("Reach")
			requestPath(if target then World.positionOf(target.player) or position else position)
		end
	end
	stepMovement(dt)
	Remotes.setState(Net.Attr.Tension, math.floor(Anchor.pressure() * 100) / 100)
end

-- Debug: legal transitions only.
function Anchor.force(to: string): (boolean, string?)
	local events, err = AnchorMachine.force(machine, to :: any, ctx(), "Debug")
	if not events then
		return false, err
	end
	for _, event in events do
		if event.kind == "Entered" then
			onEntered(event.state or machine.state, event.reason)
		elseif event.kind == "PreEcho" then
			onPreEcho(event.lead or 20)
		end
	end
	return true, nil
end

function Anchor.debugInfo(): { [string]: any }
	return {
		state = machine.state,
		timeInState = math.floor(machine.timeInState * 10) / 10,
		duration = if machine.stateDuration == math.huge then -1 else math.floor(machine.stateDuration),
		huntCooldown = math.floor(machine.huntCooldown),
		telegraphing = machine.telegraphing,
		pressure = math.floor(Anchor.pressure() * 100) / 100,
		visible = visible,
		target = if target then target.name else nil,
		godMode = godMode,
	}
end

function Anchor.reset()
	machine = AnchorMachine.new(State.stream("anchor"))
	rng = State.stream("anchor-presence")
	target = nil
	targetLostFor = 0
	catchTimer = 0
	caughtFlag = false
	pendingAppear = nil
	glimpseUntil = 0
	hide()
	setPose("Stand")
	Remotes.setState(Net.Attr.AnchorState, machine.state)
	Remotes.setState(Net.Attr.AnchorTelegraph, false)
end

return Anchor
