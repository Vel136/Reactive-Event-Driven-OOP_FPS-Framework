-- ServerBallisticsService.lua
--[[
	Server-authoritative ballistics manager supporting multiple solver types.
	- Hitscan:    Instant raycast with optional lag compensation
	- Projectile: Physics-based FastCast simulation with lag compensation
	- Bounce:     Kinematic gravity + surface reflection with lag compensation
	- Hybrid:     Analytic-trajectory with pierce, bounce, high-fidelity raycasting
]]

local Identity = "ServerBallisticsService"

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Utilities         = ReplicatedStorage.Shared.Modules.Utilities

local LogService       = require(Utilities.Logger)
local BallisticsCommon = require(ReplicatedStorage.Shared.Modules.FPSSystem.BallisticsSystem.BallisticsCommon)

local HistoryService = require(script.HistoryService)
local HitboxService  = require(script.HitboxService)
local Type           = require(script.Type)

local Logger = LogService.new(Identity, false)

local BallisticsService   = {}
BallisticsService.__index = BallisticsService
BallisticsService.__type  = Identity
BallisticsService.Common  = BallisticsCommon

BallisticsService.SolverType = {
	Hitscan    = "Hitscan",
	Projectile = "Projectile",
	Bounce     = "Bounce",
	Hybrid     = "Hybrid",
}

-- ─── Internal: context lifecycle ─────────────────────────────────────────────

