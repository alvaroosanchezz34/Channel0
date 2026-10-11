--!strict
--[[
	VHS tapes. A tape is a timeline of shots (what the screen shows) and lines (subtitled audio).
	Text lives in Strings under the keys referenced here. `{digit}` style tokens are filled by the
	server from the session seed (clue pieces) or session facts (player count).

	Shot kinds:
		Bars      SMPTE colour bars + tone
		Card      full-screen title card (style: StationID | Date | Document | Clue | Time)
		Scene     a small 3D set rendered in a ViewportFrame (scene id from Content/Scenes)
		Static    snow
		Black     nothing (a deliberate silence)
]]

export type Shot = {
	kind: "Bars" | "Card" | "Scene" | "Static" | "Black",
	duration: number,
	titleKey: string?,
	bodyKey: string?,
	style: string?,
	scene: string?,
	anchor: string?, -- Anchor pose in the scene: "Composed" | "Stare" | "Absent"
	lowerThirdKey: string?,
	timestamp: string?, -- burned-in time code shown on the shot
}

export type Line = {
	at: number, -- seconds from tape start
	key: string,
	speaker: string,
	duration: number?,
}

export type TapeDef = {
	id: string,
	labelKey: string,
	kind: "Maintenance" | "Filler" | "Clue" | "Master" | "Contract" | "Lore",
	shots: { Shot },
	lines: { Line },
	loop: boolean?,
	-- Fact set when the tape has been played to the end on any deck.
	viewedFact: string?,
	-- Candidate slot ids (map markers). Fixed tapes list one.
	slots: { string },
	spawnPhase: string, -- tape appears in the world from this phase on
	cluePiece: number?,
}

local Tapes = {}

