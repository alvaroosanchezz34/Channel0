--!strict
--[[
	Player settings: defaults and the sanitiser used by BOTH the client (before sending) and the
	server (before saving). Anything unknown or malformed falls back to the default, so a crafted
	payload can never store arbitrary data in a player's profile.
]]

export type Settings = {
	masterVolume: number,
	ambienceVolume: number,
	vhsProfile: string,
	reduceMotion: boolean,
	subtitles: boolean,
	subtitleSize: string,
	language: string,
}

local Settings = {}

Settings.Defaults = {
	masterVolume = 0.8,
	ambienceVolume = 0.8,
	vhsProfile = "Default",
	reduceMotion = false,
	subtitles = true,
	subtitleSize = "medium",
	language = "auto",
} :: Settings

Settings.Choices = {
	vhsProfile = { "Default", "Reduced", "MinimalNoise" },
	subtitleSize = { "small", "medium", "large" },
	language = { "auto", "en", "es" },
}

local function number01(value: any, default: number): number
	if type(value) ~= "number" or value ~= value then
		return default
	end
	return math.clamp(math.floor(value * 100 + 0.5) / 100, 0, 1)
end

local function choice(value: any, list: { string }, default: string): string
	if type(value) == "string" and table.find(list, value) then
		return value
	end
	return default
end

local function bool(value: any, default: boolean): boolean
	if type(value) == "boolean" then
		return value
	end
	return default
end

function Settings.sanitize(input: any): Settings
	local d = Settings.Defaults
	local t = if type(input) == "table" then input else {}
	return {
		masterVolume = number01(t.masterVolume, d.masterVolume),
		ambienceVolume = number01(t.ambienceVolume, d.ambienceVolume),
		vhsProfile = choice(t.vhsProfile, Settings.Choices.vhsProfile, d.vhsProfile),
		reduceMotion = bool(t.reduceMotion, d.reduceMotion),
		subtitles = bool(t.subtitles, d.subtitles),
		subtitleSize = choice(t.subtitleSize, Settings.Choices.subtitleSize, d.subtitleSize),
		language = choice(t.language, Settings.Choices.language, d.language),
	}
end

return Settings
