local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Utilities = ReplicatedStorage.SharedModules.Utilities
local FastCast = require(Utilities.FastCastRedux)
local Logger = require(Utilities.LogService)

local Identity = "[ProjectileSolver]"

local ProjectileSolver = {}
ProjectileSolver.__index = ProjectileSolver
FastCast.VisualizeCasts = false
function ProjectileSolver.new(ballisticsService)
	local self = setmetatable({}, ProjectileSolver)
	self.Service = ballisticsService

	-- FastCast setup
	self.Caster = FastCast.new()

	-- Mappings
	self.ContextToCast = setmetatable({}, { __mode = "k" })
	self.CastToContext = setmetatable({}, { __mode = "k" })

	-- Connect FastCast events
	self.Caster.RayHit:Connect(function(cast, result, velocity, bullet)
		self:_OnRayHit(cast, result, velocity, bullet)
	end)

	self.Caster.LengthChanged:Connect(function(cast, lastPoint, direction, length, velocity, bullet)
		self:_OnLengthChanged(cast, lastPoint, direction, length, velocity, bullet)
	end)

	self.Caster.CastTerminating:Connect(function(cast)
		self:_OnCastTerminating(cast)
	end)

	Logger.Print("ProjectileSolver initialized", Identity)
	return self
end

function ProjectileSolver:Fire(context, behavior)
	local origin = context.Origin
	local direction = context.Direction
	local speed = context.Speed

	-- Use provided behavior or create default
	local castBehavior = behavior or FastCast.newBehavior()
	if not behavior then
		castBehavior.MaxDistance = 500
		castBehavior.Acceleration = Vector3.new(0, -workspace.Gravity, 0)

		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.IgnoreWater = true
		castBehavior.RaycastParams = params
	end

	-- Fire projectile
	local cast = self.Caster:Fire(origin, direction, speed, castBehavior)

	-- Link context to cast
	context.__solverData = { Cast = cast }
	context.Bullet = cast.RayInfo.CosmeticBulletObject

	self.ContextToCast[context] = cast
	self.CastToContext[cast] = context

	return true
end

function ProjectileSolver:_OnRayHit(cast, result, velocity, bullet)
	local context = self.CastToContext[cast]
	if not context or not context.Alive then return end



	-- Trigger hit
	self.Service:_TriggerHit(context, result)
	-- Trigger termination
	self.Service:_TriggerTermination(context)
	if result then
		context:_UpdateState(result.Position, velocity)
		
		Logger.Print(string.format(
			"Projectile hit: %s at %.1f studs",
			result.Instance.Name,
			result.Distance
			), Identity)

	end
	-- Cleanup
	self:_Cleanup(context)
end

function ProjectileSolver:_OnLengthChanged(cast, lastPoint, direction, length, velocity)
	local context = self.CastToContext[cast]
	if not context or not context.Alive then return end

	-- Update state
	local currentPos = lastPoint + (direction * length)
	context:_UpdateState(currentPos, velocity, length, lastPoint)
	context.LastPoint = lastPoint
	-- Update trajectory for lag compensation
	table.insert(context.Trajectory, currentPos)

	-- Trigger travel callback
	self.Service:_TriggerTravel(context, currentPos)
end

function ProjectileSolver:_OnCastTerminating(cast)
	local context = self.CastToContext[cast]
	if not context or not context.Alive then return end

	Logger.Print("Projectile terminating", Identity)

	-- Trigger termination
	self.Service:_TriggerTermination(context)

	-- Cleanup
	self:_Cleanup(context)
end

function ProjectileSolver:_Cleanup(context)
	local cast = self.ContextToCast[context]
	if cast then
		self.CastToContext[cast] = nil
		self.ContextToCast[context] = nil
	end
end

function ProjectileSolver:Destroy()
	self.Caster = nil
	self.Service = nil
	self.ContextToCast = nil
	self.CastToContext = nil
end

return ProjectileSolver