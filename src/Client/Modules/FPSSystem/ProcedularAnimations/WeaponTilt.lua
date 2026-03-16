--!native
--!optimize 2
--[[
	Weapon Tilt Module
	Handles weapon tilt and position offset for various states (sprinting, canting, aiming, etc.)
	Frame-rate independent using exponential decay
	Now supports Roblox attributes for real-time configuration
--]]

local module = {}

local DefaultConfiguration = {
	-- Active state tilt angles (in degrees)
	WeaponTiltX = 30,
	WeaponTiltY = 50,
	WeaponTiltZ = 25,

	-- Active state position offset
	WeaponOffsetX = .3,
	WeaponOffsetY = -1,
	WeaponOffsetZ = .1,

	-- Smoothing speed (exponential decay rate per second)
	SmoothSpeed = 8.0,

	-- Base/neutral values (usually 0)
	BaseTiltX = 0,
	BaseTiltY = 0,
	BaseTiltZ = 0,

	BaseOffsetX = 0,
	BaseOffsetY = 0,
	BaseOffsetZ = 0,

	-- Internal state (do not set manually)
	CurrentTiltX = nil,
	CurrentTiltY = nil,
	CurrentTiltZ = nil,
	CurrentOffsetX = nil,
	CurrentOffsetY = nil,
	CurrentOffsetZ = nil,
	_IsActive = nil,
}

-- List of config keys that should be synced with attributes
local ATTRIBUTE_KEYS = {
	"WeaponTiltX", "WeaponTiltY", "WeaponTiltZ",
	"WeaponOffsetX", "WeaponOffsetY", "WeaponOffsetZ",
	"SmoothSpeed",
	"BaseTiltX", "BaseTiltY", "BaseTiltZ",
	"BaseOffsetX", "BaseOffsetY", "BaseOffsetZ"
}

-- Pre-cache math functions
local Exp = math.exp
local Rad = math.rad

local WeaponTilt = {}

--[[
	Frame-rate independent exponential lerp
	@param current number
	@param target number
	@param speed number - Decay rate per second
	@param deltaTime number
	@return number
]]
local function ExpLerp(current, target, speed, deltaTime)
	if deltaTime <= 0 then
		return current
	end

	local alpha = 1 - Exp(-speed * deltaTime)
	return current + (target - current) * alpha
end

--[[
	Initialize attributes on an instance
	@param instance Instance - The instance to add attributes to
]]
function WeaponTilt.InitializeAttributes(self : WeaponTilt, instance)
	if not instance or not instance:IsA("Instance") then
		warn("WeaponTilt: Invalid instance provided to InitializeAttributes")
		return
	end

	self._attributeInstance = instance

	-- Set initial attribute values from current config
	for _, key in ipairs(ATTRIBUTE_KEYS) do
		if self[key] ~= nil then
			instance:SetAttribute(key, self[key])
		end
	end

	-- Connect to attribute changes
	self._attributeConnection = instance.AttributeChanged:Connect(function(attributeName)
		-- Check if this is a config attribute
		if table.find(ATTRIBUTE_KEYS, attributeName) then
			local newValue = instance:GetAttribute(attributeName)
			if newValue ~= nil then
				self[attributeName] = newValue
			end
		end
	end)
end

--[[
	Disconnect attribute listener and cleanup
]]
function WeaponTilt.Destroy(self : WeaponTilt)
	if self._attributeConnection then
		self._attributeConnection:Disconnect()
		self._attributeConnection = nil
	end
	self._attributeInstance = nil
end

