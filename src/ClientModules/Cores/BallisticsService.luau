-- ClientBallisticsService.lua
--[[
	Central manager supporting multiple ballistics solver types
	- Hitscan: Instant raycast
	- Projectile: Physics-based FastCast simulation
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Utilities = ReplicatedStorage.SharedModules.Utilities
local FastCast = require(Utilities.FastCastRedux)
local Logger = require(Utilities.LogService)

local Identity = "[ClientBallisticsService]"

-- Import solvers

local BallisticsCommon = require(ReplicatedStorage.SharedModules.BallisticsCommon)


local BallisticsService = {}
BallisticsService.__index = BallisticsService

-- Solver types enum
BallisticsService.SolverType = {
	Hitscan = "Hitscan",
	Projectile = "Projectile",
}

function BallisticsService:_Initialize()
	-- Initialize solvers
	self.Solvers = {
		Hitscan = BallisticsCommon.HitscanSolver.new(self),
		Projectile = BallisticsCommon.ProjectileSolver.new(self),
	}

	-- Track all active bullets (solver-agnostic)
	self.ActiveBullets = setmetatable({}, { __mode = "k" })

	Logger.Print("Initialized with Hitscan and Projectile solvers", Identity)
end

--[[
	Shared callback triggers (used by both solvers)
]]
function BallisticsService:_TriggerHit(context, hitData)
	if context.Callbacks and context.Callbacks.OnHit then
		context.Callbacks.OnHit(context,hitData)
	end
end

function BallisticsService:_TriggerTravel(context, currentPos)
	if context.Callbacks and context.Callbacks.OnLengthChanged then
		context.Callbacks.OnLengthChanged(context,currentPos)
	end
end

function BallisticsService:_TriggerTermination(context)

	if context.Callbacks and context.Callbacks.OnTerminating then
		context.Callbacks.OnTerminating(context)
	end
	
	context:Terminate()
	self:_CleanupContext(context)
end

function BallisticsService:_CleanupContext(context)
	self.ActiveBullets[context] = nil
end

--[[
	Fire a bullet using specified solver type
	@param FireData: Type.DefaultData
	@param solverType: string? (optional, defaults to Projectile)
	@return BulletContext?
]]
function BallisticsService:Fire(FireData, solverType: string?)
	local Origin = FireData.Origin
	local Direction = FireData.Direction
	local Speed = FireData.Speed or 1000
	local Behavior = FireData.Behavior
	local Callbacks = FireData.Callbacks

	-- Determine solver type
	local selectedSolver = solverType 
		or (Behavior and Behavior.SolverType) 
		or BallisticsService.SolverType.Projectile
	
	
	local solver = self.Solvers[selectedSolver]
	if not solver then
		Logger.Warn(string.format("Unknown solver type: %s", tostring(selectedSolver)), Identity)
		return nil
	end

	-- Normalize direction
	local NormalizedDirection = Direction.Unit

	-- Create context
	local context = BallisticsCommon.newBullet({
		Origin = Origin,
		Direction = NormalizedDirection,
		Speed = Speed,
		SolverType = selectedSolver,
		Callbacks = Callbacks or {
			OnTerminating = nil,
			OnHit = nil,
			OnLengthChanged = nil,
		}
	})

	-- Fire using solver
	local success = solver:Fire(context, Behavior)

	if success then
		self.ActiveBullets[context] = true
		return context
	else
		context:Terminate()
		Logger.Warn(string.format("Failed to fire bullet with solver: %s", selectedSolver), Identity)
		return nil
	end
end

--[[
	Management functions
]]
function BallisticsService:GetActiveBulletCount(): number
	local count = 0
	for _ in pairs(self.ActiveBullets) do
		count += 1
	end
	return count
end

function BallisticsService:GetActiveBullets(): {[any]: any}
	local contexts = {}
	for context, _ in pairs(self.ActiveBullets) do
		table.insert(contexts, context)
	end
	return contexts
end

function BallisticsService:ClearBullet(context)
	if context then
		context:Terminate()
		self:_CleanupContext(context)
	end
end

function BallisticsService:ClearAll()
	for context, _ in pairs(self.ActiveBullets) do
		if context then
			context:Terminate()
		end
	end
	self.ActiveBullets = {}
	Logger.Print("Cleared all bullets", Identity)
end

function BallisticsService:CleanupOldBullets(maxAge: number?)
	maxAge = maxAge or 10
	local cleaned = 0

	for context, _ in pairs(self.ActiveBullets) do
		if context:GetLifetime() > maxAge then
			context:Terminate()
			self:_CleanupContext(context)
			cleaned += 1
		end
	end

	if cleaned > 0 then
		Logger.Warn(string.format("Cleaned up %d old bullets", cleaned), Identity)
	end
end

-- Singleton
local instance

local function GetInstance()
	if not instance then
		instance = setmetatable({}, BallisticsService)
		instance:_Initialize()
	end
	return instance
end

return setmetatable({}, {
	__index = function(_, key)
		return GetInstance()[key]
	end,
	__newindex = function()
		error("Cannot modify singleton service", Identity)
	end
})