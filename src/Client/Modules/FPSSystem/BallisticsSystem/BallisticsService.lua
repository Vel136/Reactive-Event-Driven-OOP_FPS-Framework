-- ClientBallisticsService.lua
--[[
	Central manager supporting multiple ballistics solver types.
	- Hitscan:    Instant raycast, optional pierce chain
	- Projectile: Physics-based FastCast simulation
	- Bounce:     Kinematic gravity + surface reflection
	- Hybrid:     Analytic-trajectory with pierce, bounce, high-fidelity raycasting
]]

local Identity = "ClientBallisticsService"

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Utilities         = ReplicatedStorage.Shared.Modules.Utilities

local LogService       = require(Utilities.Logger)
local BallisticsCommon = require(ReplicatedStorage.Shared.Modules.FPSSystem.BallisticsSystem.BallisticsCommon)

local BallisticsService   = {}
BallisticsService.__index = BallisticsService
BallisticsService.__type  = Identity
BallisticsService.Common  = BallisticsCommon

local Logger = LogService.new(Identity, false)

BallisticsService.SolverType = {
	Hitscan    = "Hitscan",
	Projectile = "Projectile",
	Bounce     = "Bounce",
	Hybrid     = "Hybrid",  
}

-- ─── Internal: context lifecycle ─────────────────────────────────────────────

function BallisticsService._TriggerPierce(self: BallisticsService, context: BulletContext, hitData: RaycastResult?, pierceCount: number, remainingDistance: number)
	local cb = context.UserData and context.UserData._callbacks
	if cb and cb.OnPierce then
		cb.OnPierce(context, hitData, pierceCount, remainingDistance)
	end
end

function BallisticsService._TriggerHit(self: BallisticsService, context: BulletContext, hitData: RaycastResult?)
	local cb = context.UserData and context.UserData._callbacks
	if cb and cb.OnHit then
		cb.OnHit(context, hitData :: any)
	end
end

function BallisticsService._TriggerTravel(self: BallisticsService, context: BulletContext, currentPos: Vector3)
	local cb = context.UserData and context.UserData._callbacks
	if cb and cb.OnTravel then
		cb.OnTravel(context, currentPos)
	end
end

function BallisticsService._TriggerBounce(self: BallisticsService, context: BulletContext, hitData: RaycastResult?, bounceCount: number, remainingDistance: number)
	local cb = context.UserData and context.UserData._callbacks
	if cb and cb.OnBounce then
		cb.OnBounce(context, hitData, bounceCount, remainingDistance)
	end
end

function BallisticsService._TriggerTermination(self: BallisticsService, context: BulletContext)
	local cb = context.UserData and context.UserData._callbacks
	if cb and cb.OnTerminating then
		cb.OnTerminating(context)
	end
	context:Terminate()
	self:_CleanupContext(context)
end

function BallisticsService._CleanupContext(self: BallisticsService, context: BulletContext)
	self.ActiveBullets[context] = nil
end

-- ─── Internal: initialization ────────────────────────────────────────────────

function BallisticsService._Initialize(self: BallisticsService)
	self.ActiveBullets = setmetatable({}, { __mode = "k" }) :: { [BulletContext]: boolean }

	self.Solvers = {
		Hitscan    = BallisticsCommon.HitscanSolver.new(),
		Projectile = BallisticsCommon.ProjectileSolver.new(),
		Bounce     = BallisticsCommon.BounceSolver.new(),
		Hybrid     = BallisticsCommon.HybridSolver.new(),
	}

	-- ── Hitscan ──────────────────────────────────────────────────────────────
	local hitscan = self.Solvers.Hitscan

	hitscan.Signals.OnHit:Connect(function(context, result)
		self:_TriggerHit(context, result)
	end)
	hitscan.Signals.OnPierce:Connect(function(context, result, pierceCount, remainingDistance)
		self:_TriggerPierce(context, result, pierceCount, remainingDistance)
	end)
	hitscan.Signals.OnTerminated:Connect(function(context)
		self:_TriggerTermination(context)
	end)

	-- ── Projectile ───────────────────────────────────────────────────────────
	local projectile = self.Solvers.Projectile

	projectile.Signals.OnHit:Connect(function(context, result)
		self:_TriggerHit(context, result)
	end)
	projectile.Signals.OnTravel:Connect(function(context, currentPos)
		self:_TriggerTravel(context, currentPos)
	end)
	projectile.Signals.OnPierce:Connect(function(context, result, pierceCount, remainingDistance)
		self:_TriggerPierce(context, result, pierceCount, remainingDistance)
	end)
	projectile.Signals.OnTerminated:Connect(function(context)
		self:_TriggerTermination(context)
	end)

	-- ── Bounce ───────────────────────────────────────────────────────────────
	local bounce = self.Solvers.Bounce

	bounce.Signals.OnHit:Connect(function(context, result)
		self:_TriggerHit(context, result)
	end)
	bounce.Signals.OnTravel:Connect(function(context, currentPos)
		self:_TriggerTravel(context, currentPos)
	end)
	bounce.Signals.OnBounce:Connect(function(context, result, bounceCount, remainingDistance)
		self:_TriggerBounce(context, result, bounceCount, remainingDistance)
	end)
	bounce.Signals.OnTerminated:Connect(function(context)
		self:_TriggerTermination(context)
	end)

	-- ── Hybrid ───────────────────────────────────────────────────────────────
	-- HybridSolver uses GetSignals() instead of a .Signals table.
	-- OnBounce fires (context, result, velocity, bounceCount) — we adapt the
	-- signature to match _TriggerBounce's (context, result, bounceCount, remaining).
	-- OnTravel fires (context, position, velocity) — we drop velocity.
	-- OnPierce fires (context, result, velocity, pierceCount) — we adapt.
	local hybridSignals = self.Solvers.Hybrid:GetSignals()

	hybridSignals.OnHit:Connect(function(context, result, velocity)
		self:_TriggerHit(context, result)
	end)
	hybridSignals.OnTravel:Connect(function(context, position, velocity)
		self:_TriggerTravel(context, position)
	end)
	hybridSignals.OnPierce:Connect(function(context, result, velocity, pierceCount)
		-- remainingDistance not provided by HybridSolver; derive from context
		local remaining = (context.UserData._maxDistance or 1000) - (context.Length or 0)
		self:_TriggerPierce(context, result, pierceCount, remaining)
	end)
	hybridSignals.OnBounce:Connect(function(context, result, velocity, bounceCount)
		local remaining = (context.UserData._maxDistance or 1000) - (context.Length or 0)
		self:_TriggerBounce(context, result, bounceCount, remaining)
	end)
	hybridSignals.OnTerminated:Connect(function(context)
		self:_TriggerTermination(context)
	end)

	Logger:Debug("_Initialize: solvers ready")
