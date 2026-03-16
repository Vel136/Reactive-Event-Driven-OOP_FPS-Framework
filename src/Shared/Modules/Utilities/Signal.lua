--!native
--!optimize 2
--!strict

--[=[
	Signal — a high-performance, type-safe event system for Luau.

	FIRE MODE GUIDE (choose the right one for your use case):

	  :FireSync(...)     — Calls every listener synchronously in priority order.
	                       Re-entrant fires are deferred to after the current fire
	                       completes. Lowest overhead; use this as your default.

	  :FireAsync(...)    — Runs every listener in a pooled coroutine. Use when
	                       listeners may yield (e.g. task.wait, Signal:Wait).
	                       Slightly higher overhead than FireSync.

	  :Fire(...)         — Smart dispatch. Calls sync listeners inline and runs
	                       async listeners (ConnectAsync) in pooled coroutines.
	                       Overhead between FireSync and FireAsync depending on
	                       the AsyncCount ratio.

	  :FireDeferred(...) — Schedules the fire to run after the current frame via
	                       task.defer. Returns immediately. Useful when you want
	                       to emit an event without affecting the current call
	                       stack at all (e.g. firing from a constructor).

	  :FireSafe(...)     — Like Fire but wraps every listener in pcall and
	                       deep-copies table arguments so listeners cannot
	                       corrupt shared data. ⚠️ EXPENSIVE — performs a full
	                       recursive copy of every table argument on every fire.
	                       Never use on hot paths. Reserve for low-frequency
	                       events where defensive safety matters more than speed.

	PRIORITY:
	  Higher numbers fire FIRST (more important = earlier execution).
	  Default priority is 0. A listener at priority 10 fires before one at
	  priority 5, which fires before one at priority 0 (default).

	WAIT RETURN CONTRACT:
	  Signal:Wait and Signal:WaitPriority return (timedOut: boolean, ...args).
	  The first return value is TRUE if the timeout elapsed before the signal
	  fired, FALSE if the signal fired normally. Always check it:

	    local timedOut, damage, source = signal:Wait(5)
	    if timedOut then
	        -- handle timeout
	    end
]=]

-- Version 3.0

-- ─── UDTF: derive Fire/Wait signatures from generic Signature param ───────────
--[=[
	These user-defined type functions (UDTFs) are run by the Luau type checker
	at compile time to derive the correct argument types for Fire and Wait from
	the Signal's generic Signature parameter. This means:

	  local sig = Signal.new<(damage: number, source: Player) -> ()>()
	  sig:Fire("oops")  -- type error: string is not number

	The fallback types are used when Signature is unknown (e.g. Signal<any>).
]=]

type function FireSignature(signal: type, signature: type, fallback: type): type
	local tag = signature.tag
	if tag == "unknown" then return fallback end
	if tag ~= "function" then
		print(`Signal<Signature> expects a 'function' type, got '{tag}'`)
		return fallback
	end
	local params = signature:parameters()
	local head = params.head or {} :: {type}
	table.insert(head, 1, signal)
	params.head = head
	return types.newfunction(params)
end

type function WaitSignature(signal: type, signature: type, fallback: type): type
	local tag = signature.tag
	if tag == "unknown" then return fallback end
	if tag ~= "function" then
		print(`Signal<Signature> expects a 'function' type, got '{tag}'`)
		return fallback
	end
	local selfParam: {type} = {signal}
	-- Wait always returns (timedOut: boolean, ...signalArgs). The timedOut
	-- boolean is prepended so callers can distinguish a timeout from a fire
	-- that passed nil arguments.
	local waitParams = {head = selfParam, tail = types.singleton(0) :: type}
	local sigParams  = signature:parameters()
	local retHead: {type} = {types.singleton(false) :: type}
	if sigParams and sigParams.head then
		for _, t in sigParams.head do
			table.insert(retHead, t)
		end
	end
	return types.newfunction(waitParams, {head = retHead})
end

type function readonly(ty: type): type
	for keyType, rwType in ty:properties() do
		if rwType.write then
			ty:setreadproperty(keyType, rwType.read or rwType.write)
		end
	end
	return ty
end

-- ─── Exported types ───────────────────────────────────────────────────────────

--[=[
	A Connection represents a single listener attached to a Signal.
	Call :Disconnect() or :Destroy() to detach it. Both are equivalent.
	Disconnecting an already-disconnected connection is a no-op.
]=]
export type Connection<Signature = () -> ()> = {
	read Signal:    Signal<Signature>,
	read Connected: boolean,
	read IsAsync:   boolean,
	read Priority:  number,
	read Fn:        Signature,

	read Disconnect: (self: Connection<Signature>) -> (),
	read Destroy:    (self: Connection<Signature>) -> (),
}

