--!strict
--[[
	Late-bound service lookup. Services call each other through this table at runtime (after
	Main has required and initialised all of them), which avoids require cycles between
	services that legitimately depend on each other (e.g. Anchor <-> Crew).
]]

local Registry = {} :: { [string]: any }

return Registry
