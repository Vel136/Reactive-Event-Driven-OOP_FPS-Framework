-- DamageCalculator.lua
--[[
	Pure damage calculation functions including:
	- Range-based damage falloff
	- Base damage calculation
	- Bonus damage hooks (override in subclasses)
	- Body part multipliers
	- Penetration calculations
]]

local Identity = "DamageCalculator"

-- ─── Services ────────────────────────────────────────────────────────────────

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ─── References ──────────────────────────────────────────────────────────────

local Utilities = ReplicatedStorage.Shared.Modules.Utilities

-- ─── Modules ─────────────────────────────────────────────────────────────────

local t          = require(Utilities:FindFirstChild("TypeCheck"))
local LogService = require(Utilities:FindFirstChild("Logger"))

-- ─── Module ──────────────────────────────────────────────────────────────────

local DamageCalculator   = {}
DamageCalculator.__index = DamageCalculator
DamageCalculator.__type  = Identity

-- ─── Private state ───────────────────────────────────────────────────────────

local Logger = LogService.new(Identity, false)

local BODY_PART_MAP = {
	LeftUpperArm  = "LeftArm",
	LeftLowerArm  = "LeftArm",
	LeftHand      = "LeftArm",
	RightUpperArm = "RightArm",
	RightLowerArm = "RightArm",
	RightHand     = "RightArm",
	LeftUpperLeg  = "LeftLeg",
	LeftLowerLeg  = "LeftLeg",
	LeftFoot      = "LeftLeg",
	RightUpperLeg = "RightLeg",
	RightLowerLeg = "RightLeg",
	RightFoot     = "RightLeg",
}

-- ─── Getters: data ───────────────────────────────────────────────────────────

--- Returns the base damage value.
function DamageCalculator.GetBaseDamage(self: DamageCalculator): number
	return self.Data.Base or 25
end

--- Returns the minimum range value.
function DamageCalculator.GetMinRange(self: DamageCalculator): number
	return self.Data.Range.Min or 0
end

--- Returns the maximum range value.
function DamageCalculator.GetMaxRange(self: DamageCalculator): number
	return self.Data.Range.Max or 800
end

--- Returns the damage dropoff multiplier (0–1).
function DamageCalculator.GetDropoff(self: DamageCalculator): number
	return self.Data.Range.Dropoff or 0.3
end

--- Returns the minimum damage (base × dropoff).
function DamageCalculator.GetMinDamage(self: DamageCalculator): number
	return self:GetBaseDamage() * self:GetDropoff()
end

--- Returns whether penetration is enabled.
function DamageCalculator.IsPenetrationEnabled(self: DamageCalculator): boolean
	return self.Data.Penetration and self.Data.Penetration.Enabled or false
end

--- Returns the maximum number of penetrations allowed.
function DamageCalculator.GetMaxPenetrations(self: DamageCalculator): number
	if not self:IsPenetrationEnabled() then return 0 end
	return self.Data.Penetration.MaxCount or 0
end

--- Returns the damage loss per penetrated wall (0–1).
function DamageCalculator.GetPenetrationLoss(self: DamageCalculator): number
	if not self:IsPenetrationEnabled() then return 1 end
	return self.Data.Penetration.LossPerWall or 0.5
end

--- Returns the damage multiplier for the given body part.
function DamageCalculator.GetBodyPartMultiplier(self: DamageCalculator, hitPart: BasePart): number
	if not hitPart then
		Logger:Debug("GetBodyPartMultiplier: no hit part, using 1.0x")
		return 1.0
	end

	local multipliers = self.Data.Multipliers
	if not multipliers then
		Logger:Debug("GetBodyPartMultiplier: no multipliers configured, using 1.0x")
		return 1.0
	end

	local partName = hitPart.Name

	if multipliers[partName] then
		Logger:Debug(string.format("GetBodyPartMultiplier: '%s' = %.2fx", partName, multipliers[partName]))
		return multipliers[partName]
	end

	local mappedPart = BODY_PART_MAP[partName]
	if mappedPart and multipliers[mappedPart] then
		Logger:Debug(string.format("GetBodyPartMultiplier: '%s' -> '%s' = %.2fx", partName, mappedPart, multipliers[mappedPart]))
		return multipliers[mappedPart]
	end

	Logger:Debug(string.format("GetBodyPartMultiplier: no match for '%s', using 1.0x", partName))
	return 1.0
end

--- Returns a stats summary table.
function DamageCalculator.GetDamageStats(self: DamageCalculator)
	return {
		BaseDamage         = self:GetBaseDamage(),
		MinDamage          = self:GetMinDamage(),
		MinRange           = self:GetMinRange(),
		MaxRange           = self:GetMaxRange(),
		Dropoff            = self:GetDropoff(),
		PenetrationEnabled = self:IsPenetrationEnabled(),
		MaxPenetrations    = self:GetMaxPenetrations(),
		PenetrationLoss    = self:GetPenetrationLoss(),
	}
end

--- Returns the metadata table.
function DamageCalculator.GetMetadata(self: DamageCalculator)
	return self._Metadata
end

-- ─── Setters ─────────────────────────────────────────────────────────────────

--- Sets the metadata table.
function DamageCalculator.SetMetadata(self: DamageCalculator, metadata: any)
	self._Metadata = metadata
end

-- ─── Damage calculations ─────────────────────────────────────────────────────

