--!native
--!optimize 2
--[[
	Spring Sway Module
	Handles physics-based weapon sway using spring simulation
	Creates bouncy "weapon lag" effect based on mouse movement
	Uses external Spring module for physics
--]]

local UserInputService = game:GetService("UserInputService")
local Spring = require(game.ReplicatedStorage.Shared.Modules.Utilities.Spring)

local module = {}

local DefaultConfiguration = {
	-- Spring properties
	-- Higher = less bouncy (0-1)
	Damping = 0.4,
	-- Higher = stiffer spring (>0)
	Stiffness = 25,

	-- Mouse sensitivity
	-- How much mouse movement affects spring
	MouseSensitivity = 1/30,

	-- Sway mapping
	-- Convert spring position to rotation
	MapToRotation = true,
	-- Scale rotation amount
	RotationMultiplier = .6,

	-- Clamping (optional)
	-- Whether to clamp sway angles
	EnableClamping = false,
	-- Maximum sway angle in degrees
	MaxSwayAngle = 20,

	-- Smoothing
	-- Final lerp alpha
	SmoothSpeed = 0.15,

	-- Inversion (weapon lag effect)
	-- Inverse the CFrame for "lag behind" feel
	InvertSway = true,

	-- Internal state (do not set manually)
	CurrentSwayCF = nil,
}

local SpringSway = {}

--[[
	Updates spring-based sway
	Should be called every frame in RenderStepped
	@param deltaTime number - Frame delta time (unused, springs are time-based)
]]
function SpringSway.Update(self : SpringSway, deltaTime)
	-- Get mouse delta and apply as force to springs
	local mouseDelta = UserInputService:GetMouseDelta()

	self.SpringX:accelerate(mouseDelta.X * self.MouseSensitivity)
	self.SpringY:accelerate(mouseDelta.Y * self.MouseSensitivity)

	-- Get spring positions
	local swayX = self.SpringX.p
	local swayY = self.SpringY.p
	local swayZ = self.SpringZ.p

	-- Optional clamping
	if self.EnableClamping then
		local maxRad = math.rad(self.MaxSwayAngle)
		swayX = math.clamp(swayX, -maxRad, maxRad)
		swayY = math.clamp(swayY, -maxRad, maxRad)
		swayZ = math.clamp(swayZ, -maxRad, maxRad)
	end

	-- Convert to CFrame
	local targetSwayCF
	if self.MapToRotation then
		-- Map spring position to rotation (like original script: Y, X, X)
		targetSwayCF = CFrame.Angles(
			swayY * self.RotationMultiplier,
			swayX * self.RotationMultiplier,
			swayX * self.RotationMultiplier
		)
	else
		-- Use as position offset
		targetSwayCF = CFrame.new(swayX, swayY, swayZ)
	end

	-- Smooth lerp to target
	self.CurrentSwayCF = self.CurrentSwayCF:Lerp(targetSwayCF, self.SmoothSpeed)
end

--[[
	Gets the spring sway CFrame
	Automatically inverted if InvertSway is true
	@return CFrame
]]
function SpringSway.GetCFrame(self : SpringSway)
	if self.InvertSway then
		return self.CurrentSwayCF:Inverse()
	end
	return self.CurrentSwayCF
end

--[[
	Gets the raw spring sway CFrame (not inverted)
	@return CFrame
]]
function SpringSway.GetRawCFrame(self : SpringSway)
	return self.CurrentSwayCF
end

--[[
	Gets current spring values (for debugging)
	@return table
]]
function SpringSway.GetSpringValues(self : SpringSway)
	local x, y, z = self.CurrentSwayCF:ToEulerAnglesXYZ()
	return {
		Position = Vector3.new(self.SpringX.p, self.SpringY.p, self.SpringZ.p),
		Velocity = Vector3.new(self.SpringX.v, self.SpringY.v, self.SpringZ.v),
		Rotation = {
			X = math.deg(x),
			Y = math.deg(y),
			Z = math.deg(z)
		}
	}
end

--[[
	Manually add force to springs (for recoil, impacts, etc.)
	@param force Vector3
]]
function SpringSway.AddForce(self : SpringSway, force)
	self.SpringX:accelerate(force.X)
	self.SpringY:accelerate(force.Y)
	self.SpringZ:accelerate(force.Z)
