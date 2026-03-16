--!native
--!optimize 2
--[[
	Camera Rotation Sway Module
	Handles camera sway based on camera rotation changes
--]]

local module = {}

-- Default Configuration
local DefaultConfiguration = {
	-- Speed at which the sway smoothly transitions (0-1 range)
	-- Higher values = snappier response, Lower values = smoother/slower
	-- Default: 0.08 (smooth, natural feeling movement)
	CameraSwayLerpSpeed = 0.08,

	-- Intensity of the rotational sway effect
	-- Higher values = more pronounced sway, Lower values = subtle sway
	-- Default: 0.1 (subtle, realistic sway)
	SwayAmount = 0.1,

	-- Internal state (don't set these directly)
	SwayCF = nil,
	LastCameraCF = nil,
}

-- RotationalSway Class
local RotationalSway = {}

--[[
	Updates camera rotation-based sway
	@param cameraCFrame CFrame - Current camera CFrame
]]
local Camera = workspace.CurrentCamera
function RotationalSway.Update(self: RotationalSway)
	local rotationDifference = Camera.CFrame:ToObjectSpace(self.LastCameraCF)
	local x, y, z = rotationDifference:ToOrientation()

	self.SwayCF = self.SwayCF:Lerp(
		CFrame.Angles(
			math.sin(x) * self.SwayAmount,
			math.sin(y) * self.SwayAmount,
			0
		),
		self.CameraSwayLerpSpeed
	)

	self.LastCameraCF = Camera.CFrame
end

--[[
	Gets the camera rotation sway CFrame
	@return CFrame
]]
function RotationalSway.GetSway(self: RotationalSway)
	return self.SwayCF
end

--[[
	Gets the camera rotation sway CFrame (alias for GetSway)
	@return CFrame
]]
function RotationalSway.GetCFrame(self: RotationalSway)
	return self.SwayCF
end

--[[
	Sets the sway amount (intensity)
	@param amount number
]]
function RotationalSway.SetSwayAmount(self: RotationalSway, amount)
	self.SwayAmount = amount
end

--[[
	Gets the current sway amount
	@return number
]]
function RotationalSway.GetSwayAmount(self: RotationalSway)
	return self.SwayAmount
end

--[[
	Resets camera rotation sway to neutral
]]
function RotationalSway.Reset(self: RotationalSway)
	self.SwayCF = CFrame.new()
	self.LastCameraCF = CFrame.new()
end

--[[
	Sets configuration values
	@param config table - Configuration overrides
]]
function RotationalSway.SetConfig(self: RotationalSway, config)
	if not config or type(config) ~= "table" then
		return false
	end

	if config.CameraSwayLerpSpeed then 
		self.CameraSwayLerpSpeed = config.CameraSwayLerpSpeed 
	end
	if config.SwayAmount then 
		self.SwayAmount = config.SwayAmount 
	end

	return true
end

--[[
	Gets current configuration values
	@return table - Copy of current configuration
]]
function RotationalSway.GetConfig(self: RotationalSway)
	return {
		CameraSwayLerpSpeed = self.CameraSwayLerpSpeed,
		SwayAmount = self.SwayAmount,
	}
end

-- Constructor
function module.new(Configuration: Configuration): RotationalSway
	local instance = table.clone(RotationalSway) :: RotationalSway

	-- Initialize state
	instance.SwayCF = CFrame.new()
	instance.LastCameraCF = CFrame.new()

	-- Apply configuration
	instance.CameraSwayLerpSpeed = Configuration and Configuration.CameraSwayLerpSpeed 
		or DefaultConfiguration.CameraSwayLerpSpeed
	instance.SwayAmount = Configuration and Configuration.SwayAmount 
		or DefaultConfiguration.SwayAmount

	return instance
end

-- Type exports
export type Configuration = typeof(DefaultConfiguration)
export type RotationalSway = typeof(RotationalSway) & Configuration

return module