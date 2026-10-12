--!strict
--[[
	Persistence: ONLY preferences and unlocked endings are saved. Session progress is never stored
	(every night starts fresh by design).

	DataStore access is wrapped in pcall with bounded retries; when it is unavailable (Studio
	without API access, outages) the game keeps running with defaults and simply does not save.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EndingContent = require(Shared.Content.Endings)
local Settings = require(Shared.Config.Settings)

local Remotes = require(script.Parent.Remotes)

local Data = {}

type Profile = { version: number, settings: Settings.Settings, endings: { [string]: boolean } }

local STORE_NAME = "Channel0Profiles_v1"
local profiles: { [number]: Profile } = {}
local dirty: { [number]: boolean } = {}
local store: DataStore? = nil
local available = false

local function key(userId: number): string
	return "u_" .. tostring(userId)
end

local function sanitizeProfile(raw: any): Profile
	local endings = {}
	if type(raw) == "table" and type(raw.endings) == "table" then
		for id in EndingContent.Defs do
			if raw.endings[id] == true then
				endings[id] = true
			end
		end
	end
	return {
		version = 1,
		settings = Settings.sanitize(if type(raw) == "table" then raw.settings else nil),
		endings = endings,
	}
end

local function withRetries<T>(fn: () -> T): (boolean, T?)
	for attempt = 1, 3 do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		warn(string.format("[Channel0] DataStore attempt %d failed: %s", attempt, tostring(result)))
		task.wait(attempt * 1.5)
	end
	return false, nil
end

local function send(player: Player)
	local profile = profiles[player.UserId]
	if profile then
		local count = 0
		for _ in profile.endings do
			count += 1
		end
		Remotes.fire(
			player,
			"Profile",
			{ settings = profile.settings, endings = profile.endings, endingsFound = count }
		)
	end
end

local function load(player: Player)
	local raw = nil
	if available and store then
		local s = store
		local ok, result = withRetries(function()
			return s:GetAsync(key(player.UserId))
		end)
		if ok then
			raw = result
		end
	end
	if player.Parent then
		profiles[player.UserId] = sanitizeProfile(raw)
		send(player)
	end
end

local function save(userId: number)
	local profile = profiles[userId]
	if not profile or not available or not store or not dirty[userId] then
		return
	end
	dirty[userId] = nil
	local s = store
	withRetries(function()
		s:UpdateAsync(key(userId), function(old: any)
			-- Merge endings so a save from another server is never lost.
			local merged = sanitizeProfile(old)
			for id in profile.endings do
				merged.endings[id] = true
			end
			merged.settings = profile.settings
			return merged
		end)
		return true
	end)
end

function Data.init()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
		available = true
	else
		warn("[Channel0] DataStore unavailable; settings and endings will not persist: " .. tostring(result))
	end
	if RunService:IsStudio() and game.GameId == 0 then
		-- Unpublished place: DataStores cannot work.
		available = false
	end

	Players.PlayerAdded:Connect(function(player)
		task.spawn(load, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(load, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		save(player.UserId)
		profiles[player.UserId] = nil
		dirty[player.UserId] = nil
	end)
	game:BindToClose(function()
		for userId in profiles do
			save(userId)
		end
	end)
	Remotes.on("Settings", function(player, payload)
		local profile = profiles[player.UserId]
		if profile then
			profile.settings = Settings.sanitize(payload)
			dirty[player.UserId] = true
		end
	end)
end

function Data.unlockEnding(player: Player, endingId: string)
	local profile = profiles[player.UserId]
	if profile and EndingContent.Defs[endingId] and not profile.endings[endingId] then
		profile.endings[endingId] = true
		dirty[player.UserId] = true
		task.spawn(save, player.UserId)
	end
	send(player)
end

function Data.endingsFound(player: Player): number
	local profile = profiles[player.UserId]
	local count = 0
	if profile then
		for _ in profile.endings do
			count += 1
		end
	end
	return count
end

return Data
