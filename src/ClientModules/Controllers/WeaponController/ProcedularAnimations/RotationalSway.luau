--[[
	Camera Rotation Sway Module
	Handles camera sway based on camera rotation changes
--]]

local RotationalSway = {}

-- Configuration
local CAMERA_SWAY_LERP_SPEED = 0.08
local SWAY_AMOUNT = 0.1

-- State Variables
local SwayCF = CFrame.new()
local LastCameraCF = CFrame.new()

--[[
	Updates camera rotation-based sway
	@param cameraCFrame CFrame - Current camera CFrame
]]
function RotationalSway.Update(cameraCFrame)
	local rotationDifference = cameraCFrame:ToObjectSpace(LastCameraCF)
	local x, y, z = rotationDifference:ToOrientation()

	SwayCF = SwayCF:Lerp(
		CFrame.Angles(
			math.sin(x) * SWAY_AMOUNT,
			math.sin(y) * SWAY_AMOUNT,
			0
		),
		CAMERA_SWAY_LERP_SPEED
	)

	LastCameraCF = cameraCFrame
end

--[[
	Gets the camera rotation sway CFrame
	@return CFrame
]]
function RotationalSway.GetSway()
	return SwayCF
end

--[[
	Sets the sway amount (intensity)
	@param amount number
]]
function RotationalSway.SetSwayAmount(amount)
	SWAY_AMOUNT = amount
end

--[[
	Gets the current sway amount
	@return number
]]
function RotationalSway.GetSwayAmount()
	return SWAY_AMOUNT
end

--[[
	Resets camera rotation sway to neutral
]]
function RotationalSway.Reset()
	SwayCF = CFrame.new()
	LastCameraCF = CFrame.new()
end

--[[
	Sets configuration values
	@param config table - Configuration overrides
]]
function RotationalSway.SetConfig(config)
	if config.CAMERA_SWAY_LERP_SPEED then CAMERA_SWAY_LERP_SPEED = config.CAMERA_SWAY_LERP_SPEED end
	if config.SWAY_AMOUNT then SWAY_AMOUNT = config.SWAY_AMOUNT end
end

return RotationalSway