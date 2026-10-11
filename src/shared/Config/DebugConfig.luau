--!strict
--[[
	Developer tools are available only in Roblox Studio, or on live servers to UserIds listed
	here AND only when the experience owner enables `AllowOnLiveServers`. Authorization is always
	evaluated server-side from the Player object, never from client-sent data.
]]
local DebugConfig = {}

DebugConfig.AllowOnLiveServers = false
DebugConfig.AllowedUserIds = {} :: { number }
DebugConfig.ToggleKey = Enum.KeyCode.F8

return DebugConfig
