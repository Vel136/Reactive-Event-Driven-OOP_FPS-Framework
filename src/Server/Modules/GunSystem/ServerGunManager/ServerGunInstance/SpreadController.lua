-- SpreadController.lua
--[[
	CS:GO-style deterministic spread system
	- Learnable, repeating patterns
	- Automatic recovery
	- Aiming vs Base spread profiles
]]

local Identity = "SpreadController"

-- ─── Services ────────────────────────────────────────────────────────────────

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ─── References ──────────────────────────────────────────────────────────────

local Utilities = ReplicatedStorage.Shared.Modules.Utilities

-- ─── Modules ─────────────────────────────────────────────────────────────────

local t          = require(Utilities:FindFirstChild("TypeCheck"))
local LogService = require(Utilities:FindFirstChild("Logger"))
local Signal     = require(Utilities:FindFirstChild("Signal"))

-- ─── Constants ───────────────────────────────────────────────────────────────

local PATTERN_SIZE   = 8
local GOLDEN_ANGLE   = 137.508

-- ─── Module ──────────────────────────────────────────────────────────────────

local SpreadController   = {}
SpreadController.__index = SpreadController
SpreadController.__type  = Identity

-- ─── Private state ───────────────────────────────────────────────────────────

local Logger = LogService.new(Identity, false)

-- ─── Getters ─────────────────────────────────────────────────────────────────

--- Returns the current spread value, accounting for recovery.
function SpreadController.GetCurrentSpread(self: SpreadController): number
	local profile = self:_GetSpreadProfile()
	local timeSinceLastShot = os.clock() - self.StateManager.LastShootTime

	if timeSinceLastShot < profile.RecoveryTime then
		return self._CurrentSpread
	end

	local recoveryDuration = timeSinceLastShot - profile.RecoveryTime
	local recovered = profile.DecreasePerSecond * recoveryDuration

	return math.max(profile.Min, self._CurrentSpread - recovered)
end

--- Returns the current shot index.
function SpreadController.GetShotIndex(self: SpreadController): number
	return self._ShotIndex
end

--- Returns the current spread state snapshot.
function SpreadController.GetState(self: SpreadController)
	return {
		CurrentSpread = self:GetCurrentSpread(),
		ShotIndex     = self:GetShotIndex(),
		Profile       = self:_GetSpreadProfile(),
		IsAiming      = self.StateManager:IsAiming(),
	}
end

--- Returns the metadata table.
function SpreadController.GetMetadata(self: SpreadController)
	return self._Metadata
end

-- ─── Setters ─────────────────────────────────────────────────────────────────

--- Sets the current spread value.
function SpreadController.SetSpread(self: SpreadController, amount: number): number
	if not t.number(amount) then
		Logger:Warn("SetSpread: invalid spread amount")
		return self._CurrentSpread
	end

	local old = self._CurrentSpread
	self._CurrentSpread = amount

	if old ~= amount then
		Logger:Debug(string.format("SetSpread: %.2f -> %.2f", old, amount))
	end

	return self._CurrentSpread
end

--- Sets the current shot index.
function SpreadController.SetShotIndex(self: SpreadController, index: number)
	if not t.number(index) then
		Logger:Warn("SetShotIndex: invalid shot index")
		return
	end

	self._ShotIndex = index
	Logger:Debug(string.format("SetShotIndex: %d", index))
end

--- Sets the metadata table.
function SpreadController.SetMetadata(self: SpreadController, metadata: any)
	self._Metadata = metadata
end

-- ─── Reset helpers ───────────────────────────────────────────────────────────

--- Resets spread to the minimum of the current profile.
function SpreadController.ResetSpread(self: SpreadController)
	local profile = self:_GetSpreadProfile()
	self:SetSpread(profile.Min)
	Logger:Print(string.format("ResetSpread: %.2f", profile.Min))
end

--- Resets the shot pattern index to 0.
function SpreadController.ResetPattern(self: SpreadController)
	self:SetShotIndex(0)
	Logger:Print("ResetPattern: pattern reset")
end

--- Resets both spread and pattern.
function SpreadController.ResetAll(self: SpreadController)
	self:ResetSpread()
	self:ResetPattern()
	Logger:Print("ResetAll: complete")
end

-- ─── Spread application ──────────────────────────────────────────────────────