--- Returns base damage at the given distance with linear falloff.
function DamageCalculator.CalculateBaseDamage(self: DamageCalculator, distance: number): number
	if not t.number(distance) then
		Logger:Warn("CalculateBaseDamage: invalid distance")
		return 0
	end

	local baseDamage = self:GetBaseDamage()
	local minRange   = self:GetMinRange()
	local maxRange   = self:GetMaxRange()
	local minDamage  = self:GetMinDamage()

	if distance <= minRange then
		Logger:Debug(string.format("CalculateBaseDamage: close range (%.1f) = %.1f", distance, baseDamage))
		return baseDamage
	end

	if distance >= maxRange then
		Logger:Debug(string.format("CalculateBaseDamage: far range (%.1f) = %.1f", distance, minDamage))
		return minDamage
	end

	local alpha  = (distance - minRange) / (maxRange - minRange)
	local damage = baseDamage - (baseDamage - minDamage) * alpha

	Logger:Debug(string.format("CalculateBaseDamage: %.1f studs (a=%.2f) = %.1f", distance, alpha, damage))
	return damage
end

--- Override in subclasses for bonus damage (crits, headshots, etc.). Returns 0 by default.
function DamageCalculator.CalculateBonusDamage(self: DamageCalculator, Context: any, Hitdata: any): number
	if not Context or not Hitdata then
		Logger:Debug("CalculateBonusDamage: invalid context or hitdata")
		return 0
	end
	return 0
end

--- Returns total damage: (base × body part multiplier) + bonus.
function DamageCalculator.CalculateTotalDamage(self: DamageCalculator, Context: any, Hitdata: any): number
	if not Context or not Hitdata then
		Logger:Warn("CalculateTotalDamage: invalid Context or Hitdata")
		return 0
	end

	local baseDamage  = self:CalculateBaseDamage(Hitdata.Distance or 0)
	local multiplier  = self:GetBodyPartMultiplier(Hitdata.Instance)
	local bonusDamage = self:CalculateBonusDamage(Context, Hitdata)
	local total       = (baseDamage * multiplier) + bonusDamage

	Logger:Print(string.format(
		"CalculateTotalDamage: %.1f × %.2fx + %.1f = %.1f",
		baseDamage, multiplier, bonusDamage, total
		))

	return total
end

--- Returns the damage multiplier after penetrating the given number of walls.
function DamageCalculator.CalculatePenetrationDamage(self: DamageCalculator, penetrationCount: number): number
	if not self:IsPenetrationEnabled() then
		Logger:Debug("CalculatePenetrationDamage: penetration disabled")
		return 0
	end

	local maxPenetrations = self:GetMaxPenetrations()
	if penetrationCount >= maxPenetrations then
		Logger:Debug(string.format("CalculatePenetrationDamage: max reached (%d/%d)", penetrationCount, maxPenetrations))
		return 0
	end

	local lossPerWall      = self:GetPenetrationLoss()
	local damageMultiplier = math.max(0, 1 - (lossPerWall * penetrationCount))

	Logger:Debug(string.format(
		"CalculatePenetrationDamage: %d/%d walls, %.2f loss/wall = %.2fx",
		penetrationCount, maxPenetrations, lossPerWall, damageMultiplier
		))

	return damageMultiplier
end

-- ─── Utility queries ─────────────────────────────────────────────────────────

--- Returns the base damage at the given range.
function DamageCalculator.GetDamageAtRange(self: DamageCalculator, range: number): number
	return self:CalculateBaseDamage(range)
end

--- Returns the maximum range at which damage stays at or above the given threshold.
function DamageCalculator.GetEffectiveRange(self: DamageCalculator, minEffectiveDamage: number): number
	local baseDamage = self:GetBaseDamage()
	local minRange   = self:GetMinRange()
	local maxRange   = self:GetMaxRange()
	local minDamage  = self:GetMinDamage()

	if minEffectiveDamage <= minDamage then
		Logger:Debug(string.format("GetEffectiveRange: threshold %.1f <= min damage, returning %.1f", minEffectiveDamage, maxRange))
		return maxRange
	end

	if minEffectiveDamage >= baseDamage then
		Logger:Debug(string.format("GetEffectiveRange: threshold %.1f >= base damage, returning %.1f", minEffectiveDamage, minRange))
		return minRange
	end

	local alpha          = (baseDamage - minEffectiveDamage) / (baseDamage - minDamage)
	local effectiveRange = minRange + (maxRange - minRange) * alpha

	Logger:Debug(string.format("GetEffectiveRange: threshold %.1f -> %.1f studs", minEffectiveDamage, effectiveRange))
	return effectiveRange
end

-- ─── Lifecycle ───────────────────────────────────────────────────────────────

--- Cleans up the DamageCalculator.
function DamageCalculator.Destroy(self: DamageCalculator)
	Logger:Debug("Destroy: cleaning up DamageCalculator")
	self.Data = nil
end

-- ─── Constructor ─────────────────────────────────────────────────────────────

local module = {}

--- Creates a new DamageCalculator.
function module.new(damageData: DamageData, metadata: any?)
	local self: DamageCalculator = setmetatable({}, { __index = DamageCalculator })

	self.Data      = damageData
	self._Metadata = metadata or {}

	Logger:Debug(string.format(
		"new: Base=%.1f Range=%.1f–%.1f Dropoff=%.2f",
		damageData.Base or 25,
		damageData.Range and damageData.Range.Min or 0,
		damageData.Range and damageData.Range.Max or 800,
		damageData.Range and damageData.Range.Dropoff or 0.3
		))

	return self
end

-- ─── Types ───────────────────────────────────────────────────────────────────

export type DamageData = {
	Base        : number,
	Range: {
		Min     : number,
		Max     : number,
		Dropoff : number,
	},
	Multipliers  : { [string]: number }?,
	Penetration: {
		Enabled     : boolean,
		MaxCount    : number,
		LossPerWall : number,
	}?,
}

export type DamageCalculator = typeof(setmetatable({}, { __index = DamageCalculator })) & {
	Data      : DamageData,
	_Metadata : any,
}

return table.freeze(module)