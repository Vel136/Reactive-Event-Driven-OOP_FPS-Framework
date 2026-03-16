-- ProjectileSolver.lua
--[[
    Thin wrapper over Vetra that presents the legacy ProjectileSolver API surface.

    Migration notes from HybridSolver → Vetra
    ──────────────────────────────────────────
    • Solver is created via Vetra.new() — signals are now per-instance, not
      module-level. Each ProjectileSolver gets its own independent Signals table.
      No more _FrameLoopActive singleton restriction.

    • BulletContext detection uses the boolean `context.Alive` field instead of
      the old method `context.IsAlive`. A raw config table (Origin/Direction/Speed)
      will have `context.Alive == nil`, which is falsy — triggering auto-wrapping
      exactly as before.

    • Vetra.BulletContext is used for wrapping raw config tables, since Vetra's
      Fire() expects objects produced by that constructor (or compatible ducks).

    • All five signals are forwarded identically:
          OnHit · OnTravel · OnTerminated · OnPierce · OnBounce
      Vetra fires additional signals (OnPreBounce, OnSegmentOpen, etc.) that callers
      can access directly via self.Solver:GetSignals() if needed.

    • Vetra.BehaviorBuilder is a strict superset of the old BehaviorBuilder.
      Existing behavior tables built with the old builder are accepted unchanged.
]]

local Identity = "ProjectileSolver"

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Utilities         = ReplicatedStorage.Shared.Modules.Utilities

-- ─── Dependencies ────────────────────────────────────────────────────────────

local Vetra         = require(Utilities.Vetra)
-- BulletContext is re-exported from Vetra so we have one canonical source.
local BulletContext = Vetra.BulletContext
local LogService    = require(Utilities.Logger)

local Logger = LogService.new(Identity, false)

-- ─── Module ──────────────────────────────────────────────────────────────────

local ProjectileSolver   = {}
ProjectileSolver.__index = ProjectileSolver
ProjectileSolver.__type  = Identity

ProjectileSolver.VisualizeCasts = false

-- ─── Constructor ─────────────────────────────────────────────────────────────

function ProjectileSolver.new()
	local self = setmetatable({}, ProjectileSolver)

	-- One Vetra solver instance per ProjectileSolver.
	-- Signals are per-instance; consumers connect once via self.Signals.
	self.Solver = Vetra.new()

	-- Re-expose the five core signals callers already depend on.
	-- Vetra fires all five plus additional lifecycle signals that callers
	-- may opt into via self.Solver:GetSignals() if desired.
	local S = self.Solver:GetSignals()

	self.Signals = {
		OnHit        = S.OnHit,
		OnTravel     = S.OnTravel,
		OnTerminated = S.OnTerminated,
		OnPierce     = S.OnPierce,
		OnBounce     = S.OnBounce,
	}

	Logger:Print("new: ProjectileSolver initialized (backed by Vetra)", Identity)
	return self
end

-- ─── Solver API ──────────────────────────────────────────────────────────────

function ProjectileSolver.Fire(self: ProjectileSolver, context: any, behavior: any)

	local resolvedBehavior = behavior

	-- Build a minimal default behavior when none is provided.
	-- Vetra.BehaviorBuilder has a strict superset of the old BehaviorBuilder API;
	-- callers that already pass a built behavior table are unaffected.
	if not resolvedBehavior then
		local params = RaycastParams.new()
		params.FilterType  = Enum.RaycastFilterType.Exclude
		params.IgnoreWater = true

		resolvedBehavior = Vetra.BehaviorBuilder.new()
			:Physics()
			:MaxDistance(500)
			:RaycastParams(params)
			:Done()
			:Build()
	end

	-- VisualizeCasts is a module-level debug toggle forwarded onto the behavior.
	-- BehaviorBuilder:Build() returns a frozen table, so we must clone it before
	-- writing. We attempt a direct write first and clone only on failure so that
	-- mutable (non-frozen) behavior tables passed by callers are not needlessly
	-- copied.
	if resolvedBehavior then
		local ok = pcall(function()
			resolvedBehavior.VisualizeCasts = ProjectileSolver.VisualizeCasts
		end)
		if not ok then
			-- Frozen table — shallow-clone and override.
			resolvedBehavior = table.clone(resolvedBehavior)
			resolvedBehavior.VisualizeCasts = ProjectileSolver.VisualizeCasts
		end
	end

	-- ─── BulletContext normalisation ─────────────────────────────────────────
	-- Vetra's live context carries `context.Alive = true` (boolean).
	-- A raw config table {Origin, Direction, Speed} has `context.Alive == nil`
	-- (falsy), so we auto-wrap it into a proper BulletContext just as before.
	-- This replaces the old `if not context.IsAlive` check (IsAlive was a method
	-- on the old BulletContext; Alive is a boolean field on Vetra's).
	local bulletContext = context
	if not context.Alive then
		bulletContext = BulletContext.new({
			Origin    = context.Origin,
			Direction = context.Direction,
			Speed     = context.Speed,
		})
		-- Preserve any UserData the caller attached to the raw config table.
		if context.UserData then
			for k, v in context.UserData do
				bulletContext.UserData[k] = v
			end
		end
	end

	-- ─── Fire ────────────────────────────────────────────────────────────────
	local cast = self.Solver:Fire(bulletContext, resolvedBehavior)
	if not cast then
		Logger:Print("Fire: Vetra rejected the cast", Identity)
		return false
	end

	-- Write solver data back onto the original context so callers that hold a
	-- reference to it can reach the underlying cast for introspection.
	context.__solverData = { Cast = cast }
	context.Bullet       = bulletContext

	Logger:Print("Fire: projectile launched via Vetra", Identity)
	return true
end

-- ─── Lifecycle ───────────────────────────────────────────────────────────────

function ProjectileSolver.Destroy(self: ProjectileSolver)
	if self.Solver then
		self.Solver:Destroy()
	end
	self.Solver  = nil
	self.Signals = nil
end

-- ─── Types ───────────────────────────────────────────────────────────────────

export type ProjectileSolver = typeof(setmetatable({}, ProjectileSolver))
export type Solver           = typeof(setmetatable({}, ProjectileSolver))

return ProjectileSolver :: Solver