--[=[
	A Signal is a typed event that listeners can connect to and fire.
	Generic parameter Signature defines the argument types for Fire and Connect.
	Example:
	  local onDamage = Signal.new<(amount: number, source: Player) -> ()>()
]=]
export type Signal<Signature = () -> ()> = {
	read Connections:  { Connection<Signature> },
	read ActiveCount:  number,
	read AsyncCount:   number,
	read Proxy:        RBXScriptConnection?,

	-- Connection management
	read Connect:      (self: Signal<Signature>, Fn: Signature, Priority: number?) -> Connection<Signature>,
	read ConnectAsync: (self: Signal<Signature>, Fn: Signature, Priority: number?) -> Connection<Signature>,
	read ConnectSync:  (self: Signal<Signature>, Fn: Signature, Priority: number?) -> Connection<Signature>,
	read Once:         (self: Signal<Signature>, Fn: Signature, Priority: number?) -> Connection<Signature>,
	read OnceAsync:    (self: Signal<Signature>, Fn: Signature, Priority: number?) -> Connection<Signature>,

	-- Fire modes (see module header for full documentation)
	read Fire:         FireSignature<any, Signature, (self: any, ...any) -> ()>,
	read FireSync:     FireSignature<any, Signature, (self: any, ...any) -> ()>,
	read FireAsync:    FireSignature<any, Signature, (self: any, ...any) -> ()>,
	read FireDeferred: FireSignature<any, Signature, (self: any, ...any) -> ()>,
	read FireSafe:     FireSignature<any, Signature, (self: any, ...any) -> ()>,

	-- Waiting (returns timedOut: boolean as first value — see module header)
	read Wait:         WaitSignature<any, Signature, (self: any, Timeout: number, Priority: number?) -> (boolean, ...any)>,
	read WaitPriority: WaitSignature<any, Signature, (self: any, Priority: number?) -> (boolean, ...any)>,

	-- Utilities
	read GetListenerCount: (self: Signal<Signature>) -> number,
	read HasListeners:     (self: Signal<Signature>) -> boolean,
	read DisconnectAll:    (self: Signal<Signature>) -> (),
	read Destroy:          (self: Signal<Signature>) -> (),
}

-- ─── Internal types ───────────────────────────────────────────────────────────

type InternalConnection = {
	Signal:     InternalSignal,
	Connected:  boolean,
	IsAsync:    boolean,
	Priority:   number,
	Fn:         (...any) -> (),
	Disconnect: (self: InternalConnection) -> (),
	Destroy:    (self: InternalConnection) -> (),
}

type InternalSignal = {
	Connections:  { InternalConnection },
	ActiveCount:  number,
	AsyncCount:   number,

	-- Why a counter and not a boolean?
	-- FireSync defers re-entrant fires via task.defer. A single top-level Fire
	-- call processes all deferred fires one at a time — never nested. But
	-- consider FireAsync: it resumes coroutines that might themselves call Fire
	-- before returning. In that scenario multiple logical fires overlap in the
	-- same tick. A boolean would think the second fire is the only one active,
	-- allow compaction mid-iteration, and corrupt the array. The counter tracks
	-- the true nesting depth, so compaction only runs when it hits zero — when
	-- every overlapping fire has truly completed.
	Firing:       number,

	-- Pre-allocated snapshot buffers. On every fire, we copy function references
	-- and async flags here before iterating, so disconnections during a handler
	-- call never affect the current iteration.
	--
	-- IMPORTANT: These buffers are owned by the signal, not by the fire call.
	-- This is safe ONLY because the Firing counter guarantees that while any
	-- fire is executing, all re-entrant fires are deferred — they never run
	-- concurrently in the same signal. If you ever remove the deferred re-entrancy
	-- guard, you MUST make ScratchFns and ScratchAsync local to each fire call
	-- instead, or two concurrent fires will corrupt each other's snapshots.
	ScratchFns:   { (...any) -> () },
	ScratchAsync: { boolean },

	Proxy: RBXScriptConnection?,
}

-- ─── Connection pool ──────────────────────────────────────────────────────────
--[=[
	Reuses Connection table objects to avoid GC pressure at high
	connect/disconnect churn rates (e.g. projectile hit handlers that
	connect on spawn and disconnect on impact, 20 times per second).
]=]
local ConnectionPool: { InternalConnection } = {}
local PoolSize = 0
local MAX_POOL_SIZE = 1000

