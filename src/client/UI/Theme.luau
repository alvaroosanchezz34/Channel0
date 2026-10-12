--!strict
--[[
	Visual language of the interface: 1998 broadcast equipment. Phosphor amber and green text on
	near-black panels, monospaced type, hard edges. Everything diegetic-looking; nothing glossy.
]]

local Theme = {}

Theme.Colors = {
	Panel = Color3.fromRGB(14, 14, 12),
	PanelLight = Color3.fromRGB(28, 27, 24),
	Edge = Color3.fromRGB(70, 66, 56),
	Amber = Color3.fromRGB(255, 176, 64),
	AmberDim = Color3.fromRGB(150, 100, 40),
	Green = Color3.fromRGB(120, 255, 140),
	Red = Color3.fromRGB(235, 60, 50),
	Text = Color3.fromRGB(232, 226, 210),
	TextDim = Color3.fromRGB(150, 145, 130),
	Black = Color3.fromRGB(0, 0, 0),
	White = Color3.fromRGB(255, 255, 255),
	Blue = Color3.fromRGB(30, 50, 170),
}

Theme.Font = Enum.Font.Code
Theme.FontTitle = Enum.Font.Arcade
Theme.FontBody = Enum.Font.SourceSans

Theme.SubtitleSizes = { small = 18, medium = 22, large = 28 }

-- SMPTE colour bars (top row), used by every "Bars" screen.
Theme.Bars = {
	Color3.fromRGB(192, 192, 192),
	Color3.fromRGB(192, 192, 0),
	Color3.fromRGB(0, 192, 192),
	Color3.fromRGB(0, 192, 0),
	Color3.fromRGB(192, 0, 192),
	Color3.fromRGB(192, 0, 0),
	Color3.fromRGB(0, 0, 192),
}

return Theme
