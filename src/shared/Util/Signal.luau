--!strict
--[[
	Minimal synchronous signal for module-to-module communication on the same machine.
	Handlers run in order of connection; a handler that errors does not stop the others.
]]

export type Connection = { Disconnect: (self: Connection) -> (), Connected: boolean }
export type Signal<T...> = {
	Connect: (self: Signal<T...>, fn: (T...) -> ()) -> Connection,
	Once: (self: Signal<T...>, fn: (T...) -> ()) -> Connection,
	Fire: (self: Signal<T...>, T...) -> (),
	DisconnectAll: (self: Signal<T...>) -> (),
	Destroy: (self: Signal<T...>) -> (),
}

local Signal = {}
Signal.__index = Signal

type Handler = { fn: (...any) -> (), connected: boolean }

function Signal.new<T...>(): Signal<T...>
	local self = setmetatable({ _handlers = {} :: { Handler } }, Signal)
	return (self :: any) :: Signal<T...>
end

function Signal:Connect(fn: (...any) -> ()): Connection
	local handler: Handler = { fn = fn, connected = true }
	table.insert(self._handlers, handler)
	local connection = {}
	connection.Connected = true
	function connection.Disconnect(conn: any)
		if not handler.connected then
			return
		end
		handler.connected = false
		conn.Connected = false
		local list = self._handlers
		local index = table.find(list, handler)
		if index then
			table.remove(list, index)
		end
	end
	return (connection :: any) :: Connection
end

function Signal:Once(fn: (...any) -> ()): Connection
	local connection: Connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		fn(...)
	end)
	return connection
end

function Signal:Fire(...: any)
	-- Copy so handlers that disconnect during dispatch do not shift the iteration.
	local snapshot = table.clone(self._handlers)
	for _, handler in snapshot do
		if handler.connected then
			local ok, err = pcall(handler.fn, ...)
			if not ok then
				warn("[Signal] handler error:", err)
			end
		end
	end
end

function Signal:DisconnectAll()
	for _, handler in self._handlers do
		handler.connected = false
	end
	table.clear(self._handlers)
end

Signal.Destroy = Signal.DisconnectAll

return Signal
