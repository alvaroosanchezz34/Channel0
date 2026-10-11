--!strict
-- RemoteEvent throttles: { capacity, refill per second } token buckets per player per channel.
local NetConfig = {}

NetConfig.Limits = {
	Ready = { 4, 0.5 },
	DeviceAction = { 12, 8 },
	DeviceClose = { 6, 2 },
	Flashlight = { 6, 3 },
	Sprint = { 10, 4 },
	Settings = { 3, 0.2 },
	Snapshot = { 3, 0.2 },
	Debug = { 20, 10 },
	Choice = { 4, 1 },
}

return NetConfig