--[[
	Creates a clone of this WeaponTilt instance with the same configuration
	@return WeaponTilt - A new instance with copied settings
]]
function WeaponTilt.Clone(self : WeaponTilt)
	local clonedConfig = {
		-- Copy active state configuration
		WeaponTiltX = self.WeaponTiltX,
		WeaponTiltY = self.WeaponTiltY,
		WeaponTiltZ = self.WeaponTiltZ,
		WeaponOffsetX = self.WeaponOffsetX,
		WeaponOffsetY = self.WeaponOffsetY,
		WeaponOffsetZ = self.WeaponOffsetZ,

		-- Copy base state configuration
		BaseTiltX = self.BaseTiltX,
		BaseTiltY = self.BaseTiltY,
		BaseTiltZ = self.BaseTiltZ,
		BaseOffsetX = self.BaseOffsetX,
		BaseOffsetY = self.BaseOffsetY,
		BaseOffsetZ = self.BaseOffsetZ,

		-- Copy smoothing speed
		SmoothSpeed = self.SmoothSpeed,
	}

	return module.new(clonedConfig) :: WeaponTilt
end

--[[
	Set active state (enables weapon tilt/offset)
	@param IsActive boolean
]]
function WeaponTilt.SetActive(self : WeaponTilt, IsActive)
	self._IsActive = IsActive
end

--[[
	Get active state
	@return boolean
]]
function WeaponTilt.IsActive(self : WeaponTilt)
	return self._IsActive
end

--[[
	Update function (call every frame in RenderStepped)
	@param deltaTime number - Time since last frame
]]
function WeaponTilt.Update(self : WeaponTilt, deltaTime)
	if not deltaTime or deltaTime <= 0 then
		return
	end

	-- Determine target values based on active state
	local targetTiltX, targetTiltY, targetTiltZ
	local targetOffsetX, targetOffsetY, targetOffsetZ

	if self._IsActive then
		targetTiltX = self.WeaponTiltX
		targetTiltY = self.WeaponTiltY
		targetTiltZ = self.WeaponTiltZ
		targetOffsetX = self.WeaponOffsetX
		targetOffsetY = self.WeaponOffsetY
		targetOffsetZ = self.WeaponOffsetZ
	else
		targetTiltX = self.BaseTiltX
		targetTiltY = self.BaseTiltY
		targetTiltZ = self.BaseTiltZ
		targetOffsetX = self.BaseOffsetX
		targetOffsetY = self.BaseOffsetY
		targetOffsetZ = self.BaseOffsetZ
	end

	-- Frame-rate independent interpolation using exponential decay
	self.CurrentTiltX = ExpLerp(self.CurrentTiltX, targetTiltX, self.SmoothSpeed, deltaTime)
	self.CurrentTiltY = ExpLerp(self.CurrentTiltY, targetTiltY, self.SmoothSpeed, deltaTime)
	self.CurrentTiltZ = ExpLerp(self.CurrentTiltZ, targetTiltZ, self.SmoothSpeed, deltaTime)

	self.CurrentOffsetX = ExpLerp(self.CurrentOffsetX, targetOffsetX, self.SmoothSpeed, deltaTime)
	self.CurrentOffsetY = ExpLerp(self.CurrentOffsetY, targetOffsetY, self.SmoothSpeed, deltaTime)
	self.CurrentOffsetZ = ExpLerp(self.CurrentOffsetZ, targetOffsetZ, self.SmoothSpeed, deltaTime)
end

--[[
	Get the CFrame to apply to viewmodel
	@return CFrame
]]
function WeaponTilt.GetCFrame(self : WeaponTilt)
	return CFrame.new(self.CurrentOffsetX, self.CurrentOffsetY, self.CurrentOffsetZ)
		* CFrame.Angles(
			Rad(self.CurrentTiltX),  -- X-axis pitch
			Rad(self.CurrentTiltY),  -- Y-axis yaw
			Rad(self.CurrentTiltZ)   -- Z-axis roll
		)
end

--[[
	Get current tilt values (for debugging)
	@return table - {X, Y, Z}
]]
function WeaponTilt.GetTiltValues(self : WeaponTilt)
	return {
		X = self.CurrentTiltX,
		Y = self.CurrentTiltY,
		Z = self.CurrentTiltZ
	}
end

--[[
	Get current offset values (for debugging)
	@return table - {X, Y, Z}
]]
function WeaponTilt.GetOffsetValues(self : WeaponTilt)
	return {
		X = self.CurrentOffsetX,
		Y = self.CurrentOffsetY,
		Z = self.CurrentOffsetZ
	}
