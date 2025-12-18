--[[
	Walk Tilt Module
	Handles camera tilt based on movement direction
--]]

local WalkTilt = {}

-- Configuration
local MAX_WALK_TILT = math.rad(5) -- 5 degrees max tilt
local WALK_TILT_LERP_SPEED = 0.1

-- State Variables
local WalkTiltCF = CFrame.new()

--[[
	Updates walking tilt effect based on movement direction
	@param humanoid Humanoid - The player's humanoid
	@param cameraCFrame CFrame - Current camera CFrame
]]
function WalkTilt.Update(humanoid, cameraCFrame)
	if not humanoid then return end

	local moveDirection = humanoid.MoveDirection
	local relativeMove = cameraCFrame:VectorToObjectSpace(moveDirection)

	-- Calculate tilt based on left/right movement
	local tiltAmount = math.clamp(-relativeMove.X, -1, 1)
	local tiltAngle = tiltAmount * MAX_WALK_TILT

	WalkTiltCF = WalkTiltCF:Lerp(
		CFrame.Angles(0, 0, tiltAngle),
		WALK_TILT_LERP_SPEED
	)
end

--[[
	Gets the walk tilt CFrame
	@return CFrame
]]
function WalkTilt.GetTilt()
	return WalkTiltCF
end

--[[
	Resets walk tilt to neutral
]]
function WalkTilt.Reset()
	WalkTiltCF = CFrame.new()
end

--[[
	Sets configuration values
	@param config table - Configuration overrides
]]
function WalkTilt.SetConfig(config)
	if config.MAX_WALK_TILT then MAX_WALK_TILT = config.MAX_WALK_TILT end
	if config.WALK_TILT_LERP_SPEED then WALK_TILT_LERP_SPEED = config.WALK_TILT_LERP_SPEED end
end

return WalkTilt