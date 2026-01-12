local SprintTilt = {}

-- Configuration
SprintTilt.Config = {
	-- Sprint tilt angles (in degrees)
	sprintTiltX = -20,    -- Pitch
	sprintTiltY = 70,     -- Yaw 
	sprintTiltZ = 30,   -- Roll 

	-- Sprint position offset
	sprintOffsetX = 2,
	sprintOffsetY = -.3,  -- Lower the gun
	sprintOffsetZ = -1,

	-- Smoothing speed (0.1 = slow, 0.3 = fast)
	smoothSpeed = 0.15,

	-- Idle/neutral values (usually 0)
	idleTiltX = 0,
	idleTiltY = 0,
	idleTiltZ = 0,

	idleOffsetX = 0,
	idleOffsetY = 0,
	idleOffsetZ = 0,
}

-- Internal state
local currentTiltX = 0
local currentTiltY = 0
local currentTiltZ = 0

local currentOffsetX = 0
local currentOffsetY = 0
local currentOffsetZ = 0

local isSprinting = false

-- Set sprint state
function SprintTilt.SetSprinting(sprinting)
	isSprinting = sprinting
end

-- Get sprint state
function SprintTilt.IsSprinting()
	return isSprinting
end

-- Update function (call every frame in RenderStepped)
function SprintTilt.Update(deltaTime)
	local config = SprintTilt.Config
	local smoothSpeed = config.smoothSpeed

	-- Determine target values based on sprint state
	local targetTiltX, targetTiltY, targetTiltZ
	local targetOffsetX, targetOffsetY, targetOffsetZ

	if isSprinting then
		targetTiltX = config.sprintTiltX
		targetTiltY = config.sprintTiltY
		targetTiltZ = config.sprintTiltZ
		targetOffsetX = config.sprintOffsetX
		targetOffsetY = config.sprintOffsetY
		targetOffsetZ = config.sprintOffsetZ
	else
		targetTiltX = config.idleTiltX
		targetTiltY = config.idleTiltY
		targetTiltZ = config.idleTiltZ
		targetOffsetX = config.idleOffsetX
		targetOffsetY = config.idleOffsetY
		targetOffsetZ = config.idleOffsetZ
	end

	-- Smoothly interpolate rotation
	currentTiltX = currentTiltX + (targetTiltX - currentTiltX) * smoothSpeed
	currentTiltY = currentTiltY + (targetTiltY - currentTiltY) * smoothSpeed
	currentTiltZ = currentTiltZ + (targetTiltZ - currentTiltZ) * smoothSpeed

	-- Smoothly interpolate position
	currentOffsetX = currentOffsetX + (targetOffsetX - currentOffsetX) * smoothSpeed
	currentOffsetY = currentOffsetY + (targetOffsetY - currentOffsetY) * smoothSpeed
	currentOffsetZ = currentOffsetZ + (targetOffsetZ - currentOffsetZ) * smoothSpeed
end

-- Get the CFrame to apply to viewmodel
function SprintTilt.GetCFrame()
	return CFrame.new(currentOffsetX, currentOffsetY, currentOffsetZ)
		* CFrame.Angles(
			math.rad(currentTiltX),  -- X-axis pitch
			math.rad(currentTiltY),  -- Y-axis yaw
			math.rad(currentTiltZ)   -- Z-axis roll
		)
end

-- Get current tilt values (for debugging)
function SprintTilt.GetTiltValues()
	return {
		x = currentTiltX,
		y = currentTiltY,
		z = currentTiltZ
	}
end

-- Get current offset values (for debugging)
function SprintTilt.GetOffsetValues()
	return {
		x = currentOffsetX,
		y = currentOffsetY,
		z = currentOffsetZ
	}
end

-- Reset all values to neutral
function SprintTilt.Reset()
	currentTiltX = 0
	currentTiltY = 0
	currentTiltZ = 0
	currentOffsetX = 0
	currentOffsetY = 0
	currentOffsetZ = 0
	isSprinting = false
end

return SprintTilt