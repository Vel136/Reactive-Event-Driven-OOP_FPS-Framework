--!native
--!optimize 2
--[[
	Spring Sway Module
	Handles physics-based weapon sway using spring simulation
	Creates bouncy "weapon lag" effect based on mouse movement
	Uses external Spring module for physics
--]]

local UserInputService = game:GetService("UserInputService")
local Spring = require(game.ReplicatedStorage.SharedModules.Utilities.Spring)

local SpringSway = {}

-- Configuration
SpringSway.Config = {
	-- Spring properties
	damping = 0.3,              -- Higher = less bouncy (0-1)
	stiffness = 25,              -- Higher = stiffer spring (>0)

	-- Mouse sensitivity
	mouseSensitivity = 1/100,     -- How much mouse movement affects spring

	-- Sway mapping
	mapToRotation = true,        -- Convert spring position to rotation
	rotationMultiplier = 0.7,    -- Scale rotation amount

	-- Clamping (optional)
	enableClamping = false,      -- Whether to clamp sway angles
	maxSwayAngle = 10,            -- Maximum sway angle in degrees

	-- Smoothing
	smoothSpeed = 0.15,           -- Final lerp alpha

	-- Inversion (weapon lag effect)
	invertSway = true,           -- Inverse the CFrame for "lag behind" feel
}

-- State Variables
local swaySpringX = Spring.new(0)
local swaySpringY = Spring.new(0)
local swaySpringZ = Spring.new(0)
local currentSwayCF = CFrame.new()

--[[
	Initialize springs with current config
]]
function SpringSway.Init()
	local config = SpringSway.Config

	swaySpringX.d = config.damping
	swaySpringX.s = config.stiffness

	swaySpringY.d = config.damping
	swaySpringY.s = config.stiffness

	swaySpringZ.d = config.damping
	swaySpringZ.s = config.stiffness
end

--[[
	Updates spring-based sway
	Should be called every frame in RenderStepped
	@param deltaTime number - Frame delta time (unused, springs are time-based)
]]
function SpringSway.Update(deltaTime)
	local config = SpringSway.Config

	-- Get mouse delta and apply as force to springs
	local mouseDelta = UserInputService:GetMouseDelta()

	swaySpringX:accelerate(mouseDelta.X * config.mouseSensitivity)
	swaySpringY:accelerate(mouseDelta.Y * config.mouseSensitivity)

	-- Get spring positions
	local swayX = swaySpringX.p
	local swayY = swaySpringY.p
	local swayZ = swaySpringZ.p

	-- Optional clamping
	if config.enableClamping then
		local maxRad = math.rad(config.maxSwayAngle)
		swayX = math.clamp(swayX, -maxRad, maxRad)
		swayY = math.clamp(swayY, -maxRad, maxRad)
		swayZ = math.clamp(swayZ, -maxRad, maxRad)
	end

	-- Convert to CFrame
	local targetSwayCF
	if config.mapToRotation then
		-- Map spring position to rotation (like original script: Y, X, X)
		targetSwayCF = CFrame.Angles(
			swayY * config.rotationMultiplier,
			swayX * config.rotationMultiplier,
			swayX * config.rotationMultiplier
		)
	else
		-- Use as position offset
		targetSwayCF = CFrame.new(swayX, swayY, swayZ)
	end

	-- Smooth lerp to target
	currentSwayCF = currentSwayCF:Lerp(targetSwayCF, config.smoothSpeed)

	return true
end

--[[
	Gets the spring sway CFrame
	Automatically inverted if Config.invertSway is true
	@return CFrame
]]
function SpringSway.GetCFrame()
	if SpringSway.Config.invertSway then
		return currentSwayCF:Inverse()
	end
	return currentSwayCF
end

--[[
	Gets the raw spring sway CFrame (not inverted)
	@return CFrame
]]
function SpringSway.GetRawCFrame()
	return currentSwayCF
end

--[[
	Gets current spring values (for debugging)
	@return table
]]
function SpringSway.GetSpringValues()
	local x, y, z = currentSwayCF:ToEulerAnglesXYZ()
	return {
		position = Vector3.new(swaySpringX.p, swaySpringY.p, swaySpringZ.p),
		velocity = Vector3.new(swaySpringX.v, swaySpringY.v, swaySpringZ.v),
		rotation = {
			x = math.deg(x),
			y = math.deg(y),
			z = math.deg(z)
		}
	}
end

--[[
	Manually add force to springs (for recoil, impacts, etc.)
	@param force Vector3
]]
function SpringSway.AddForce(force)
	swaySpringX:accelerate(force.X)
	swaySpringY:accelerate(force.Y)
	swaySpringZ:accelerate(force.Z)
end

--[[
	Manually set spring velocities (for instant effects)
	@param velocity Vector3
]]
function SpringSway.SetVelocity(velocity)
	swaySpringX.v = velocity.X
	swaySpringY.v = velocity.Y
	swaySpringZ.v = velocity.Z
end

--[[
	Resets all spring values to neutral
]]
function SpringSway.Reset()
	swaySpringX.p = 0
	swaySpringX.v = 0
	swaySpringX.t = 0

	swaySpringY.p = 0
	swaySpringY.v = 0
	swaySpringY.t = 0

	swaySpringZ.p = 0
	swaySpringZ.v = 0
	swaySpringZ.t = 0

	currentSwayCF = CFrame.new()
end

--[[
	Sets configuration values
	@param config table - Configuration overrides
]]
function SpringSway.SetConfig(config)
	if not config or type(config) ~= "table" then
		return false
	end

	for key, value in pairs(config) do
		if SpringSway.Config[key] ~= nil then
			SpringSway.Config[key] = value
		end
	end

	-- Update spring properties
	swaySpringX.d = SpringSway.Config.damping
	swaySpringX.s = SpringSway.Config.stiffness

	swaySpringY.d = SpringSway.Config.damping
	swaySpringY.s = SpringSway.Config.stiffness

	swaySpringZ.d = SpringSway.Config.damping
	swaySpringZ.s = SpringSway.Config.stiffness

	return true
end

--[[
	Gets a copy of current configuration
	@return table
]]
function SpringSway.GetConfig()
	local copy = {}
	for key, value in pairs(SpringSway.Config) do
		copy[key] = value
	end
	return copy
end

--[[
	Gets the internal spring objects (advanced usage)
	@return table - {x, y, z}
]]
function SpringSway.GetSprings()
	return {
		x = swaySpringX,
		y = swaySpringY,
		z = swaySpringZ
	}
end

-- Initialize on module load
SpringSway.Init()

return SpringSway