-- ─── Thread pools ─────────────────────────────────────────────────────────────
--[=[
	Two pools of pooled coroutines for async dispatch.

	FreeThreads      — used by FireAsync and the async branch of Fire.
	                   No error handling; errors propagate to the coroutine.

	FreeSafeThreads  — used by FireSafe's async branch. Wraps execution in
	                   pcall so a crashing async handler doesn't kill the
	                   coroutine and is instead warned about.

	Each coroutine parks itself in a yield loop after completing its task,
	so resuming it with a new (fn, args, n) triple reuses the same OS thread
	rather than allocating a fresh one.
]=]
local FreeThreads:     { thread } = {}
local FreeSafeThreads: { thread } = {}

local table_unpack      = table.unpack
local table_clone       = table.clone
local table_clear       = table.clear
local table_insert      = table.insert
local task_defer        = task.defer
local coroutine_create  = coroutine.create
local coroutine_resume  = coroutine.resume
local coroutine_yield   = coroutine.yield
local coroutine_running = coroutine.running

local function SafeThreadRunner()
	while true do
		local fn, args, n = coroutine_yield()
		local ok, err = pcall(fn, table_unpack(args, 1, n))
		if not ok then warn("Signal FireSafe (async) error:", err) end
		table_insert(FreeSafeThreads, coroutine_running())
	end
end

local function AcquireSafeThread(): thread
	local count = #FreeSafeThreads
	if count > 0 then
		local thread = FreeSafeThreads[count]
		FreeSafeThreads[count] = nil
		return thread
	end
	local thread = coroutine_create(SafeThreadRunner)
	coroutine_resume(thread)
	return thread
end

local function ThreadRunner()
	while true do
		local callback, args, n = coroutine_yield()
		callback(table_unpack(args, 1, n))
		table_insert(FreeThreads, coroutine_running())
	end
end

local function AcquireThread(): thread
	local count = #FreeThreads
	if count > 0 then
		local thread = FreeThreads[count]
		FreeThreads[count] = nil
		return thread
	end
	local thread = coroutine_create(ThreadRunner)
	coroutine_resume(thread)
	return thread
end

-- ─── Helpers ──────────────────────────────────────────────────────────────────

--[=[
	Finds the index at which to insert a new connection so the array remains
	sorted in DESCENDING priority order (highest priority = index 1 = fires first).

	Fast path: priority 0 (the default) always appends to the end. Since 0 is
	by far the most common priority, this avoids a binary search in the
	overwhelming majority of Connect calls.

	Binary search: for non-zero priorities, we find the first position where the
	existing connection's priority is strictly less than the new one. Inserting
	there maintains descending sort order, so higher-priority listeners always
	fire before lower-priority ones.
]=]
local function FindInsertIndex(Connections: { InternalConnection }, Priority: number): number
	-- Fast path: default priority — just append
	if Priority == 0 then
		return #Connections + 1
	end

	local Count = #Connections
	if Count == 0 or Connections[Count].Priority > Priority then
		return Count + 1
	end

	-- Binary search for insertion point in descending order.
	-- Invariant: everything left of lo has priority >= Priority (fires before us).
	-- Everything at hi or right has priority < Priority (fires after us).
	local lo, hi = 1, Count + 1
	while lo < hi do
		local mid = (lo + hi) // 2
		if Connections[mid].Priority > Priority then
			lo = mid + 1
		else
			hi = mid
		end
	end
	return lo
end

--[=[
	Removes disconnected entries from the Connections array in a single linear
	pass, shifting live connections down to fill the gaps. Only called when
	Firing == 0 (no fire is currently executing), so modifying the array is safe.

	Why not remove entries immediately on Disconnect? Because Disconnect can be
	called from inside a Fire handler, while we're actively iterating the array.
	Immediate removal would shift indices and cause the iterator to skip or
	double-visit entries. The deferred compaction pattern avoids this entirely.
]=]
local function CompactConnections(Connections: { InternalConnection }, ActiveCount: number)
	if ActiveCount == #Connections then return end
	local WriteIndex = 1
	local Count = #Connections
	for ReadIndex = 1, Count do
		local Conn = Connections[ReadIndex]
		if Conn.Connected then
			if WriteIndex ~= ReadIndex then
				Connections[WriteIndex] = Conn
			end
			WriteIndex += 1
		end
	end
	for i = WriteIndex, Count do
		Connections[i] = nil
	end
end

--[=[
	Snapshots function references and async flags into the pre-allocated scratch
	arrays before a fire begins. Returns the count and a boolean indicating
	whether any async listeners are present (used to skip async machinery in
	the sync-only fast path).
]=]
local function SnapshotFns(
	Connections:  { InternalConnection },
	ScratchFns:   { (...any) -> () },
	ScratchAsync: { boolean }
): (number, boolean)
	local Count = #Connections
	local HasAsync = false
	for i = 1, Count do
		local Conn = Connections[i]
		ScratchFns[i]   = Conn.Fn
		ScratchAsync[i] = Conn.IsAsync
		if Conn.IsAsync then
			HasAsync = true
		end
	end
	return Count, HasAsync
