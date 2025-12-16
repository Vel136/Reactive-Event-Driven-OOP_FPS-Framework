--[[
	Gun Kick Module
	Handles procedural gun recoil with automatic recovery (Frame-rate independent)
	Call Kick() from external scripts to trigger recoil
--]]

local GunKick = {}

-- Configuration (now in per-second rates)
local KICK_INTENSITY = 1.0
local RECOVERY_SPEED = 8 -- Changed from 0.15 to per-second rate
local ROTATION_RECOVERY_SPEED = 6.0 -- Changed from 0.12 to per-second rate
local KICK_SNAP_SPEED = 25.0 -- Changed from 0.5 to per-second rate for snappy kick

-- Recoil ranges (in radians)
local KICK_ROTATION_X_MIN = math.rad(2)   -- Minimum upward kick
local KICK_ROTATION_X_MAX = math.rad(5)   -- Maximum upward kick
local KICK_ROTATION_Y_MIN = math.rad(-1)  -- Left variation
local KICK_ROTATION_Y_MAX = math.rad(1)   -- Right variation
local KICK_ROTATION_Z_MIN = math.rad(-0.5) -- Roll left
local KICK_ROTATION_Z_MAX = math.rad(0.5)  -- Roll right

-- Position kick ranges (studs)
local KICK_POSITION_X_MIN = -0.05
local KICK_POSITION_X_MAX = 0.05
local KICK_POSITION_Y_MIN = -0.03
local KICK_POSITION_Y_MAX = 0.03
local KICK_POSITION_Z_MIN = 0.1   -- Backward kick
local KICK_POSITION_Z_MAX = 0.2

-- State Variables
local CurrentRotationKick = CFrame.new()
local CurrentPositionKick = CFrame.new()
local TargetRotationKick = CFrame.new()
local TargetPositionKick = CFrame.new()

local IsKicking = false
local KickStartTime = 0
local LastKickTime = 0

-- Random number generator with seed
local random = Random.new()

--[[
	Generates a random number between min and max
	@param min number
	@param max number
	@return number
]]
local function RandomRange(min, max)
	return min + random:NextNumber() * (max - min)
end

--[[
	Triggers a gun kick with random recoil
	Call this function when the gun fires
	@param intensity number - Optional intensity multiplier (default 1.0)
]]
function GunKick.Kick(intensity)
	intensity = intensity or 1.0
	local finalIntensity = KICK_INTENSITY * intensity

	-- Generate random rotation kick
	local rotX = RandomRange(KICK_ROTATION_X_MIN, KICK_ROTATION_X_MAX) * finalIntensity
	local rotY = RandomRange(KICK_ROTATION_Y_MIN, KICK_ROTATION_Y_MAX) * finalIntensity
	local rotZ = RandomRange(KICK_ROTATION_Z_MIN, KICK_ROTATION_Z_MAX) * finalIntensity

	-- Generate random position kick
	local posX = RandomRange(KICK_POSITION_X_MIN, KICK_POSITION_X_MAX) * finalIntensity
	local posY = RandomRange(KICK_POSITION_Y_MIN, KICK_POSITION_Y_MAX) * finalIntensity
	local posZ = RandomRange(KICK_POSITION_Z_MIN, KICK_POSITION_Z_MAX) * finalIntensity

	-- Add to current kick (allows for kick stacking during rapid fire)
	TargetRotationKick = TargetRotationKick * CFrame.Angles(rotX, rotY, rotZ)
	TargetPositionKick = TargetPositionKick * CFrame.new(posX, posY, posZ)

	IsKicking = true
	KickStartTime = os.clock()
	LastKickTime = os.clock()
end

