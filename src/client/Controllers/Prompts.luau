--!strict
--[[
	Custom ProximityPrompt presentation: a small amber label tag in the world, localised from the
	prompt's PromptKey attribute, showing the key/button for the current input device. On touch
	devices the tag itself is the button.
]]

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")

local Make = require(script.Parent.Parent.UI.Make)
local Store = require(script.Parent.Store)
local Theme = require(script.Parent.Parent.UI.Theme)

local Prompts = {}

local shown: { [ProximityPrompt]: BillboardGui } = {}

local function keyLabel(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType): string
	if inputType == Enum.ProximityPromptInputType.Touch then
		return "TAP"
	elseif inputType == Enum.ProximityPromptInputType.Gamepad then
		return string.gsub(prompt.GamepadKeyCode.Name, "Button", "")
	end
	return prompt.KeyboardKeyCode.Name
end

local function textFor(prompt: ProximityPrompt): string
	local key = prompt:GetAttribute("PromptKey")
	if type(key) == "string" then
		local text = Store.t(key)
		local tape = prompt:GetAttribute("TapeId")
		if tape and prompt.ObjectText ~= "" then
			text ..= "  ·  " .. prompt.ObjectText
		end
		return text
	end
	return prompt.ActionText
end

local function show(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType)
	if prompt.Style ~= Enum.ProximityPromptStyle.Custom or shown[prompt] then
		return
	end
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local billboard = Make.new("BillboardGui", {
		Name = "CH0Prompt",
		Adornee = prompt.Parent,
		AlwaysOnTop = true,
		Size = UDim2.fromOffset(260, 44),
		StudsOffset = Vector3.new(0, 1.2, 0),
		LightInfluence = 0,
		Active = true,
		Parent = playerGui,
	})
	local touch = inputType == Enum.ProximityPromptInputType.Touch
	local frame = Make.new(if touch then "TextButton" else "Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Colors.Panel,
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		Parent = billboard,
	}, { Make.stroke(Theme.Colors.AmberDim, 1), Make.corner(2) })
	if touch then
		(frame :: TextButton).Text = ""
		local button = frame :: TextButton
		button.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch then
				prompt:InputHoldBegin()
			end
		end)
		button.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch then
				prompt:InputHoldEnd()
			end
		end)
	end
	Make.text({
		Text = keyLabel(prompt, inputType),
		Size = UDim2.new(0, 46, 1, -10),
		Position = UDim2.fromOffset(5, 5),
		TextXAlignment = Enum.TextXAlignment.Center,
		BackgroundColor3 = Theme.Colors.Amber,
		BackgroundTransparency = 0,
		TextColor3 = Theme.Colors.Panel,
		TextScaled = true,
		Parent = frame,
	})
	local label = Make.text({
		Name = "Action",
		Text = textFor(prompt),
		Size = UDim2.new(1, -62, 1, -6),
		Position = UDim2.fromOffset(58, 3),
		TextColor3 = Theme.Colors.Amber,
		TextScaled = true,
		Parent = frame,
	})
	prompt:GetAttributeChangedSignal("PromptKey"):Connect(function()
		label.Text = textFor(prompt)
	end)
	shown[prompt] = billboard
end

local function hide(prompt: ProximityPrompt)
	local billboard = shown[prompt]
	if billboard then
		billboard:Destroy()
		shown[prompt] = nil
	end
end

function Prompts.init()
	ProximityPromptService.PromptShown:Connect(show)
	ProximityPromptService.PromptHidden:Connect(hide)
end

return Prompts
