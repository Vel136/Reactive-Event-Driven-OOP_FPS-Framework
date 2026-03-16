 --!native
--!optimize 2
--[[
	Bullet Eject Module
	Handles realistic shell casing ejection for weapons
	Uses object pooling and physics-based trajectories
	Supports configurable ejection patterns and forces
	Accepts both Attachment and BasePart as ejection points
--]]

local RunService = game:GetService("RunService")
local ObjectCache = require(game.ReplicatedStorage.Shared.Modules.Utilities.ObjectCache)

local module = {}

local DefaultConfiguration = {
	-- Ejection direction (relative to camera/attachment)
	-- Positive values go right, up, forward respectively
	EjectRight = 1.2,
	EjectUp = 0.5,
	EjectForward = -0.25,

	-- Ejection force
	BaseSpeed = 18,
	SpeedVariance = 2, -- ±variance in speed

	-- Angular randomness (in radians)
	AngleNoise = math.rad(3),

	-- Angular velocity ranges
	AngularVelocity = {
		X = {Min = -12, Max = 12},
		Y = {Min = -20, Max = 20},
		Z = {Min = -12, Max = 12},
	},

	-- Lifetime
	CasingLifetime = 1,

	-- Object pooling
	PoolSize = 30,
	PoolContainer = nil, -- Set this to workspace.Effects or similar

	-- Performance
	UseRenderStepped = true, -- Update ejection point CFrame every frame

	-- Internal state (do not set manually)
	CurrentEjectCFrame = nil,
}

local BulletEject = {}

--[[
	Gets the world CFrame of the ejection point
	@return CFrame
]]
function BulletEject.GetEjectionPointCFrame(self : BulletEject)
	if self.EjectionPoint then
		if self.EjectionPoint:IsA("Attachment") then
			return self.EjectionPoint.WorldCFrame
		elseif self.EjectionPoint:IsA("BasePart") then
			return self.EjectionPoint.CFrame
		end
	end
	return CFrame.new()
end

--[[
	Ejects a shell casing with physics
	@param cameraOrAttachmentCF CFrame - Camera CFrame or custom attachment CFrame (optional)
]]
function BulletEject.Eject(self : BulletEject, cameraOrAttachmentCF)
	if not self.EjectionPoint and not cameraOrAttachmentCF then
		warn("BulletEject: No ejection point or CFrame provided")
		return nil
	end

	-- Get the ejection point CFrame
	local ejectCF = self.CurrentEjectCFrame or self:GetEjectionPointCFrame()
	local cameraCF = cameraOrAttachmentCF or workspace.CurrentCamera.CFrame

	-- Get a bullet from the pool
	local bullet = self.BulletCache:GetPart(ejectCF)
	bullet.CFrame = ejectCF
	bullet.Anchored = false
	
	if not bullet then
		warn("BulletEject: Failed to get bullet from cache")
		return nil
	end
	
	-- Calculate ejection direction
	local dir = 
		cameraCF.RightVector * self.EjectRight +
		cameraCF.UpVector * self.EjectUp +
		cameraCF.LookVector * self.EjectForward

	dir = dir.Unit

	-- Apply angular noise
	local yaw = (math.random() - 0.5) * self.AngleNoise
	local pitch = (math.random() - 0.5) * self.AngleNoise

	local noiseCF = 
		CFrame.fromAxisAngle(cameraCF.UpVector, yaw) *
		CFrame.fromAxisAngle(cameraCF.RightVector, pitch)

	dir = noiseCF:VectorToWorldSpace(dir).Unit

	-- Apply speed variance
	local speed = self.BaseSpeed + (math.random() - 0.5) * self.SpeedVariance * 2

	-- Set velocities
	bullet.AssemblyLinearVelocity = dir * speed
	bullet.AssemblyAngularVelocity = Vector3.new(
		math.random(self.AngularVelocity.X.Min, self.AngularVelocity.X.Max),
		math.random(self.AngularVelocity.Y.Min, self.AngularVelocity.Y.Max),
		math.random(self.AngularVelocity.Z.Min, self.AngularVelocity.Z.Max)
	)
	
	-- Return bullet to cache after lifetime
	task.delay(self.CasingLifetime, function()
		self.BulletCache:ReturnPart(bullet)
	end)

	return bullet
end

--[[
	Updates the cached ejection point CFrame (call in RenderStepped)
	Only needed if UseRenderStepped is true
]]
function BulletEject.Update(self : BulletEject)
	if self.EjectionPoint then
		self.CurrentEjectCFrame = self:GetEjectionPointCFrame()
	end
end

--[[
	Updates configuration values
	@param config table - Configuration overrides
]]
function BulletEject.SetConfig(self : BulletEject, config)
	if not config or type(config) ~= "table" then
		return false
	end

	for key, value in pairs(config) do
		if self[key] ~= nil and key ~= "BulletCache" and key ~= "EjectionPoint" and key ~= "RenderConnection" then
			self[key] = value
		end
	end

	return true
end

