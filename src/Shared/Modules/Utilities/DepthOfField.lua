--!native
--!optimize 2

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Spring = require(game.ReplicatedStorage.Shared.Modules.Utilities.Spring)

local module = {}

local DefaultConfiguration = {
	-- Focus Settings
	FocusDistance = 20,
	NearBlurDistance = 0.5,
	FarBlurDistance = 50,
	InFocusRadius = 10,

	-- Blur Intensity (0-1 range) - BASE VALUES
	NearIntensity = 0.2,
	FarIntensity = 0.5,


	IntensityBuildup = true, -- Enable spring-based intensity
	IntensityDamping = 0.7, -- How quickly intensity recovers
	IntensityStiffness = 6, -- How springy the recovery is
	MaxNearIntensity = 1.0, -- Maximum near intensity cap
	MaxFarIntensity = 0.8, -- Maximum far intensity cap
	IntensityDecayRate = 0.95, -- How fast buildup decays per second (0-1)

	-- Spring Properties
	Damping = 0.8,
	Stiffness = 8,

	-- Auto Focus
	AutoFocus = true,
	AutoFocusMaxDistance = 500,
	RaycastFilter = nil,

	-- Enhanced Smoothness Settings
	FocusDeadzone = 2,
	MaxFocusSpeed = 200,
	FocusSmoothing = 0.3,
	DynamicIntensity = true,
	MultiSampleRaycast = true,
	AdaptiveDamping = true,

	-- Performance
	UpdateRate = 60,
	AdaptiveUpdateRate = true,
	Enabled = true,

	-- Internal state (do not set manually)
	DepthOfFieldEffect = nil,
	Camera = nil,
	RaycastParams = nil,
	PreviousTarget = nil,
	_lastFocusDistance = nil,
}

local DepthOfField = {}

--[[
	Creates the DepthOfFieldEffect instance
	Internal use only
]]
function DepthOfField._CreateEffect(self : DepthOfField)
	if self.DepthOfFieldEffect then
		self.DepthOfFieldEffect:Destroy()
	end

	local dofEffect = Instance.new("DepthOfFieldEffect")
	dofEffect.Name = "FPS_DOF"
	dofEffect.FocusDistance = self.FocusDistance
	dofEffect.InFocusRadius = self.InFocusRadius
	dofEffect.NearIntensity = self.NearIntensity
	dofEffect.FarIntensity = self.FarIntensity
	dofEffect.Enabled = self.Enabled
	dofEffect.Parent = self.Camera

	self.DepthOfFieldEffect = dofEffect
end

