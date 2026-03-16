-- FuseController.lua
--[[
	Manages grenade fuse timing:
	- Cook time tracking (holding before throw)
	- Fuse countdown after throw (accounts for already-cooked time)
	- Supports multiple concurrent fuses via returned handles
	- Each StartFuse() returns a FuseHandle — cancel or query it independently
	- Fuse timing is backed by Promise for clean cancellation
]]

local Identity = "FuseController"

-- ─── Services ────────────────────────────────────────────────────────────────

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ─── References ──────────────────────────────────────────────────────────────

local Utilities = ReplicatedStorage.Shared.Modules.Utilities

-- ─── Modules ─────────────────────────────────────────────────────────────────

local Signal     = require(Utilities:FindFirstChild("Signal"))
local LogService = require(Utilities:FindFirstChild("Logger"))
local Promise    = require(Utilities.Promise)

-- ─── Module ──────────────────────────────────────────────────────────────────

local FuseController   = {}
FuseController.__index = FuseController
FuseController.__type  = Identity

-- ─── Private state ───────────────────────────────────────────────────────────

local Logger = LogService.new(Identity, false)

-- ─── Getters ─────────────────────────────────────────────────────────────────

--- Returns how many seconds have elapsed since cooking started (0 if not cooking).
function FuseController.GetElapsedCookTime(self: FuseController): number
	if not self._IsCooking then return self._CookedTime end
	return os.clock() - self._CookStartTime
end

--- Returns whether the grenade is currently being cooked.
function FuseController.IsCooking(self: FuseController): boolean
	return self._IsCooking
end

--- Returns whether any fuse is currently active.
function FuseController.IsFuseActive(self: FuseController): boolean
	return self._ActiveFuseCount > 0
end

--- Returns the fuse state snapshot.
function FuseController.GetState(self: FuseController)
	return {
		IsCooking     = self._IsCooking,
		IsFuseActive  = self:IsFuseActive(),
		ActiveFuses   = self._ActiveFuseCount,
		CookedTime    = self:GetElapsedCookTime(),
		TotalFuseTime = self.FuseTime,
	}
end

-- ─── Cook ────────────────────────────────────────────────────────────────────

--- Starts cooking the grenade. No-op if already cooking.
function FuseController.StartCook(self: FuseController)
	if self._IsCooking then
		Logger:Debug("StartCook: already cooking")
		return
	end

	self._IsCooking     = true
	self._CookStartTime = os.clock()
	self._CookedTime    = 0

	Logger:Print("StartCook: cooking started")
end

--- Cancels an in-progress cook and resets cooked time.
--- Does NOT affect any already-thrown fuse handles.
function FuseController.CancelCook(self: FuseController)
	if not self._IsCooking then return end

	self._IsCooking  = false
	self._CookedTime = 0

	Logger:Print("CancelCook: cook cancelled, cooked time reset")
end

-- ─── Fuse ────────────────────────────────────────────────────────────────────

--[[
	Starts a fuse countdown for one thrown grenade.

	Snapshots the current cooked time, computes the remaining fuse duration,
	and calls onExpired when the timer runs out. Returns a FuseHandle whose
	underlying Promise can be cancelled independently from any other active fuses.

	Cancelling the handle rejects the Promise, so onExpired is never called.

	@param onExpired function — called when this specific fuse expires
	@return FuseHandle
]]
function FuseController.StartFuse(self: FuseController, onExpired: () -> ()): FuseHandle
	local cookedTime  = self:GetElapsedCookTime()
	self._IsCooking   = false
	self._CookedTime  = 0

	local remaining   = math.max(0, self.FuseTime - cookedTime)
	local startTime   = os.clock()
	self._ActiveFuseCount += 1

	Logger:Print(string.format(
		"StartFuse: fuse=%.2fs cooked=%.2fs remaining=%.2fs (active=%d)",
		self.FuseTime, cookedTime, remaining, self._ActiveFuseCount
		))

	local handle: FuseHandle = {
		_startTime = startTime,
		_duration  = remaining,
		_promise   = nil,
	}

	handle._promise = Promise.delay(remaining)
		:andThen(function()
			self._ActiveFuseCount = math.max(0, self._ActiveFuseCount - 1)

			Logger:Print(string.format(
				"StartFuse: fuse expired (active=%d)",
				self._ActiveFuseCount
				))

			self.Signals.OnFuseExpired:Fire()

			if onExpired then
				onExpired()
			end
		end)
		:catch(function(err)
			-- Cancelled promises are silent — any other rejection is worth logging
			if err ~= Promise.Error.Kind.AlreadyCancelled then
				Logger:Warn(string.format("StartFuse: promise rejected unexpectedly — %s", tostring(err)))
			end
		end)

	self.Signals.OnFuseStarted:Fire()
	return handle
