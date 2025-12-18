--[[
	Camera Rotation Sway Module
	Handles camera sway based on camera rotation changes
--]]

local CameraRotationSway = {}

-- Configuration
local CAMERA_SWAY_LERP_SPEED = 0.08
local SWAY_AMOUNT = 0.3

-- State Variables
local SwayCF = CFrame.new()
local LastCameraCF = CFrame.new()

--[[
	Updates camera rotation-based sway
	@param cameraCFrame CFrame - Current camera CFrame
]]
function CameraRotationSway.Update(cameraCFrame)
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
function CameraRotationSway.GetSway()
	return SwayCF
end

--[[
	Sets the sway amount (intensity)
	@param amount number
]]
function CameraRotationSway.SetSwayAmount(amount)
	SWAY_AMOUNT = amount
end

--[[
	Gets the current sway amount
	@return number
]]
function CameraRotationSway.GetSwayAmount()
	return SWAY_AMOUNT
end

--[[
	Resets camera rotation sway to neutral
]]
function CameraRotationSway.Reset()
	SwayCF = CFrame.new()
	LastCameraCF = CFrame.new()
end

--[[
	Sets configuration values
	@param config table - Configuration overrides
]]
function CameraRotationSway.SetConfig(config)
	if config.CAMERA_SWAY_LERP_SPEED then CAMERA_SWAY_LERP_SPEED = config.CAMERA_SWAY_LERP_SPEED end
	if config.SWAY_AMOUNT then SWAY_AMOUNT = config.SWAY_AMOUNT end
end

return CameraRotationSway