end

-- ─── Connection:Disconnect ────────────────────────────────────────────────────
--[=[
	Detaches this listener from its Signal. Safe to call multiple times —
	subsequent calls are no-ops.

	SAFETY NOTE for Destroy: Signal:Destroy calls DisconnectAll, which sets
	Connected = false and nils Signal + Fn on every connection before pooling
	them. This means if a caller holds a stale Connection reference and calls
	:Disconnect() after the Signal is destroyed, the `if not self.Connected`
	guard at the top returns immediately — no nil-index on self.Signal.
	The safety is guaranteed by DisconnectAll always setting Connected = false
	BEFORE pooling, so the guard always fires first on stale connections.
]=]
local function Connection_Disconnect(self: InternalConnection)
	if not self.Connected then return end
	self.Connected = false

	local Sig = self.Signal
	Sig.ActiveCount -= 1
	if self.IsAsync then
		Sig.AsyncCount -= 1
	end

	-- Only compact immediately if no fire is executing. If a fire IS executing
	-- (Firing > 0), the compaction is deferred until the fire completes, so we
	-- never modify the connections array while it's being iterated.
	if Sig.Firing == 0 then
		CompactConnections(Sig.Connections, Sig.ActiveCount)
	end

	-- Return to pool for reuse, capped to prevent unbounded memory growth.
	if PoolSize < MAX_POOL_SIZE then
		PoolSize += 1
		ConnectionPool[PoolSize] = self
	end

	-- Nil out Signal and Fn so pooled connections don't hold strong references
	-- to objects that may have been garbage-collected since disconnect.
	self.Signal = nil :: any
	self.Fn     = nil :: any
end

-- ─── Signal class ─────────────────────────────────────────────────────────────

local SignalClass = {} :: InternalSignal
SignalClass.Connections  = {}
SignalClass.ActiveCount  = 0
SignalClass.AsyncCount   = 0
SignalClass.Firing       = 0
SignalClass.ScratchFns   = {}
SignalClass.ScratchAsync = {}

--[=[
	FireSync: calls every listener synchronously in descending priority order.

	Re-entrancy: if a listener calls FireSync on the same signal, the inner
	fire is deferred via task.defer to run after the current fire finishes.
	This prevents stack overflows from recursive signals and keeps execution
	order predictable. Note that deferred fires run in the order they were
	deferred — FIFO.

	Compaction: runs after the fire if any listeners disconnected during it.
]=]
function SignalClass.FireSync(self: InternalSignal, ...: any)
	if self.Firing > 0 then task_defer(self.FireSync, self, ...) return end

	local Connections = self.Connections
	local SnapCount = #Connections
	if SnapCount == 0 then return end

	-- Snapshot into ScratchFns before firing. See the ScratchFns comment in
	-- InternalSignal for why this is on the signal rather than a local table.
	local ScratchFns = self.ScratchFns
	for i = 1, SnapCount do
		ScratchFns[i] = Connections[i].Fn
	end

	-- Increment Firing before calling any handler. This prevents re-entrant
	-- fires from running concurrently and ensures compaction defers correctly.
	-- Decrement BEFORE the last call so that if the last handler itself causes
	-- a re-entrant fire, the Firing count is already back to 0 and the deferred
	-- fire can proceed immediately after this function returns.
	self.Firing += 1
	for i = 1, SnapCount - 1 do
		ScratchFns[i](...)
	end
	self.Firing -= 1
	ScratchFns[SnapCount](...)

	if self.ActiveCount ~= #self.Connections then
		CompactConnections(self.Connections, self.ActiveCount)
	end
end

--[=[
	FireAsync: runs every listener in a pooled coroutine thread.

	Use when listeners may yield (task.wait, Signal:Wait, etc.). Each listener
	gets its own coroutine from the pool, so they run concurrently and don't
	block each other. Same re-entrancy and compaction rules as FireSync.

	Note: errors inside async listeners propagate to the coroutine and are
	silently swallowed unless you use FireSafe instead.
]=]
function SignalClass.FireAsync(self: InternalSignal, ...: any)
	if self.Firing > 0 then task_defer(self.FireAsync, self, ...) return end

	local Connections = self.Connections
	local SnapCount = #Connections
	if SnapCount == 0 then return end

	local ScratchFns = self.ScratchFns
	for i = 1, SnapCount do
		ScratchFns[i] = Connections[i].Fn
	end

	local n    = select("#", ...)
	local args = { ... }

	self.Firing += 1
	for i = 1, SnapCount - 1 do
		coroutine_resume(AcquireThread(), ScratchFns[i], args, n)
	end
	self.Firing -= 1
	coroutine_resume(AcquireThread(), ScratchFns[SnapCount], args, n)

	if self.ActiveCount ~= #self.Connections then
		CompactConnections(self.Connections, self.ActiveCount)
	end