Tapes.Defs = {
	Orientation = {
		id = "Orientation",
		labelKey = "tape.Orientation.label",
		kind = "Maintenance",
		viewedFact = "orientationViewed",
		slots = { "Slot_LobbyDesk" },
		spawnPhase = "Arrival",
		shots = {
			{ kind = "Bars", duration = 3 },
			{ kind = "Card", duration = 3, style = "StationID", titleKey = "tape.Orientation.card" },
			{ kind = "Scene", duration = 44, scene = "MasterControlDay", anchor = "Absent", lowerThirdKey = "tape.Orientation.lower", timestamp = "06/14/96 14:02" },
			{ kind = "Black", duration = 2 },
		},
		lines = {
			{ at = 6.5, key = "tape.Orientation.l1", speaker = "Marsh" },
			{ at = 11.5, key = "tape.Orientation.l2", speaker = "Marsh" },
			{ at = 17, key = "tape.Orientation.l3", speaker = "Marsh" },
			{ at = 22.5, key = "tape.Orientation.l4", speaker = "Marsh" },
			{ at = 27.5, key = "tape.Orientation.l5", speaker = "Marsh" },
			{ at = 32.5, key = "tape.Orientation.l6", speaker = "Marsh" },
			{ at = 38.5, key = "tape.Orientation.l7", speaker = "Marsh" },
			{ at = 45, key = "tape.Orientation.l8", speaker = "Marsh" },
		},
	},
	Filler = {
		id = "Filler",
		labelKey = "tape.Filler.label",
		kind = "Filler",
		loop = true,
		slots = { "Slot_ArchiveFiller" },
		spawnPhase = "Arrival",
		shots = {
			{ kind = "Bars", duration = 18 },
			{ kind = "Card", duration = 7, style = "StationID", titleKey = "tape.Filler.card" },
			{ kind = "Bars", duration = 14 },
			-- One frame that should not be on a filler tape. Nobody is meant to notice the first time.
			{ kind = "Scene", duration = 0.4, scene = "MasterControlNight", anchor = "Stare" },
			{ kind = "Bars", duration = 12 },
		},
		lines = {},
	},
	Hale1984 = {
		id = "Hale1984",
		labelKey = "tape.Hale1984.label",
		kind = "Clue",
		cluePiece = 1,
		viewedFact = "hale1Viewed",
		slots = { "Slot_Archive_A", "Slot_Archive_B", "Slot_Editing_Shelf", "Slot_Office_Desk", "Slot_Security_Desk", "Slot_Lockers_Bench", "Slot_Workshop_Bench", "Slot_MCR_Rack" },
		spawnPhase = "Anomaly",
		shots = {
			{ kind = "Card", duration = 3, style = "Date", titleKey = "tape.Hale1984.card" },
			{ kind = "Scene", duration = 30, scene = "StudioADesk", anchor = "Composed", lowerThirdKey = "tape.lower.hale", timestamp = "03/09/84 02:04" },
			{ kind = "Card", duration = 6, style = "Clue", titleKey = "tape.Hale1984.clue" },
			{ kind = "Scene", duration = 4, scene = "StudioADesk", anchor = "Composed", timestamp = "03/09/84 02:05" },
			{ kind = "Static", duration = 1.5 },
		},
		lines = {
			{ at = 3.5, key = "tape.Hale1984.l1", speaker = "Hale" },
			{ at = 8.5, key = "tape.Hale1984.l2", speaker = "Hale" },
			{ at = 14, key = "tape.Hale1984.l3", speaker = "Hale" },
			{ at = 21, key = "tape.Hale1984.l4", speaker = "Hale" },
			{ at = 27, key = "tape.Hale1984.l5", speaker = "Hale" },
			{ at = 34, key = "tape.Hale1984.l6", speaker = "Hale" },
			{ at = 40, key = "tape.Hale1984.l7", speaker = "Hale" },
		},
	},
	Calloway1986 = {
		id = "Calloway1986",
		labelKey = "tape.Calloway1986.label",
		kind = "Clue",
		cluePiece = 2,
		viewedFact = "hale2Viewed",
		slots = { "Slot_Archive_A", "Slot_Archive_B", "Slot_Editing_Shelf", "Slot_Office_Desk", "Slot_Security_Desk", "Slot_Lockers_Bench", "Slot_Workshop_Bench", "Slot_MCR_Rack" },
		spawnPhase = "Anomaly",
		shots = {
			{ kind = "Card", duration = 2.5, style = "Date", titleKey = "tape.Calloway1986.card" },
			{ kind = "Scene", duration = 30, scene = "StudioADesk", anchor = "Absent", timestamp = "11/02/86 23:51" },
			{ kind = "Card", duration = 6, style = "Clue", titleKey = "tape.Calloway1986.clue" },
			{ kind = "Scene", duration = 6, scene = "StudioADesk", anchor = "Absent", timestamp = "11/02/86 23:53" },
			{ kind = "Black", duration = 1 },
		},
		lines = {
			{ at = 3, key = "tape.Calloway1986.l1", speaker = "Calloway" },
			{ at = 8, key = "tape.Calloway1986.l2", speaker = "Calloway" },
			{ at = 14, key = "tape.Calloway1986.l3", speaker = "Calloway" },
			{ at = 20, key = "tape.Calloway1986.l4", speaker = "Calloway" },
			{ at = 26, key = "tape.Calloway1986.l5", speaker = "Calloway" },
			{ at = 33, key = "tape.Calloway1986.l6", speaker = "Calloway" },
			{ at = 39.5, key = "tape.Calloway1986.l7", speaker = "Calloway" },
		},
	},
	Hale1987 = {
		id = "Hale1987",
		labelKey = "tape.Hale1987.label",
		kind = "Clue",
		cluePiece = 3,
		viewedFact = "hale3Viewed",
		slots = { "Slot_Archive_Restricted", "Slot_Archive_B", "Slot_Editing_Shelf", "Slot_Office_Desk", "Slot_Security_Desk", "Slot_Workshop_Bench" },
		spawnPhase = "Anomaly",
		shots = {
			{ kind = "Card", duration = 3, style = "Date", titleKey = "tape.Hale1987.card" },
			{ kind = "Scene", duration = 16, scene = "StudioADesk", anchor = "Composed", lowerThirdKey = "tape.lower.hale", timestamp = "10/17/87 02:16" },
			{ kind = "Scene", duration = 12, scene = "StudioADesk", anchor = "Stare", lowerThirdKey = "tape.Hale1987.chyron", timestamp = "10/17/87 02:17" },
			{ kind = "Scene", duration = 5, scene = "StudioADesk", anchor = "Stare", timestamp = "10/17/87 02:17" },
			{ kind = "Static", duration = 2 },
			{ kind = "Card", duration = 4, style = "Time", titleKey = "tape.Hale1987.end" },
		},
		lines = {
			{ at = 3.5, key = "tape.Hale1987.l1", speaker = "Hale" },
			{ at = 9, key = "tape.Hale1987.l2", speaker = "Hale" },
			{ at = 15, key = "tape.Hale1987.l3", speaker = "Hale" },
			{ at = 19.5, key = "tape.Hale1987.l4", speaker = "Caption", duration = 7 },
			{ at = 31.5, key = "tape.Hale1987.l5", speaker = "Calloway" },
		},
	},
	Master1987 = {
		id = "Master1987",
		labelKey = "tape.Master1987.label",
		kind = "Master",
		viewedFact = "masterPreviewed",
		slots = { "Slot_StudioB_Desk" },
		spawnPhase = "Escalation",
		shots = {
			{ kind = "Scene", duration = 20, scene = "StudioBMemory", anchor = "Composed", timestamp = "10/17/87 02:17" },
			{ kind = "Black", duration = 2 },
		},
		lines = {
			{ at = 2, key = "tape.Master1987.l1", speaker = "Caption", duration = 8 },
			{ at = 12, key = "tape.Master1987.l2", speaker = "Hale" },
		},
	},
	Contract1961 = {
		id = "Contract1961",
		labelKey = "tape.Contract1961.label",
		kind = "Contract",
		viewedFact = "contractViewed",
		slots = { "Slot_StudioA_Drawer" },
		spawnPhase = "Escalation",
		shots = {
			{ kind = "Card", duration = 5, style = "Document", titleKey = "tape.Contract1961.card" },
			{ kind = "Card", duration = 26, style = "Document", titleKey = "tape.Contract1961.card", bodyKey = "tape.Contract1961.body" },
			{ kind = "Black", duration = 2 },
		},
		lines = {
			{ at = 5, key = "tape.Contract1961.l1", speaker = "Halvorsen" },
			{ at = 11, key = "tape.Contract1961.l2", speaker = "Halvorsen" },
			{ at = 16, key = "tape.Contract1961.l3", speaker = "Halvorsen" },
			{ at = 22, key = "tape.Contract1961.l4", speaker = "Halvorsen" },
			{ at = 28, key = "tape.Contract1961.l5", speaker = "Halvorsen" },
		},
	},
	Party1986 = {
		id = "Party1986",
		labelKey = "tape.Party1986.label",
		kind = "Lore",
		viewedFact = "loreParty",
		slots = { "Slot_Archive_A", "Slot_Archive_B", "Slot_Editing_Shelf", "Slot_Office_Desk", "Slot_Lockers_Bench", "Slot_MCR_Rack" },
		spawnPhase = "Maintenance",
		shots = {
			{ kind = "Scene", duration = 26, scene = "LobbyParty", anchor = "Absent", timestamp = "12/19/86 21:40" },
			{ kind = "Scene", duration = 5, scene = "StudioADesk", anchor = "Composed", timestamp = "12/19/86 21:41" },
			{ kind = "Static", duration = 1 },
		},
		lines = {
			{ at = 1, key = "tape.Party1986.l1", speaker = "Okafor" },
			{ at = 5, key = "tape.Party1986.l2", speaker = "Seidel" },
			{ at = 9, key = "tape.Party1986.l3", speaker = "Calloway" },
			{ at = 14, key = "tape.Party1986.l4", speaker = "Okafor" },
			{ at = 19, key = "tape.Party1986.l5", speaker = "Calloway" },
			{ at = 26.5, key = "tape.Party1986.l6", speaker = "Caption", duration = 5 },
		},
	},
	Guard1991 = {
		id = "Guard1991",
		labelKey = "tape.Guard1991.label",
		kind = "Lore",
		viewedFact = "loreGuard",
		slots = { "Slot_Archive_A", "Slot_Archive_B", "Slot_Security_Desk", "Slot_Office_Desk", "Slot_Workshop_Bench" },
		spawnPhase = "Maintenance",
		shots = {
			{ kind = "Scene", duration = 28, scene = "HallwaySecurity", anchor = "Absent", timestamp = "04/02/91 03:10" },
			{ kind = "Scene", duration = 8, scene = "HallwaySecurity", anchor = "Absent", timestamp = "04/02/91 03:21" },
			{ kind = "Static", duration = 1.5 },
		},
		lines = {
			{ at = 1.5, key = "tape.Guard1991.l1", speaker = "Guard" },
			{ at = 8, key = "tape.Guard1991.l2", speaker = "Guard" },
			{ at = 15, key = "tape.Guard1991.l3", speaker = "Guard" },
			{ at = 22, key = "tape.Guard1991.l4", speaker = "Guard" },
			{ at = 28.5, key = "tape.Guard1991.l5", speaker = "Caption", duration = 7 },
		},
	},
	Weather1979 = {
		id = "Weather1979",
		labelKey = "tape.Weather1979.label",
		kind = "Lore",
		viewedFact = "loreWeather",
		slots = { "Slot_Archive_A", "Slot_Archive_B", "Slot_Editing_Shelf", "Slot_Lockers_Bench", "Slot_MCR_Rack" },
		spawnPhase = "Maintenance",
		shots = {
			{ kind = "Card", duration = 3, style = "Date", titleKey = "tape.Weather1979.card" },
			{ kind = "Scene", duration = 22, scene = "StudioADesk", anchor = "Composed", lowerThirdKey = "tape.lower.hale", timestamp = "09/03/79 23:58" },
			{ kind = "Bars", duration = 3 },
		},
		lines = {
			{ at = 3.5, key = "tape.Weather1979.l1", speaker = "Hale" },
			{ at = 9, key = "tape.Weather1979.l2", speaker = "Hale" },
			{ at = 15, key = "tape.Weather1979.l3", speaker = "Hale" },
			{ at = 21, key = "tape.Weather1979.l4", speaker = "Hale" },
		},
	},
} :: { [string]: TapeDef }

