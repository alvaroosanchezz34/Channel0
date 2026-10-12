--[[
	Content and contract checks: localisation completeness, settings sanitising, the sound
	registry, the network contract and the debug defaults. These catch the bugs that are easy to
	ship and hard to notice in a playtest (a missing Spanish line, a cue naming a sound that does
	not exist, a debug flag left open).
]]

local fs = require("@lune/fs")
local Loader = require("../harness/Loader")

local function sourceFiles(root: string, out: { string }?): { string }
	local list = out or {}
	for _, entry in fs.readDir(root) do
		local path = root .. "/" .. entry
		if fs.isDir(path) then
			sourceFiles(path, list)
		elseif string.match(entry, "%.luau$") then
			table.insert(list, path)
		end
	end
	return list
end

local function tokens(text: string): string
	local found = {}
	for name in string.gmatch(text, "{(%w+)}") do
		found[name] = true
	end
	local list = {}
	for name in found do
		table.insert(list, name)
	end
	table.sort(list)
	return table.concat(list, ",")
end

return function(T)
	local describe, it, expect = T.describe, T.it, T.expect

	local Strings = Loader.load("src/shared/Content/Strings")
	local Settings = Loader.load("src/shared/Config/Settings")
	local AudioConfig = Loader.load("src/shared/Config/AudioConfig")
	local NetContract = Loader.load("src/shared/Net")
	local NetConfig = Loader.load("src/shared/Config/NetConfig")
	local Objectives = Loader.load("src/shared/Content/Objectives")
	local Endings = Loader.load("src/shared/Content/Endings")
	local Events = Loader.load("src/shared/Content/Events")
	local Tapes = Loader.load("src/shared/Content/Tapes")

	describe("Strings", function()
		it("has the same keys in English and Spanish", function()
			local missing = {}
			for key in Strings.en do
				if Strings.es[key] == nil then
					table.insert(missing, "es:" .. key)
				end
			end
			for key in Strings.es do
				if Strings.en[key] == nil then
					table.insert(missing, "en:" .. key)
				end
			end
			table.sort(missing)
			expect(table.concat(missing, " ")).toBe("")
		end)

		it("uses the same {tokens} in both languages", function()
			local mismatched = {}
			for key, text in Strings.en do
				local es = Strings.es[key]
				if es and tokens(text) ~= tokens(es) then
					table.insert(mismatched, key)
				end
			end
			table.sort(mismatched)
			expect(table.concat(mismatched, " ")).toBe("")
		end)

		it("substitutes vars and localises @key values", function()
			Strings.en["test.outer"] = "Panel {panel} says {what}"
			Strings.es["test.outer"] = "El panel {panel} dice {what}"
			Strings.en["test.inner"] = "hello"
			Strings.es["test.inner"] = "hola"
			expect(Strings.get("en", "test.outer", { panel = "A", what = "@test.inner" })).toBe("Panel A says hello")
			expect(Strings.get("es", "test.outer", { panel = "B", what = "@test.inner" })).toBe("El panel B dice hola")
			Strings.en["test.outer"], Strings.es["test.outer"] = nil, nil
			Strings.en["test.inner"], Strings.es["test.inner"] = nil, nil
		end)

		it("falls back to the key itself and keeps unknown tokens", function()
			expect(Strings.get("es", "no.such.key")).toBe("no.such.key")
			expect(Strings.get("en", "ui.crew", { count = 2 })).toBe("NIGHT CREW 2/{max}")
		end)

		it("picks Spanish for any es-* locale", function()
			expect(Strings.languageFor("es-es")).toBe("es")
			expect(Strings.languageFor("es-MX")).toBe("es")
			expect(Strings.languageFor("en-us")).toBe("en")
			expect(Strings.languageFor(nil)).toBe("en")
		end)

		it("covers every key named by the content tables", function()
			local missing = {}
			local function need(key: string?)
				if key and Strings.en[key] == nil then
					table.insert(missing, key)
				end
			end
			for _, def in Objectives.Defs or Objectives.List or {} do
				need(def.textKey)
				need(def.hintKey)
			end
			for _, def in Endings.Defs do
				need(def.titleKey)
				need(def.summaryKey)
				for _, req in def.requirements do
					need(req.textKey)
				end
			end
			for _, def in Events.Defs do
				need(def.descriptionKey)
			end
			for id in Tapes.Defs do
				-- The client localises tape names as tape.<id>.label.
				need("tape." .. id .. ".label")
			end
			table.sort(missing)
			expect(table.concat(missing, " ")).toBe("")
		end)

		it("covers every literal string key used in the game code", function()
			local prefixes = {
				ui = true,
				set = true,
				dev = true,
				req = true,
				sub = true,
				notice = true,
				hint = true,
				obj = true,
				prompt = true,
				intro = true,
				speaker = true,
				evt = true,
				["end"] = true,
			}
			local missing = {}
			for _, path in sourceFiles("src") do
				local source = fs.readFile(path)
				for key in string.gmatch(source, '"([%a]+%.[%w_.]+)"') do
					local prefix = string.match(key, "^(%a+)%.")
					-- Keys ending in "." are built dynamically ("dev.switcher." .. source).
					if prefix and prefixes[prefix] and string.sub(key, -1) ~= "." and Strings.en[key] == nil then
						table.insert(missing, key .. " (" .. path .. ")")
					end
				end
			end
			table.sort(missing)
			expect(table.concat(missing, "\n")).toBe("")
		end)
	end)

	describe("Settings.sanitize", function()
		it("returns defaults for garbage", function()
			for _, input in { nil, 42, "x", { masterVolume = "loud", reduceMotion = "yes" } } do
				local s = Settings.sanitize(input)
				expect(s.masterVolume).toBe(Settings.Defaults.masterVolume)
				expect(s.reduceMotion).toBe(Settings.Defaults.reduceMotion)
				expect(s.vhsProfile).toBe(Settings.Defaults.vhsProfile)
			end
		end)

		it("clamps volumes, rejects NaN and unknown choices", function()
			local s = Settings.sanitize({
				masterVolume = 7,
				ambienceVolume = 0 / 0,
				vhsProfile = "Off",
				subtitleSize = "huge",
				language = "fr",
			})
			expect(s.masterVolume).toBe(1)
			expect(s.ambienceVolume).toBe(Settings.Defaults.ambienceVolume)
			-- The VHS filter cannot be switched off, only softened.
			expect(s.vhsProfile).toBe("Default")
			expect(s.subtitleSize).toBe("medium")
			expect(s.language).toBe("auto")
		end)

		it("keeps valid values and drops unknown fields", function()
			local s = Settings.sanitize({
				masterVolume = 0.333,
				vhsProfile = "MinimalNoise",
				reduceMotion = true,
				language = "es",
				evil = string.rep("x", 1000),
			})
			expect(s.masterVolume).toBe(0.33)
			expect(s.vhsProfile).toBe("MinimalNoise")
			expect(s.reduceMotion).toBeTruthy()
			expect(s.language).toBe("es")
			expect((s :: any).evil).toBe(nil)
		end)
	end)

	describe("AudioConfig", function()
		-- Informational: essential sounds still waiting for an uploaded id (not a failure).
		local pending = {}
		for name, def in AudioConfig.Sounds do
			if def.essential and def.id == "" then
				table.insert(pending, name)
			end
		end
		table.sort(pending)
		if #pending > 0 then
			print(
				string.format(
					"note: %d essential sounds have no uploaded id yet: %s",
					#pending,
					table.concat(pending, ", ")
				)
			)
		end

		it("gives every sound a source file and a known group", function()
			local bad = {}
			for name, def in AudioConfig.Sounds do
				if type(def.file) ~= "string" or def.file == "" or AudioConfig.Groups[def.group] == nil then
					table.insert(bad, name)
				end
				-- No invented ids: an id is either empty or a real rbxassetid URI.
				if def.id ~= "" and not string.match(def.id, "^rbxassetid://%d+$") then
					table.insert(bad, name .. " (id)")
				end
			end
			table.sort(bad)
			expect(table.concat(bad, " ")).toBe("")
		end)

		it("only maps uploaded ids onto sounds that exist", function()
			local bad = {}
			for name, id in AudioConfig.Ids do
				if AudioConfig.Sounds[name] == nil or not string.match(id, "^rbxassetid://%d+$") then
					table.insert(bad, name)
				end
			end
			expect(table.concat(bad, " ")).toBe("")
		end)

		it("defines every sound named by a server or client cue", function()
			local missing = {}
			for _, path in sourceFiles("src") do
				local source = fs.readFile(path)
				for name in string.gmatch(source, 'sound%s*=%s*"([%w_]+)"') do
					if AudioConfig.Sounds[name] == nil then
						table.insert(missing, name .. " (" .. path .. ")")
					end
				end
			end
			table.sort(missing)
			expect(table.concat(missing, " ")).toBe("")
		end)
	end)

	describe("Network contract", function()
		it("rate-limits every client-to-server remote", function()
			for _, name in NetContract.ClientToServer do
				expect(NetConfig.Limits[name] ~= nil).toBeTruthy()
			end
			expect(NetConfig.Limits[NetContract.DebugRemote] ~= nil).toBeTruthy()
		end)

		it("does not list the debug remote among the always-created remotes", function()
			expect(table.find(NetContract.ClientToServer, NetContract.DebugRemote)).toBe(nil)
			expect(table.find(NetContract.ServerToClient, NetContract.DebugRemote)).toBe(nil)
		end)
	end)

	describe("DebugConfig", function()
		it("ships with live-server debug disabled and an empty allowlist", function()
			local source = fs.readFile("src/shared/Config/DebugConfig.luau")
			expect(string.find(source, "DebugConfig.AllowOnLiveServers = false", 1, true) ~= nil).toBeTruthy()
			expect(string.find(source, "DebugConfig.AllowedUserIds = {} :: { number }", 1, true) ~= nil).toBeTruthy()
		end)
	end)
end
