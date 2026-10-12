--!strict
--[[
	CHANNEL 0 client entry point. The Store goes first (every other controller reads it), then
	the rest start independently: one controller failing or waiting on the map never blocks the
	others, and errors are reported with the controller's name.
]]

local Controllers = script.Parent:WaitForChild("Controllers")

local Store = require(Controllers:WaitForChild("Store")) :: any
Store.init()

local ORDER = {
	"VHS",
	"Audio",
	"HUD",
	"Player",
	"Prompts",
	"Devices",
	"Menu",
	"Monitors",
	"StationFX",
	"Debug",
}

for _, name in ORDER do
	local module = require(Controllers:WaitForChild(name)) :: any
	task.spawn(function()
		local ok, err = pcall(module.init)
		if not ok then
			warn("[Channel0] client controller " .. name .. " failed to start: " .. tostring(err))
		end
	end)
end
