--!native
--!optimize 2
--[[
	Procedural Sway Module
	Handles weapon sway during aiming with breathing simulation
	Frame-rate independent using delta time
	Now supports position offsets for aim and idle states
	Supports Roblox attributes for real-time configuration
--]]

-- Pre-cache math functions
local Sin = math.sin
local Cos = math.cos
local Exp = math.exp
local Log = math.log
local PI2 = math.pi * 2
local CF = CFrame.new

local module = {}

-- Default Configuration
local DefaultConfiguration = {
	-- Time in seconds to reach aim position (99% completion)
	AimTime = 0.35,
	-- Time to return to idle
	IdleTime = 0.2,
	-- Speed multiplier for sway oscillation
	SwaySpeed = 1,
	-- Breathing rate multiplier
	BreathRate = 0.5,
	-- Maximum sway displacement
	SwayAmplitude = 0.01,
	-- Target completion percentage for lerp (0.99 = 99%)
	CompletionPercent = 0.99,

	-- Aim state position offset
	AimOffsetX = 0,
	AimOffsetY = 0,
	AimOffsetZ = 0,

	-- Idle state position offset
	IdleOffsetX = 0,
	IdleOffsetY = 0,
	IdleOffsetZ = 0,

	-- Internal state (don't set these directly)
	AimCFrame = nil,
	Elapsed = nil,
	AimLerpSpeed = nil,
	IdleLerpSpeed = nil,
	CurrentOffsetX = nil,
	CurrentOffsetY = nil,
	CurrentOffsetZ = nil,
	_IsActive = nil,
}

-- List of config keys that should be synced with attributes
local ATTRIBUTE_KEYS = {
	"AimTime", "IdleTime",
	"SwaySpeed", "BreathRate", "SwayAmplitude",
	"CompletionPercent",
	"AimOffsetX", "AimOffsetY", "AimOffsetZ",
	"IdleOffsetX", "IdleOffsetY", "IdleOffsetZ"
}

-- Conversion constant calculation
local function CalculateLerpSpeed(aimTime, completionPercent)
	return -Log(1 - completionPercent) / aimTime
end

-- Frame-rate independent exponential lerp for offset smoothing
local function ExpLerp(current, target, speed, deltaTime)
	if deltaTime <= 0 then
		return current
	end
	local alpha = 1 - Exp(-speed * deltaTime)
	return current + (target - current) * alpha
end

-- ProceduralSway Class
local ProceduralSway = {}

--[[
	Initialize attributes on an instance
	@param instance Instance - The instance to add attributes to
]]
function ProceduralSway.InitializeAttributes(self : ProceduralSway, instance)
	if not instance or not instance:IsA("Instance") then
		warn("ProceduralSway: Invalid instance provided to InitializeAttributes")
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

				-- Recalculate lerp speeds if timing changed
				if attributeName == "AimTime" or attributeName == "CompletionPercent" then
					self.AimLerpSpeed = CalculateLerpSpeed(self.AimTime, self.CompletionPercent)
				end
				if attributeName == "IdleTime" or attributeName == "CompletionPercent" then
					self.IdleLerpSpeed = CalculateLerpSpeed(self.IdleTime, self.CompletionPercent)
				end
			end
		end
	end)
end

--[[
	Disconnect attribute listener and cleanup
]]
function ProceduralSway.Destroy(self : ProceduralSway)
	if self._attributeConnection then
		self._attributeConnection:Disconnect()
		self._attributeConnection = nil
	end
	self._attributeInstance = nil
end

--[[
	Set active state (enables aiming mode)
	@param IsActive boolean
]]
function ProceduralSway.SetActive(self : ProceduralSway, IsActive)
	self._IsActive = IsActive
end

--[[
	Get active state
	@return boolean
]]
function ProceduralSway.IsActive(self : ProceduralSway)
	return self._IsActive
end

