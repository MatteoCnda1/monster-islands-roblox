--!strict
export type Connection = {
	Disconnect: (self: Connection) -> (),
	Connected: boolean,
}

export type Signal<T...> = {
	Connect: (self: Signal<T...>, fn: (T...) -> ()) -> Connection,
	Fire: (self: Signal<T...>, T...) -> (),
	Wait: (self: Signal<T...>) -> T...,
	Destroy: (self: Signal<T...>) -> (),
}

local Signal = {}
Signal.__index = Signal

function Signal.new<T...>(): Signal<T...>
	local self = setmetatable({
		_listeners = {},
	}, Signal)
	return (self :: any) :: Signal<T...>
end

function Signal:Connect(fn: (...any) -> ()): Connection
	local connection = {
		Connected = true,
		Disconnect = function(conn)
			if not conn.Connected then return end
			conn.Connected = false
			local idx = table.find(self._listeners, fn)
			if idx then
				table.remove(self._listeners, idx)
			end
		end,
	}
	table.insert(self._listeners, fn)
	return connection
end

function Signal:Fire(...: any)
	-- Iterate over copy to allow safe mutation during dispatch
	local listeners = table.clone(self._listeners)
	for _, fn in ipairs(listeners) do
		task.spawn(fn, ...)
	end
end

function Signal:Wait(): ...any
	local thread = coroutine.running()
	local conn: Connection? = nil
	conn = self:Connect(function(...: any)
		if conn then
			conn:Disconnect()
		end
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end

function Signal:Destroy()
	table.clear(self._listeners)
end

return Signal