-- Number of optional lore tapes placed per session (picked by seed).
Tapes.LoreCount = 2
Tapes.ClueTapes = { "Hale1984", "Calloway1986", "Hale1987" }
Tapes.LoreTapes = { "Party1986", "Guard1991", "Weather1979" }

-- Candidate values for the lost (zero channel) frequency. Each is split into three clue pieces:
-- tens digit, units digit, and the two decimals.
Tapes.LostFrequencies = { 61.15, 64.85, 69.35, 76.05, 79.45, 83.65, 86.25, 93.45, 96.85 }

function Tapes.duration(def: TapeDef): number
	local total = 0
	for _, shot in def.shots do
		total += shot.duration
	end
	return total
end

-- Returns the shot active at `t` seconds and its start time.
function Tapes.shotAt(def: TapeDef, t: number): (Shot?, number)
	local length = Tapes.duration(def)
	if def.loop and length > 0 then
		t = t % length
	end
	local cursor = 0
	for _, shot in def.shots do
		if t < cursor + shot.duration then
			return shot, cursor
		end
		cursor += shot.duration
	end
	return nil, cursor
end

-- Splits a frequency like 69.35 into { "6", "9", "35" }.
function Tapes.cluePieces(frequency: number): { string }
	local text = string.format("%05.2f", frequency)
	return { string.sub(text, 1, 1), string.sub(text, 2, 2), string.sub(text, 4, 5) }
end

return Tapes