end

--[=[
	Fire: respects each connection's individual IsAsync flag.

	Sync connections are called inline; async connections (ConnectAsync) are
	dispatched to a pooled coroutine. This is the most flexible mode and the
	right choice when your signal has a mix of listeners that may or may not
	yield.

	Sync-only fast path: if AsyncCount == 0, skips the ScratchAsync snapshot
	and async machinery entirely. In practice most signals are sync-only, so
	this fast path runs the majority of the time.
]=]
function SignalClass.Fire(self: InternalSignal, ...: any)
	if self.Firing > 0 then task_defer(self.Fire, self, ...) return end

	local Connections = self.Connections
	local SnapCount = #Connections
	if SnapCount == 0 then return end

	-- ── Sync-only fast path ───────────────────────────────────────────────────
	if self.AsyncCount == 0 then
		local ScratchFns = self.ScratchFns
		for i = 1, SnapCount do
			ScratchFns[i] = Connections[i].Fn
		end
		self.Firing += 1
		for i = 1, SnapCount - 1 do
			ScratchFns[i](...)
		end
		self.Firing -= 1
		ScratchFns[SnapCount](...)
		if self.ActiveCount ~= #self.Connections then
			CompactConnections(self.Connections, self.ActiveCount)
		end
		return
	end

	-- ── Mixed sync/async path ─────────────────────────────────────────────────
	local ScratchFns   = self.ScratchFns
	local ScratchAsync = self.ScratchAsync

	for i = 1, SnapCount do
		local Conn      = Connections[i]
		ScratchFns[i]   = Conn.Fn
		ScratchAsync[i] = Conn.IsAsync
	end

	local n    = select("#", ...)
	local args = { ... }

	self.Firing += 1
	for i = 1, SnapCount - 1 do
		if ScratchAsync[i] then
			coroutine_resume(AcquireThread(), ScratchFns[i], args, n)
		else
			ScratchFns[i](...)
		end
	end
	self.Firing -= 1

	if ScratchAsync[SnapCount] then
		coroutine_resume(AcquireThread(), ScratchFns[SnapCount], args, n)
	else
		ScratchFns[SnapCount](...)
	end

	if self.ActiveCount ~= #self.Connections then
		CompactConnections(self.Connections, self.ActiveCount)
	end
end

--[=[
	FireDeferred: schedules the fire to happen after the current frame.

	Returns immediately. The actual fire runs on the next task.defer cycle,
	using FireSync semantics. Use when you want to emit an event from a
	constructor or initialization function without affecting the current
	call stack.
]=]
function SignalClass.FireDeferred(self: InternalSignal, ...: any)
	task_defer(self.FireSync, self, ...)
end

--[=[
	Recursively deep-copies a value for FireSafe's argument isolation.

	Why: when a signal fires with a table argument, all listeners receive a
	reference to the same table. If one listener mutates it, later listeners
	see the mutated version — a classic action-at-a-distance bug. FireSafe
	prevents this by giving each listener its own independent copy.

	Rules:
	  - Non-table values (numbers, strings, Vectors, etc.) are returned as-is.
	  - Roblox Instance types are passed by reference — they're not owned data
	    and deep-copying them would be meaningless.
	  - Plain tables are recursively copied. Cycle detection via the `seen`
	    map prevents infinite loops on self-referential tables.
	  - Tables with metatables are shallow-copied with the original metatable
	    preserved — deep-copying a metatable could corrupt class identity.

	⚠️ PERFORMANCE: This function allocates a new table for every plain table
	in the argument tree, on every FireSafe call. Never use FireSafe on signals
	that fire frequently (multiple times per frame). It is intended for
	low-frequency, safety-critical events only.
]=]
local function SafeCopyArg(v: any, seen: { [any]: any }?): any
	if type(v) ~= "table" then return v end
	if typeof(v) == "Instance"
		or typeof(v) == "RBXScriptSignal"
		or typeof(v) == "RBXConnection"
	then
		return v
	end
	seen = seen or {}
	if seen[v] then return seen[v] end
	local copy = {}
	seen[v] = copy
	for k, val in pairs(v) do
		local copiedKey = type(k) == "table" and SafeCopyArg(k, seen) or k
		-- Only deep-copy plain tables (no metatable). Tables with metatables
		-- are likely class instances — preserve their identity.
		local copiedVal = (type(val) == "table" and getmetatable(val) == nil)
			and SafeCopyArg(val, seen)
			or val
		copy[copiedKey] = copiedVal
	end
	local mt = getmetatable(v)
	if mt then setmetatable(copy, mt) end
	return copy