end

-- ─── Public API ──────────────────────────────────────────────────────────────

function BallisticsService.Fire(self: BallisticsService, fireData: FireData, solverType: string?): BulletContext?
	local origin    = fireData.Origin
	local direction = fireData.Direction
	local speed     = fireData.Speed    or 1000
	local behavior  = fireData.Behavior
	local callbacks = fireData.Callbacks

	local selectedSolver: string = solverType
		or (behavior and behavior.SolverType)
		or BallisticsService.SolverType.Projectile

	local solver = self.Solvers[selectedSolver]

	if not solver then
		Logger:Warn(string.format("Fire: unknown solver type '%s'", selectedSolver))
		return nil
	end

	-- For HybridSolver, behavior must be a HybridBehavior built via BehaviorBuilder.
	-- If the caller passed a plain BallisticsBehavior table, auto-convert it.
	local resolvedBehavior = behavior

	local context: BulletContext = BallisticsCommon.newBullet({
		Origin    = origin,
		Direction = direction.Unit,
		Speed     = speed,
	})

	-- Callbacks live in UserData._callbacks so Vetra's BulletContext is never
	-- asked for a field it doesn't have.
	if callbacks then
		context.UserData._callbacks = callbacks
	end

	-- Store MaxDistance in UserData so signal handlers can derive remainingDistance
	if selectedSolver == BallisticsService.SolverType.Hybrid then
		context.UserData._maxDistance = (behavior and behavior.MaxDistance) or 1000
	end

	local success: boolean = solver:Fire(context, resolvedBehavior)

	if success then
		self.ActiveBullets[context] = true
		return context
	end

	context:Terminate()
	Logger:Warn(string.format("Fire: solver '%s' failed to fire", selectedSolver))
	return nil
end

-- ─── Remaining public API (unchanged) ────────────────────────────────────────

function BallisticsService.GetActiveBulletCount(self: BallisticsService): number
	local count = 0
	for _ in pairs(self.ActiveBullets) do count += 1 end
	return count
end

function BallisticsService.GetActiveBullets(self: BallisticsService): { BulletContext }
	local contexts: { BulletContext } = {}
	for context in pairs(self.ActiveBullets) do
		table.insert(contexts, context)
	end
	return contexts
end

function BallisticsService.ClearBullet(self: BallisticsService, context: BulletContext)
	if context then
		context:Terminate()
		self:_CleanupContext(context)
	end
end

function BallisticsService.ClearAll(self: BallisticsService)
	for context in pairs(self.ActiveBullets) do
		if context then context:Terminate() end
	end
	self.ActiveBullets = {}
	Logger:Debug("ClearAll: all bullets cleared")
end

function BallisticsService.CleanupOldBullets(self: BallisticsService, maxAge: number?)
	local age     = maxAge or 10
	local cleaned = 0
	for context in pairs(self.ActiveBullets) do
		if context:GetLifetime() > age then
			context:Terminate()
			self:_CleanupContext(context)
			cleaned += 1
		end
	end
	if cleaned > 0 then
		Logger:Warn(string.format("CleanupOldBullets: removed %d stale bullets", cleaned))
	end
end

-- ─── Types ───────────────────────────────────────────────────────────────────

type BulletContext    = BallisticsCommon.BulletContext
type BulletCallbacks  = BallisticsCommon.BulletCallbacks
type HitscanSolver    = BallisticsCommon.HitscanSolver
type ProjectileSolver = BallisticsCommon.ProjectileSolver
type BounceSolver     = BallisticsCommon.BounceSolver

type FireData = {
	Origin     : Vector3,
	Direction  : Vector3,
	Speed      : number?,
	Behavior   : { SolverType: string?, [string]: any }?,
	Callbacks  : BulletCallbacks?,
}

export type BallisticsBehavior = BallisticsCommon.BallisticsBehavior

export type BallisticsService = typeof(setmetatable({}, BallisticsService)) & {
	ActiveBullets : { [BulletContext]: boolean },
	Solvers       : {
		Hitscan    : HitscanSolver,
		Projectile : ProjectileSolver,
		Bounce     : BounceSolver,
		Hybrid     : any,
	},
}

-- ─── Singleton ───────────────────────────────────────────────────────────────

local _instance: BallisticsService

return setmetatable({}, {
	__index = function(_, key)
		if not _instance then
			_instance = setmetatable({}, BallisticsService) :: BallisticsService
			_instance:_Initialize()
		end
		return _instance[key]
	end,
	__newindex = function()
		error("BallisticsService is read-only")
	end,
}) :: BallisticsService