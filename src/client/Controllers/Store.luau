--!strict
--[[
	Client cache of everything the server publishes, plus local settings and localisation.
	Controllers read from here and listen to `Changed` (kind) instead of each wiring remotes.
]]

local LocalizationService = game:GetService("LocalizationService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Settings = require(Shared.Config.Settings)
local Signal = require(Shared.Util.Signal)
local Strings = require(Shared.Content.Strings)

local Net = require(script.Parent.Net)

local Store = {}

Store.Changed = Signal.new() :: any -- (kind: string, payload: any)
Store.settings = table.clone(Settings.Defaults) :: Settings.Settings
Store.profile = { endings = {}, endingsFound = 0 } :: { [string]: any }
Store.signal = {} :: { [string]: any }
Store.objectives = { phase = "Arrival", list = {} } :: { [string]: any }
Store.crew = {} :: { { [string]: any } }
Store.inventory = { tapes = {}, key = false } :: { [string]: any }
Store.feeds = {} :: { [string]: any }
Store.decks = {} :: { [string]: any }
Store.clueVars = {} :: { [string]: any }
Store.ending = nil :: { [string]: any }?
Store.taken = nil :: { [string]: any }?

local function systemLanguage(): string
	local ok, locale = pcall(function()
		return LocalizationService.RobloxLocaleId
	end)
	if not ok then
		locale = Players.LocalPlayer.LocaleId
	end
	return Strings.languageFor(locale)
end

function Store.language(): string
	local chosen = Store.settings.language
	if chosen == "en" or chosen == "es" then
		return chosen
	end
	return systemLanguage()
end

function Store.t(key: string, vars: { [string]: any }?): string
	return Strings.get(Store.language(), key, vars)
end

function Store.setSettings(partial: { [string]: any })
	local merged = table.clone(Store.settings) :: any
	for k, v in partial do
		merged[k] = v
	end
	Store.settings = Settings.sanitize(merged)
	Net.send("Settings", Store.settings)
	Store.Changed:Fire("settings", Store.settings)
end

function Store.me(): { [string]: any }?
	for _, entry in Store.crew do
		if entry.userId == Players.LocalPlayer.UserId then
			return entry
		end
	end
	return nil
end

function Store.init()
	Net.on("Profile", function(payload)
		Store.profile = payload
		Store.settings = Settings.sanitize(payload.settings)
		Store.Changed:Fire("settings", Store.settings)
		Store.Changed:Fire("profile", payload)
	end)
	Net.on("Signal", function(snapshot)
		Store.signal = snapshot
		Store.Changed:Fire("signal", snapshot)
	end)
	Net.on("Objectives", function(payload)
		Store.objectives = payload
		Store.Changed:Fire("objectives", payload)
	end)
	Net.on("Crew", function(list)
		Store.crew = list
		Store.Changed:Fire("crew", list)
	end)
	Net.on("Inventory", function(payload)
		Store.inventory = payload
		Store.Changed:Fire("inventory", payload)
	end)
	Net.on("Feeds", function(payload)
		Store.feeds = payload
		Store.Changed:Fire("feeds", payload)
	end)
	Net.on("Decks", function(payload, vars)
		Store.decks = payload
		Store.clueVars = vars or {}
		Store.Changed:Fire("decks", payload)
	end)
	Net.on("Ending", function(payload)
		Store.ending = payload
		Store.Changed:Fire("ending", payload)
	end)
	Net.on("Cue", function(cue)
		if type(cue) == "table" and type(cue.kind) == "string" then
			if cue.kind == "Taken" then
				Store.taken = cue
			elseif cue.kind == "Recovered" then
				Store.taken = nil
			end
			Store.Changed:Fire("cue", cue)
		end
	end)
	Net.on("Device", function(message)
		Store.Changed:Fire("device", message)
	end)
	Net.on("DebugState", function(message)
		Store.Changed:Fire("debug", message)
	end)
	Net.onState(Net.Attr.Session, function(value)
		if value == "Lobby" then
			Store.ending = nil
			Store.taken = nil
		end
		Store.Changed:Fire("session", value)
	end)
end

return Store