--[[
	Sets a new ejection point (Attachment or BasePart)
	@param ejectionPoint Attachment | BasePart
]]
function BulletEject.SetEjectionPoint(self : BulletEject, ejectionPoint)
	if not ejectionPoint then
		warn("BulletEject: No ejection point provided")
		return false
	end

	if not (ejectionPoint:IsA("Attachment") or ejectionPoint:IsA("BasePart")) then
		warn("BulletEject: Ejection point must be an Attachment or BasePart")
		return false
	end

	self.EjectionPoint = ejectionPoint
	self.CurrentEjectCFrame = self:GetEjectionPointCFrame()
	return true
end

--[[
	Gets current configuration as a table
	@return table
]]
function BulletEject.GetConfig(self : BulletEject)
	return {
		EjectRight = self.EjectRight,
		EjectUp = self.EjectUp,
		EjectForward = self.EjectForward,
		BaseSpeed = self.BaseSpeed,
		SpeedVariance = self.SpeedVariance,
		AngleNoise = self.AngleNoise,
		AngularVelocity = self.AngularVelocity,
		CasingLifetime = self.CasingLifetime,
		PoolSize = self.PoolSize,
	}
end

--[[
	Manually returns a bullet to the pool
	@param bullet BasePart
]]
function BulletEject.ReturnBullet(self : BulletEject, bullet)
	if bullet then
		self.BulletCache:ReturnPart(bullet)
	end
end

--[[
	Gets the object cache instance (advanced usage)
	@return ObjectCache
]]
function BulletEject.GetCache(self : BulletEject)
	return self.BulletCache
end

--[[
	Cleans up the module and disconnects events
]]
function BulletEject.Destroy(self : BulletEject)
	if self.RenderConnection then
		self.RenderConnection:Disconnect()
		self.RenderConnection = nil
	end

	-- Note: ObjectCache doesn't have a built-in destroy method
	-- so we just clear the reference
	self.BulletCache = nil
	self.EjectionPoint = nil
end

--[[
	Creates a new BulletEject instance
	@param EjectionPoint Attachment | BasePart - The ejection point (Attachment or BasePart)
	@param Bullet BasePart - The bullet/shell template to clone
	@param Configuration table - Configuration overrides
	@return BulletEject
]]
function module.new(EjectionPoint, Bullet,EmptyBullet, Configuration : Configuration) : BulletEject
	if not EjectionPoint then
		warn("BulletEject: No ejection point provided")
		return nil
	end

	if not (EjectionPoint:IsA("Attachment") or EjectionPoint:IsA("BasePart")) then
		warn("BulletEject: Ejection point must be an Attachment or BasePart")
		return nil
	end

	if not Bullet or not Bullet:IsA("BasePart") then
		warn("BulletEject: Invalid bullet template provided")
		return nil
	end

	local bulletEject = table.clone(BulletEject) :: BulletEject

	-- Initialize configuration
	bulletEject.EjectRight = Configuration and Configuration.EjectRight or DefaultConfiguration.EjectRight
	bulletEject.EjectUp = Configuration and Configuration.EjectUp or DefaultConfiguration.EjectUp
	bulletEject.EjectForward = Configuration and Configuration.EjectForward or DefaultConfiguration.EjectForward
	bulletEject.BaseSpeed = Configuration and Configuration.BaseSpeed or DefaultConfiguration.BaseSpeed
	bulletEject.SpeedVariance = Configuration and Configuration.SpeedVariance or DefaultConfiguration.SpeedVariance
	bulletEject.AngleNoise = Configuration and Configuration.AngleNoise or DefaultConfiguration.AngleNoise
	bulletEject.AngularVelocity = Configuration and Configuration.AngularVelocity or DefaultConfiguration.AngularVelocity
	bulletEject.CasingLifetime = Configuration and Configuration.CasingLifetime or DefaultConfiguration.CasingLifetime
	bulletEject.PoolSize = Configuration and Configuration.PoolSize or DefaultConfiguration.PoolSize
	bulletEject.UseRenderStepped = if Configuration and Configuration.UseRenderStepped ~= nil then Configuration.UseRenderStepped else DefaultConfiguration.UseRenderStepped

	-- Store ejection point reference
	bulletEject.EjectionPoint = EjectionPoint
	bulletEject.CurrentEjectCFrame = bulletEject:GetEjectionPointCFrame()

	-- Initialize object cache
	local poolContainer = (Configuration and Configuration.PoolContainer) or DefaultConfiguration.PoolContainer or workspace
	bulletEject.BulletCache = ObjectCache.new(
		Bullet,
		bulletEject.PoolSize,
		poolContainer
	)

	-- Setup RenderStepped connection if needed
	if bulletEject.UseRenderStepped then
		bulletEject.RenderConnection = RunService.RenderStepped:Connect(function()
			bulletEject:Update()
		end)
	end

	return bulletEject
end

export type Configuration = typeof(DefaultConfiguration)
export type BulletEject = typeof(BulletEject) & Configuration & {
	EjectionPoint: Attachment | BasePart,
	BulletCache: any,
	RenderConnection: RBXScriptConnection?,
}

return module