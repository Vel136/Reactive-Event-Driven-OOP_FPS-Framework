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

	local baseDamage = self.Data.Base or 25
	local minRange = self.Data.Range.Min or 0
	local maxRange = self.Data.Range.Max or 800
	local dropoff = self.Data.Range.Dropoff or 0.3

	-- Close range - maximum damage
	if distance <= minRange then
		return baseDamage
	end

	-- Far range - minimum damage (base * dropoff)
	local minDamage = baseDamage * dropoff
	if distance >= maxRange then
		return minDamage
	end

	-- Linear interpolation between min and max range
	local alpha = (distance - minRange) / (maxRange - minRange)
	return baseDamage - (baseDamage - minDamage) * alpha
end

--[[
	Calculates total damage including bonus modifiers
	Can be overridden in weapon subclasses for special damage calculation
	@param Context - Context data (weapon, player, etc.)
	@param Hitdata - Hit information (Instance, Distance, etc.)
	@return number - Total damage
]]
function DamageCalculator:CalculateTotalDamage(Context, Hitdata): number
	if not Context or not Hitdata then 
		Logger.Warn("[DamageCalculator] Invalid Context or Hitdata")
		return 0 
	end

	local baseDamage = self:CalculateBaseDamage(Hitdata.Distance or 0)
	local bonusDamage = self:CalculateBonusDamage(Context, Hitdata)
	local multiplier = self:GetBodyPartMultiplier(Hitdata.Instance)

	-- Apply body part multiplier to base damage, then add bonus
	return (baseDamage * multiplier) + bonusDamage
end

--[[
	Gets the damage multiplier for a specific body part
	@param hitPart - The part that was hit
	@return number - Multiplier value (defaults to 1.0)
]]
function DamageCalculator:GetBodyPartMultiplier(hitPart: BasePart): number
	if not hitPart then return 1.0 end

	local multipliers = self.Data.Multipliers
	if not multipliers then return 1.0 end

	local partName = hitPart.Name

	-- Check for exact match first
	if multipliers[partName] then
		return multipliers[partName]
	end

	-- Check for common humanoid body parts
	local bodyPartMap = {
		["Head"] = "Head",
		["UpperTorso"] = "UpperTorso",
		["LowerTorso"] = "LowerTorso",
		["LeftUpperArm"] = "LeftArm",
		["LeftLowerArm"] = "LeftArm",
		["LeftHand"] = "LeftArm",
		["RightUpperArm"] = "RightArm",
		["RightLowerArm"] = "RightArm",
		["RightHand"] = "RightArm",
		["LeftUpperLeg"] = "LeftLeg",
		["LeftLowerLeg"] = "LeftLeg",
		["LeftFoot"] = "LeftLeg",
		["RightUpperLeg"] = "RightLeg",
		["RightLowerLeg"] = "RightLeg",
		["RightFoot"] = "RightLeg",
	}

	local mappedPart = bodyPartMap[partName]
	if mappedPart and multipliers[mappedPart] then
		return multipliers[mappedPart]
	end

	-- Default multiplier
	return 1.0
end

--[[
	Override this in subclasses for custom bonus damage
	Examples: headshot multipliers, penetration damage, critical hits
	@param Context - Context data
	@param Hitdata - Hit information
	@return number - Bonus damage to add
]]
function DamageCalculator:CalculateBonusDamage(Context, Hitdata): number
	if not Context or not Hitdata then 
		return 0 
	end

	-- Base implementation returns 0
	-- Override in weapon-specific subclasses for special mechanics
	return 0
end

--[[
	Calculates penetration damage reduction
	@param penetrationCount - Number of objects already penetrated
	@return number - Damage multiplier (0-1)
]]
function DamageCalculator:CalculatePenetrationDamage(penetrationCount: number): number
	if not self.Data.Penetration or not self.Data.Penetration.Enabled then
		return 0
	end

	local maxPenetrations = self.Data.Penetration.MaxCount or 0
	if penetrationCount >= maxPenetrations then
		return 0
	end

	local lossPerWall = self.Data.Penetration.LossPerWall or 0.5
	local damageMultiplier = math.max(0, 1 - (lossPerWall * penetrationCount))

	return damageMultiplier
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
	local baseDamage = self.Data.Base or 25
	local minRange = self.Data.Range.Min or 0
	local maxRange = self.Data.Range.Max or 800
	local dropoff = self.Data.Range.Dropoff or 0.3
	local minDamage = baseDamage * dropoff

	-- If threshold is below min damage, return max range
	if minEffectiveDamage <= minDamage then
		return maxRange
	end

	-- If threshold is above max damage, return min range
	if minEffectiveDamage >= baseDamage then
		return minRange
	end

	-- Calculate range where damage equals threshold
	local alpha = (baseDamage - minEffectiveDamage) / (baseDamage - minDamage)
	return minRange + (maxRange - minRange) * alpha
end

--[[
	Cleanup
]]
function DamageCalculator:Destroy()
	self.Data = nil
end

return DamageCalculator