--[[
	Update function (call every frame in RenderStepped)
	Handles both aiming and idle states based on _IsActive
	@param deltaTime number - Time since last frame
	@param PrimaryCFrame CFrame - Only used when _IsActive is true
	@param TargetCFrame CFrame - Only used when _IsActive is true
]]
function ProceduralSway.Update(self : ProceduralSway, deltaTime, PrimaryCFrame, TargetCFrame)
	if not deltaTime or deltaTime <= 0 then
		return
	end

	self.Elapsed = self.Elapsed + deltaTime

	if self._IsActive then
		-- AIMING MODE
		-- Smoothly interpolate offset toward aim offset
		self.CurrentOffsetX = ExpLerp(self.CurrentOffsetX, self.AimOffsetX, self.AimLerpSpeed, deltaTime)
		self.CurrentOffsetY = ExpLerp(self.CurrentOffsetY, self.AimOffsetY, self.AimLerpSpeed, deltaTime)
		self.CurrentOffsetZ = ExpLerp(self.CurrentOffsetZ, self.AimOffsetZ, self.AimLerpSpeed, deltaTime)

		-- Calculate aim offset
		local offset = TargetCFrame:ToObjectSpace(PrimaryCFrame)

		-- Procedural breathing/sway
		local swayX = Sin(self.Elapsed * self.SwaySpeed * PI2) * self.SwayAmplitude
		local swayY = Cos(self.Elapsed * self.BreathRate * PI2) * (self.SwayAmplitude * 0.3)
		offset = offset * CF(swayX, swayY, 0) 

		-- Frame-rate independent lerp
		local alpha = 1 - Exp(-self.AimLerpSpeed * deltaTime)
		self.AimCFrame = self.AimCFrame:Lerp(offset, alpha)
	else
		-- IDLE MODE
		-- Smoothly interpolate offset toward idle offset
		self.CurrentOffsetX = ExpLerp(self.CurrentOffsetX, self.IdleOffsetX, self.IdleLerpSpeed, deltaTime)
		self.CurrentOffsetY = ExpLerp(self.CurrentOffsetY, self.IdleOffsetY, self.IdleLerpSpeed, deltaTime)
		self.CurrentOffsetZ = ExpLerp(self.CurrentOffsetZ, self.IdleOffsetZ, self.IdleLerpSpeed, deltaTime)

		-- Calculate idle breathing motion
		local swayX = Sin(self.Elapsed * self.SwaySpeed * PI2) * self.SwayAmplitude
		local swayY = Cos(self.Elapsed * self.BreathRate * PI2) * (self.SwayAmplitude * 0.3)
		local idleBreathing = CF(swayX, swayY, 0)

		-- Lerp toward idle breathing position
		local alpha = 1 - Exp(-self.IdleLerpSpeed * deltaTime)
		self.AimCFrame = self.AimCFrame:Lerp(idleBreathing, alpha)
	end
end

--[[
	Get the CFrame to apply to viewmodel
	@return CFrame
]]
function ProceduralSway.GetCFrame(self : ProceduralSway)
	-- Apply current position offset to the sway CFrame
	return CF(self.CurrentOffsetX, self.CurrentOffsetY, self.CurrentOffsetZ) * self.AimCFrame
end

--[[
	Get current offset values (for debugging)
	@return table - {X, Y, Z}
]]
function ProceduralSway.GetCurrentOffset(self : ProceduralSway)
	return {
		X = self.CurrentOffsetX,
		Y = self.CurrentOffsetY,
		Z = self.CurrentOffsetZ
	}
end

--[[
	Reset all values to neutral
]]
function ProceduralSway.Reset(self : ProceduralSway)
	self.AimCFrame = CF()
	self.Elapsed = 0
	self.CurrentOffsetX = 0
	self.CurrentOffsetY = 0
	self.CurrentOffsetZ = 0
	self._IsActive = false
end