end

--[=[
	FireSafe: defensive fire with pcall error isolation and argument deep-copy.

	⚠️ EXPENSIVE. See SafeCopyArg and the module header for cost details.

	Error handling: sync listener errors are caught by pcall and warned.
	Async listener errors are caught by the safe thread pool and warned.
	A crashing listener never prevents subsequent listeners from running.

	Argument isolation: table arguments are deep-copied before dispatch so
	listener mutations cannot affect other listeners or the caller's data.
]=]
function SignalClass.FireSafe(self: InternalSignal, ...: any)
	if self.Firing > 0 then task_defer(self.FireSafe, self, ...) return end

	local Connections = self.Connections
	local SnapCount = #Connections
	if SnapCount == 0 then return end

	local ScratchFns   = self.ScratchFns
	local ScratchAsync = self.ScratchAsync
	SnapshotFns(Connections, ScratchFns, ScratchAsync)

	local n    = select("#", ...)
	local Args: { any } = {}
	for i = 1, n do
		Args[i] = SafeCopyArg((select(i, ...)))
	end

	self.Firing += 1
	for i = 1, SnapCount - 1 do
		local Fn = ScratchFns[i]
		if ScratchAsync[i] then
			coroutine_resume(AcquireSafeThread(), Fn, Args, n)
		else
			local ok, err = pcall(Fn, table_unpack(Args, 1, n))
			if not ok then warn("Signal FireSafe (sync) error:", err) end
		end
	end
	self.Firing -= 1

	local Fn = ScratchFns[SnapCount]
	if ScratchAsync[SnapCount] then
		coroutine_resume(AcquireSafeThread(), Fn, Args, n)
	else
		local ok, err = pcall(Fn, table_unpack(Args, 1, n))
		if not ok then warn("Signal FireSafe (sync) error:", err) end
	end

	if self.ActiveCount ~= #self.Connections then
		CompactConnections(self.Connections, self.ActiveCount)
	end
end

function SignalClass.HasListeners(self: InternalSignal): boolean
	return self.ActiveCount > 0
end

function SignalClass.GetListenerCount(self: InternalSignal): number
	return self.ActiveCount
end

-- ─── Connection class prototype ───────────────────────────────────────────────

local ConnectionClass = {
	Signal     = nil,
	Fn         = function() end,
	Priority   = 0,
	IsAsync    = false,
	Connected  = true,
	Disconnect = Connection_Disconnect,
	Destroy    = Connection_Disconnect,
}

-- ─── Connect ──────────────────────────────────────────────────────────────────
--[=[
	Attaches a listener function to this Signal.

	Priority (optional, default 0): higher numbers fire first. A listener at
	priority 10 fires before one at priority 5, which fires before priority 0.
	Listeners with equal priority fire in the order they were connected.

	Returns a Connection object. Call :Disconnect() on it to detach.
	Connections are pooled — creating and destroying many connections at high
	frequency incurs no GC pressure.
]=]
function SignalClass.Connect(self: InternalSignal, Fn: (...any) -> (), Priority: number?): InternalConnection
	local P = Priority or 0
	local Connections = self.Connections

	-- Compact before inserting so FindInsertIndex sees a clean sorted array.
	-- Without this, dead (disconnected) entries in the middle could cause
	-- FindInsertIndex to compute the wrong insertion point.
	if self.ActiveCount ~= #Connections then
		CompactConnections(Connections, self.ActiveCount)
	end

	local Conn: InternalConnection
	if PoolSize > 0 then
		Conn = ConnectionPool[PoolSize]
		PoolSize -= 1
		Conn.Signal    = self
		Conn.Fn        = Fn
		Conn.Connected = true
		Conn.IsAsync   = false
		Conn.Priority  = P
	else
		Conn = table_clone(ConnectionClass)
		Conn.Signal    = self
		Conn.Fn        = Fn
		Conn.Connected = true
		Conn.IsAsync   = false
		Conn.Priority  = P
	end

	table_insert(Connections, FindInsertIndex(Connections, P), Conn)
	self.ActiveCount += 1
	return Conn
end

-- ConnectSync is an explicit alias for Connect for callers who want to be
-- explicit about their intent in a mixed sync/async codebase.
SignalClass.ConnectSync = SignalClass.Connect

