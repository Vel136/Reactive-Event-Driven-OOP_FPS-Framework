-- BallisticsService.lua
--[[
	Central manager for all bullets fired in the game
	Singleton service that handles FastCast for all weapons
	Now uses BulletContext for solver-agnostic weapon integration
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Utilities = ReplicatedStorage.SharedModules.Utilities
local FastCast = require(Utilities.FastCastRedux)
local Logger = require(Utilities:FindFirstChild("LogService"))
local BulletContext = require(script.BulletContext)

local BallisticsService = {}
BallisticsService.__index = BallisticsService
FastCast.VisualizeCasts = false

-- Private singleton instance
local instance

--[[
	Gets or creates the singleton instance
]]
local function GetInstance()
	if not instance then
		instance = setmetatable({}, BallisticsService)
		instance:_Initialize()
	end
	return instance
end

--[[
	Internal: Initializes the service
]]
function BallisticsService:_Initialize()
	-- Core FastCast (solver implementation)
	self.Caster = FastCast.new()
	-- [context] = cast (reverse lookup for solver cleanup)
	self.ActiveBullets = setmetatable({}, { __mode = "k" }) -- weak keys (context)
	-- [cast] = context (forward lookup)
	self.CastToContext = {} 

	-- Default behavior
	self.DefaultBehavior = FastCast.newBehavior()
	self.DefaultBehavior.MaxDistance = 500
	self.DefaultBehavior.Acceleration = Vector3.new(0, -workspace.Gravity, 0)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true
	self.DefaultBehavior.RaycastParams = params

	-- Connect FastCast events (solver-specific)
	self.Caster.RayHit:Connect(function(cast, result, velocity, bullet)
		self:_OnRayHit(cast, result, velocity, bullet)
	end)

	self.Caster.LengthChanged:Connect(function(cast, lastPoint, direction, length, velocity, bullet)
		self:_OnLengthChanged(cast, lastPoint, direction, length, velocity, bullet)
	end)

	self.Caster.CastTerminating:Connect(function(cast)
		self:_OnCastTerminating(cast)
	end)

	Logger.Print("[BallisticsService] Initialized", "[BallisticsService]")
end

--[[
	Internal: Handles RayHit event from FastCast
	Translates solver event to weapon callback with BulletContext
]]
function BallisticsService:_OnRayHit(cast, result, velocity, bullet)
	local context = self.CastToContext[cast]
	if not context or not context.Alive then return end

	-- Update context state
	context:_UpdateState(result.Position, velocity)

	-- Create solver-agnostic hit data
	local hitData = {
		Instance = result.Instance,
		Position = result.Position,
		Normal = result.Normal,
		Material = result.Material,
		Distance = result.Distance,
	}

	-- Call weapon's hit handler with context (NO CAST OBJECT)
	if context.Weapon and context.Weapon._OnBulletHit then
		context.Weapon:_OnBulletHit(context, hitData)
	end
	if context.Weapon and context.Weapon._OnBulletTerminating then
		context.Weapon:_OnBulletTerminating(context)
	end
	-- Terminate context
	context:Terminate()
	self:_CleanupContext(context)
end

--[[
	Internal: Handles LengthChanged event from FastCast
	Translates solver event to weapon callback with BulletContext
]]
function BallisticsService:_OnLengthChanged(cast, lastPoint, direction, length, velocity)
	local context = self.CastToContext[cast]
	if not context or not context.Alive then return end

	local currentPos = lastPoint + (direction * length)
	context:_UpdateState(currentPos,velocity,length,lastPoint)

	-- Call weapon's travel handler with context (NO CAST OBJECT)
	if context.Weapon and context.Weapon._OnBulletTravel then
		context.Weapon:_OnBulletTravel(context)
	end
end

--[[
	Internal: Handles CastTerminating event from FastCast
	Translates solver event to weapon callback with BulletContext
]]
function BallisticsService:_OnCastTerminating(cast)
	local context = self.CastToContext[cast]
	if not context then return end

	-- Call weapon's termination handler with context (NO CAST OBJECT)
	if context.Weapon and context.Weapon._OnBulletTerminating then
		context.Weapon:_OnBulletTerminating(context)
	end
	
	-- Clean up
	context:Terminate()
	self:_CleanupContext(context)
end

--[[
	Internal: Cleans up context mappings
]]
function BallisticsService:_CleanupContext(context)
	local cast = self.ActiveBullets[context]
	if cast then
		self.CastToContext[cast] = nil
		self.ActiveBullets[context] = nil
	end
end

--[[ 
	Fire a bullet (solver-agnostic API)
	@param weapon: Weapon instance
	@param origin: Vector3
	@param direction: Vector3 (should be normalized)
	@param speed: number? (optional)
	@param behavior: FastCastBehavior? (optional)
	@return BulletContext
]]
function BallisticsService:Fire(weapon, origin, direction, speed, behavior)
	if not weapon or not origin or not direction then
		Logger.Warn("[BallisticsService] Invalid Fire parameters", "[BallisticsService]")
		return nil
	end

	local bulletSpeed = speed or (weapon.Data and weapon.Data.BulletSpeed) or 1000
	local castBehavior = behavior or self.DefaultBehavior

	-- Ensure direction is normalized
	local normalizedDirection = direction.Unit

	-- Create BulletContext FIRST (solver-agnostic)
	local context = BulletContext.new({
		Weapon = weapon,
		Origin = origin,
		Direction = normalizedDirection,
		Speed = bulletSpeed,
		SolverData = nil -- Will be populated after cast creation
	})

	-- Fire using FastCast (solver-specific implementation)
	local cast = self.Caster:Fire(origin, normalizedDirection, bulletSpeed, castBehavior)
	
	context.Bullet = cast.RayInfo.CosmeticBulletObject
	-- Link context to cast (bidirectional mapping)
	context.__solverData = {
		Cast = cast,
		Terminate = function()
			if context and context.Terminate then
				pcall(function() context:Terminate() end)
			end
		end
	}

	self.ActiveBullets[context] = cast
	self.CastToContext[cast] = context

	-- Return context (NOT cast)
	return context
end

--[[
	Gets the number of active bullets
	@return number
]]
function BallisticsService:GetActiveBulletCount(): number
	local count = 0
	for _ in pairs(self.ActiveBullets) do
		count += 1
	end
	return count
end

--[[
	Gets all active bullet contexts
	@return table<BulletContext>
]]
function BallisticsService:GetActiveBullets(): {[any]: any}
	local contexts = {}
	for context, _ in pairs(self.ActiveBullets) do
		table.insert(contexts, context)
	end
	return contexts
end

--[[
	Clears a specific bullet by context
	@param context: BulletContext
]]
function BallisticsService:ClearBullet(context)
	if context then
		context:Terminate()
		self:_CleanupContext(context)
	end
end

--[[
	Clears all active bullets (use with caution)
]]
function BallisticsService:ClearAll()
	for context, _ in pairs(self.ActiveBullets) do
		if context then
			context:Terminate()
		end
	end

	self.ActiveBullets = {}
	self.CastToContext = {}
	Logger.Print("[BallisticsService] Cleared all bullets", "[BallisticsService]")
end

--[[
	Cleanup old bullets that may be stuck (safety measure)
	@param maxAge: number - Maximum age in seconds before cleanup
]]
function BallisticsService:CleanupOldBullets(maxAge: number?)
	maxAge = maxAge or 10 -- Default 10 seconds
	local cleaned = 0

	for context, _ in pairs(self.ActiveBullets) do
		if context:GetLifetime() > maxAge then
			context:Terminate()
			self:_CleanupContext(context)
			cleaned += 1
		end
	end

	if cleaned > 0 then
		Logger.Warn(string.format("[BallisticsService] Cleaned up %d old bullets", cleaned), "[BallisticsService]")
	end
end

-- Return the singleton getter
return setmetatable({}, {
	__index = function(_, key)
		return GetInstance()[key]
	end,
	__newindex = function()
		error("[BallisticsService] Cannot modify singleton service", "[BallisticsService]")
	end
})