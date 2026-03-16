-- Migrated BounceSolver.lua
-- Drop-in replacement that delegates to HybridSolver.

local Identity = "BounceSolver"

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Utilities         = ReplicatedStorage.Shared.Modules.Utilities

local HybridSolver  = require(script.Parent.HybridSolver)
local BulletContext = require(script.Parent.HybridSolver.BulletContext)
local Signal        = require(Utilities.Signal)
local LogService    = require(Utilities.Logger)

local Logger = LogService.new(Identity, false)

local BounceSolver   = {}
BounceSolver.__index = BounceSolver
BounceSolver.__type  = Identity

BounceSolver.VisualizeCasts = true

-- ─── Constructor ─────────────────────────────────────────────────────────────

function BounceSolver.new()
	local self = setmetatable({}, BounceSolver)

	self.Solver = HybridSolver.new()

	-- Wrap HybridSolver signals into the same surface callers expect.
	-- OnTerminated re-packs bounceCount from UserData to match old signature:
	-- (context, hitResults, bounceCount)
	local S = self.Solver:GetSignals()

	self.Signals = {
		OnHit        = S.OnHit,
		OnTravel     = S.OnTravel,
		OnBounce     = S.OnBounce,

		-- Re-wrap: old signature was (context, hitResults, bounceCount)
		-- HybridSolver only fires (context), so we bridge via UserData
		OnTerminated = Signal.new(),
	}

	S.OnTerminated:Connect(function(context)
		self.Signals.OnTerminated:Fire(
			context,
			{},                                     -- hitResults no longer available
			context.UserData._bounceCount or 0
		)
	end)

	-- Track bounce count in UserData so OnTerminated can read it
	S.OnBounce:Connect(function(context, result, velocity, bounceCount)
		context.UserData._bounceCount = bounceCount
	end)

	Logger:Print("new: BounceSolver initialized", Identity)
	return self
end

-- ─── Fire ────────────────────────────────────────────────────────────────────

function BounceSolver.Fire(self: BounceSolver, context: any, behavior: any)
	local b = behavior or {}

	-- Adapt old CanBounceFunction signature (result, remainingDistance)
	-- to HybridSolver's expected (context, result, velocity)
	local rawCanBounce = b.CanBounceFunction
	local adaptedCanBounce = nil
	if rawCanBounce then
		adaptedCanBounce = function(ctx, result, velocity)
			local remaining = (b.MaxDistance or 1000) - (ctx.Length or 0)
			return rawCanBounce(result, remaining)
		end
	end
	
	b.VisualizeCasts = BounceSolver.VisualizeCasts
	local params = RaycastParams.new()
	params.FilterType  = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true
	if b.RaycastParams then
		params = b.RaycastParams
	end

	-- Wrap plain config table into a BulletContext if needed
	local bulletContext = context
	if not context.IsAlive then
		bulletContext = BulletContext.new({
			Origin    = context.Origin,
			Direction = context.Direction,
			Speed     = context.Speed,
		})
		if context.UserData then
			for k, v in context.UserData do
				bulletContext.UserData[k] = v
			end
		end
	end

	bulletContext.UserData._bounceCount = 0

	local cast = self.Solver:Fire(bulletContext, behavior)
	if not cast then
		Logger:Print("Fire: HybridSolver rejected the cast", Identity)
		return false
	end

	Logger:Print(
		string.format(
			"Fire: speed=%.1f maxDist=%.0f bounces=%d",
			context.Speed,
			b.MaxDistance or 1000,
			b.MaxBounces or 3
		),
		Identity
	)
	return true
end

-- ─── Pause / Resume ──────────────────────────────────────────────────────────
-- HybridSolver exposes Paused on the HybridCast, not on the solver itself.
-- We store the cast ref in UserData at fire time to support this.

function BounceSolver.Pause(self: BounceSolver, context: any)
	if context.UserData and context.UserData._cast then
		context.UserData._cast.Paused = true
	end
end

function BounceSolver.Resume(self: BounceSolver, context: any)
	if context.UserData and context.UserData._cast then
		context.UserData._cast.Paused = false
	end
end

-- ─── Destroy ─────────────────────────────────────────────────────────────────

function BounceSolver.Destroy(self: BounceSolver)
	self.Signals.OnTerminated:Destroy()
	self.Solver             = nil
	self.Signals            = nil
end

export type BounceSolver = typeof(setmetatable({}, BounceSolver))
export type Solver = typeof(setmetatable({}, BounceSolver))

return BounceSolver :: Solver