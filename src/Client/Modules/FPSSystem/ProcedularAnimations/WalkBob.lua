--!native
--!optimize 2
--[[
	Walk Bob Module
	Handles weapon bobbing during movement
	Frame-rate independent with proper exponential decay
	Object-oriented design with instance support
--]]

local module = {}

local DefaultConfiguration = {
	-- Movement bobbing (when walking/running)
	-- Overall scale of movement bob
	MovementIntensity = 0.025,
	-- Speed of horizontal sway
	HorizontalFrequency = 8,
	HorizontalIntensity = 1,
	-- Speed of vertical bob (2x horizontal for realistic gait)
	VerticalFrequency = 16,
	VerticalIntensity = 1,
	-- Speed of forward-backward motion
	DepthFrequency = 8,
	DepthIntensity = 1,
	-- Rotation strength in degrees
	RotationIntensity = 3,
	
	-- Speed parameters
	-- Minimum speed to trigger movement bob
	MovementThreshold = 0.1,
	-- Maximum player speed for normalization
	MaxExpectedSpeed = 16,

	-- Smoothing (exponential decay rate per second)
	-- Higher = faster/more responsive transitions (10-20 recommended)
	SmoothSpeed = 15.0,

	-- Internal state (do not set manually)
	CurrentBobCF = nil,
	TargetBobCF = nil,
	IsMoving = nil,
	CurrentSpeed = nil,
	TimeAccumulator = nil,
}

-- Pre-cache math functions
local Sin = math.sin
local Cos = math.cos
local Exp = math.exp
local Rad = math.rad
local Min = math.min
local Max = math.max

local WalkBob = {}

--[[
	Set movement state
	@param moving boolean
	@param speed number - Current movement speed
]]
function WalkBob.SetMoving(self : WalkBob, moving, speed)
	self.IsMoving = moving
	self.CurrentSpeed = speed or 0
end

--[[
	Get current movement state
	@return boolean, number - IsMoving, CurrentSpeed
]]
function WalkBob.GetMovingState(self : WalkBob)
	return self.IsMoving, self.CurrentSpeed
end

--[[
	Update function (call every frame in RenderStepped)
	@param deltaTime number - Time since last frame
]]
function WalkBob.Update(self : WalkBob, deltaTime)
	if not deltaTime or deltaTime <= 0 then
		return
	end

	-- Always accumulate time for continuous wave
	self.TimeAccumulator = self.TimeAccumulator + deltaTime
	local time = self.TimeAccumulator

	-- Calculate target bob transform
	if self.IsMoving and self.CurrentSpeed > self.MovementThreshold then
		-- Normalize speed (0 to 1 range)
		local speedScale = Min(self.CurrentSpeed / self.MaxExpectedSpeed, 1.0)
		local intensity = self.MovementIntensity * speedScale

		-- Position bobbing using sine/cosine waves (no PI2 multiplier for natural feel)
		-- Horizontal bob (left-right)
		local xOffset = intensity * Sin(time * self.HorizontalFrequency) * self.HorizontalIntensity

		-- Vertical bob (up-down)
		local yOffset = intensity * Cos(time * self.VerticalFrequency) * self.VerticalIntensity

		-- Depth bob (forward-backward)
		local zOffset = intensity * Sin(time * self.DepthFrequency) * self.DepthIntensity

		-- Rotation bobbing (tilting motion)
		-- Pitch (up-down rotation)
		local pitchRot = Rad(self.RotationIntensity * speedScale * Sin(time * self.VerticalFrequency))

		-- Yaw (left-right rotation)
		local yawRot = Rad(self.RotationIntensity * speedScale * Cos(time * self.HorizontalFrequency))

		self.TargetBobCF = CFrame.new(xOffset, yOffset, -zOffset)
			* CFrame.Angles(pitchRot, yawRot, 0)
	else
		-- No movement = no bob (return to neutral)
		self.TargetBobCF = CFrame.new()
	end

	-- Frame-rate independent exponential interpolation
	local alpha = 1 - Exp(-self.SmoothSpeed * deltaTime)
	self.CurrentBobCF = self.CurrentBobCF:Lerp(self.TargetBobCF, alpha)
end

--[[
	Gets the walk bob CFrame
	@return CFrame
]]
function WalkBob.GetCFrame(self : WalkBob)
	return self.CurrentBobCF
