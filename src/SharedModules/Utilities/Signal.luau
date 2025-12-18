--!strict
-- Signal module by Drastic
-- Fastest signal module possibly

export type Connection = {
	Signal: Signal,
	Connected: boolean,

	Next: Connection | any,
	Prev: Connection | any,

	Fn: <T...>(T...) -> (T...),
	read Disconnect: (Connection) -> (),
	read Destroy: (Connection) -> (),
}

export type Signal = {
	Connections: Connection | false,
	Proxy: RBXScriptConnection?,

	Fire: <T...>(Signal, T...) -> (),
	Once: <T...>(Signal, Fn: (T...)->(T...)) -> Connection,
	Wait: (Signal) -> (any),
	Connect: <T...>(Signal, Fn: (T...)->(T...)) -> Connection,
	DisconnectAll: (Signal) -> (),
	Destroy: (Signal) -> (),
}

local FreeRunnerThread: thread?

local function AcquireRunnerThreadAndCallEventHandler(Fn, ...)
	local AcquiredRunnerThread = FreeRunnerThread
	FreeRunnerThread = nil
	Fn(...)
	FreeRunnerThread = AcquiredRunnerThread
end

local function RunEventHandlerInFreeThread(...)
	AcquireRunnerThreadAndCallEventHandler(...)
	while true do
		AcquireRunnerThreadAndCallEventHandler(coroutine.yield())
	end
end

local function Connection_Disconnect(self: Connection)
	if not self.Connected then return end
	self.Connected = false

	local Signal = self.Signal
	local Prev, Next = self.Prev, self.Next

	if Prev then
		Prev.Next = Next
	end

	if Next then
		Next.Prev = Prev
	end

	if Signal.Connections == self then
		Signal.Connections = Next
	end
end

local ConnectionClass: Connection = {
	-- Have memory reserved for these values
	Fn = function() end :: <T...>(T...)->(T...),
	Signal = {}::Signal,
	Next = false,
	Prev = false,
	Connected = true,

	Disconnect = Connection_Disconnect,
	Destroy = Connection_Disconnect,
}

local SignalClass = {
	Connections = false,
}

function SignalClass.Fire<T...>(self: Signal, ...: T...)	
	local Node = self.Connections
	if not Node then return end

	local function ThreadTask(...)
		while Node do
			if Node.Connected then
				Node.Fn(...)
			end

			Node = Node and Node.Next
		end
	end

	while Node do
		FreeRunnerThread = FreeRunnerThread or coroutine.create(RunEventHandlerInFreeThread)
		task.spawn(FreeRunnerThread::thread, ThreadTask, ...)
		Node = Node and Node.Next
	end
end

function SignalClass.FireDeferred<T...>(self: Signal, ...: T...)
	task.defer(self.Fire, self, ...)

end

function SignalClass.Once<T...>(self: Signal, Fn: (T...) -> (T...)): Connection
	local Disconnected = false
	local Connection: Connection; Connection = self:Connect(function(...)
		if Disconnected then return end
		Disconnected = true
		Connection:Disconnect()
		Fn(...)
	end)

	return Connection :: Connection
end

function SignalClass.Wait(self: Signal)
	local Running = coroutine.running()
	self:Once(function(...)
		if coroutine.status(Running) ~= "suspended" then return end
		task.spawn(Running, ...)
	end)
	return coroutine.yield()
end

function SignalClass.Connect<T...>(self: Signal, Fn: <T...>(T...) -> (T...)): Connection
	local NextConnection = self.Connections
	local Connection = table.clone(ConnectionClass)
	Connection.Signal = self
	Connection.Fn = Fn

	if NextConnection then
		Connection.Next = NextConnection
		NextConnection.Prev = Connection
	end

	self.Connections = Connection

	return Connection 
end

function SignalClass.DisconnectAll(self: Signal)
	self.Connections = false
end

function SignalClass.Destroy(self: Signal)
	self:DisconnectAll()

	-- odd typechecker workaround :(
	local Proxy = self.Proxy
	if Proxy then
		Proxy:Disconnect()
	end

	table.clear(self :: {[any]:any})
end

local Module = {}

function Module.new(): Signal
	return table.clone(SignalClass) :: Signal
end

function Module.Wrap(RBXScriptSignal: RBXScriptSignal): Signal
	local NewSignal = table.clone(SignalClass)

	NewSignal.Proxy = RBXScriptSignal:Connect(function(...)
		NewSignal:Fire(...)
	end)

	return NewSignal :: Signal
end

return Module 