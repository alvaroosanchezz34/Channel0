--!strict
--[[
	In-shift HUD: current tasks, signal strip (quality, ON AIR / DEAD AIR, slate), notices,
	subtitles (spoken lines, radio through static, captions), carried tapes and the carrier key,
	stamina, and touch buttons for flashlight / sprint on mobile. Deliberately sparse: the VHS
	layer and the world do most of the talking.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Make = require(script.Parent.Parent.UI.Make)
local Net = require(script.Parent.Net)
local Store = require(script.Parent.Store)
local Theme = require(script.Parent.Parent.UI.Theme)

local HUD = {}

local gui: ScreenGui
local root: Frame
local objectivesFrame: Frame
local objectiveList: Frame
local signalBar: Frame
local signalLabel: TextLabel
local airLabel: TextLabel
local noticeLabel: TextLabel
local phaseLabel: TextLabel
local subtitleFrame: Frame
local inventoryLabel: TextLabel
local staminaBar: Frame
local staminaFrame: Frame
local touchFrame: Frame
local noticeUntil = 0
local phaseUntil = 0

type Subtitle = { label: TextLabel, untilTime: number }
local subtitles: { Subtitle } = {}
local rng = Random.new()

HUD.onFlashlight = nil :: (() -> ())?
HUD.onSprint = nil :: ((boolean) -> ())?

local function scramble(text: string, clarity: number): string
	if clarity >= 0.95 then
		return text
	end
	local out = {}
	for _, code in utf8.codes(text) do
		local ch = utf8.char(code)
		if ch ~= " " and rng:NextNumber() > clarity then
			table.insert(out, if rng:NextNumber() < 0.5 then "·" else "-")
		else
			table.insert(out, ch)
		end
	end
	return table.concat(out)
end

function HUD.subtitle(text: string, speaker: string?, duration: number?, color: Color3?)
	if not Store.settings.subtitles and speaker ~= "Caption" then
		-- Spoken lines are optional; captions describing sounds stay (they carry information).
		return
	end
	local size = Theme.SubtitleSizes[Store.settings.subtitleSize] or 22
	local who: string = speaker or ""
	local name = if who ~= "" and who ~= "Caption" then Store.t("speaker." .. who) else ""
	local label = Make.text({
		Text = if name ~= "" then name .. ":  " .. text else text,
		Size = UDim2.new(1, 0, 0, size * 2.3),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextSize = size,
		Font = Theme.FontBody,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = color or (if speaker == "Caption" then Theme.Colors.TextDim else Theme.Colors.Text),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		LayoutOrder = math.floor(os.clock() * 10),
		Parent = subtitleFrame,
	})
	table.insert(subtitles, { label = label, untilTime = os.clock() + (duration or 5) })
	while #subtitles > 3 do
		local oldest = table.remove(subtitles, 1)
		if oldest then
			oldest.label:Destroy()
		end
	end
end

function HUD.notice(text: string, style: string?)
	noticeLabel.Text = text
	noticeLabel.TextColor3 = if style == "Alert"
		then Theme.Colors.Red
		elseif style == "Fault" then Theme.Colors.Amber
		else Theme.Colors.Text
	noticeUntil = os.clock() + 4.5
end

local function renderObjectives()
	for _, child in objectiveList:GetChildren() do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	local list = Store.objectives.list or {}
	local order = 0
	for _, entry in list do
		if not entry.condition or Net.state(Net.Attr.Phase) ~= "Arrival" then
			order += 1
			local text = Store.t(entry.textKey, { progress = entry.progress, goal = entry.goal })
			-- Texts that already show "{progress}/{goal}" get no second counter.
			local inline = string.find(Store.t(entry.textKey), "{progress}", 1, true) ~= nil
			if entry.goal and entry.goal > 1 and not inline then
				text ..= string.format("  %d/%d", entry.progress, entry.goal)
			end
			local prefix = if entry.done then "■ " elseif entry.condition then "◆ " else "□ "
			Make.text({
				Text = prefix .. text .. (if entry.optional and not entry.condition then "  (opt.)" else ""),
				TextColor3 = if entry.done then Theme.Colors.TextDim else Theme.Colors.Amber,
				AutomaticSize = Enum.AutomaticSize.Y,
				TextSize = 17,
				LayoutOrder = order,
				Parent = objectiveList,
			})
			if not entry.done and entry.hintKey and not entry.condition then
				order += 1
				Make.text({
					Text = "   " .. Store.t(entry.hintKey),
					TextColor3 = Theme.Colors.TextDim,
					AutomaticSize = Enum.AutomaticSize.Y,
					TextSize = 14,
					Font = Theme.FontBody,
					LayoutOrder = order,
					Parent = objectiveList,
				})
			end
			for _, hint in entry.extraHints or {} do
				order += 1
				Make.text({
					Text = "   › " .. Store.t(hint),
					TextColor3 = Theme.Colors.Green,
					AutomaticSize = Enum.AutomaticSize.Y,
					TextSize = 14,
					Font = Theme.FontBody,
					LayoutOrder = order,
					Parent = objectiveList,
				})
			end
		end
	end
end

local function renderInventory()
	local inv = Store.inventory
	local parts = {}
	for _, tape in inv.tapes or {} do
		table.insert(parts, Store.t("tape." .. tape .. ".label"))
	end
	local text = Store.t("ui.tapes")
		.. ": "
		.. (if #parts > 0 then table.concat(parts, "  |  ") else Store.t("ui.noTapes"))
	if inv.key then
		text ..= "    ⚿ CARRIER KEY"
	end
	inventoryLabel.Text = text
end

local function build()
	gui = Make.screen("HUD", 10, Players.LocalPlayer:WaitForChild("PlayerGui"))
	root =
		Make.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, Parent = gui })

	objectivesFrame = Make.new("Frame", {
		Size = UDim2.new(0, 340, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Position = UDim2.new(1, -24, 0, 70),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundColor3 = Theme.Colors.Panel,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		Parent = root,
	}, { Make.padding(10), Make.list(Enum.FillDirection.Vertical, 4) })
	Make.text({
		Text = "",
		Name = "Title",
		TextColor3 = Theme.Colors.TextDim,
		TextSize = 14,
		LayoutOrder = 0,
		Parent = objectivesFrame,
	})
	objectiveList = Make.new("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		Parent = objectivesFrame,
	}, { Make.list(Enum.FillDirection.Vertical, 2) })

	local signalFrame = Make.new("Frame", {
		Size = UDim2.fromOffset(260, 54),
		Position = UDim2.fromOffset(30, 62),
		BackgroundTransparency = 1,
		Parent = root,
	})
	signalLabel = Make.text({
		Text = "SIGNAL",
		Size = UDim2.new(1, 0, 0, 18),
		TextSize = 15,
		TextColor3 = Theme.Colors.TextDim,
		Parent = signalFrame,
	})
	local track = Make.new("Frame", {
		Size = UDim2.new(1, 0, 0, 8),
		Position = UDim2.fromOffset(0, 22),
		BackgroundColor3 = Theme.Colors.PanelLight,
		BorderSizePixel = 0,
		Parent = signalFrame,
	})
	signalBar = Make.new(
		"Frame",
		{ Size = UDim2.fromScale(0, 1), BackgroundColor3 = Theme.Colors.Green, BorderSizePixel = 0, Parent = track }
	)
	airLabel = Make.text({
		Text = "",
		Size = UDim2.new(1, 0, 0, 20),
		Position = UDim2.fromOffset(0, 34),
		TextSize = 17,
		Parent = signalFrame,
	})

	phaseLabel = Make.text({
		Text = "",
		Size = UDim2.new(1, 0, 0, 60),
		Position = UDim2.fromScale(0, 0.28),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = 44,
		Font = Theme.FontTitle,
		TextColor3 = Theme.Colors.Text,
		TextStrokeTransparency = 0.5,
		TextTransparency = 1,
		Parent = root,
	})
	noticeLabel = Make.text({
		Text = "",
		Size = UDim2.new(0.6, 0, 0, 30),
		Position = UDim2.fromScale(0.2, 0.14),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = 22,
		TextStrokeTransparency = 0.5,
		Parent = root,
	})

	inventoryLabel = Make.text({
		Text = "",
		Size = UDim2.new(0, 520, 0, 22),
		Position = UDim2.new(1, -24, 1, -70),
		AnchorPoint = Vector2.new(1, 1),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextSize = 16,
		TextColor3 = Theme.Colors.TextDim,
		Parent = root,
	})
	staminaFrame = Make.new("Frame", {
		Size = UDim2.fromOffset(160, 4),
		Position = UDim2.new(0.5, 0, 1, -52),
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundColor3 = Theme.Colors.PanelLight,
		BorderSizePixel = 0,
		Parent = root,
	})
	staminaBar = Make.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Colors.TextDim,
		BorderSizePixel = 0,
		Parent = staminaFrame,
	})

	-- Subtitles live in their own top-most layer so the VHS filter never makes them unreadable.
	local subGui = Make.screen("Subtitles", 40, Players.LocalPlayer:WaitForChild("PlayerGui"))
	subtitleFrame = Make.new("Frame", {
		Size = UDim2.new(0.7, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Position = UDim2.new(0.15, 0, 1, -96),
		AnchorPoint = Vector2.new(0, 1),
		BackgroundTransparency = 1,
		Parent = subGui,
	}, { Make.list(Enum.FillDirection.Vertical, 4, Enum.HorizontalAlignment.Center) })

	touchFrame = Make.new("Frame", {
		Size = UDim2.fromOffset(200, 90),
		Position = UDim2.new(1, -20, 1, -170),
		AnchorPoint = Vector2.new(1, 1),
		BackgroundTransparency = 1,
		Visible = UserInputService.TouchEnabled,
		Parent = root,
	}, { Make.list(Enum.FillDirection.Horizontal, 10) })
	Make.button({ Text = Store.t("ui.flashlight"), Size = UDim2.fromOffset(90, 80), Parent = touchFrame }, function()
		if HUD.onFlashlight then
			(HUD.onFlashlight :: () -> ())()
		end
	end)
	local sprint = Make.button(
		{ Text = Store.t("ui.sprint"), Size = UDim2.fromOffset(90, 80), Parent = touchFrame },
		function() end
	)
	sprint.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch and HUD.onSprint then
			(HUD.onSprint :: (boolean) -> ())(true)
		end
	end)
	sprint.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch and HUD.onSprint then
			(HUD.onSprint :: (boolean) -> ())(false)
		end
	end)
