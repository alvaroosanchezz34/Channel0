--!strict
--[[
	Client side of the network contract (Shared/Net). Waits for the server's remotes, exposes
	`on(name, fn)` for server events and `send(name, ...)` for intents. The client never sends
	identities or results, only requests the server validates.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local NetContract = require(Shared.Net)

local Net = {}

local folder = ReplicatedStorage:WaitForChild(NetContract.FolderName)
local stateFolder = ReplicatedStorage:WaitForChild(NetContract.StateFolderName)

function Net.on(name: string, fn: (...any) -> ())
	local remote = folder:WaitForChild(name) :: RemoteEvent
	remote.OnClientEvent:Connect(function(...)
		local args = table.pack(...)
		local ok, err = pcall(function()
			fn(table.unpack(args, 1, args.n))
		end)
		if not ok then
			warn("[Channel0] client handler " .. name .. ": " .. tostring(err))
		end
	end)
end

function Net.send(name: string, ...: any)
	local remote = folder:FindFirstChild(name)
	if remote and remote:IsA("RemoteEvent") then
		remote:FireServer(...)
	end
end

function Net.hasRemote(name: string): boolean
	return folder:FindFirstChild(name) ~= nil
end

function Net.state(name: string): any
	return stateFolder:GetAttribute(name)
end

function Net.onState(name: string, fn: (value: any) -> ())
	stateFolder:GetAttributeChangedSignal(name):Connect(function()
		fn(stateFolder:GetAttribute(name))
	end)
end

Net.Attr = NetContract.Attr

return Net
