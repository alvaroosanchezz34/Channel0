--!strict
--[[
	Session lifecycle: Lobby -> Intro -> Running -> Ending -> Results -> Resetting -> Lobby.
	Single owner of the session state (Shared/Logic/SessionMachine lists the legal edges), the
	main simulation loop, player join/leave, spawning and the cue helpers every service uses.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Net = require(Shared.Net)
local SessionMachine = require(Shared.Logic.SessionMachine)
local Tapes = require(Shared.Content.Tapes)

local Registry = require(script.Parent.Registry)
local Remotes = require(script.Parent.Remotes)
local State = require(script.Parent.State)
local World = require(script.Parent.World)

local Session = {}

local countdown: number? = nil
local stateTimer = 0

------------------------------------------------------------------ cue helpers

function Session.cueTo(player: Player, cue: { [string]: any })
	Remotes.fire(player, "Cue", cue)
end

function Session.cueAll(cue: { [string]: any })
	Remotes.fireAll("Cue", cue)
end

function Session.cueList(players: { Player }, cue: { [string]: any })
	Remotes.fireList(players, "Cue", cue)
end

-- Cue for players within `radius` studs of a point (taken players watching feeds included).
function Session.cueNear(position: Vector3, radius: number, cue: { [string]: any })
	Remotes.fireList(World.playersNear(position, radius), "Cue", cue)
end

function Session.cueDebug(cue: { [string]: any })
	if Registry.Debug then
		Registry.Debug.broadcast(cue)
	end
end

------------------------------------------------------------------ state machine

local function setSession(to: string)
	assert(SessionMachine.canTransition(State.session, to), `illegal session transition {State.session} -> {to}`)
	State.session = to
	stateTimer = 0
	Remotes.setState(Net.Attr.Session, to)
	Registry.Doors.refreshPrompts()
end

local function spawnAt(player: Player, marker: BasePart?)
	if not player.Parent then
		return
	end
	if not player.Character or not World.rootOf(player) then
		player:LoadCharacter()
	end
	local character = player.Character or player.CharacterAdded:Wait()
	character:WaitForChild("HumanoidRootPart", 5)
	Registry.Crew.prepareCharacter(player)
	local root = World.rootOf(player)
	if root then
		root.Anchored = false
	end
	if marker then
		World.teleport(player, marker.CFrame)
	end
end

local function lobbySpawn(index: number): BasePart?
	local spawns = World.spawns("Spawn_Lobby_")
	return spawns[((index - 1) % math.max(1, #spawns)) + 1]
end

local function shiftSpawn(index: number): BasePart?
	local spawns = World.spawns("Spawn_Shift_")
	return spawns[((index - 1) % math.max(1, #spawns)) + 1]
end

local function crewIndex(member: State.CrewMember): number
	for i, m in State.members() do
		if m == member then
			return i
		end
	end
	return 1
end

local function newSeed(): number
	return Random.new():NextInteger(100000, 999999)
end

local function prepareNight()
	local seed = newSeed()
	State.newNight(seed)
	local lostRng = State.stream("lost-frequency")
	State.lostFrequency = lostRng:Pick(Tapes.LostFrequencies)
	State.cluePieces = Tapes.cluePieces(State.lostFrequency)
	Remotes.setState(Net.Attr.Seed, seed)
	Registry.Signal.reset()
	Registry.Lighting.reset()
	Registry.Doors.reset()
	Registry.Tapes.reset()
	Registry.Tapes.plan()
	Registry.Devices.reset()
	Registry.Devices.planPanels()
	Registry.Anchor.reset()
	Registry.Director.reset()
	Registry.Radio.reset()
	Registry.Feeds.reset()
	Registry.Crew.reset()
	Registry.Phase.reset()
end

function Session.startIntro()
	if State.session ~= "Lobby" then
		return
	end
	countdown = nil
	Remotes.setState(Net.Attr.Countdown, -1)
	setSession("Intro")
	for _, member in State.members({ "Lobby" }) do
		State.setStatus(member, "Active")
		member.ready = false
		member.secondChances = GameConfig.Scaling.SoloSecondChances
	end
	Registry.Phase.reset()
	Session.cueAll({ kind = "Intro", duration = GameConfig.IntroDuration })
end

local function startRunning()
	setSession("Running")
	State.runStartedAt = os.clock()
	for _, member in State.members({ "Active" }) do
		task.spawn(spawnAt, member.player, shiftSpawn(crewIndex(member)))
		Registry.Tapes.sendInventory(member)
	end
	Registry.Phase.enter("Arrival")
	Registry.Feeds.publish(true)
	Registry.Tapes.publishDecks()
	Registry.Crew.publish()
end

function Session.beginEnding(endingId: string, actor: State.CrewMember?)
	if State.session ~= "Running" then
		return
	end
	setSession("Ending")
	local info =
		{ id = endingId, actor = if actor then actor.name else nil, actorId = if actor then actor.userId else nil }
	for _, member in State.members() do
		Registry.Devices.releaseAll(member.player)
	end
	local names = {}
	for _, member in State.members({ "Active", "Taken" }) do
		table.insert(names, member.name)
	end
	local payload = {
		id = endingId,
		actor = info.actor,
		actorId = info.actorId,
		crew = names,
		seed = State.seed,
		clock = State.clock,
		duration = math.floor(os.clock() - State.runStartedAt),
		lostFrequency = State.lostFrequency,
	}
	for _, member in State.members({ "Active", "Taken" }) do
		Registry.Data.unlockEnding(member.player, endingId)
	end
	for _, player in Players:GetPlayers() do
		local p = table.clone(payload) :: { [string]: any }
		p.endingsFound = Registry.Data.endingsFound(player)
		Remotes.fire(player, "Ending", p)
	end
end

local function reset()
	setSession("Resetting")
	prepareNight()
	for _, member in State.members() do
		State.setStatus(member, "Lobby")
		member.ready = false
		member.joinedLate = false
		task.spawn(spawnAt, member.player, lobbySpawn(crewIndex(member)))
		Registry.Tapes.sendInventory(member)
	end
	setSession("Lobby")
	Registry.Crew.publish()
end

------------------------------------------------------------------ zones

function Session.onZoneEntered(_member: State.CrewMember, zone: string)
	if State.session ~= "Running" then
		return
	end
	if zone == "MasterControl" then
		State.setFact("reachedMCR", true)
	elseif zone == "StudioB" and State.fact("studioBOpen") then
		if not State.fact("studioBEntered") then
			State.setFact("studioBEntered", true)
			Registry.Signal.openZeroChannel()
		end
	end
end

------------------------------------------------------------------ players

local function onPlayerAdded(player: Player)
	if #State.members() >= GameConfig.MaxPlayers then
		-- Server is full for this night; Roblox's MaxPlayers should prevent this, but be safe.
		player:Kick("This night shift is full.")
		return
	end
	local member = State.addCrew(player)
	member.secondChances = GameConfig.Scaling.SoloSecondChances
	player.CharacterAdded:Connect(function()
		Registry.Crew.prepareCharacter(player)
	end)
	Registry.Phase.sendObjectives(player)
	Registry.Tapes.publishDecks()
	Registry.Feeds.publish(true)
	if State.session == "Running" then
		-- Late join: arrives at reception and joins the crew immediately.
		State.setStatus(member, "Active")
		member.joinedLate = true
		task.spawn(spawnAt, player, World.marker("Spawn_Late"))
		Session.cueTo(player, { kind = "Notice", key = "notice.lateJoin" })
		Registry.Tapes.sendInventory(member)
	elseif State.session == "Lobby" then
		task.spawn(spawnAt, player, lobbySpawn(#State.members()))
	else
		-- Intro / Ending / Results: watch from the lobby, play next night.
		State.setStatus(member, "Spectating")
		task.spawn(spawnAt, player, lobbySpawn(#State.members()))
	end
	Registry.Crew.publish()
end

local function onPlayerRemoving(player: Player)
	local member = State.member(player)
	if not member then
		return
	end
	Registry.Devices.releaseAll(player)
	Registry.Tapes.dropAll(member)
	Registry.Devices.returnKey(member)
	State.removeCrew(player)
	if State.session == "Running" then
		Session.cueAll({ kind = "Notice", key = "notice.disconnect", vars = { name = member.name } })
		if State.shiftCount() == 0 then
			reset()
		else
			Registry.Crew.checkAllTaken()
		end
	end
end

------------------------------------------------------------------ lobby

local function stepLobby(dt: number)
	local members = State.members({ "Lobby" })
	local readyCount = 0
	for _, member in members do
		if member.ready then
			readyCount += 1
		end
	end
	if #members >= GameConfig.MinPlayersToStart and readyCount > 0 then
		local target = if readyCount == #members
			then GameConfig.Lobby.AllReadyCountdown
			else GameConfig.Lobby.AnyReadyCountdown
		countdown = math.min(countdown or target, target)
		countdown = (countdown :: number) - dt
		Remotes.setState(Net.Attr.Countdown, math.max(0, math.ceil(countdown :: number)))
		if (countdown :: number) <= 0 then
			Session.startIntro()
		end
	else
		countdown = nil
		Remotes.setState(Net.Attr.Countdown, -1)
	end
end

------------------------------------------------------------------ main loop

local fastTimer, slowTimer = 0, 0

local function heartbeat(dt: number)
	stateTimer += dt
	local session = State.session
	if session == "Lobby" then
		stepLobby(dt)
	elseif session == "Intro" then
		if stateTimer >= GameConfig.IntroDuration then
			startRunning()
		end
	elseif session == "Running" then
		fastTimer += dt
		if fastTimer >= 0.1 then
			local step = fastTimer
			fastTimer = 0
			Registry.Phase.step(step)
			Registry.Signal.step(step)
			Registry.Anchor.step(step)
			Registry.Crew.step(step)
			Registry.Tapes.step()
			Registry.Lighting.step()
			Registry.Radio.step(step)
			Registry.Feeds.step(step)
			Registry.Director.step(step)
		end
		slowTimer += dt
		if slowTimer >= 0.5 then
			slowTimer = 0
			Registry.Devices.step()
		end
	elseif session == "Ending" then
		if stateTimer >= 14 then
			setSession("Results")
		end
	elseif session == "Results" then
		if stateTimer >= GameConfig.ResultsDuration then
			reset()
		end
	end
end

function Session.init()
	Remotes.on("Ready", function(player, ready)
		local member = State.member(player)
		if member and type(ready) == "boolean" and State.session == "Lobby" and member.status == "Lobby" then
			member.ready = ready
			Registry.Crew.publish()
		end
	end)
end

function Session.start()
	prepareNight()
	Remotes.setState(Net.Attr.Session, "Lobby")
	Remotes.setState(Net.Attr.Countdown, -1)
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	RunService.Heartbeat:Connect(heartbeat)
end

-- Debug helpers.
function Session.debugStart()
	if State.session == "Lobby" then
		for _, member in State.members({ "Lobby" }) do
			member.ready = true
		end
		Session.startIntro()
	end
end

function Session.debugReset()
	if State.session ~= "Resetting" and State.session ~= "Lobby" then
		reset()
	end
end

return Session
