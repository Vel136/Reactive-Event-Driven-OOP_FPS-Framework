-- SpreadController.lua
--[[
	Manages weapon spread mechanics including:
	- Spread accumulation per shot
	- Automatic spread recovery
	- Aiming vs Base spread profiles
	- Directional spread application
]]

local ReplicatedStorage = game:GetService('ReplicatedStorage')
local Utilities = ReplicatedStorage.SharedModules.Utilities
local t = require(Utilities:FindFirstChild("TypeCheck"))
local Logger = require(Utilities:FindFirstChild("LogService"))
local Signal = require(Utilities:FindFirstChild("Signal"))
local Observer = require(Utilities:FindFirstChild('Observer'))
local SpreadController = {}
SpreadController.__index = SpreadController

--[[
	Creates a new SpreadController
	@param spreadData - Spread configuration from weapon data
	@param stateManager - Reference to StateManager for aiming state
	@return SpreadController instance
]]
function SpreadController.new(spreadData, stateManager)
	local self = setmetatable({}, SpreadController)

	self.Data = spreadData
	self.StateManager = stateManager

	-- Tracking
	self.CurrentSpread = Instance.new("IntValue")
	self.CurrentSpread.Value = spreadData.Base.Min
	self.LastShootTime = 0
	return self
end

--[[
	Gets the current spread profile based on aiming state
	@return table - Current spread profile (Base or Aiming)
]]
function SpreadController:_GetSpreadProfile()
	local isAiming = self.StateManager:IsAiming()
	return isAiming and self.Data.Aiming or self.Data.Base
end

--[[
	Calculates current spread with automatic recovery
	@return number - Current spread value in degrees
]]
function SpreadController:GetCurrentSpread()
	local profile = self:_GetSpreadProfile()
	local timeSinceLastShot = os.clock() - self.LastShootTime

	-- Not yet in recovery phase
	if timeSinceLastShot < profile.RecoveryTime then
		return self.CurrentSpread.Value
	end

	-- Calculate recovered amount
	local recoveryDuration = timeSinceLastShot - profile.RecoveryTime
	local recovered = profile.DecreasePerSecond * recoveryDuration

	return math.max(
		profile.Min,
		self.CurrentSpread.Value - recovered
	)
end

--[[
	Applies spread to a direction vector using cone distribution
	@param direction - Base direction vector
	@return Vector3 - Direction with spread applied
]]
function SpreadController:ApplySpread(direction: Vector3): Vector3
	if not t.Vector3(direction) then 
		Logger.Warn("[SpreadController] Invalid direction vector")
		return direction 
	end

	local profile = self:_GetSpreadProfile()

	-- Get current spread (with automatic recovery)
	local currentSpread = self:GetCurrentSpread()

	-- Increase spread for this shot
	local newSpread = math.clamp(
		currentSpread + profile.IncreasePerShot,
		profile.Min,
		profile.Max
	)

	self.CurrentSpread.Value = newSpread
	self.LastShootTime = os.clock()

	-- Cone math for random spread within cone
	local angleRad = math.rad(newSpread)
	local cosTheta = math.cos(angleRad)

	local z = cosTheta + (1 - cosTheta) * math.random()
	local phi = math.random() * math.pi * 2
	local sinT = math.sqrt(1 - z * z)

	local x = sinT * math.cos(phi)
	local y = sinT * math.sin(phi)

	local localDir = Vector3.new(x, y, -z)
	local rot = CFrame.lookAt(Vector3.zero, direction)

	return rot:VectorToWorldSpace(localDir).Unit
end

--[[
	Manually sets spread value
	@param amount - Spread amount to set
	@return number - New spread value
]]
function SpreadController:SetSpread(amount: number): number
	if not t.number(amount) then 
		Logger.Warn("Invalid spread amount","[SpreadController]")
		return self.CurrentSpread.Value 
	end

	self.CurrentSpread.Value = amount
	return self.CurrentSpread.Value
end

--[[
	Resets spread to minimum (called on aim state change)
	@param isAiming - New aiming state
]]
function SpreadController:OnAimChanged(isAiming: boolean)
	local profile = isAiming and self.Data.Aiming or self.Data.Base
	self.CurrentSpread.Value = profile.Min
	Logger.Print("Reset spread to: "..self.CurrentSpread.Value,"[SpreadController]")
end

--[[
	Updates the last shoot time (called externally after firing)
]]
function SpreadController:UpdateShootTime()
	self.LastShootTime = os.clock()
end

--[[
	Cleanup
]]
function SpreadController:Destroy()
	if self.CurrentSpread then
		self.CurrentSpread:Destroy()
	end
	self.StateManager = nil
	self.Data = nil
end

return SpreadController