function BallisticsService._TriggerPierce(self: BallisticsService, context: BulletContext, hitData: RaycastResult?, pierceCount: number, remainingDistance: number)
	Logger:Print(
		string.format("_TriggerPierce: pierce #%d, %.1f studs remaining", pierceCount, remainingDistance),
		Identity
	)
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
	-- HybridSolver uses GetSignals() rather than a .Signals table.
	--
	-- IMPORTANT — trajectory for lag compensation:
	-- HybridSolver does not write to context.Trajectory. We build it here
	-- via OnTravel so FireWithCompensation has a segment list to replay.
	-- OnHit also appends the final impact position for the last segment.
	local hybridSignals = self.Solvers.Hybrid:GetSignals()

	hybridSignals.OnTravel:Connect(function(context, position, velocity)
		-- Initialise the table on first travel tick so old contexts without
		-- Trajectory (hitscan, etc.) are never affected.
		if not context.Trajectory then
			context.Trajectory = { context.Origin }
		end
		table.insert(context.Trajectory, position)
		self:_TriggerTravel(context, position)
	end)

	hybridSignals.OnHit:Connect(function(context, result, velocity)
		-- Append the terminal hit position so the last trajectory segment
		-- reaches all the way to the impact point for compensation replay.
		if context.Trajectory and result then
			table.insert(context.Trajectory, result.Position)
		end
		self:_TriggerHit(context, result)
	end)

	hybridSignals.OnPierce:Connect(function(context, result, velocity, pierceCount)
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

	Logger:Print("_Initialize: solvers ready", Identity)
end

-- ─── Public API ──────────────────────────────────────────────────────────────

function BallisticsService.Fire(self: BallisticsService, fireData: Type.DefaultData, solverType: string?): BulletContext?
	if not Type.FireDataCheck(fireData) then
		Logger:Warn("Fire: invalid fire data", Identity)
		return nil
	end

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
		Logger:Warn(string.format("Fire: unknown solver type '%s'", selectedSolver), Identity)
		return nil
	end

	local resolvedBehavior = behavior

	local context: BulletContext = BallisticsCommon.newBullet({
		Origin    = origin,
		Direction = direction.Unit,
		Speed     = speed,
	})

	if callbacks then
		context.UserData._callbacks = callbacks
	end

	if selectedSolver == BallisticsService.SolverType.Hybrid then
		context.UserData._maxDistance = (behavior and behavior.MaxDistance) or 1000
		-- Seed the trajectory table now so FireWithCompensation's pre-Fire
		-- OnTerminating callback always finds at least the origin point.
		context.Trajectory = { origin }
	end

	local success: boolean = solver:Fire(context, resolvedBehavior)

	if success then
		self.ActiveBullets[context] = true
		return context
	end

	context:Terminate()
	Logger:Warn(string.format("Fire: solver '%s' failed to fire", selectedSolver), Identity)
	return nil
end

--- Fires a bullet with server-side lag compensation applied on termination.
--[[
	Identical contract to the original. Works transparently for Hybrid because
	we populate context.Trajectory via OnTravel above — FireWithCompensation
	never needs to know which solver produced the segments.

	The compensation callback is still injected BEFORE Fire() so hitscan
	(which resolves synchronously) is always covered.
]]
function BallisticsService.FireWithCompensation(self: BallisticsService, lagData: Type.LagCompensationData): BulletContext?
	if not Type.LagDataCheck(lagData) then
		Logger:Warn("FireWithCompensation: invalid lag compensation data", Identity)
		return nil
	end

	local fireTime       = lagData.FireTime
	local player         = lagData.Player
	local hitRadius      = lagData.HitRadius or 2
	local onHitValidated = lagData.OnHitValidated

	local callbacks: BulletCallbacks = lagData.Callbacks or {}
	local originalOnTerminating      = callbacks.OnTerminating

	callbacks.OnTerminating = function(context: BulletContext)
		if originalOnTerminating then
			originalOnTerminating(context)
		end

		local trajectory = context.Trajectory
		if not trajectory or #trajectory < 2 then
			Logger:Print("FireWithCompensation: trajectory too short to compensate", Identity)
			return
		end

		local character = player and player.Character
		if not character then return end

		local hitboxSnapshot = HistoryService:GetMovementData(character, fireTime)
		if not hitboxSnapshot then
			Logger:Print("FireWithCompensation: no history snapshot available", Identity)
			return
		end

		for i = 1, #trajectory - 1 do
			local segStart = trajectory[i]
			local segEnd   = trajectory[i + 1]

			for partName, partData in pairs(hitboxSnapshot) do
				local hitboxPos = partData.CFrame.Position

				if BallisticsCommon.LineIntersectsSphere(segStart, segEnd, hitboxPos, hitRadius) then
					Logger:Print(
						string.format(
							"FireWithCompensation: hit validated on '%s' (segment %d/%d)",
							partName, i, #trajectory - 1
						),
						Identity
					)

					local hitData: HitData = {
						Instance       = character:FindFirstChild(partName),
						Position       = hitboxPos,
						Normal         = (segStart - hitboxPos).Unit,
						Material       = Enum.Material.Plastic,
						Distance       = (segStart - context.Origin).Magnitude,
						LagCompensated = true,
					}

					self:_TriggerHit(context, hitData :: any)

					if onHitValidated then
						onHitValidated(context, hitData)
					end

					return
				end
			end
		end

		Logger:Print("FireWithCompensation: no hit validated after trajectory replay", Identity)
	end

	local context: BulletContext? = self:Fire({
		Origin    = lagData.Origin,
		Direction = lagData.Direction,
		Speed     = lagData.Speed,
		Behavior  = lagData.Behavior,
		Callbacks = callbacks,
	})

	return context
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
	Logger:Print("ClearAll: all bullets cleared", Identity)
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
		Logger:Warn(string.format("CleanupOldBullets: removed %d stale bullets", cleaned), Identity)
	end
end

-- ─── Types ───────────────────────────────────────────────────────────────────

type BulletContext    = BallisticsCommon.BulletContext
type BulletCallbacks  = BallisticsCommon.BulletCallbacks
type HitData          = BallisticsCommon.HitData
type HitscanSolver    = BallisticsCommon.HitscanSolver
type ProjectileSolver = BallisticsCommon.ProjectileSolver
type BounceSolver     = BallisticsCommon.BounceSolver

type Solvers = {
	Hitscan    : HitscanSolver,
	Projectile : ProjectileSolver,
	Bounce     : BounceSolver,
	Hybrid     : any,
}

export type BallisticsService = typeof(setmetatable({}, BallisticsService)) & {
	ActiveBullets : { [BulletContext]: boolean },
	Solvers       : Solvers,
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