end

--- Cancels a specific fuse handle returned by StartFuse.
--- Safe to call even if the fuse has already expired or been cancelled.
function FuseController.CancelFuse(self: FuseController, handle: FuseHandle)
	if not handle then return end

	local p = handle._promise
	if not p or p:getStatus() ~= Promise.Status.Started then return end

	self._ActiveFuseCount = math.max(0, self._ActiveFuseCount - 1)
	p:cancel()

	Logger:Print(string.format(
		"CancelFuse: handle cancelled (active=%d)",
		self._ActiveFuseCount
		))
end

--- Returns how many seconds remain on a specific fuse handle.
--- Returns 0 if the handle is no longer pending.
function FuseController.GetHandleRemainingTime(_self: FuseController, handle: FuseHandle): number
	if not handle or not handle._promise or handle._promise:getStatus() ~= Promise.Status.Started then return 0 end
	local elapsed = os.clock() - handle._startTime
	return math.max(0, handle._duration - elapsed)
end

--- Returns whether a handle's fuse is still counting down.
function FuseController.IsHandleActive(_self: FuseController, handle: FuseHandle): boolean
	return handle ~= nil and handle._promise ~= nil and handle._promise:isPending()
end

-- ─── Lifecycle ───────────────────────────────────────────────────────────────

--- Cleans up the FuseController.
--- In-flight handles are the caller's responsibility — cancel them before destroying.
function FuseController.Destroy(self: FuseController)
	Logger:Print("Destroy: cleaning up FuseController")

	self:CancelCook()

	for _, signal in pairs(self.Signals) do
		signal:Destroy()
	end

	Logger:Debug("Destroy: complete")
end

-- ─── Constructor ─────────────────────────────────────────────────────────────

local module = {}

--- Creates a new FuseController.
--- @param fuseTime number — total fuse duration in seconds
function module.new(fuseTime: number): FuseController
	assert(fuseTime and fuseTime > 0, "FuseController.new: fuseTime must be a positive number")

	local self: FuseController = setmetatable({}, { __index = FuseController })

	self.FuseTime         = fuseTime
	self._IsCooking       = false
	self._CookStartTime   = 0
	self._CookedTime      = 0
	self._ActiveFuseCount = 0

	self.Signals = {
		OnFuseStarted = Signal.new(),
		OnFuseExpired = Signal.new(),
	}

	Logger:Debug(string.format("new: FuseTime=%.2fs", fuseTime))
	return self
end

-- ─── Types ───────────────────────────────────────────────────────────────────

export type FuseHandle = {
	_startTime : number,
	_duration  : number,
	_promise   : any, -- Promise
}

export type FuseController = typeof(setmetatable({}, { __index = FuseController })) & {
	FuseTime          : number,
	_IsCooking        : boolean,
	_CookStartTime    : number,
	_CookedTime       : number,
	_ActiveFuseCount  : number,
	Signals : {
		OnFuseStarted : Signal.Signal<() -> ()>,
		OnFuseExpired : Signal.Signal<() -> ()>,
	},
}

return table.freeze(module)