--[[
	Updates configuration values
	@param config table - Configuration overrides
]]
function ProceduralSway.SetConfig(self : ProceduralSway, config : Configuration)
	if not config or type(config) ~= "table" then
		return false
	end

	for key, value in pairs(config) do
		if self[key] ~= nil and key ~= "AimCFrame" and key ~= "Elapsed" 
			and key ~= "CurrentOffsetX" and key ~= "CurrentOffsetY" and key ~= "CurrentOffsetZ"
			and key ~= "_IsActive" then
			self[key] = value

			-- Also update attribute if instance is set
			if self._attributeInstance and table.find(ATTRIBUTE_KEYS, key) then
				self._attributeInstance:SetAttribute(key, value)
			end
		end
	end

	-- Recalculate lerp speeds if timing changed
	if config.AimTime or config.CompletionPercent then
		self.AimLerpSpeed = CalculateLerpSpeed(self.AimTime, self.CompletionPercent)
	end
	if config.IdleTime or config.CompletionPercent then
		self.IdleLerpSpeed = CalculateLerpSpeed(self.IdleTime, self.CompletionPercent)
	end

	return true
end

--[[
	Get current configuration
	@return table
]]
function ProceduralSway.GetConfig(self : ProceduralSway)
	local copy = {}
	for key, value in pairs(self) do
		if type(value) ~= "function" and key ~= "AimCFrame" and key ~= "Elapsed" 
			and key ~= "CurrentOffsetX" and key ~= "CurrentOffsetY" and key ~= "CurrentOffsetZ"
			and key ~= "_IsActive" then
			copy[key] = value
		end
	end
	return copy
end

--[[
	Creates a new ProceduralSway instance
	@param Configuration table - Configuration overrides
	@return ProceduralSway
]]
function module.new(Configuration : Configuration) : ProceduralSway
	local instance = setmetatable({},{__index = ProceduralSway}) :: ProceduralSway

	-- Initialize state
	instance.AimCFrame = CF()
	instance.Elapsed = 0
	instance.CurrentOffsetX = 0
	instance.CurrentOffsetY = 0
	instance.CurrentOffsetZ = 0
	instance._IsActive = false

	-- Apply configuration
	instance.AimTime = Configuration and Configuration.AimTime or DefaultConfiguration.AimTime
	instance.IdleTime = Configuration and Configuration.IdleTime or DefaultConfiguration.IdleTime
	instance.SwaySpeed = Configuration and Configuration.SwaySpeed or DefaultConfiguration.SwaySpeed
	instance.BreathRate = Configuration and Configuration.BreathRate or DefaultConfiguration.BreathRate
	instance.SwayAmplitude = Configuration and Configuration.SwayAmplitude or DefaultConfiguration.SwayAmplitude
	instance.CompletionPercent = Configuration and Configuration.CompletionPercent or DefaultConfiguration.CompletionPercent

	-- Apply offset configuration
	instance.AimOffsetX = Configuration and Configuration.AimOffsetX or DefaultConfiguration.AimOffsetX
	instance.AimOffsetY = Configuration and Configuration.AimOffsetY or DefaultConfiguration.AimOffsetY
	instance.AimOffsetZ = Configuration and Configuration.AimOffsetZ or DefaultConfiguration.AimOffsetZ

	instance.IdleOffsetX = Configuration and Configuration.IdleOffsetX or DefaultConfiguration.IdleOffsetX
	instance.IdleOffsetY = Configuration and Configuration.IdleOffsetY or DefaultConfiguration.IdleOffsetY
	instance.IdleOffsetZ = Configuration and Configuration.IdleOffsetZ or DefaultConfiguration.IdleOffsetZ

	-- Calculate lerp speeds
	instance.AimLerpSpeed = CalculateLerpSpeed(instance.AimTime, instance.CompletionPercent)
	instance.IdleLerpSpeed = CalculateLerpSpeed(instance.IdleTime, instance.CompletionPercent)

	return instance
end

-- Type exports
export type Configuration = typeof(DefaultConfiguration)
export type ProceduralSway = typeof(setmetatable({} :: Configuration,{__index = ProceduralSway}))

return module