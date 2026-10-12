--!strict
--[[
	Developer panel (F8). It exists on the client for everyone, but stays hidden and inert until the
	server sends a DebugState message, which it only does to authorized players (Studio, or an
	allow-listed UserId on a server where debug is enabled). Buttons send whitelisted commands
	through the Debug remote; the server re-checks authorization on every call.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EventDefs = require(Shared.Content.Events)
local NetContract = require(Shared.Net)
local TapeDefs = require(Shared.Content.Tapes)

local Make = require(script.Parent.Parent.UI.Make)
local Net = require(script.Parent.Net)
local Store = require(script.Parent.Store)
local Theme = require(script.Parent.Parent.UI.Theme)

local Debug = {}

local authorized = false
local gui: ScreenGui? = nil
local frame: Frame
local stateLabel: TextLabel
local resultLabel: TextLabel
local god = false

local function send(command: string, arg: any?)
	Net.send(NetContract.DebugRemote, command, arg)
end

type Entry = { label: string, run: () -> () }

local function describe(snapshot: { [string]: any }): string
	local lines = {
		string.format(
			"session %s · phase %s · clock %s · seed %s",
			tostring(snapshot.session),
			tostring(snapshot.phase),
			tostring(snapshot.clock),
			tostring(snapshot.seed)
		),
		string.format(
			"lost freq %s · panels A %s / B %s",
			tostring(snapshot.lostFrequency),
			tostring(snapshot.panels and snapshot.panels.A),
			tostring(snapshot.panels and snapshot.panels.B)
		),
	}
	local anchor = snapshot.anchor or {}
	table.insert(
		lines,
		string.format(
			"ANCHOR %s %ss/%ss · target %s · pressure %s · hunt cd %s%s",
			tostring(anchor.state),
			tostring(anchor.timeInState),
			tostring(anchor.duration),
			tostring(anchor.target),
			tostring(anchor.pressure),
			tostring(anchor.huntCooldown),
			if anchor.godMode then " · GOD" else ""
		)
	)
	local director = snapshot.director or {}
	table.insert(
		lines,
		string.format("director budget %s · scheduled %s", tostring(director.budget), tostring(director.scheduled))
	)
	local log = director.log or {}
	for i = math.max(1, #log - 5), #log do
		table.insert(lines, "  " .. tostring(log[i]))
	end
	local signal = snapshot.signal or {}
	table.insert(
		lines,
		string.format(
			"signal q%s · %s MHz · on air %s",
			tostring(signal.quality),
			tostring(signal.frequency),
			tostring(signal.onAir)
		)
	)
	table.insert(lines, "facts: " .. table.concat(snapshot.facts or {}, ", "))
	local counters = {}
	for k, v in snapshot.counters or {} do
		table.insert(counters, k .. "=" .. tostring(v))
	end
	table.sort(counters)
	table.insert(lines, "counters: " .. table.concat(counters, ", "))
	local endings = {}
	for _, report in snapshot.endings or {} do
		table.insert(
			endings,
			string.format("%s(%s)", tostring(report.id), if report.met then "OK" else "-" .. #(report.missing or {}))
		)
	end
	table.insert(lines, "endings: " .. table.concat(endings, " "))
	local tapes = {}
	for tape, slot in snapshot.tapes or {} do
		table.insert(tapes, tape .. "@" .. tostring(slot))
	end
	table.sort(tapes)
	table.insert(lines, "tapes: " .. table.concat(tapes, " "))
	return table.concat(lines, "\n")
end

local function build()
	local screen = Make.screen("Debug", 50, Players.LocalPlayer:WaitForChild("PlayerGui"))
	gui = screen
	frame = Make.new("Frame", {
		Size = UDim2.new(0, 520, 1, -40),
		Position = UDim2.fromOffset(20, 20),
		BackgroundColor3 = Theme.Colors.Panel,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		Visible = false,
		Parent = screen,
	}, { Make.stroke(Theme.Colors.Red, 1) })
	Make.modal(frame)
	local scroll = Make.new("ScrollingFrame", {
		Size = UDim2.new(1, -16, 1, -16),
		Position = UDim2.fromOffset(8, 8),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Parent = frame,
	}, { Make.list(Enum.FillDirection.Vertical, 6) })
	Make.text({
		Text = Store.t("ui.debug") .. "  [F8]",
		TextColor3 = Theme.Colors.Red,
		LayoutOrder = 0,
		Parent = scroll,
	})
	stateLabel =
		Make.text({ Text = "", TextSize = 14, AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1, Parent = scroll })
	resultLabel =
		Make.text({ Text = "", TextSize = 14, TextColor3 = Theme.Colors.Amber, LayoutOrder = 2, Parent = scroll })

	local order = 3
	local function group(title: string, entries: { Entry })
		Make.text({
			Text = title,
			TextSize = 14,
			TextColor3 = Theme.Colors.TextDim,
			LayoutOrder = order,
			Parent = scroll,
		})
		order += 1
		local holder = Make.new("Frame", {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			LayoutOrder = order,
			Parent = scroll,
		}, { Make.new("UIGridLayout", { CellSize = UDim2.fromOffset(120, 30), CellPadding = UDim2.fromOffset(4, 4) }) })
		order += 1
		for _, entry in entries do
			Make.button({ Text = entry.label, TextSize = 13, Parent = holder }, entry.run)
		end
	end

	group("SESSION", {
		{
			label = "start",
			run = function()
				send("start")
			end,
		},
		{
			label = "reset",
			run = function()
				send("reset")
			end,
		},
		{
			label = "skip phase",
			run = function()
				send("skipPhase")
			end,
		},
		{
			label = "god",
			run = function()
				god = not god
				send("god", god)
			end,
		},
		{
			label = "take me",
			run = function()
				send("takeSelf")
			end,
		},
		{
			label = "give key",
			run = function()
				send("giveKey")
			end,
		},
	})
	local states: { Entry } = {}
	for _, state in { "Dormant", "Broadcast", "Observing", "Displacement", "Manifestation", "Hunt", "Withdrawal" } do
		table.insert(states, {
			label = state,
			run = function()
				send("anchor", state)
			end,
		})
	end
	group("THE ANCHOR", states)
	local events: { Entry } = {}
	for _, def in EventDefs.Defs do
		local id = def.id
		table.insert(events, {
			label = id,
			run = function()
				send("event", id)
			end,
		})
	end
	group("EVENTS", events)
	local tapes: { Entry } = {}
	for id in TapeDefs.Defs do
		table.insert(tapes, {
			label = id,
			run = function()
				send("giveTape", id)
			end,
		})
	end
	table.sort(tapes, function(a, b)
		return a.label < b.label
	end)
	group("TAPES", tapes)
	local facts: { Entry } = {}
	for _, name in
		{ "phaseCrisis", "allClueTapesViewed", "lostFrequencyLocked", "masterInMCR", "channel0OnAir", "contractViewed" }
	do
		table.insert(facts, {
			label = name,
			run = function()
				send("fact", { name = name, value = true })
			end,
		})
	end
	group("FACTS = true", facts)
end

local function onDebug(message: { [string]: any })
	if type(message) ~= "table" then
		return
	end
	if not authorized then
		authorized = true
		build()
	end
	if message.kind == "state" then
		stateLabel.Text = describe(message)
	elseif message.kind == "result" then
		resultLabel.Text = string.format(
			"%s → %s%s",
			tostring(message.command),
			if message.ok then "ok" else "FAILED",
			if message.err then " (" .. tostring(message.err) .. ")" else ""
		)
	elseif message.kind == "cue" and type(message.cue) == "table" then
		resultLabel.Text = "cue: "
			.. tostring(message.cue.kind)
			.. " "
			.. tostring(message.cue.key or message.cue.sound or "")
	end
end

function Debug.init()
	-- Where the server never created the remote, no DebugState ever arrives and nothing is built.
	Store.Changed:Connect(function(kind, payload)
		if kind == "debug" then
			onDebug(payload)
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.F8 and authorized and gui then
			frame.Visible = not frame.Visible
		end
	end)
end

return Debug
