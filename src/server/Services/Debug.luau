--!strict
--[[
	Developer tools. Enabled only:
	  * in Roblox Studio, or
	  * on live servers when DebugConfig.AllowOnLiveServers is true AND the player's UserId is in
	    DebugConfig.AllowedUserIds.

	Authorization is evaluated on the server from the Player object delivered by OnServerEvent; no
	client-provided name or id is ever trusted. On a live server with debug disabled the Debug
	remote is never created at all. Commands are a fixed whitelist: there is no way to run
	arbitrary code, change other players, or touch persistence.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DebugConfig = require(Shared.Config.DebugConfig)
local Net = require(Shared.Net)
local Tapes = require(Shared.Content.Tapes)

local Registry = require(script.Parent.Registry)
local Remotes = require(script.Parent.Remotes)
local State = require(script.Parent.State)

local Debug = {}

local enabled = false
local pushTimer = 0

function Debug.isAuthorized(player: Player): boolean
	if not enabled then
		return false
	end
	if RunService:IsStudio() then
		return true
	end
	return DebugConfig.AllowOnLiveServers and table.find(DebugConfig.AllowedUserIds, player.UserId) ~= nil
end

local function authorizedPlayers(): { Player }
	local list = {}
	for _, player in Players:GetPlayers() do
		if Debug.isAuthorized(player) then
			table.insert(list, player)
		end
	end
	return list
end

function Debug.broadcast(cue: { [string]: any })
	if enabled then
		Remotes.fireList(authorizedPlayers(), "DebugState", { kind = "cue", cue = cue })
	end
end

local function snapshot(): { [string]: any }
	local facts = {}
	for name, value in State.facts do
		if value then
			table.insert(facts, name)
		end
	end
	table.sort(facts)
	return {
		kind = "state",
		session = State.session,
		phase = State.phase,
		clock = State.clock,
		seed = State.seed,
		lostFrequency = State.lostFrequency,
		facts = facts,
		counters = table.clone(State.counters),
		anchor = Registry.Anchor.debugInfo(),
		director = Registry.Director.debugInfo(),
		signal = Registry.Signal.snapshot(),
		endings = Registry.Endings.report(),
		tapes = table.clone(Registry.Tapes.assignment),
		panels = {
			A = Registry.Devices.panels.A and table.concat(Registry.Devices.panels.A.order, "-"),
			B = Registry.Devices.panels.B and table.concat(Registry.Devices.panels.B.order, "-"),
		},
	}
end

local Commands: { [string]: (player: Player, arg: any) -> (boolean, string?) } = {
	start = function()
		Registry.Session.debugStart()
		return true, nil
	end,
	reset = function()
		Registry.Session.debugReset()
		return true, nil
	end,
	skipPhase = function()
		if State.session ~= "Running" then
			return false, "not running"
		end
		Registry.Phase.skip()
		return true, nil
	end,
	anchor = function(_, arg)
		if type(arg) ~= "string" then
			return false, "state expected"
		end
		return Registry.Anchor.force(arg)
	end,
	event = function(_, arg)
		if type(arg) ~= "string" then
			return false, "event id expected"
		end
		return Registry.Director.run(arg, true)
	end,
	god = function(_, arg)
		Registry.Anchor.setGodMode(arg == true)
		return true, nil
	end,
	giveTape = function(player, arg)
		local member = State.member(player)
		if type(arg) ~= "string" or not Tapes.Defs[arg] or not member then
			return false, "unknown tape"
		end
		if not table.find(member.tapes, arg) and #member.tapes < 3 then
			table.insert(member.tapes, arg)
			Registry.Tapes.location[arg] = "carried"
			Registry.Tapes.sendInventory(member)
		end
		return true, nil
	end,
	giveKey = function(player)
		local member = State.member(player)
		if member then
			member.hasKey = true
			State.setFact("keyTaken", true)
			State.setFact("hasKillKey", true)
			Registry.Tapes.sendInventory(member)
		end
		return true, nil
	end,
	fact = function(_, arg)
		if type(arg) ~= "table" or type(arg.name) ~= "string" or type(arg.value) ~= "boolean" or #arg.name > 40 then
			return false, "{ name, value } expected"
		end
		State.setFact(arg.name, arg.value)
		return true, nil
	end,
	takeSelf = function(player)
		local member = State.member(player)
		if member then
			Registry.Crew.take(member)
		end
		return true, nil
	end,
}

function Debug.init()
	enabled = RunService:IsStudio() or (DebugConfig.AllowOnLiveServers and #DebugConfig.AllowedUserIds > 0)
	Remotes.setState(Net.Attr.DebugEnabled, enabled)
	if not enabled then
		return
	end
	Remotes.createDebugRemote()
	Remotes.on(Net.DebugRemote, function(player, command, arg)
		if not Debug.isAuthorized(player) then
			return
		end
		if not Remotes.isString(command, 24) then
			return
		end
		local handler = Commands[command]
		if not handler then
			return
		end
		local ok, err = handler(player, arg)
		Remotes.fire(player, "DebugState", { kind = "result", command = command, ok = ok, err = err })
		Remotes.fire(player, "DebugState", snapshot())
	end)
	RunService.Heartbeat:Connect(function(dt)
		pushTimer += dt
		if pushTimer >= 1 then
			pushTimer = 0
			local who = authorizedPlayers()
			if #who > 0 then
				Remotes.fireList(who, "DebugState", snapshot())
			end
		end
	end)
end

return Debug
