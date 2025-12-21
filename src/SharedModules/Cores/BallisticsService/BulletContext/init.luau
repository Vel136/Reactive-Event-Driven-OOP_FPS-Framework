-- BulletContext.lua
--[[
	Solver-agnostic bullet runtime object
	Represents a bullet's state and lifecycle without exposing solver internals
]]

local HttpService = game:GetService("HttpService")

local BulletContextType = require(script.Type)
export type BulletContext = BulletContextType.BulletContext
export type BulletSnapshot = BulletContextType.BulletSnapshot
export type BulletContextConfig = BulletContextType.BulletContextConfig

local BulletContext = {}
BulletContext.__index = BulletContext

--[[
	Creates a new BulletContext
	@param config: BulletContextConfig
	@return BulletContext
]]
function BulletContext.new(config: BulletContextConfig): BulletContext
	assert(config.Weapon, "[BulletContext] Weapon is required")
	assert(config.Origin, "[BulletContext] Origin is required")
	assert(config.Direction, "[BulletContext] Direction is required")
	assert(config.Speed, "[BulletContext] Speed is required")

	local self = setmetatable({}, BulletContext)

	-- Identity
	self.Id = HttpService:GenerateGUID(false)

	-- Ownership
	self.Weapon = config.Weapon

	-- Initial state (immutable)
	self.Origin = config.Origin
	self.Direction = config.Direction  -- Always normalized
	self.Speed = config.Speed
	self.StartTime = os.clock()
	self.Bullet = nil
	-- Runtime state (updated by solver)
	self.Position = nil
	self.Velocity = self.Direction * self.Speed
	self.Alive = true
	self.Length = 0
	self.LastPoint = Vector3.new()
	
	-- Private solver data (undocumented, internal use only)
	self.__solverData = config.SolverData

	return self
end

--[[
	Updates bullet position and velocity
	Called by solver during simulation
	⚠️ INTERNAL USE ONLY - Do not call from weapon code
	@param position: Vector3
	@param velocity: Vector3
]]
function BulletContext:_UpdateState(currentPos : Vector3,velocity: Vector3,length : number?,lastPoint : number?)
	if not self.Alive then return end
	
	if currentPos then
		self.Position = currentPos
	end
	if velocity then
		self.Velocity = velocity
	end
	if length then
		self.Length = length
	end
	if lastPoint then
		self.LastPoint = lastPoint
	end
end

--[[
	Terminates the bullet
	Can be called by weapon or solver
]]
function BulletContext:Terminate()
	if not self.Alive then return end

	self.Alive = false
	-- Ownership
	self.Weapon = nil

	-- Initial state (immutable)
	self.Origin = nil
	self.Direction = nil
	self.Speed = nil
	self.StartTime = nil
	self.Bullet = nil
	-- Runtime state (updated by solver)
	self.Position = nil
	self.Velocity = nil
	self.Alive = nil
	self.Length = nil
	self.LastPoint = nil
	-- Notify solver to clean up
	if self.__solverData and typeof(self.__solverData) == "table" then
		if self.__solverData.Terminate then
			self.__solverData.Terminate()
			self.__solverData = nil
		end
	end
end

--[[
	Gets the bullet's lifetime
	@return number - Age in seconds
]]
function BulletContext:GetLifetime(): number
	return os.clock() - self.StartTime
end

--[[
	Gets the distance traveled from origin
	@return number - Distance in studs
]]
function BulletContext:GetDistanceTraveled(): number
	return (self.Position - self.Origin).Magnitude
end

--[[
	Checks if bullet is still alive
	@return boolean
]]
function BulletContext:IsAlive(): boolean
	return self.Alive
end

--[[
	Gets a read-only snapshot of the context
	Useful for debugging or serialization
	@return BulletSnapshot
]]
function BulletContext:GetSnapshot(): BulletSnapshot
	return {
		Id = self.Id,
		Origin = self.Origin,
		Direction = self.Direction,
		Speed = self.Speed,
		Position = self.Position,
		Velocity = self.Velocity,
		Alive = self.Alive,
		Lifetime = self:GetLifetime(),
		DistanceTraveled = self:GetDistanceTraveled(),
	}
end

return BulletContext