--[=[
	Attaches an async listener. When this signal is fired with :Fire(), this
	listener runs in a pooled coroutine rather than inline. Use for listeners
	that may yield.

	Has no special meaning with :FireSync() (all listeners run synchronously)
	or :FireAsync() (all listeners run asynchronously regardless of this flag).
	The IsAsync flag is only meaningful with :Fire() and :FireSafe().
]=]
function SignalClass.ConnectAsync(self: InternalSignal, Fn: (...any) -> (), Priority: number?): InternalConnection
	local Conn = self:Connect(Fn, Priority)
	Conn.IsAsync   = true
	self.AsyncCount += 1
	return Conn
end

--[=[
	Attaches a listener that automatically disconnects after firing once.

	IMPLEMENTATION NOTE (upvalue capture pattern):
	  `Conn` is declared with `local Conn` before the wrapper closure is created.
	  In Lua, closures capture *variables* (upvalue references), not their values
	  at creation time. So even though `Conn` is nil when the closure is created,
	  by the time the closure actually executes (when the signal fires), `Conn`
	  has been assigned the Connection returned by self:Connect. This is a
	  well-defined Lua language behavior, not a trick — it's the standard pattern
	  for self-referential once-listeners.

	  The `fired` guard prevents double-execution in the rare case where the
	  signal fires twice in the same frame before the Disconnect takes effect
	  (e.g. if two nested fires overlap due to coroutines).
]=]
function SignalClass.Once(self: InternalSignal, Fn: (...any) -> (), Priority: number?): InternalConnection
	-- Declare Conn before the closure so the closure captures the upvalue
	-- reference, which will hold the Connection by the time the signal fires.
	local Conn: InternalConnection
	local fired = false
	Conn = self:Connect(function(...)
		if fired then return end
		fired = true
		Conn:Disconnect()
		Fn(...)
	end, Priority)
	return Conn
end

--[=[
	Async variant of Once. The listener runs in a pooled coroutine and
	auto-disconnects after the first fire. Same upvalue pattern as Once.
]=]
function SignalClass.OnceAsync(self: InternalSignal, Fn: (...any) -> (), Priority: number?): InternalConnection
	local Conn: InternalConnection
	local fired = false
	Conn = self:ConnectAsync(function(...)
		if fired then return end
		fired = true
		Conn:Disconnect()
		Fn(...)
	end, Priority)
	return Conn
end

-- ─── Wait / WaitPriority ──────────────────────────────────────────────────────
--[=[
	WaitPriority: suspends the current coroutine until the signal fires.

	MUST be called from inside a coroutine or task (not the root script thread).

	Returns: (timedOut: boolean, ...signalArgs)
	  timedOut is always FALSE from WaitPriority since there is no timeout.
	  It is included for API consistency with Wait so call sites can use the
	  same destructuring pattern regardless of which method they use.

	Priority (optional): controls which listeners are notified first. The
	internal Once listener uses this priority level.
]=]
function SignalClass.WaitPriority(self: InternalSignal, Priority: number?): ...any
	local co = coroutine_running()
	if not co then
		error("Signal:WaitPriority must be called from inside a coroutine or task", 2)
	end
	self:Once(function(...)
		-- Prepend false (timedOut = false) so the return matches Wait's contract.
		local ok, err = coroutine_resume(co, false, ...)
		if not ok then warn("Signal.WaitPriority resume failed:", err) end
	end, Priority)
	return coroutine_yield()
end

--[=[
	Wait: suspends the current coroutine until the signal fires or timeout elapses.

	MUST be called from inside a coroutine or task.

	Parameters:
	  timeout  — seconds to wait before giving up. Pass 0 or nil for no timeout
	             (equivalent to WaitPriority).
	  Priority — optional listener priority (see Connect).

	Returns: (timedOut: boolean, ...signalArgs)
	  timedOut = FALSE  → signal fired normally; signalArgs are the fired values.
	  timedOut = TRUE   → timeout elapsed before the signal fired; signalArgs
	                       are all nil. Always check this value:

	    local timedOut, damage, source = mySignal:Wait(5)
	    if timedOut then
	        warn("waited 5 seconds, signal never fired")
	        return
	    end
	    -- damage and source are valid here

	The `done` flag prevents a race where both the signal fires AND the timeout
	fires in the same scheduler step — only the first one to run resumes the
	coroutine, the second is a no-op.
]=]
function SignalClass.Wait(self: InternalSignal, timeout: number, Priority: number?): ...any
	local co = coroutine_running()
	if not co then
		error("Signal:Wait must be called from inside a coroutine or task", 2)
	end

	if timeout and timeout > 0 then
		local done = false
		local connection: InternalConnection?

		-- resumeWith is called by EITHER the signal firing OR the timeout
		-- expiring. The `done` flag ensures only the first caller wins.
		-- timedOut is passed as the first return value so callers can
		-- distinguish a timeout (true) from a normal signal fire (false).
		local function resumeWith(timedOut: boolean, ...)
			if done then return end
			done = true
			if connection then
				connection:Disconnect()
				connection = nil
			end
			local ok, err = coroutine_resume(co, timedOut, ...)
			if not ok then warn("Signal.Wait resume failed:", err) end
		end

		-- Connect the once-listener. If the signal fires, resumeWith(false, ...)
		-- is called with the signal's arguments and timedOut = false.
		connection = self:Once(function(...)
			resumeWith(false, ...)
		end, Priority)

		-- Schedule the timeout. If it fires first, resumeWith(true) is called
		-- with no signal args and timedOut = true.
		task.delay(timeout, resumeWith, true)
	else
		-- No timeout — equivalent to WaitPriority
		self:Once(function(...)
			local ok, err = coroutine_resume(co, false, ...)
			if not ok then warn("Signal.Wait resume failed:", err) end
		end, Priority)
	end

	return coroutine_yield()
