-- SpreadController.lua
--[[
	CS:GO-style deterministic spread system
	- Learnable, repeating patterns
	- Automatic recovery
	- Aiming vs Base spread profiles
]]

local ReplicatedStorage = game:GetService('ReplicatedStorage')
local Utilities = ReplicatedStorage.SharedModules.Utilities
local t = require(Utilities:FindFirstChild("TypeCheck"))
local Logger = require(Utilities:FindFirstChild("LogService"))
local Signal = require(Utilities:FindFirstChild("Signal"))

local SpreadController = {}
SpreadController.__index = SpreadController

-- Pattern configuration
local PATTERN_SIZE = 8
local GOLDEN_ANGLE = 137.508

function SpreadController.new(spreadData, stateManager)
	local self = setmetatable({}, SpreadController)

	self.Data = spreadData
	self.StateManager = stateManager

	-- Tracking
	self.CurrentSpread = Instance.new("NumberValue")
	self.CurrentSpread.Value = spreadData.Base.Min
	self.LastShootTime = 0

	-- Pattern tracking
	self.ShotIndex = 0

	return self
end


function SpreadController:_GetSpreadProfile()
	local isAiming = self.StateManager:IsAiming()
	return isAiming and self.Data.Aiming or self.Data.Base
end


function SpreadController:GetCurrentSpread(): number
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

function SpreadController:_GetSeededOffset_CirclePattern(shotIndex: number)
	-- Distribute evenly on a circle
	local patternIndex = (shotIndex - 1) % PATTERN_SIZE
	local angle = math.rad(patternIndex * (360 / PATTERN_SIZE))

	-- All shots at edge of spread cone
	local radius = 1.0

	local x = math.cos(angle) * radius
	local y = math.sin(angle) * radius

	return x, y
end

function SpreadController:_GetSeededOffset_ResetSpiral(shotIndex: number)
	-- Reset pattern every 8 shots
	local patternIndex = (shotIndex - 1) % PATTERN_SIZE

	-- Golden angle for even distribution
	local angle = math.rad(patternIndex * GOLDEN_ANGLE)

	-- Radius grows from 0 to 1 within pattern
	local radius = patternIndex / PATTERN_SIZE

	local x = math.cos(angle) * radius
	local y = math.sin(angle) * radius

	return x, y
end


function SpreadController:_GetSeededOffset_InfiniteSpiral(shotIndex: number)

	local angle = math.rad(shotIndex * GOLDEN_ANGLE)
	local radius = ((shotIndex - 1) % PATTERN_SIZE) / PATTERN_SIZE

	local x = math.cos(angle) * radius
	local y = math.sin(angle) * radius

	return x, y
end

function SpreadController:_GetSeededOffset(shotIndex: number)
	return self:_GetSeededOffset_CirclePattern(shotIndex)
	-- or: return self:_GetSeededOffset_ResetSpiral(shotIndex)
	-- or: return self:_GetSeededOffset_InfiniteSpiral(shotIndex)
end

--[[
	Applies spread to a direction vector
	@param direction - Base direction vector
	@return Vector3 - Direction with spread applied
]]
function SpreadController:ApplySpread(direction: Vector3): Vector3
	if not t.Vector3(direction) then 
		Logger.Warn("[SpreadController] Invalid direction vector")
		return direction 
	end

	local profile = self:_GetSpreadProfile()

	-- Get current spread with recovery
	local currentSpread = self:GetCurrentSpread()

	-- Increase spread for next shot
	local newSpread = math.clamp(
		currentSpread + profile.IncreasePerShot,
		profile.Min,
		profile.Max
	)

	self.CurrentSpread.Value = newSpread
	self.LastShootTime = os.clock()

	-- Increment shot counter
	self.ShotIndex = self.ShotIndex + 1

	-- Get pattern offset (-1 to 1 range)
	local offsetX, offsetY = self:_GetSeededOffset(self.ShotIndex)

	-- Replace line 170-171 with:
	local angleRad = math.rad(newSpread)
	local spreadMagnitude = math.sin(angleRad) -- Better for gameplay feel
	
	-- Apply offsets
	local x = offsetX * spreadMagnitude
	local y = offsetY * spreadMagnitude
	local z = -1 -- Forward

	local localDir = Vector3.new(x, y, z).Unit
	local rot = CFrame.lookAt(Vector3.zero, direction)

	return rot:VectorToWorldSpace(localDir).Unit
end

--[[
	Manually sets spread value
]]
function SpreadController:SetSpread(amount: number): number
	if not t.number(amount) then 
		Logger.Warn("Invalid spread amount", "[SpreadController]")
		return self.CurrentSpread.Value 
	end

	self.CurrentSpread.Value = amount
	return self.CurrentSpread.Value
end

--[[
	Resets spread and pattern when aim state changes
]]
function SpreadController:OnAimChanged(isAiming: boolean)
	local profile = isAiming and self.Data.Aiming or self.Data.Base
	self.CurrentSpread.Value = profile.Min
	self.ShotIndex = 0 -- Reset pattern
	Logger.Print("Reset spread to: " .. self.CurrentSpread.Value, "[SpreadController]")
end

--[[
	Resets pattern (useful for burst weapons)
]]
function SpreadController:ResetPattern()
	self.ShotIndex = 0
end

--[[
	Gets shot index for debugging
]]
function SpreadController:GetShotIndex(): number
	return self.ShotIndex
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