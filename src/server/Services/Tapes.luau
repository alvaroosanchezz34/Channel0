--!strict
--[[
	VHS tapes: seeded placement, pickups, inventories and the two playback decks. Playback is a
	server timeline (tape id + server start time); clients render the shots and subtitles from it,
	so every player near a monitor sees the same frame and nobody can fake having watched a tape.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local PhaseOrder = require(Shared.Logic.PhaseOrder)
local Strings = require(Shared.Content.Strings)
local TapeContent = require(Shared.Content.Tapes)

local Registry = require(script.Parent.Registry)
local Remotes = require(script.Parent.Remotes)
local State = require(script.Parent.State)
local World = require(script.Parent.World)

local Tapes = {}

export type Deck = {
	id: string,
	zone: string,
	tape: string?,
	playing: boolean,
	startedAt: number,
	ejected: string?, -- tape left on the tray by a jam
	finished: boolean,
}

Tapes.decks = {
	VTR_MCR = {
		id = "VTR_MCR",
		zone = "MasterControl",
		tape = nil,
		playing = false,
		startedAt = 0,
		ejected = nil,
		finished = false,
	},
	VTR_Editing = {
		id = "VTR_Editing",
		zone = "Editing",
		tape = nil,
		playing = false,
		startedAt = 0,
		ejected = nil,
		finished = false,
	},
} :: { [string]: Deck }

-- tapeId -> slotId chosen for this night.
Tapes.assignment = {} :: { [string]: string }
-- tapeId -> where it is now: "pending" | "slot" | "carried" | "deck" | "hidden"
Tapes.location = {} :: { [string]: string }
local models: { [string]: Model } = {}
local folder: Folder

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function labelText(tapeId: string): string
	local def = TapeContent.Defs[tapeId]
	return if def then Strings.get("en", def.labelKey) else tapeId
end

function Tapes.init()
	folder = Instance.new("Folder")
	folder.Name = "Tapes"
	folder.Parent = Workspace
end

-- Seeded placement: fixed tapes use their only slot; clue and lore tapes draw distinct slots.
function Tapes.plan()
	table.clear(Tapes.assignment)
	table.clear(Tapes.location)
	local rng = State.stream("tapes")
	local used: { [string]: boolean } = {}
	local ids = {}
	for id in TapeContent.Defs do
		table.insert(ids, id)
	end
	table.sort(ids)
	-- Fixed tapes first so random ones never take their slots.
	for _, id in ids do
		local def = TapeContent.Defs[id]
		if #def.slots == 1 then
			Tapes.assignment[id] = def.slots[1]
			used[def.slots[1]] = true
		end
	end
	local lore = rng:Shuffle(table.clone(TapeContent.LoreTapes))
	local chosenLore = {}
	for i = 1, math.min(TapeContent.LoreCount, #lore) do
		chosenLore[lore[i]] = true
	end
	for _, id in ids do
		local def = TapeContent.Defs[id]
		local isLore = table.find(TapeContent.LoreTapes, id) ~= nil
		if #def.slots > 1 and (not isLore or chosenLore[id]) then
			local options = {}
			for _, slot in def.slots do
				if not used[slot] and World.slots[slot] then
					table.insert(options, slot)
				end
			end
			if #options > 0 then
				local slot = rng:Pick(options)
				Tapes.assignment[id] = slot
				used[slot] = true
			end
		end
	end
	for id in Tapes.assignment do
		Tapes.location[id] = "pending"
	end
end

local function spawnModel(tapeId: string)
	local slotId = Tapes.assignment[tapeId]
	local slot = slotId and World.slots[slotId]
	local template = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Tape")
	if not slot or not template or models[tapeId] then
		return
	end
	local model = (template :: Model):Clone()
	model.Name = "Tape_" .. tapeId
	model:SetAttribute("TapeId", tapeId)
	model:PivotTo(slot.CFrame)
	local label = model:FindFirstChild("Label")
	local gui = label and label:FindFirstChild("LabelGui")
	local text = gui and gui:FindFirstChildOfClass("TextLabel")
	if text then
		text.Text = labelText(tapeId)
	end
	local body = model.PrimaryPart or model:FindFirstChild("Body")
	if body and body:IsA("BasePart") then
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "Prompt"
		prompt.Style = Enum.ProximityPromptStyle.Custom
		prompt.ActionText = "Pick up"
		prompt.ObjectText = labelText(tapeId)
		prompt.MaxActivationDistance = 6
		prompt.RequiresLineOfSight = false
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
		prompt:SetAttribute("PromptKey", "prompt.pickup")
		prompt:SetAttribute("TapeId", tapeId)
		prompt.Parent = body
		prompt.Triggered:Connect(function(player)
			Tapes.pickup(player, tapeId)
		end)
	end
	model.Parent = folder
	models[tapeId] = model
	Tapes.location[tapeId] = "slot"
end

-- Places every tape whose phase has arrived (hidden tapes wait for their reveal).
function Tapes.spawnForPhase(phase: string)
	for id, location in Tapes.location do
		local def = TapeContent.Defs[id]
		if location == "pending" and PhaseOrder.atLeast(phase, def.spawnPhase) then
			if id == "Contract1961" then
				Tapes.location[id] = "hidden" -- revealed by searching the Studio A desk drawer
			else
				spawnModel(id)
			end
		end
	end
end

function Tapes.reveal(tapeId: string): boolean
	if Tapes.location[tapeId] == "hidden" then
		spawnModel(tapeId)
		return true
	end
	return false
end

local function sendInventory(member: State.CrewMember)
	Remotes.fire(member.player, "Inventory", { tapes = table.clone(member.tapes), key = member.hasKey })
end
Tapes.sendInventory = sendInventory

function Tapes.pickup(player: Player, tapeId: string)
	local member = State.member(player)
	local model = models[tapeId]
	if not member or member.status ~= "Active" or not model or Tapes.location[tapeId] ~= "slot" then
		return
	end
	local position = World.positionOf(player)
	if not position or (position - model:GetPivot().Position).Magnitude > GameConfig.Player.InteractRange then
		return
	end
	if #member.tapes >= GameConfig.Player.MaxTapes then
		Registry.Devices.message(player, "dev.full")
		return
	end
	model:Destroy()
	models[tapeId] = nil
	table.insert(member.tapes, tapeId)
	Tapes.location[tapeId] = "carried"
	sendInventory(member)
	Remotes.fire(player, "Cue", { kind = "Notice", key = "notice.pickup", vars = { tape = labelText(tapeId) } })
	Remotes.fire(player, "Cue", { kind = "Sound", sound = "TapePickup" })
end

-- Returns a member's tapes to their slots (disconnect).
function Tapes.dropAll(member: State.CrewMember)
	for _, tapeId in member.tapes do
		Tapes.location[tapeId] = "pending"
		spawnModel(tapeId)
	end
	table.clear(member.tapes)
end

local function publishDecks()
	local payload = {}
	for id, deck in Tapes.decks do
		payload[id] = {
			tape = deck.tape,
			playing = deck.playing,
			startedAt = deck.startedAt,
			ejected = deck.ejected,
			finished = deck.finished,
		}
	end
	Remotes.fireAll("Decks", payload, { p1 = State.cluePieces[1], p2 = State.cluePieces[2], p3 = State.cluePieces[3] })
end
Tapes.publishDecks = publishDecks

local function syncFacts()
	local mcr = Tapes.decks.VTR_MCR
	State.setFact("fillerInMCR", mcr.tape == "Filler")
	State.setFact("masterInMCR", mcr.tape == "Master1987")
	local playing = false
	for _, deck in Tapes.decks do
		playing = playing or deck.playing
	end
	State.setFact("tapePlaying", playing)
	Registry.Signal.setVtrLoaded(mcr.tape ~= nil)
end

function Tapes.deckView(deckId: string, member: State.CrewMember?): { [string]: any }
	local deck = Tapes.decks[deckId]
	return {
		deck = deckId,
		tape = deck.tape,
		tapeLabel = if deck.tape then labelText(deck.tape) else nil,
		playing = deck.playing,
		ejected = deck.ejected,
		ejectedLabel = if deck.ejected then labelText(deck.ejected) else nil,
		carried = if member then table.clone(member.tapes) else {},
	}
end

function Tapes.insert(member: State.CrewMember, deckId: string, tapeId: string): (boolean, string?)
	local deck = Tapes.decks[deckId]
	if not deck then
		return false, "invalid"
	end
	if deck.tape then
		return false, "occupied"
	end
	if tapeId == "tray" then
		if not deck.ejected then
			return false, "invalid"
		end
		deck.tape = deck.ejected
		deck.ejected = nil
		Tapes.location[deck.tape :: any] = "deck"
	else
		local index = table.find(member.tapes, tapeId)
		if not index then
			return false, "notCarried"
		end
		table.remove(member.tapes, index)
		deck.tape = tapeId
		Tapes.location[tapeId] = "deck"
		sendInventory(member)
	end
	deck.playing = true
	deck.finished = false
	deck.startedAt = serverNow()
	Registry.Session.cueNear(
		World.devices[deckId].Position,
		40,
		{ kind = "Sound", sound = "VTRInsert", position = World.devices[deckId].Position }
	)
	syncFacts()
	publishDecks()
	return true, nil
end

function Tapes.eject(member: State.CrewMember, deckId: string): (boolean, string?)
	local deck = Tapes.decks[deckId]
	local tapeId = deck and (deck.tape or deck.ejected)
	if not deck or not tapeId then
		return false, "empty"
	end
	if #member.tapes >= GameConfig.Player.MaxTapes then
		return false, "full"
	end
	deck.tape = nil
	deck.ejected = nil
	deck.playing = false
	deck.finished = false
	table.insert(member.tapes, tapeId)
	Tapes.location[tapeId] = "carried"
	sendInventory(member)
	Registry.Session.cueNear(
		World.devices[deckId].Position,
		40,
		{ kind = "Sound", sound = "VTREject", position = World.devices[deckId].Position }
	)
	syncFacts()
	publishDecks()
	return true, nil
end

function Tapes.setPlaying(deckId: string, playing: boolean)
	local deck = Tapes.decks[deckId]
	if not deck or not deck.tape or deck.playing == playing then
		return
	end
	deck.playing = playing
	if playing then
		-- Restarting a tape plays it from the top (a viewing only counts when watched to the end).
		deck.startedAt = serverNow()
		deck.finished = false
	end
	syncFacts()
	publishDecks()
end

-- VTR jam fault: the MCR deck spits its tape onto the tray.
function Tapes.jam(deckId: string): boolean
	local deck = Tapes.decks[deckId]
	if not deck or not deck.tape then
		return false
	end
	deck.ejected = deck.tape
	deck.tape = nil
	deck.playing = false
	syncFacts()
	publishDecks()
	return true
end

local function markViewed(deck: Deck, tapeId: string)
	local def = TapeContent.Defs[tapeId]
	if def.viewedFact and not State.fact(def.viewedFact) then
		State.setFact(def.viewedFact, true)
		if def.kind == "Clue" then
			State.addCounter("clueTapesViewed")
			State.setFact("allClueTapesViewed", State.counter("clueTapesViewed") >= #TapeContent.ClueTapes)
		end
		local position = World.devices[deck.id].Position
		Registry.Session.cueNear(
			position,
			60,
			{ kind = "Notice", key = "notice.tapeViewed", vars = { tape = labelText(tapeId) } }
		)
	end
end

function Tapes.step()
	local now = serverNow()
	for _, deck in Tapes.decks do
		if deck.playing and deck.tape then
			local def = TapeContent.Defs[deck.tape]
			if not def.loop and now - deck.startedAt >= TapeContent.duration(def) then
				deck.playing = false
				deck.finished = true
				markViewed(deck, deck.tape)
				syncFacts()
				publishDecks()
			end
		end
	end
end

-- Elapsed seconds on a deck's tape (for events that hook into playback).
function Tapes.elapsed(deckId: string): number
	local deck = Tapes.decks[deckId]
	return if deck and deck.playing then serverNow() - deck.startedAt else 0
end

function Tapes.reset()
	for _, model in models do
		model:Destroy()
	end
	table.clear(models)
	for _, deck in Tapes.decks do
		deck.tape = nil
		deck.playing = false
		deck.startedAt = 0
		deck.ejected = nil
		deck.finished = false
	end
	for _, member in State.crew do
		table.clear(member.tapes)
		member.hasKey = false
	end
	table.clear(Tapes.location)
	table.clear(Tapes.assignment)
	syncFacts()
	publishDecks()
end

return Tapes
