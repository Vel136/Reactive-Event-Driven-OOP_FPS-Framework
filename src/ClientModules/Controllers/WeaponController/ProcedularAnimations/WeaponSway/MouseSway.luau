--[[
	Mouse Sway Module
	Handles camera sway based on mouse movement (position and rotation)
--]]

local UserInputService = game:GetService("UserInputService")

local MouseSway = {}

-- Configuration
local MOUSE_SWAY_DIVISOR_CAM = 50
local MOUSE_SWAY_DIVISOR_ROT = 150
local MOUSE_SWAY_CLAMP = 0.3
local ROTATION_SWAY_CLAMP = 0.03
local SWAY_LERP_SPEED = 0.1

-- State Variables
local SwayCam = CFrame.new()
local SwayRot = CFrame.new()

--[[
	Updates mouse-based camera sway
	Should be called every frame
]]
function MouseSway.Update()
	local mouseDelta = UserInputService:GetMouseDelta()

	-- Camera position sway
	local swayCamX = math.clamp(
		mouseDelta.X / MOUSE_SWAY_DIVISOR_CAM,
		-MOUSE_SWAY_CLAMP,
		MOUSE_SWAY_CLAMP
	)
	local swayCamY = math.clamp(
		mouseDelta.Y / MOUSE_SWAY_DIVISOR_CAM,
		-MOUSE_SWAY_CLAMP,
		MOUSE_SWAY_CLAMP
	)

	SwayCam = SwayCam:Lerp(
		CFrame.new(-swayCamX, swayCamY, 0),
		SWAY_LERP_SPEED
	)

	-- Rotation sway
	local swayRotX = math.clamp(
		mouseDelta.X / MOUSE_SWAY_DIVISOR_ROT,
		-ROTATION_SWAY_CLAMP,
		ROTATION_SWAY_CLAMP
	)
	local swayRotY = math.clamp(
		mouseDelta.Y / MOUSE_SWAY_DIVISOR_ROT,
		-ROTATION_SWAY_CLAMP,
		ROTATION_SWAY_CLAMP
	)

	SwayRot = SwayRot:Lerp(
		CFrame.Angles(-swayRotY, -swayRotX, 0),
		SWAY_LERP_SPEED
	)
end

--[[
	Gets the position sway CFrame
	@return CFrame
]]
function MouseSway.GetPositionSway()
	return SwayCam
end

--[[
	Gets the rotation sway CFrame
	@return CFrame
]]
function MouseSway.GetRotationSway()
	return SwayRot
end

--[[
	Gets the combined mouse sway (rotation * position)
	@return CFrame
]]
function MouseSway.GetCombinedSway()
	return SwayRot * SwayCam
end

--[[
	Resets mouse sway to neutral
]]
function MouseSway.Reset()
	SwayCam = CFrame.new()
	SwayRot = CFrame.new()
end

--[[
	Sets configuration values
	@param config table - Configuration overrides
]]
function MouseSway.SetConfig(config)
	if config.MOUSE_SWAY_DIVISOR_CAM then MOUSE_SWAY_DIVISOR_CAM = config.MOUSE_SWAY_DIVISOR_CAM end
	if config.MOUSE_SWAY_DIVISOR_ROT then MOUSE_SWAY_DIVISOR_ROT = config.MOUSE_SWAY_DIVISOR_ROT end
	if config.MOUSE_SWAY_CLAMP then MOUSE_SWAY_CLAMP = config.MOUSE_SWAY_CLAMP end
	if config.ROTATION_SWAY_CLAMP then ROTATION_SWAY_CLAMP = config.ROTATION_SWAY_CLAMP end
	if config.SWAY_LERP_SPEED then SWAY_LERP_SPEED = config.SWAY_LERP_SPEED end
end

return MouseSway