end

--[[
	Manually set spring velocities (for instant effects)
	@param velocity Vector3
]]
function SpringSway.SetVelocity(self : SpringSway, velocity)
	self.SpringX.v = velocity.X
	self.SpringY.v = velocity.Y
	self.SpringZ.v = velocity.Z
end

--[[
	Resets all spring values to neutral
]]
function SpringSway.Reset(self : SpringSway)
	self.SpringX.p = 0
	self.SpringX.v = 0
	self.SpringX.t = 0

	self.SpringY.p = 0
	self.SpringY.v = 0
	self.SpringY.t = 0

	self.SpringZ.p = 0
	self.SpringZ.v = 0
	self.SpringZ.t = 0

	self.CurrentSwayCF = CFrame.new()
end

--[[
	Updates configuration values
	@param config table - Configuration overrides
]]
function SpringSway.SetConfig(self : SpringSway, config)
	if not config or type(config) ~= "table" then
		return false
	end

	for key, value in pairs(config) do
		if self[key] ~= nil and key ~= "SpringX" and key ~= "SpringY" and key ~= "SpringZ" and key ~= "CurrentSwayCF" then
			self[key] = value
		end
	end

	-- Update spring properties
	self.SpringX.d = self.Damping
	self.SpringX.s = self.Stiffness

	self.SpringY.d = self.Damping
	self.SpringY.s = self.Stiffness

	self.SpringZ.d = self.Damping
	self.SpringZ.s = self.Stiffness

	return true
end

--[[
	Gets the internal spring objects (advanced usage)
	@return table - {X, Y, Z}
]]
function SpringSway.GetSprings(self : SpringSway)
	return {
		X = self.SpringX,
		Y = self.SpringY,
		Z = self.SpringZ
	}
end

--[[
	Creates a new SpringSway instance
	@param Configuration table - Configuration overrides
	@return SpringSway
]]
function module.new(Configuration : Configuration) : SpringSway
	local springSway = table.clone(SpringSway) :: SpringSway

	-- Initialize configuration
	springSway.Damping = Configuration and Configuration.Damping or DefaultConfiguration.Damping
	springSway.Stiffness =  Configuration and Configuration.Stiffness or DefaultConfiguration.Stiffness
	springSway.MouseSensitivity = Configuration and Configuration.MouseSensitivity or DefaultConfiguration.MouseSensitivity
	springSway.MapToRotation = if  Configuration and Configuration.MapToRotation ~= nil then Configuration.MapToRotation else DefaultConfiguration.MapToRotation
	springSway.RotationMultiplier =  Configuration and Configuration.RotationMultiplier or DefaultConfiguration.RotationMultiplier
	springSway.EnableClamping = if  Configuration and Configuration.EnableClamping ~= nil then Configuration.EnableClamping else DefaultConfiguration.EnableClamping
	springSway.MaxSwayAngle = Configuration and Configuration.MaxSwayAngle or DefaultConfiguration.MaxSwayAngle
	springSway.SmoothSpeed = Configuration and Configuration.SmoothSpeed or DefaultConfiguration.SmoothSpeed
	springSway.InvertSway = if  Configuration and Configuration.InvertSway ~= nil then Configuration.InvertSway else DefaultConfiguration.InvertSway

	-- Initialize springs
	springSway.SpringX = Spring.new(0)
	springSway.SpringX.d = springSway.Damping
	springSway.SpringX.s = springSway.Stiffness

	springSway.SpringY = Spring.new(0)
	springSway.SpringY.d = springSway.Damping
	springSway.SpringY.s = springSway.Stiffness

	springSway.SpringZ = Spring.new(0)
	springSway.SpringZ.d = springSway.Damping
	springSway.SpringZ.s = springSway.Stiffness

	-- Initialize state
	springSway.CurrentSwayCF = CFrame.new()

	return springSway
end

export type Configuration = typeof(DefaultConfiguration)
export type SpringSway = typeof(SpringSway) & Configuration & {
	SpringX: any,
	SpringY: any,
	SpringZ: any,
}

return module