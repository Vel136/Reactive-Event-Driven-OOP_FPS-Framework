-- DamageCalculator.lua
--[[
	Pure damage calculation functions including:
	- Range-based damage falloff
	- Base damage calculation
	- Bonus damage hooks (override in subclasses)
]]

local ReplicatedStorage = game:GetService('ReplicatedStorage')
local Utilities = ReplicatedStorage.SharedModules.Utilities
local t = require(Utilities:FindFirstChild("TypeCheck"))
local Logger = require(Utilities:FindFirstChild("LogService"))

local DamageCalculator = {}
DamageCalculator.__index = DamageCalculator

--[[
	Creates a new DamageCalculator
	@param damageData - Damage configuration from weapon data
	@return DamageCalculator instance
]]
function DamageCalculator.new(damageData)
	local self = setmetatable({}, DamageCalculator)

	self.Data = damageData

	return self
end

--[[
	Calculates base damage based on distance with linear falloff
	@param distance - Distance to target
	@return number - Calculated damage
]]
function DamageCalculator:CalculateBaseDamage(distance: number): number
	if not t.number(distance) then
		Logger.Warn("[DamageCalculator] Invalid distance")
		return 0
	end

	local minDamage = self.Data.Min or 20
	local maxDamage = self.Data.Max or 50
	local minRange = self.Data.Range.Min or 0
	local maxRange = self.Data.Range.Max or 300

	-- Close range - maximum damage
	if distance <= minRange then
		return maxDamage
	end

	-- Far range - minimum damage
	if distance >= maxRange then
		return minDamage
	end

	-- Linear interpolation between min and max range
	local alpha = (distance - minRange) / (maxRange - minRange)
	return maxDamage - (maxDamage - minDamage) * alpha
end

--[[
	Calculates total damage including bonus modifiers
	Can be overridden in weapon subclasses for special damage calculation
	@param distance - Distance to target
	@param cast - FastCast cast object
	@param result - RaycastResult
	@param velocity - Bullet velocity
	@param bullet - Bullet part
	@return number - Total damage
]]
function DamageCalculator:CalculateTotalDamage(distance: number, cast: any?, result: RaycastResult?, velocity: Vector3?, bullet: any?): number
	local baseDamage = self:CalculateBaseDamage(distance)
	local bonusDamage = self:CalculateBonusDamage(cast, result, velocity, bullet)

	return baseDamage + bonusDamage
end

--[[
	Override this in subclasses for custom bonus damage
	Examples: headshot multipliers, penetration damage, critical hits
	@param cast - FastCast cast object
	@param result - RaycastResult
	@param velocity - Bullet velocity
	@param bullet - Bullet part
	@return number - Bonus damage (default: 0)
]]
function DamageCalculator:CalculateBonusDamage(cast: any?, result: RaycastResult?, velocity: Vector3?, bullet: any?): number
	-- Override in subclasses for custom behavior
	-- Example: Check if result.Instance.Name == "Head" then return baseDamage * 0.5
	return 0
end

--[[
	Gets damage at specific range (utility function)
	@param range - Distance to check
	@return number - Damage at that range
]]
function DamageCalculator:GetDamageAtRange(range: number): number
	return self:CalculateBaseDamage(range)
end

--[[
	Gets the effective range where damage is above threshold
	@param minEffectiveDamage - Minimum damage threshold
	@return number - Maximum effective range
]]
function DamageCalculator:GetEffectiveRange(minEffectiveDamage: number): number
	local minDamage = self.Data.Min or 20
	local maxDamage = self.Data.Max or 50
	local minRange = self.Data.Range.Min or 0
	local maxRange = self.Data.Range.Max or 300

	-- If threshold is below min damage, return max range
	if minEffectiveDamage <= minDamage then
		return maxRange
	end

	-- If threshold is above max damage, return min range
	if minEffectiveDamage >= maxDamage then
		return minRange
	end

	-- Calculate range where damage equals threshold
	local alpha = (maxDamage - minEffectiveDamage) / (maxDamage - minDamage)
	return minRange + (maxRange - minRange) * alpha
end

--[[
	Cleanup
]]
function DamageCalculator:Destroy()
	self.Data = nil
end

return DamageCalculator