--- Applies spread to a direction vector and returns the deflected direction.
function SpreadController.ApplySpread(self: SpreadController, direction: Vector3): Vector3
	if not t.Vector3(direction) then
		Logger:Warn("ApplySpread: invalid direction vector")
		return direction
	end

	local profile      = self:_GetSpreadProfile()
	local currentSpread = self:GetCurrentSpread()

	local newSpread = math.clamp(
		currentSpread + profile.IncreasePerShot,
		profile.Min,
		profile.Max
	)
	self:SetSpread(newSpread)

	local newShotIndex = self:GetShotIndex() + 1
	self:SetShotIndex(newShotIndex)

	local offsetX, offsetY = self:_GetSeededOffset(newShotIndex)

	local angleRad        = math.rad(newSpread)
	local spreadMagnitude = math.sin(angleRad)

	local localDir = Vector3.new(offsetX * spreadMagnitude, offsetY * spreadMagnitude, -1).Unit
	local rot      = CFrame.lookAt(Vector3.zero, direction)

	return rot:VectorToWorldSpace(localDir).Unit
end

-- ─── Event handlers ──────────────────────────────────────────────────────────

--- Called when aim state changes; resets spread and pattern for the new profile.
function SpreadController.OnAimChanged(self: SpreadController, isAiming: boolean)
	local profile = isAiming and self.Data.Aiming or self.Data.Base
	self:SetSpread(profile.Min)
	self:SetShotIndex(0)
	Logger:Print(string.format("OnAimChanged: reset spread to %.2f", profile.Min))
end

-- ─── Internal ────────────────────────────────────────────────────────────────

--- Returns the active spread profile based on current aim state.
function SpreadController._GetSpreadProfile(self: SpreadController)
	return self.StateManager:IsAiming() and self.Data.Aiming or self.Data.Base
end

--- Circle pattern: evenly distributes shots around a circle.
function SpreadController._GetSeededOffset_CirclePattern(self: SpreadController, shotIndex: number)
	local patternIndex = (shotIndex - 1) % PATTERN_SIZE
	local angle        = math.rad(patternIndex * (360 / PATTERN_SIZE))
	return math.cos(angle), math.sin(angle)
end

--- Reset spiral: golden angle distribution that resets every PATTERN_SIZE shots.
function SpreadController._GetSeededOffset_ResetSpiral(self: SpreadController, shotIndex: number)
	local patternIndex = (shotIndex - 1) % PATTERN_SIZE
	local angle        = math.rad(patternIndex * GOLDEN_ANGLE)
	local radius       = patternIndex / PATTERN_SIZE
	return math.cos(angle) * radius, math.sin(angle) * radius
end

--- Infinite spiral: golden angle distribution that never resets.
function SpreadController._GetSeededOffset_InfiniteSpiral(self: SpreadController, shotIndex: number)
	local angle  = math.rad(shotIndex * GOLDEN_ANGLE)
	local radius = ((shotIndex - 1) % PATTERN_SIZE) / PATTERN_SIZE
	return math.cos(angle) * radius, math.sin(angle) * radius
end

--- Returns the pattern offset for the given shot index (defaults to circle).
function SpreadController._GetSeededOffset(self: SpreadController, shotIndex: number)
	return self:_GetSeededOffset_CirclePattern(shotIndex)
	-- or: return self:_GetSeededOffset_ResetSpiral(shotIndex)
	-- or: return self:_GetSeededOffset_InfiniteSpiral(shotIndex)
end

-- ─── Lifecycle ───────────────────────────────────────────────────────────────

--- Cleans up the SpreadController.
function SpreadController.Destroy(self: SpreadController)
	Logger:Print("Destroy: cleaning up SpreadController")

	self.StateManager = nil
	self.Data         = nil

	Logger:Debug("Destroy: complete")
end

-- ─── Constructor ─────────────────────────────────────────────────────────────

local module = {}

--- Creates a new SpreadController.
function module.new(spreadData: SpreadData, stateManager: any, metadata: any?)
	local self: SpreadController = setmetatable({}, { __index = SpreadController })

	self.Data         = spreadData
	self.StateManager = stateManager

	self._CurrentSpread = spreadData.Base.Min
	self._ShotIndex     = 0
	self._Metadata      = metadata or {}

	Logger:Debug(string.format(
		"new: Base(%.2f–%.2f) Aiming(%.2f–%.2f)",
		spreadData.Base.Min,   spreadData.Base.Max,
		spreadData.Aiming.Min, spreadData.Aiming.Max
		))

	return self
end

-- ─── Types ───────────────────────────────────────────────────────────────────

export type SpreadProfile = {
	Min              : number,
	Max              : number,
	IncreasePerShot  : number,
	DecreasePerSecond: number,
	RecoveryTime     : number,
}

export type SpreadData = {
	Base   : SpreadProfile,
	Aiming : SpreadProfile,
}

export type SpreadController = typeof(setmetatable({}, { __index = SpreadController })) & {
	Data            : SpreadData,
	StateManager    : any,
	_CurrentSpread  : number,
	_ShotIndex      : number,
	_Metadata       : any,
}

return table.freeze(module)