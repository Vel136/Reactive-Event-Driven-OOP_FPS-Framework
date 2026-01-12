local WalkBob = {}

-- Configuration
WalkBob.Config = {
	-- Movement bobbing (when walking/running)
	movementIntensity = 0.025,        -- Overall scale of movement bob
	horizontalFrequency = 8,          -- Speed of horizontal sway
	verticalFrequency = 16,           -- Speed of vertical bob (2x horizontal for realistic gait)
	rotationIntensity = 1,            -- Rotation strength in degrees

	-- Speed threshold
	movementThreshold = 0.1,          -- Minimum speed to trigger movement bob

	-- Smoothing
	smoothSpeed = 0.1,                -- Lerp alpha for smooth transitions
}

-- Internal state
local currentBobCF = CFrame.new()
local isMoving = false
local currentSpeed = 0
local timeAccumulator = 0

-- Set movement state
function WalkBob.SetMoving(moving, speed)
	isMoving = moving
	currentSpeed = speed or 0
end

-- Update function (call every frame in RenderStepped)
function WalkBob.Update(deltaTime)
	local config = WalkBob.Config

	timeAccumulator = timeAccumulator + deltaTime
	local time = timeAccumulator

	local targetBobCF

	if isMoving and currentSpeed > config.movementThreshold then
		-- Movement bobbing with speed scaling
		local speedScale = currentSpeed / 10
		local intensity = config.movementIntensity * speedScale

		-- Position bobbing
		local xOffset = intensity * math.sin(time * config.horizontalFrequency)
		local yOffset = intensity * math.cos(time * config.verticalFrequency)

		-- Rotation bobbing
		local pitchRot = math.rad(config.rotationIntensity * speedScale * math.sin(time * config.verticalFrequency))
		local yawRot = math.rad(config.rotationIntensity * speedScale * math.cos(time * config.horizontalFrequency))

		targetBobCF = CFrame.new(xOffset, yOffset, 0)
			* CFrame.Angles(pitchRot, yawRot, 0)
	else
		-- No movement = no bob (let ProceduralSway handle idle breathing)
		targetBobCF = CFrame.new()
	end

	-- Smoothly interpolate to target
	currentBobCF = currentBobCF:Lerp(targetBobCF, config.smoothSpeed)
end

function WalkBob.GetCFrame()
	return currentBobCF
end

function WalkBob.Reset()
	currentBobCF = CFrame.new()
	isMoving = false
	currentSpeed = 0
	timeAccumulator = 0
end

return WalkBob