end

--[[
	Gets the target bob CFrame (for debugging)
	@return CFrame
]]
function WalkBob.GetTargetCFrame(self : WalkBob)
	return self.TargetBobCF
end

--[[
	Gets debug information
	@return table
]]
function WalkBob.GetDebugInfo(self : WalkBob)
	local x, y, z = self.CurrentBobCF:ToEulerAnglesXYZ()
	local pos = self.CurrentBobCF.Position

	return {
		IsMoving = self.IsMoving,
		CurrentSpeed = self.CurrentSpeed,
		TimeAccumulator = self.TimeAccumulator,
		Position = {X = pos.X, Y = pos.Y, Z = pos.Z},
		Rotation = {
			X = math.deg(x),
			Y = math.deg(y),
			Z = math.deg(z)
		}
	}
end

--[[
	Resets all values to neutral
]]
function WalkBob.Reset(self : WalkBob)
	self.CurrentBobCF = CFrame.new()
	self.TargetBobCF = CFrame.new()
	self.IsMoving = false
	self.CurrentSpeed = 0
	self.TimeAccumulator = 0
end

--[[
	Updates configuration values
	@param config table - Configuration overrides
]]
function WalkBob.SetConfig(self : WalkBob, config : Configuration)
	if not config or type(config) ~= "table" then
		return false
	end

	for key, value in pairs(config) do
		if self[key] ~= nil and key ~= "CurrentBobCF" and key ~= "TargetBobCF" 
			and key ~= "IsMoving" and key ~= "CurrentSpeed" and key ~= "TimeAccumulator" then
			self[key] = value
		end
	end

	return true
end

--[[
	Sets the time accumulator directly (advanced usage)
	Useful for synchronizing walk bob with animation cycles
	@param time number
]]
function WalkBob.SetTimeAccumulator(self : WalkBob, time)
	self.TimeAccumulator = time
end

--[[
	Gets the current time accumulator value
	@return number
]]
function WalkBob.GetTimeAccumulator(self : WalkBob)
	return self.TimeAccumulator
end

--[[
	Creates a new WalkBob instance
	@param Configuration table - Configuration overrides
	@return WalkBob
]]
function module.new(Configuration : Configuration) : WalkBob
	local walkBob = table.clone(WalkBob)

	-- Initialize configuration
	walkBob.MovementIntensity = Configuration and Configuration.MovementIntensity or DefaultConfiguration.MovementIntensity
	walkBob.HorizontalFrequency = Configuration and Configuration.HorizontalFrequency or DefaultConfiguration.HorizontalFrequency
	walkBob.HorizontalIntensity = Configuration and Configuration.HorizontalIntensity or DefaultConfiguration.HorizontalIntensity
	
	walkBob.VerticalFrequency = Configuration and Configuration.VerticalFrequency or DefaultConfiguration.VerticalFrequency
	walkBob.VerticalIntensity = Configuration and Configuration.VerticalIntensity or DefaultConfiguration.VerticalIntensity
	
	walkBob.DepthFrequency = Configuration and Configuration.DepthFrequency or DefaultConfiguration.DepthFrequency
	walkBob.DepthIntensity = Configuration and Configuration.DepthIntensity or DefaultConfiguration.DepthIntensity
	
	walkBob.RotationIntensity = Configuration and Configuration.RotationIntensity or DefaultConfiguration.RotationIntensity
	
	walkBob.MovementThreshold = Configuration and Configuration.MovementThreshold or DefaultConfiguration.MovementThreshold
	walkBob.MaxExpectedSpeed = Configuration and Configuration.MaxExpectedSpeed or DefaultConfiguration.MaxExpectedSpeed

	walkBob.SmoothSpeed = Configuration and Configuration.SmoothSpeed or DefaultConfiguration.SmoothSpeed

	-- Initialize state
	walkBob.CurrentBobCF = CFrame.new()
	walkBob.TargetBobCF = CFrame.new()
	walkBob.IsMoving = false
	walkBob.CurrentSpeed = 0
	walkBob.TimeAccumulator = 0

	return walkBob
end

export type Configuration = typeof(DefaultConfiguration)
export type WalkBob = typeof(WalkBob) & Configuration

return module