--[[
	Updates the gun kick animation
	Call this every frame (RenderStepped)
	@param deltaTime number - Time since last frame
]]
function GunKick.Update(deltaTime)
	local timeSinceLastKick = os.clock() - LastKickTime

	-- If enough time has passed since last kick, start recovering
	if timeSinceLastKick > 0.1 then
		-- Calculate frame-rate independent lerp alphas
		local recoveryAlpha = 1 - math.exp(-RECOVERY_SPEED * deltaTime)
		local rotationRecoveryAlpha = 1 - math.exp(-ROTATION_RECOVERY_SPEED * deltaTime)

		-- Smoothly recover rotation to neutral
		CurrentRotationKick = CurrentRotationKick:Lerp(
			CFrame.new(),
			rotationRecoveryAlpha
		)

		-- Smoothly recover position to neutral
		CurrentPositionKick = CurrentPositionKick:Lerp(
			CFrame.new(),
			recoveryAlpha
		)

		-- Reset targets
		TargetRotationKick = TargetRotationKick:Lerp(
			CFrame.new(),
			rotationRecoveryAlpha
		)

		TargetPositionKick = TargetPositionKick:Lerp(
			CFrame.new(),
			recoveryAlpha
		)

		-- Check if fully recovered
		local rotMagnitude = (CurrentRotationKick.Position - Vector3.new()).Magnitude
		local posMagnitude = (CurrentPositionKick.Position - Vector3.new()).Magnitude

		if rotMagnitude < 0.001 and posMagnitude < 0.001 then
			IsKicking = false
			CurrentRotationKick = CFrame.new()
			CurrentPositionKick = CFrame.new()
			TargetRotationKick = CFrame.new()
			TargetPositionKick = CFrame.new()
		end
	else
		-- Apply kick immediately (snappy kick) with frame-rate independent lerp
		local snapAlpha = 1 - math.exp(-KICK_SNAP_SPEED * deltaTime)

		CurrentRotationKick = CurrentRotationKick:Lerp(
			TargetRotationKick,
			snapAlpha
		)

		CurrentPositionKick = CurrentPositionKick:Lerp(
			TargetPositionKick,
			snapAlpha
		)
	end
end

--[[
	Gets the combined kick CFrame (rotation and position)
	@return CFrame
]]
function GunKick.GetKick()
	return CurrentRotationKick * CurrentPositionKick
end

--[[
	Gets only the rotation kick CFrame
	@return CFrame
]]
function GunKick.GetRotationKick()
	return CurrentRotationKick
end

--[[
	Gets only the position kick CFrame
	@return CFrame
]]
function GunKick.GetPositionKick()
	return CurrentPositionKick
end

--[[
	Checks if currently kicking
	@return boolean
]]
function GunKick.IsKicking()
	return IsKicking
end

--[[
	Resets all kick values to neutral
]]
function GunKick.Reset()
	CurrentRotationKick = CFrame.new()
	CurrentPositionKick = CFrame.new()
	TargetRotationKick = CFrame.new()
	TargetPositionKick = CFrame.new()
	IsKicking = false
	KickStartTime = 0
	LastKickTime = 0
end

--[[
	Sets configuration values
	@param config table - Configuration overrides
]]
function GunKick.SetConfig(config)
	if config.KICK_INTENSITY then KICK_INTENSITY = config.KICK_INTENSITY end
	if config.RECOVERY_SPEED then RECOVERY_SPEED = config.RECOVERY_SPEED end
	if config.ROTATION_RECOVERY_SPEED then ROTATION_RECOVERY_SPEED = config.ROTATION_RECOVERY_SPEED end
	if config.KICK_SNAP_SPEED then KICK_SNAP_SPEED = config.KICK_SNAP_SPEED end

	-- Rotation ranges
	if config.KICK_ROTATION_X_MIN then KICK_ROTATION_X_MIN = config.KICK_ROTATION_X_MIN end
	if config.KICK_ROTATION_X_MAX then KICK_ROTATION_X_MAX = config.KICK_ROTATION_X_MAX end
	if config.KICK_ROTATION_Y_MIN then KICK_ROTATION_Y_MIN = config.KICK_ROTATION_Y_MIN end
	if config.KICK_ROTATION_Y_MAX then KICK_ROTATION_Y_MAX = config.KICK_ROTATION_Y_MAX end
	if config.KICK_ROTATION_Z_MIN then KICK_ROTATION_Z_MIN = config.KICK_ROTATION_Z_MIN end
	if config.KICK_ROTATION_Z_MAX then KICK_ROTATION_Z_MAX = config.KICK_ROTATION_Z_MAX end

	-- Position ranges
	if config.KICK_POSITION_X_MIN then KICK_POSITION_X_MIN = config.KICK_POSITION_X_MIN end
	if config.KICK_POSITION_X_MAX then KICK_POSITION_X_MAX = config.KICK_POSITION_X_MAX end
	if config.KICK_POSITION_Y_MIN then KICK_POSITION_Y_MIN = config.KICK_POSITION_Y_MIN end
	if config.KICK_POSITION_Y_MAX then KICK_POSITION_Y_MAX = config.KICK_POSITION_Y_MAX end
	if config.KICK_POSITION_Z_MIN then KICK_POSITION_Z_MIN = config.KICK_POSITION_Z_MIN end
	if config.KICK_POSITION_Z_MAX then KICK_POSITION_Z_MAX = config.KICK_POSITION_Z_MAX end
end

return GunKick