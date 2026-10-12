--!strict
--[[
	Tiny declarative helper for building instances: Make("Frame", { props }, { children }).
	Keeps UI code readable without pulling in a framework.
]]

local Theme = require(script.Parent.Theme)

local Make = {}

function Make.new(className: string, props: { [string]: any }?, children: { any }?): any
	local instance = Instance.new(className) :: any
	local parent = nil
	if props then
		for key, value in props do
			if key == "Parent" then
				parent = value
			else
				instance[key] = value
			end
		end
	end
	if children then
		for _, child in children do
			child.Parent = instance
		end
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

function Make.corner(radius: number): Instance
	return Make.new("UICorner", { CornerRadius = UDim.new(0, radius) })
end

function Make.stroke(color: Color3, thickness: number, transparency: number?): Instance
	return Make.new("UIStroke", { Color = color, Thickness = thickness, Transparency = transparency or 0 })
end

function Make.padding(px: number): Instance
	local d = UDim.new(0, px)
	return Make.new("UIPadding", { PaddingLeft = d, PaddingRight = d, PaddingTop = d, PaddingBottom = d })
end

function Make.list(direction: Enum.FillDirection, padding: number, align: Enum.HorizontalAlignment?): Instance
	return Make.new("UIListLayout", {
		FillDirection = direction,
		Padding = UDim.new(0, padding),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = align or Enum.HorizontalAlignment.Left,
	})
end

function Make.text(props: { [string]: any }): TextLabel
	local base = {
		BackgroundTransparency = 1,
		Font = Theme.Font,
		TextColor3 = Theme.Colors.Text,
		TextSize = 18,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 22),
	}
	for k, v in props do
		base[k] = v
	end
	return Make.new("TextLabel", base)
end

-- A hardware-style push button. `onActivate` fires on click/tap/gamepad.
function Make.button(props: { [string]: any }, onActivate: () -> ()): TextButton
	local base = {
		BackgroundColor3 = Theme.Colors.PanelLight,
		BorderSizePixel = 0,
		AutoButtonColor = true,
		Font = Theme.Font,
		TextColor3 = Theme.Colors.Amber,
		TextSize = 18,
		Size = UDim2.new(0, 160, 0, 40),
		TextWrapped = true,
	}
	for k, v in props do
		base[k] = v
	end
	local button = Make.new("TextButton", base, { Make.stroke(Theme.Colors.Edge, 1), Make.corner(3) })
	button.Activated:Connect(onActivate)
	return button
end

-- Full-screen-safe root ScreenGui.
function Make.screen(name: string, order: number, parent: Instance): ScreenGui
	return Make.new("ScreenGui", {
		Name = name,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = order,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = parent,
	})
end

function Make.bars(parent: Instance)
	local holder = Make.new(
		"Frame",
		{ Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, Parent = parent }
	)
	for i, color in Theme.Bars do
		Make.new("Frame", {
			Size = UDim2.new(1 / #Theme.Bars, 1, 0.68, 0),
			Position = UDim2.fromScale((i - 1) / #Theme.Bars, 0),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			Parent = holder,
		})
	end
	local bottom = {
		Color3.fromRGB(0, 33, 76),
		Color3.fromRGB(255, 255, 255),
		Color3.fromRGB(50, 0, 106),
		Color3.fromRGB(19, 19, 19),
		Color3.fromRGB(9, 9, 9),
		Color3.fromRGB(29, 29, 29),
	}
	for i, color in bottom do
		Make.new("Frame", {
			Size = UDim2.new(1 / #bottom, 1, 0.32, 0),
			Position = UDim2.fromScale((i - 1) / #bottom, 0.68),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			Parent = holder,
		})
	end
	return holder
end

return Make
