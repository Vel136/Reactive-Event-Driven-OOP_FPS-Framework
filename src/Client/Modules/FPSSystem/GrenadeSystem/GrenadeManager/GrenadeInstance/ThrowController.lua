-- ThrowController.lua
--[[
	Handles grenade throw mechanics:
	- Velocity calculation from direction and charge
	- Charge system (hold to throw farther)
	- Underhand / overhand throw force profiles
]]

local Identity = "ThrowController"

-- ─── Services ────────────────────────────────────────────────────────────────

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ─── References ──────────────────────────────────────────────────────────────

local Utilities = ReplicatedStorage.Shared.Modules.Utilities

-- ─── Modules ─────────────────────────────────────────────────────────────────

local Signal     = require(Utilities:FindFirstChild("Signal"))
local LogService = require(Utilities:FindFirstChild("Logger"))

-- ─── Module ──────────────────────────────────────────────────────────────────

local ThrowController   = {}
ThrowController.__index = ThrowController
ThrowController.__type  = Identity

-- ─── Private state ───────────────────────────────────────────────────────────

local Logger = LogService.new(Identity, false)

-- ─── Getters ─────────────────────────────────────────────────────────────────

--- Returns the current charge (0–1).
function ThrowController.GetCharge(self: ThrowController): number
	if not self._IsCharging then return 0 end

	local elapsed = os.clock() - self._ChargeStartTime
	return math.clamp(elapsed / self.Data.MaxChargeTime, 0, 1)
end

--- Returns whether the throw is currently being charged.
function ThrowController.IsCharging(self: ThrowController): boolean
	return self._IsCharging
end

--- Returns the throw state snapshot.
function ThrowController.GetState(self: ThrowController)
	return {
		IsCharging = self._IsCharging,
		Charge     = self:GetCharge(),
		MinForce   = self.Data.MinForce,
		MaxForce   = self.Data.MaxForce,
	}
end

-- ─── Charge ──────────────────────────────────────────────────────────────────

--- Begins charging the throw. No-op if already charging.
function ThrowController.StartCharge(self: ThrowController)
	if self._IsCharging then
		Logger:Debug("StartCharge: already charging")
		return
	end

	self._IsCharging      = true
	self._ChargeStartTime = os.clock()
	self.Signals.OnChargeStarted:Fire()

	Logger:Print("StartCharge: charge started")
end

--- Cancels an in-progress charge without throwing.
function ThrowController.CancelCharge(self: ThrowController)
	if not self._IsCharging then return end

	self._IsCharging      = false
	self._ChargeStartTime = 0
	self.Signals.OnChargeCancelled:Fire()

	Logger:Print("CancelCharge: charge cancelled")
end

--- Commits the charge and returns the final charge value (0–1), then resets.
function ThrowController.CommitCharge(self: ThrowController): number
	local charge = self:GetCharge()

	self._IsCharging      = false
	self._ChargeStartTime = 0

	Logger:Debug(string.format("CommitCharge: %.2f", charge))
	return charge
end

-- ─── Velocity calculation ────────────────────────────────────────────────────

--- Calculates the throw velocity vector from a direction and optional force override.
--- If force is not provided, uses the current charge to interpolate between min and max force.
function ThrowController.CalculateVelocity(self: ThrowController, direction: Vector3, force: number?): Vector3
	local throwForce

	if force then
		throwForce = force
	else
		local charge = self:CommitCharge()
		throwForce   = self.Data.MinForce + (self.Data.MaxForce - self.Data.MinForce) * charge
	end

	-- Apply a slight upward arc so the grenade doesn't fly flat
	local arcedDirection = (direction + Vector3.new(0, self.Data.ArcBias or 0.2, 0)).Unit
	local velocity       = arcedDirection * throwForce

	Logger:Debug(string.format(
		"CalculateVelocity: force=%.1f arc=%.2f velocity=%s",
		throwForce,
		self.Data.ArcBias or 0.2,
		tostring(velocity)
		))

	self.Signals.OnVelocityCalculated:Fire(velocity, throwForce)
	return velocity
end

-- ─── Lifecycle ───────────────────────────────────────────────────────────────

--- Cleans up the ThrowController.
function ThrowController.Destroy(self: ThrowController)
	Logger:Print("Destroy: cleaning up ThrowController")

	for _, signal in pairs(self.Signals) do
		signal:Destroy()
	end

	self.Data = nil
	Logger:Debug("Destroy: complete")
end

-- ─── Constructor ─────────────────────────────────────────────────────────────

local module = {}

--- Creates a new ThrowController.
function module.new(throwData: ThrowData): ThrowController
	assert(throwData,          "ThrowController.new: throwData is required")
	assert(throwData.MinForce, "ThrowController.new: missing MinForce")
	assert(throwData.MaxForce, "ThrowController.new: missing MaxForce")

	local self: ThrowController = setmetatable({}, { __index = ThrowController })

	self.Data             = throwData
	self._IsCharging      = false
	self._ChargeStartTime = 0

	self.Signals = {
		OnChargeStarted      = Signal.new(),
		OnChargeCancelled    = Signal.new(),
		OnVelocityCalculated = Signal.new(),
	}

	Logger:Debug(string.format("new: MinForce=%.1f MaxForce=%.1f MaxChargeTime=%.1fs ArcBias=%.2f",
		throwData.MinForce,
		throwData.MaxForce,
		throwData.MaxChargeTime or 1,
		throwData.ArcBias       or 0.2
		))

	return self
end

-- ─── Types ───────────────────────────────────────────────────────────────────

export type ThrowData = {
	MinForce      : number, -- Force when thrown instantly (no charge)
	MaxForce      : number, -- Force at full charge
	MaxChargeTime : number, -- Seconds to reach full charge
	ArcBias       : number, -- Upward angle added to direction (default 0.2)
}

export type ThrowController = typeof(setmetatable({}, { __index = ThrowController })) & {
	Data             : ThrowData,
	_IsCharging      : boolean,
	_ChargeStartTime : number,
	Signals : {
		OnChargeStarted      : Signal.Signal<() -> ()>,
		OnChargeCancelled    : Signal.Signal<() -> ()>,
		OnVelocityCalculated : Signal.Signal<(velocity: Vector3, force: number) -> ()>,
	},
}

return table.freeze(module)