--!strict
--[[
	CHANNEL 0 server entry point. Requires every service, registers it for late-bound lookup,
	then runs init() for all services before start() for any, so cross-service calls made during
	start() always find an initialised target.
]]

local Services = script.Parent:WaitForChild("Services")
local Registry = require(Services.Registry)

local ORDER = {
	"Remotes",
	"World",
	"State",
	"Data",
	"Lighting",
	"Doors",
	"Signal",
	"Tapes",
	"Radio",
	"Feeds",
	"Crew",
	"Phase",
	"Anchor",
	"Director",
	"Endings",
	"Devices",
	"Session",
	"Debug",
}

local modules = {}
for _, name in ORDER do
	local module = require(Services:WaitForChild(name)) :: any
	Registry[name] = module
	table.insert(modules, module)
end
for _, module in modules do
	if module.init then
		module.init()
	end
end
for _, module in modules do
	if module.start then
		module.start()
	end
end