end

-- ─── DisconnectAll / Destroy ──────────────────────────────────────────────────
--[=[
	Disconnects every listener and returns their Connection objects to the pool.

	SAFETY CONTRACT for stale Connection references:
	  DisconnectAll sets Connected = false AND nils Signal + Fn on every
	  connection BEFORE returning them to the pool. This means any caller that
	  holds a stale Connection reference after DisconnectAll (or Destroy) and
	  calls :Disconnect() on it will hit the `if not self.Connected then return
	  end` guard at the top of Connection_Disconnect and return safely — it will
	  NEVER reach the `self.Signal.ActiveCount` line with a nil Signal.
	  The ordering guarantee (Connected = false first) is what makes this safe.
]=]
function SignalClass.DisconnectAll(self: InternalSignal)
	local Connections = self.Connections
	local Count = #Connections
	if Count == 0 then return end

	for i = 1, Count do
		local Conn = Connections[i]
		Conn.Connected = false   -- Must be set BEFORE pooling (see safety contract above)
		if PoolSize < MAX_POOL_SIZE then
			PoolSize += 1
			ConnectionPool[PoolSize] = Conn
		end
		Conn.Signal = nil :: any
		Conn.Fn     = nil :: any
	end

	table_clear(Connections)
	self.ActiveCount = 0
	self.AsyncCount  = 0
end

--[=[
	Destroys the Signal, disconnecting all listeners and releasing the Roblox
	proxy connection if one exists (see Signal.wrap).

	After Destroy, the Signal table is cleared. Do not call any methods on a
	destroyed Signal — they will error with a nil-index. The Signal reference
	itself should be set to nil after calling Destroy.
]=]
function SignalClass.Destroy(self: InternalSignal)
	self:DisconnectAll()
	local Proxy = self.Proxy
	if Proxy then
		Proxy:Disconnect()
	end
	table_clear(self :: { [any]: any })
end

-- ─── Module ───────────────────────────────────────────────────────────────────

local Module = {}

--[=[
	Creates a new Signal.

	Generic parameter Signature defines the argument types for Fire and Connect.
	Using the generic ensures the type checker validates your fire arguments:

	  -- Typed usage:
	  local onDamage = Signal.new<(amount: number, source: Player) -> ()>()
	  onDamage:Fire(50, somePlayer)   -- ✓ type-checks
	  onDamage:Fire("oops")           -- ✗ type error at compile time

	  -- Untyped usage (Signal<any> or Signal.new()):
	  local generic = Signal.new()
	  generic:Fire("anything", 123)   -- ✓ no type enforcement
]=]
function Module.new<Signature>(): Signal<Signature>
	local NewSignal = table_clone(SignalClass) :: any
	NewSignal.Connections  = {}
	NewSignal.Firing       = 0
	NewSignal.AsyncCount   = 0
	NewSignal.ScratchFns   = {}
	NewSignal.ScratchAsync = {}
	NewSignal.Proxy        = nil
	return NewSignal
end

--[=[
	Wrap: proxies a Roblox RBXScriptSignal into a Signal, giving it priority
	ordering, async dispatch, FireSafe, Wait, and all other Signal features.

	The internal RBXScriptConnection is stored in Signal.Proxy and disconnected
	automatically when Signal:Destroy() is called.

	Example:
	  local onTouched = Signal.wrap(part.Touched)
	  onTouched:Connect(function(hit) ... end, 10)  -- priority 10, fires first
]=]
function Module.wrap<Signature>(RobloxSignal: RBXScriptSignal): Signal<Signature>
	local signal = Module.new()
	local conn = RobloxSignal:Connect(function(...)
		(signal :: any):Fire(...)
	end)
	signal.Proxy = conn
	return signal
end

return setmetatable(Module, {
	__call = function()
		return Module.new()
	end,
})