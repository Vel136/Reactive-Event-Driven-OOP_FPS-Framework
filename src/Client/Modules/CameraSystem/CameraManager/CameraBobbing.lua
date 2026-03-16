--!native
--!optimize 2
--[[
	Camera Bobbing Module
	Handles camera head bob using CameraOffset for natural walking motion
	Version 2.0
--]]

local module = {}

-- Pre-cache
local sin = math.sin
local cos = math.cos
local clamp = math.clamp
local round = math.round
local clock = os.clock
local V3 = Vector3.new

-- Default Configuration
local DefaultBobbingConfig = {
	-- Vertical Bobbing (Up/Down Motion)
	VerticalFrequency = 10,       -- How fast the head bobs up and down
	VerticalIntensity = 0.05,     -- How much the camera moves vertically

	-- Horizontal Bobbing (Side-to-Side Motion)
	HorizontalFrequency = 8,      -- How fast the head sways left and right
	HorizontalIntensity = 0.03,   -- How much the camera moves horizontally

	-- Velocity Settings
	VelocityMultiplier = 100,     -- Scales bobbing based on movement speed
	VelocitySmoothness = 0.2,     -- How smoothly velocity changes affect bobbing (0-1)

	-- WalkSpeed Adaptation
	UseWalkSpeedScale = true,     -- Scale bobbing frequency based on WalkSpeed
	BaseWalkSpeed = 16,           -- Reference WalkSpeed for default bobbing (default Roblox WalkSpeed)
}

-- Utility: Linear interpolation
local function NumLerp(num1: number, num2: number, rate: number): number
	return num1 + (num2 - num1) * rate
end

-- Utility: Calculate sine curve for oscillation
local function CalculateCurve(base: number, set: number): number
	return sin(clock() * base) * set
end

-- Type Definitions
export type Configuration = {
	-- Vertical Bobbing (Up/Down Motion)
	VerticalFrequency: number?,    -- How fast the head bobs up and down (default: 10)
	VerticalIntensity: number?,    -- How much the camera moves vertically (default: 0.05)

	-- Horizontal Bobbing (Side-to-Side Motion)
	HorizontalFrequency: number?,  -- How fast the head sways left and right (default: 8)
	HorizontalIntensity: number?,  -- How much the camera moves horizontally (default: 0.03)

	-- Velocity Settings
	VelocityMultiplier: number?,   -- Scales bobbing based on movement speed (default: 100)
	VelocitySmoothness: number?,   -- How smoothly velocity changes affect bobbing, 0-1 (default: 0.2)

	-- WalkSpeed Adaptation
	UseWalkSpeedScale: boolean?,   -- Scale bobbing frequency based on WalkSpeed (default: true)
	BaseWalkSpeed: number?,        -- Reference WalkSpeed for default bobbing (default: 16)
}

local CameraBobbing = {
	VerticalFrequency = DefaultBobbingConfig.VerticalFrequency,
	VerticalIntensity = DefaultBobbingConfig.VerticalIntensity,
	HorizontalFrequency = DefaultBobbingConfig.HorizontalFrequency,
	HorizontalIntensity = DefaultBobbingConfig.HorizontalIntensity,
	VelocityMultiplier = DefaultBobbingConfig.VelocityMultiplier,
	VelocitySmoothness = DefaultBobbingConfig.VelocitySmoothness,
	UseWalkSpeedScale = DefaultBobbingConfig.UseWalkSpeedScale,
	BaseWalkSpeed = DefaultBobbingConfig.BaseWalkSpeed,

	CurrentVelocity = 0,
	HumanoidRootPart = nil :: BasePart?,
	Humanoid = nil :: Humanoid?,
}