--[[
	Performs raycast-based auto focus with multi-sampling
	Internal use only
]]
function DepthOfField._PerformAutoFocus(self : DepthOfField)
	local camera = self.Camera
	local origin = camera.CFrame.Position
	local centerDir = camera.CFrame.LookVector

	local raycastParams = self.RaycastParams or RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = self.RaycastFilter or {}

	local newTarget

	if self.MultiSampleRaycast then
		local samples = {}
		local sampleOffsets = {
			Vector3.new(0, 0, 0),
			Vector3.new(0.02, 0, 0),
			Vector3.new(-0.02, 0, 0),
			Vector3.new(0, 0.02, 0),
			Vector3.new(0, -0.02, 0),
		}

		for _, offset in ipairs(sampleOffsets) do
			local direction = (centerDir + offset).Unit
			local result = workspace:Raycast(
				origin,
				direction * self.AutoFocusMaxDistance,
				raycastParams
			)

			if result then
				table.insert(samples, result.Distance)
			end
		end

		if #samples > 0 then
			table.sort(samples)
			newTarget = samples[math.ceil(#samples / 2)]
		else
			newTarget = self.AutoFocusMaxDistance
		end
	else
		local result = workspace:Raycast(
			origin, 
			centerDir * self.AutoFocusMaxDistance,
			raycastParams
		)

		newTarget = result and result.Distance or self.AutoFocusMaxDistance
	end

	local currentTarget = self.FocusSpring.t
	local delta = math.abs(newTarget - currentTarget)

	if delta > self.FocusDeadzone then
		if self.PreviousTarget and self.FocusSmoothing > 0 then
			newTarget = self.PreviousTarget * self.FocusSmoothing + 
				newTarget * (1 - self.FocusSmoothing)
		end

		self.FocusSpring.t = newTarget
		self.PreviousTarget = newTarget
	end
end

--[[
	Updates depth of field effect
	Should be called every frame or at specified update rate
	@param deltaTime number - Frame delta time
]]
function DepthOfField.Update(self : DepthOfField, deltaTime)
	if not self.Enabled or not self.DepthOfFieldEffect then
		return
	end

	local previousFocusDistance = self.FocusSpring.p

	if self.AutoFocus then
		self:_PerformAutoFocus()
	end

	if self.MaxFocusSpeed > 0 then
		local targetDistance = self.FocusSpring.t
		local currentDistance = self.FocusSpring.p
		local maxChange = self.MaxFocusSpeed * deltaTime

		if math.abs(targetDistance - currentDistance) > maxChange then
			local direction = math.sign(targetDistance - currentDistance)
			self.FocusSpring.t = currentDistance + (direction * maxChange)
		end
	end

	if self.AdaptiveDamping then
		local focusVelocity = math.abs(self.FocusSpring.v)
		local adaptiveDamping = self.Damping + (focusVelocity / 100) * 0.2
		self.FocusSpring.d = math.clamp(adaptiveDamping, self.Damping, 1)
	end

	local focusDistance = self.FocusSpring.p

	if self.AdaptiveUpdateRate then
		local isSettled = math.abs(self.FocusSpring.v) < 0.5

		if isSettled and self._lastFocusDistance then
			local delta = math.abs(focusDistance - self._lastFocusDistance)
			if delta < 0.1 then
				self._lastFocusDistance = focusDistance
				return
			end
		end
	end

	self._lastFocusDistance = focusDistance
	self.DepthOfFieldEffect.FocusDistance = focusDistance


	if self.IntensityBuildup then
		-- Natural decay towards base intensity
		local decayFactor = math.pow(self.IntensityDecayRate, deltaTime * 60)
		self.NearIntensitySpring.t = self.NearIntensity * decayFactor + 
			self.NearIntensitySpring.t * (1 - decayFactor)
		self.FarIntensitySpring.t = self.FarIntensity * decayFactor + 
			self.FarIntensitySpring.t * (1 - decayFactor)

		-- Get current spring positions
		local currentNear = math.clamp(self.NearIntensitySpring.p, 0, self.MaxNearIntensity)
		local currentFar = math.clamp(self.FarIntensitySpring.p, 0, self.MaxFarIntensity)

		-- Apply dynamic intensity scaling if enabled
		if self.DynamicIntensity then
			local intensityScale = math.clamp(focusDistance / 50, 0.5, 1.5)
			self.DepthOfFieldEffect.FarIntensity = currentFar * intensityScale
			self.DepthOfFieldEffect.NearIntensity = currentNear * (2 - intensityScale)
		else
			self.DepthOfFieldEffect.NearIntensity = currentNear
			self.DepthOfFieldEffect.FarIntensity = currentFar
		end
	else
		-- Original behavior without buildup
		if self.DynamicIntensity then
			local intensityScale = math.clamp(focusDistance / 50, 0.5, 1.5)
			self.DepthOfFieldEffect.FarIntensity = self.FarIntensity * intensityScale
			self.DepthOfFieldEffect.NearIntensity = self.NearIntensity * (2 - intensityScale)
		else
			self.DepthOfFieldEffect.NearIntensity = self.NearIntensity
			self.DepthOfFieldEffect.FarIntensity = self.FarIntensity
		end
	end
end

--[[
	Adds intensity buildup (call when shooting/recoiling)
	@param nearAmount number - Amount to add to near intensity
	@param farAmount number? - Amount to add to far intensity (defaults to nearAmount * 0.6)
]]
function DepthOfField.AddIntensity(self : DepthOfField, nearAmount, farAmount)
	if not self.IntensityBuildup then
		return
	end

	farAmount = farAmount or (nearAmount * 0.6)

	-- Add to spring targets (accumulates)
	self.NearIntensitySpring.t = math.clamp(
		self.NearIntensitySpring.t + nearAmount,
		0,
		self.MaxNearIntensity
	)

	self.FarIntensitySpring.t = math.clamp(
		self.FarIntensitySpring.t + farAmount,
		0,
		self.MaxFarIntensity
	)
end

--[[
	Applies an instant intensity spike (bypasses spring)
	Useful for sudden events like explosions
	@param nearAmount number
	@param farAmount number?
]]
function DepthOfField.SpikeIntensity(self : DepthOfField, nearAmount, farAmount)
	if not self.IntensityBuildup then
		return
	end

	farAmount = farAmount or (nearAmount * 0.6)

	-- Directly set position for instant effect
	self.NearIntensitySpring.p = math.clamp(
		self.NearIntensitySpring.p + nearAmount,
		0,
		self.MaxNearIntensity
	)

	self.FarIntensitySpring.p = math.clamp(
		self.FarIntensitySpring.p + farAmount,
		0,
		self.MaxFarIntensity
	)
end

--[[
	Resets intensity to base values
	@param instant boolean? - Skip spring animation
]]
function DepthOfField.ResetIntensity(self : DepthOfField, instant)
	if not self.IntensityBuildup then
		return
	end

	if instant then
		self.NearIntensitySpring.p = self.NearIntensity
		self.NearIntensitySpring.v = 0
		self.FarIntensitySpring.p = self.FarIntensity
		self.FarIntensitySpring.v = 0
	end

	self.NearIntensitySpring.t = self.NearIntensity
	self.FarIntensitySpring.t = self.FarIntensity
end

--[[
	Sets the focus distance
	@param distance number - Distance in studs
	@param instant boolean? - Skip spring animation
]]
function DepthOfField.SetFocus(self : DepthOfField, distance, instant)
	if instant then
		self.FocusSpring.p = distance
		self.FocusSpring.v = 0
	end
	self.FocusSpring.t = distance
	self.PreviousTarget = distance
end

--[[
	Sets BASE blur intensity (what it returns to)
	@param near number - Near intensity (0-1)
	@param far number - Far intensity (0-1)
]]
function DepthOfField.SetIntensity(self : DepthOfField, near, far)
	self.NearIntensity = near
	self.FarIntensity = far
	
	if self.DepthOfFieldEffect and not self.IntensityBuildup and not self.DynamicIntensity then
		self.DepthOfFieldEffect.NearIntensity = near
		self.DepthOfFieldEffect.FarIntensity = far
	end
end

--[[
	Sets focus target to a position or part
	@param target Vector3 | BasePart
]]
function DepthOfField.SetTarget(self : DepthOfField, target)
	local targetPos = if typeof(target) == "Instance" 
		then target.Position 
		else target

	local distance = (targetPos - self.Camera.CFrame.Position).Magnitude
	self:SetFocus(distance)
end

--[[
	Enables the depth of field effect
]]
function DepthOfField.Enable(self : DepthOfField)
	self.Enabled = true
	if self.DepthOfFieldEffect then
		self.DepthOfFieldEffect.Enabled = true
	end
end

--[[
	Disables the depth of field effect
]]
function DepthOfField.Disable(self : DepthOfField)
	self.Enabled = false
	if self.DepthOfFieldEffect then
		self.DepthOfFieldEffect.Enabled = false
	end
end

--[[
	Toggles the depth of field effect on/off
]]
function DepthOfField.Toggle(self : DepthOfField)
	if self.Enabled then
		self:Disable()
	else
		self:Enable()
	end
end

--[[
	Resets spring to neutral state
]]
function DepthOfField.Reset(self : DepthOfField)
	self.FocusSpring.p = self.FocusDistance
	self.FocusSpring.v = 0
	self.FocusSpring.t = self.FocusDistance
	self.PreviousTarget = self.FocusDistance
	self._lastFocusDistance = self.FocusDistance

	if self.IntensityBuildup then
		self:ResetIntensity(true)
	end
end

--[[
	Gets current spring values (for debugging)
	@return table
]]
function DepthOfField.GetSpringValues(self : DepthOfField)
	local values = {
		Focus = {
			Position = self.FocusSpring.p,
			Velocity = self.FocusSpring.v,
			Target = self.FocusSpring.t,
		}
	}

	if self.IntensityBuildup then
		values.NearIntensity = {
			Position = self.NearIntensitySpring.p,
			Velocity = self.NearIntensitySpring.v,
			Target = self.NearIntensitySpring.t,
		}
		values.FarIntensity = {
			Position = self.FarIntensitySpring.p,
			Velocity = self.FarIntensitySpring.v,
			Target = self.FarIntensitySpring.t,
		}
	end

	return values
end

--[[
	Manually add force to focus spring (for shake effects)
	@param force number
]]
function DepthOfField.AddForce(self : DepthOfField, force)
	self.FocusSpring:accelerate(force)
end

--[[
	Updates configuration values
	@param config table - Configuration overrides
]]
function DepthOfField.SetConfig(self : DepthOfField, config)
	if not config or type(config) ~= "table" then
		return false
	end

	for key, value in pairs(config) do
		if self[key] ~= nil and key ~= "FocusSpring" and key ~= "DepthOfFieldEffect" 
			and key ~= "Camera" and key ~= "PreviousTarget" and key ~= "_lastFocusDistance"
			and key ~= "NearIntensitySpring" and key ~= "FarIntensitySpring" then
			self[key] = value
		end
	end

	if config.Damping then
		self.FocusSpring.d = config.Damping
	end
	if config.Stiffness then
		self.FocusSpring.s = config.Stiffness
	end

	-- Update intensity spring properties
	if self.IntensityBuildup then
		if config.IntensityDamping then
			self.NearIntensitySpring.d = config.IntensityDamping
			self.FarIntensitySpring.d = config.IntensityDamping
		end
		if config.IntensityStiffness then
			self.NearIntensitySpring.s = config.IntensityStiffness
			self.FarIntensitySpring.s = config.IntensityStiffness
		end
	end

	if self.DepthOfFieldEffect then
		if config.InFocusRadius then
			self.DepthOfFieldEffect.InFocusRadius = config.InFocusRadius
		end
		if config.Enabled ~= nil then
			self.DepthOfFieldEffect.Enabled = config.Enabled
		end
	end

	return true
end

--[[
	Gets the internal spring object (advanced usage)
	@return Spring
]]
function DepthOfField.GetSpring(self : DepthOfField)
	return self.FocusSpring
end

--[[
	Destroys the depth of field instance
]]
function DepthOfField.Destroy(self : DepthOfField)
	if self.UpdateConnection then
		self.UpdateConnection:Disconnect()
		self.UpdateConnection = nil
	end

	if self.DepthOfFieldEffect then
		self.DepthOfFieldEffect:Destroy()
		self.DepthOfFieldEffect = nil
	end

	setmetatable(self, nil)
end

--[[
	Creates a new DepthOfField instance
	@param camera Camera? - Camera to apply effect to (defaults to CurrentCamera)
	@param Configuration table? - Configuration overrides
	@return DepthOfField
]]
function module.new(camera : Camera?, Configuration : Configuration?) : DepthOfField
	local depthOfField = table.clone(DepthOfField) :: DepthOfField

	depthOfField.Camera = camera or Workspace.CurrentCamera

	-- Initialize configuration
	depthOfField.FocusDistance = Configuration and Configuration.FocusDistance or DefaultConfiguration.FocusDistance
	depthOfField.NearBlurDistance = Configuration and Configuration.NearBlurDistance or DefaultConfiguration.NearBlurDistance
	depthOfField.FarBlurDistance = Configuration and Configuration.FarBlurDistance or DefaultConfiguration.FarBlurDistance
	depthOfField.InFocusRadius = Configuration and Configuration.InFocusRadius or DefaultConfiguration.InFocusRadius
	depthOfField.NearIntensity = Configuration and Configuration.NearIntensity or DefaultConfiguration.NearIntensity
	depthOfField.FarIntensity = Configuration and Configuration.FarIntensity or DefaultConfiguration.FarIntensity
	depthOfField.Damping = Configuration and Configuration.Damping or DefaultConfiguration.Damping
	depthOfField.Stiffness = Configuration and Configuration.Stiffness or DefaultConfiguration.Stiffness
	depthOfField.AutoFocus = if Configuration and Configuration.AutoFocus ~= nil then Configuration.AutoFocus else DefaultConfiguration.AutoFocus
	depthOfField.AutoFocusMaxDistance = Configuration and Configuration.AutoFocusMaxDistance or DefaultConfiguration.AutoFocusMaxDistance
	depthOfField.RaycastFilter = Configuration and Configuration.RaycastFilter or DefaultConfiguration.RaycastFilter
	depthOfField.UpdateRate = Configuration and Configuration.UpdateRate or DefaultConfiguration.UpdateRate
	depthOfField.Enabled = if Configuration and Configuration.Enabled ~= nil then Configuration.Enabled else DefaultConfiguration.Enabled

	-- Enhanced settings
	depthOfField.FocusDeadzone = Configuration and Configuration.FocusDeadzone or DefaultConfiguration.FocusDeadzone
	depthOfField.MaxFocusSpeed = Configuration and Configuration.MaxFocusSpeed or DefaultConfiguration.MaxFocusSpeed
	depthOfField.FocusSmoothing = Configuration and Configuration.FocusSmoothing or DefaultConfiguration.FocusSmoothing
	depthOfField.DynamicIntensity = if Configuration and Configuration.DynamicIntensity ~= nil then Configuration.DynamicIntensity else DefaultConfiguration.DynamicIntensity
	depthOfField.MultiSampleRaycast = if Configuration and Configuration.MultiSampleRaycast ~= nil then Configuration.MultiSampleRaycast else DefaultConfiguration.MultiSampleRaycast
	depthOfField.AdaptiveDamping = if Configuration and Configuration.AdaptiveDamping ~= nil then Configuration.AdaptiveDamping else DefaultConfiguration.AdaptiveDamping
	depthOfField.AdaptiveUpdateRate = if Configuration and Configuration.AdaptiveUpdateRate ~= nil then Configuration.AdaptiveUpdateRate else DefaultConfiguration.AdaptiveUpdateRate

	-- Intensity buildup settings
	depthOfField.IntensityBuildup = if Configuration and Configuration.IntensityBuildup ~= nil then Configuration.IntensityBuildup else DefaultConfiguration.IntensityBuildup
	depthOfField.IntensityDamping = Configuration and Configuration.IntensityDamping or DefaultConfiguration.IntensityDamping
	depthOfField.IntensityStiffness = Configuration and Configuration.IntensityStiffness or DefaultConfiguration.IntensityStiffness
	depthOfField.MaxNearIntensity = Configuration and Configuration.MaxNearIntensity or DefaultConfiguration.MaxNearIntensity
	depthOfField.MaxFarIntensity = Configuration and Configuration.MaxFarIntensity or DefaultConfiguration.MaxFarIntensity
	depthOfField.IntensityDecayRate = Configuration and Configuration.IntensityDecayRate or DefaultConfiguration.IntensityDecayRate

	-- Internal state
	depthOfField.RaycastParams = RaycastParams.new()
	depthOfField.PreviousTarget = depthOfField.FocusDistance
	depthOfField._lastFocusDistance = depthOfField.FocusDistance

	-- Initialize springs
	depthOfField.FocusSpring = Spring.new(depthOfField.FocusDistance)
	depthOfField.FocusSpring.d = depthOfField.Damping
	depthOfField.FocusSpring.s = depthOfField.Stiffness

	-- Initialize intensity springs
	if depthOfField.IntensityBuildup then
		depthOfField.NearIntensitySpring = Spring.new(depthOfField.NearIntensity)
		depthOfField.NearIntensitySpring.d = depthOfField.IntensityDamping
		depthOfField.NearIntensitySpring.s = depthOfField.IntensityStiffness

		depthOfField.FarIntensitySpring = Spring.new(depthOfField.FarIntensity)
		depthOfField.FarIntensitySpring.d = depthOfField.IntensityDamping
		depthOfField.FarIntensitySpring.s = depthOfField.IntensityStiffness
	end

	-- Create effect
	depthOfField:_CreateEffect()

	-- Start update loop
	local updateInterval = if depthOfField.UpdateRate > 0 
		then 1 / depthOfField.UpdateRate 
		else 0
	local lastUpdate = 0

	depthOfField.UpdateConnection = RunService.RenderStepped:Connect(function(deltaTime)
		lastUpdate = lastUpdate + deltaTime
		if updateInterval > 0 and lastUpdate < updateInterval then
			return
		end
		lastUpdate = 0

		depthOfField:Update(deltaTime)
	end)

	return depthOfField
end

-- Enhanced preset configurations
module.Presets = {
	Cinematic = {
		Damping = 0.9,
		Stiffness = 4,
		NearIntensity = .125,
		FarIntensity = 0.45,
		MaxNearIntensity = 5,
		InFocusRadius = 5,
		FocusSmoothing = 0.4,
		MaxFocusSpeed = 150,
		DynamicIntensity = true,
		IntensityBuildup = true,
		IntensityDamping = 0.8,
		IntensityStiffness = 5,
	},

	Snappy = {
		Damping = 0.7,
		Stiffness = 15,
		NearIntensity = 0.6,
		FarIntensity = 0.4,
		InFocusRadius = 15,
		FocusSmoothing = 0.1,
		MaxFocusSpeed = 300,
		FocusDeadzone = 3,
		IntensityBuildup = true,
		IntensityDamping = 0.6,
		IntensityStiffness = 10,
	},

	Realistic = {
		Damping = 0.85,
		Stiffness = 8,
		NearIntensity = 0.75,
		FarIntensity = 0.5,
		InFocusRadius = 10,
		FocusSmoothing = 0.3,
		MaxFocusSpeed = 200,
		DynamicIntensity = true,
		MultiSampleRaycast = true,
		IntensityBuildup = true,
		IntensityDamping = 0.7,
		IntensityStiffness = 6,
		IntensityDecayRate = 0.92,
	},

	FPSShooter = {
		Damping = 0.8,
		Stiffness = 10,
		NearIntensity = 0.3,
		FarIntensity = 0.4,
		InFocusRadius = 12,
		IntensityBuildup = true,
		IntensityDamping = 0.65,
		IntensityStiffness = 8,
		MaxNearIntensity = 10,
		IntensityDecayRate = 0.99, -- Faster recovery
		
		DynamicIntensity = true,
		MultiSampleRaycast = true,
		FocusSmoothing = 0.3,
		MaxFocusSpeed = 700,
	},
}

export type Configuration = typeof(DefaultConfiguration)
export type DepthOfField = typeof(DepthOfField) & Configuration & {
	FocusSpring: any,
	NearIntensitySpring: any?,
	FarIntensitySpring: any?,
	UpdateConnection: RBXScriptConnection?,
}

return module