end

local function onCue(cue: { [string]: any })
	local kind = cue.kind
	if kind == "Subtitle" and type(cue.key) == "string" then
		HUD.subtitle(Store.t(cue.key, cue.vars), cue.speaker, cue.duration)
	elseif kind == "Notice" and type(cue.key) == "string" then
		HUD.notice(Store.t(cue.key, cue.vars), cue.style)
	elseif kind == "PhaseNotice" and type(cue.key) == "string" then
		phaseLabel.Text = Store.t(cue.key)
		phaseUntil = os.clock() + 4
	elseif kind == "Radio" and type(cue.key) == "string" then
		local clarity = math.clamp(tonumber(cue.clarity) or 0, 0, 1)
		local text = if cue.station == "Static"
			then "[static]"
			else scramble(Store.t(cue.key, cue.vars), 0.25 + clarity * 0.75)
		local station = if cue.station
				and cue.station ~= "Static"
				and cue.station ~= "Taken"
			then Store.t("freq." .. cue.station .. ".name")
			else "RADIO"
		HUD.subtitle("((" .. station .. ")) " .. text, "Caption", 5, Theme.Colors.Green)
	end
end

local function update()
	local running = Net.state(Net.Attr.Session) == "Running" and Store.taken == nil
	root.Visible = running
	if not running then
		return
	end
	local now = os.clock()
	local signal = Store.signal
	local q = (signal.quality or 0) / 100
	signalBar.Size = UDim2.fromScale(q, 1)
	signalBar.BackgroundColor3 = if q < 0.25
		then Theme.Colors.Red
		elseif q < 0.55 then Theme.Colors.Amber
		else Theme.Colors.Green
	signalLabel.Text =
		string.format("%s  %03d   %06.2f MHz", Store.t("ui.signal"), signal.quality or 0, signal.frequency or 0)
	if signal.deadAir then
		airLabel.Text =
			string.format("● %s  %d", Store.t("ui.deadAir"), math.max(0, 16 - math.floor(signal.deadAirTimer or 0)))
		airLabel.TextColor3 = if math.floor(now * 2) % 2 == 0 then Theme.Colors.Red else Theme.Colors.TextDim
	elseif signal.onAir == "Slate" then
		airLabel.Text = "■ " .. Store.t("sub.slate")
		airLabel.TextColor3 = Theme.Colors.Amber
	elseif (signal.quality or 0) > 22 then
		airLabel.Text = "● " .. Store.t("ui.onAir") .. "  " .. Store.t("dev.switcher." .. (signal.onAir or "Bars"))
		airLabel.TextColor3 = Theme.Colors.Red
	else
		airLabel.Text = ""
	end
	noticeLabel.TextTransparency = if now < noticeUntil then 0 else math.min(1, (now - noticeUntil) * 2)
	phaseLabel.TextTransparency = if now < phaseUntil then 0 else math.min(1, (now - phaseUntil))
	local title = objectivesFrame:FindFirstChild("Title") :: TextLabel?
	if title then
		title.Text = Store.t("ui.objective") .. (if Net.state(Net.Attr.Stalled) then "   ◷" else "")
	end
	for i = #subtitles, 1, -1 do
		if now >= subtitles[i].untilTime then
			subtitles[i].label:Destroy()
			table.remove(subtitles, i)
		end
	end
	local character = Players.LocalPlayer.Character
	local stamina = character and character:GetAttribute("Stamina")
	if type(stamina) == "number" then
		staminaBar.Size = UDim2.fromScale(stamina, 1)
		staminaFrame.Visible = stamina < 0.99
	end
end

function HUD.init()
	build()
	Store.Changed:Connect(function(kind, payload)
		if kind == "objectives" then
			renderObjectives()
		elseif kind == "inventory" then
			renderInventory()
		elseif kind == "settings" then
			renderObjectives()
			renderInventory()
		elseif kind == "cue" then
			onCue(payload)
		elseif kind == "device" and payload.op == "message" then
			HUD.subtitle(Store.t(payload.key, payload.vars), "Caption", 5, Theme.Colors.Amber)
		end
	end)
	renderInventory()
	RunService.Heartbeat:Connect(update)
end

return HUD