function CameraBobbing.Update(self: CameraBobbing, deltaTime: number)
	if not self.HumanoidRootPart or not self.Humanoid then
		warn("CameraBobbing: HumanoidRootPart or Humanoid not set")
		return
	end

	-- Get current velocity magnitude
	local velocity = self.HumanoidRootPart.AssemblyLinearVelocity
	local targetVelocity = round(V3(velocity.X, velocity.Y, velocity.Z).Magnitude)

	-- Smooth velocity transition
	local lerpRate = clamp(self.VelocitySmoothness * deltaTime * 60, 0, 1)
	self.CurrentVelocity = NumLerp(self.CurrentVelocity, targetVelocity, lerpRate)

	local vel = self.CurrentVelocity
	local velocityScale = vel / self.VelocityMultiplier

	-- Calculate WalkSpeed scale factor
	local walkSpeedScale = 1
	if self.UseWalkSpeedScale then
		walkSpeedScale = self.Humanoid.WalkSpeed / self.BaseWalkSpeed
	end

	-- Calculate vertical bob (up and down motion) with WalkSpeed scaling
	local verticalBob = CalculateCurve(
		self.VerticalFrequency * walkSpeedScale, 
		self.VerticalIntensity
	) * velocityScale

	-- Calculate horizontal bob (side to side motion) with WalkSpeed scaling
	local horizontalBob = CalculateCurve(
		self.HorizontalFrequency * walkSpeedScale, 
		self.HorizontalIntensity
	) * velocityScale

	-- Apply bobbing to camera offset
	self.Humanoid.CameraOffset = V3(horizontalBob, verticalBob, 0)
end

function CameraBobbing.SetConfig(self: CameraBobbing, Configuration: Configuration)
	self.VerticalFrequency = Configuration.VerticalFrequency or self.VerticalFrequency
	self.VerticalIntensity = Configuration.VerticalIntensity or self.VerticalIntensity
	self.HorizontalFrequency = Configuration.HorizontalFrequency or self.HorizontalFrequency
	self.HorizontalIntensity = Configuration.HorizontalIntensity or self.HorizontalIntensity
	self.VelocityMultiplier = Configuration.VelocityMultiplier or self.VelocityMultiplier
	self.VelocitySmoothness = Configuration.VelocitySmoothness or self.VelocitySmoothness
	self.UseWalkSpeedScale = Configuration.UseWalkSpeedScale ~= nil and Configuration.UseWalkSpeedScale or self.UseWalkSpeedScale
	self.BaseWalkSpeed = Configuration.BaseWalkSpeed or self.BaseWalkSpeed

	return true
end

function CameraBobbing.SetHumanoidRootPart(self: CameraBobbing, hrp: BasePart)
	self.HumanoidRootPart = hrp
end

function CameraBobbing.SetHumanoid(self: CameraBobbing, humanoid: Humanoid)
	self.Humanoid = humanoid
end

function CameraBobbing.Reset(self: CameraBobbing)
	self.CurrentVelocity = 0
	if self.Humanoid then
		self.Humanoid.CameraOffset = V3(0, 0, 0)
	end
end

function module.new(Configuration: Configuration?, HumanoidRootPart: BasePart?, Humanoid: Humanoid?): CameraBobbing
	local instance = setmetatable({},{__index = CameraBobbing})

	instance.VerticalFrequency = Configuration and Configuration.VerticalFrequency or DefaultBobbingConfig.VerticalFrequency
	instance.VerticalIntensity = Configuration and Configuration.VerticalIntensity or DefaultBobbingConfig.VerticalIntensity
	instance.HorizontalFrequency = Configuration and Configuration.HorizontalFrequency or DefaultBobbingConfig.HorizontalFrequency
	instance.HorizontalIntensity = Configuration and Configuration.HorizontalIntensity or DefaultBobbingConfig.HorizontalIntensity
	instance.VelocityMultiplier = Configuration and Configuration.VelocityMultiplier or DefaultBobbingConfig.VelocityMultiplier
	instance.VelocitySmoothness = Configuration and Configuration.VelocitySmoothness or DefaultBobbingConfig.VelocitySmoothness
	instance.UseWalkSpeedScale = Configuration and (Configuration.UseWalkSpeedScale ~= nil and Configuration.UseWalkSpeedScale or DefaultBobbingConfig.UseWalkSpeedScale) or DefaultBobbingConfig.UseWalkSpeedScale
	instance.BaseWalkSpeed = Configuration and Configuration.BaseWalkSpeed or DefaultBobbingConfig.BaseWalkSpeed

	instance.CurrentVelocity = 0
	instance.HumanoidRootPart = HumanoidRootPart
	instance.Humanoid = Humanoid
	
	return instance
end

export type CameraBobbing = typeof(setmetatable({},{__index = CameraBobbing}))

return module