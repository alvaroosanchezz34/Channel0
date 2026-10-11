--!strict
--[[
	Trove: owns cleanup for a lifetime (a controller, an event, a session).
	Anything added is released exactly once when :Clean() runs, in reverse order.
	Supported: RBXScriptConnection, Instance, function, thread, objects with :Destroy() or :Disconnect().
]]

export type Trove = {
	Add: <T>(self: Trove, item: T) -> T,
	Connect: (self: Trove, signal: RBXScriptSignal, fn: (...any) -> ()) -> RBXScriptConnection,
	Extend: (self: Trove) -> Trove,
	Clean: (self: Trove) -> (),
	Destroy: (self: Trove) -> (),
	_items: { any },
	_cleaning: boolean,
}

local Trove = {}
Trove.__index = Trove

local function release(item: any)
	local kind = typeof(item)
	if kind == "RBXScriptConnection" then
		item:Disconnect()
	elseif kind == "Instance" then
		item:Destroy()
	elseif kind == "function" then
		item()
	elseif kind == "thread" then
		if coroutine.status(item) ~= "dead" then
			pcall(task.cancel, item)
		end
	elseif kind == "table" then
		if type(item.Destroy) == "function" then
			item:Destroy()
		elseif type(item.Disconnect) == "function" then
			item:Disconnect()
		end
	end
end

function Trove.new(): Trove
	local self = setmetatable({ _items = {}, _cleaning = false }, Trove)
	return (self :: any) :: Trove
end

function Trove.Add<T>(self: Trove, item: T): T
	if self._cleaning then
		-- Adding during cleanup would leak; release immediately instead.
		release(item)
		return item
	end
	table.insert(self._items, item)
	return item
end

function Trove.Connect(self: Trove, signal: RBXScriptSignal, fn: (...any) -> ()): RBXScriptConnection
	local connection = signal:Connect(fn)
	self:Add(connection)
	return connection
end

function Trove.Extend(self: Trove): Trove
	local child = Trove.new()
	self:Add(child)
	return child
end

function Trove.Clean(self: Trove)
	if self._cleaning then
		return
	end
	self._cleaning = true
	local items = self._items
	self._items = {}
	for index = #items, 1, -1 do
		local ok, err = pcall(release, items[index])
		if not ok then
			warn("[Trove] cleanup error:", err)
		end
	end
	self._cleaning = false
end

Trove.Destroy = Trove.Clean

return Trove
