--!strict
--[[
	Creates the remotes and wraps every client -> server channel with a per-player token bucket and
	basic argument validation. Handlers only ever see a real Player object (from OnServerEvent),
	never an identity claimed by the client.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local NetConfig = require(Shared.Config.NetConfig)
local RateLimiter = require(Shared.Util.RateLimiter)

local Remotes = {}

local folder: Folder
local stateFolder: Folder
local events: { [string]: RemoteEvent } = {}
local limiters: { [string]: RateLimiter.RateLimiter } = {}
local dropped: { [number]: number } = {}

function Remotes.init()
	folder = Instance.new("Folder")
	folder.Name = Net.FolderName
	for _, name in Net.ServerToClient do
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = folder
		events[name] = remote
	end
	for _, name in Net.ClientToServer do
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = folder
		events[name] = remote
		local limit = NetConfig.Limits[name]
		if limit then
			limiters[name] = RateLimiter.new(limit[1], limit[2])
		end
	end
	folder.Parent = ReplicatedStorage

	stateFolder = Instance.new("Folder")
	stateFolder.Name = Net.StateFolderName
	stateFolder.Parent = ReplicatedStorage

	Players.PlayerRemoving:Connect(function(player)
		for _, limiter in limiters do
			limiter:Forget(player.UserId)
		end
		dropped[player.UserId] = nil
	end)
end

-- Creates the debug remote. Only DebugService calls this, and only when debug may be enabled.
function Remotes.createDebugRemote(): RemoteEvent
	local remote = Instance.new("RemoteEvent")
	remote.Name = Net.DebugRemote
	remote.Parent = folder
	events[Net.DebugRemote] = remote
	limiters[Net.DebugRemote] = RateLimiter.new(NetConfig.Limits.Debug[1], NetConfig.Limits.Debug[2])
	return remote
end

function Remotes.setState(name: string, value: any)
	if stateFolder:GetAttribute(name) ~= value then
		stateFolder:SetAttribute(name, value)
	end
end

function Remotes.getState(name: string): any
	return stateFolder:GetAttribute(name)
end

function Remotes.fire(player: Player, name: string, ...: any)
	local remote = events[name]
	if remote and player.Parent == Players then
		remote:FireClient(player, ...)
	end
end

function Remotes.fireAll(name: string, ...: any)
	local remote = events[name]
	if remote then
		remote:FireAllClients(...)
	end
end

function Remotes.fireList(players: { Player }, name: string, ...: any)
	for _, player in players do
		Remotes.fire(player, name, ...)
	end
end

-- Connects a validated, rate-limited handler for a client -> server channel.
function Remotes.on(name: string, handler: (player: Player, ...any) -> ())
	local remote = events[name]
	assert(remote, "unknown remote " .. name)
	local limiter = limiters[name]
	remote.OnServerEvent:Connect(function(player: Player, ...)
		if limiter and not limiter:Allow(player.UserId, os.clock()) then
			dropped[player.UserId] = (dropped[player.UserId] or 0) + 1
			return
		end
		local ok: boolean, err: any = pcall(handler, player, ...)
		if not ok then
			warn(string.format("[Channel0] %s handler error for %d: %s", name, player.UserId, tostring(err)))
		end
	end)
end

-- Argument helpers: reject anything that is not exactly the expected shape.
function Remotes.isString(value: any, maxLength: number): boolean
	return type(value) == "string" and #value > 0 and #value <= maxLength
end

function Remotes.isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

return Remotes