end

--[[
	Reset all values to neutral
]]
function WeaponTilt.Reset(self : WeaponTilt)
	self.CurrentTiltX = 0
	self.CurrentTiltY = 0
	self.CurrentTiltZ = 0
	self.CurrentOffsetX = 0
	self.CurrentOffsetY = 0
	self.CurrentOffsetZ = 0
	self._IsActive = false
end

--[[
	Updates configuration values
	@param config table - Configuration overrides
]]
function WeaponTilt.SetConfig(self : WeaponTilt, config)
	if not config or type(config) ~= "table" then
		return false
	end

	for key, value in pairs(config) do
		if self[key] ~= nil and key ~= "CurrentTiltX" and key ~= "CurrentTiltY" and key ~= "CurrentTiltZ" 
			and key ~= "CurrentOffsetX" and key ~= "CurrentOffsetY" and key ~= "CurrentOffsetZ" 
			and key ~= "_IsActive" then
			self[key] = value

			-- Also update attribute if instance is set
			if self._attributeInstance and table.find(ATTRIBUTE_KEYS, key) then
				self._attributeInstance:SetAttribute(key, value)
			end
		end
	end

	return true
end

--[[
	Creates a new WeaponTilt instance
	@param Configuration table - Configuration overrides
	@return WeaponTilt
]]
function module.new(Configuration : Configuration) : WeaponTilt
	local weaponTilt = table.clone(WeaponTilt) :: WeaponTilt

	-- Initialize configuration
	weaponTilt.WeaponTiltX = Configuration and Configuration.WeaponTiltX or DefaultConfiguration.WeaponTiltX
	weaponTilt.WeaponTiltY = Configuration and Configuration.WeaponTiltY or DefaultConfiguration.WeaponTiltY
	weaponTilt.WeaponTiltZ = Configuration and Configuration.WeaponTiltZ or DefaultConfiguration.WeaponTiltZ

	weaponTilt.WeaponOffsetX = Configuration and Configuration.WeaponOffsetX or DefaultConfiguration.WeaponOffsetX
	weaponTilt.WeaponOffsetY = Configuration and Configuration.WeaponOffsetY or DefaultConfiguration.WeaponOffsetY
	weaponTilt.WeaponOffsetZ = Configuration and Configuration.WeaponOffsetZ or DefaultConfiguration.WeaponOffsetZ

	weaponTilt.SmoothSpeed = Configuration and Configuration.SmoothSpeed or DefaultConfiguration.SmoothSpeed

	weaponTilt.BaseTiltX = Configuration and Configuration.BaseTiltX or DefaultConfiguration.BaseTiltX
	weaponTilt.BaseTiltY = Configuration and Configuration.BaseTiltY or DefaultConfiguration.BaseTiltY
	weaponTilt.BaseTiltZ = Configuration and Configuration.BaseTiltZ or DefaultConfiguration.BaseTiltZ

	weaponTilt.BaseOffsetX = Configuration and Configuration.BaseOffsetX or DefaultConfiguration.BaseOffsetX
	weaponTilt.BaseOffsetY = Configuration and Configuration.BaseOffsetY or DefaultConfiguration.BaseOffsetY
	weaponTilt.BaseOffsetZ = Configuration and Configuration.BaseOffsetZ or DefaultConfiguration.BaseOffsetZ

	-- Initialize state
	weaponTilt.CurrentTiltX = 0
	weaponTilt.CurrentTiltY = 0
	weaponTilt.CurrentTiltZ = 0
	weaponTilt.CurrentOffsetX = 0
	weaponTilt.CurrentOffsetY = 0
	weaponTilt.CurrentOffsetZ = 0
	weaponTilt._IsActive = false

	return weaponTilt
end



export type Configuration = typeof(DefaultConfiguration)
export type WeaponTilt = typeof(WeaponTilt) & Configuration

return module