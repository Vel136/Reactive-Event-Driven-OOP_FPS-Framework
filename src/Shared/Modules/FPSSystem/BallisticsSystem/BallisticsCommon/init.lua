-- BallisticsCommon.lua
--[[
	Shared utilities and type re-exports for the ballistics system.
	- Geometry helpers (sphere intersection, segment distance)
	- BulletContext factory  (now sourced from Vetra)
	- Solver constructors
	- Central type re-export point for consumers

    Vetra migration notes
    ─────────────────────
    HybridSolver/init.lua is now a one-line re-export of Vetra.  All existing
    call-sites that do `BallisticsCommon.HybridSolver.new()` receive a proper
    Vetra solver instance transparently.

    BulletContext is sourced from Vetra so there is a single canonical type used
    by all solvers.  The public newBullet() helper continues to work unchanged.
]]

local Identity = "BallisticsCommon"

-- ─── Services ────────────────────────────────────────────────────────────────

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ─── References ──────────────────────────────────────────────────────────────

local BallisticsSystem = ReplicatedStorage.Shared.Modules.FPSSystem.BallisticsSystem
local Utilities        = ReplicatedStorage.Shared.Modules.Utilities

-- ─── Modules ─────────────────────────────────────────────────────────────────

-- BulletContext is now sourced from Vetra — one canonical type for all solvers.
local Vetra            = require(Utilities.Vetra)
local BulletContext    = Vetra.BulletContext

local HitscanSolver    = require(script.Solvers.HitscanSolver)
local ProjectileSolver = require(script.Solvers.ProjectileSolver)
local BounceSolver     = require(script.Solvers.BounceSolver)
-- HybridSolver is a thin re-export of Vetra (see HybridSolver/init.lua).
local HybridSolver     = require(script.Solvers.HybridSolver)
-- ─── Module ──────────────────────────────────────────────────────────────────

local BallisticsCommon = {}

-- ─── Solver constructors ─────────────────────────────────────────────────────

BallisticsCommon.Vetra            = Vetra           -- direct Vetra access
BallisticsCommon.HybridSolver	  = HybridSolver
BallisticsCommon.BounceSolver     = BounceSolver
BallisticsCommon.HitscanSolver    = HitscanSolver
BallisticsCommon.ProjectileSolver = ProjectileSolver

-- ─── Geometry helpers ────────────────────────────────────────────────────────

--- Returns true if the line segment from startPos to endPos intersects a sphere.
function BallisticsCommon.LineIntersectsSphere(
	startPos     : Vector3,
	endPos       : Vector3,
	sphereCenter : Vector3,
	sphereRadius : number
): boolean
	local d             = endPos - startPos
	local f             = startPos - sphereCenter
	local a             = d:Dot(d)
	local b             = 2 * f:Dot(d)
	local c             = f:Dot(f) - sphereRadius ^ 2
	local discriminant  = b ^ 2 - 4 * a * c

	if discriminant < 0 then return false end

	discriminant = math.sqrt(discriminant)
	local t1 = (-b - discriminant) / (2 * a)
	local t2 = (-b + discriminant) / (2 * a)

	return (t1 >= 0 and t1 <= 1) or (t2 >= 0 and t2 <= 1)
end

--- Returns the closest distance from point C to segment AB, and the closest point on AB.
function BallisticsCommon.DistancePointToSegment(A: Vector3, B: Vector3, C: Vector3): (number, Vector3)
	local AB      = B - A
	local AC      = C - A
	local abLenSq = AB:Dot(AB)

	if abLenSq == 0 then
		return (C - A).Magnitude, A
	end

	local t            = math.clamp(AC:Dot(AB) / abLenSq, 0, 1)
	local closestPoint = A + AB * t

	return (C - closestPoint).Magnitude, closestPoint
end

-- ─── BulletContext factory ───────────────────────────────────────────────────

--- Creates and returns a new BulletContext.
function BallisticsCommon.newBullet(config: BulletContextConfig): BulletContext
	return BulletContext.new(config)
end

-- ─── Behavior factory ───────────────────────────────────────────────────
local validKeys = {
	RaycastParams = true, Acceleration = true, MaxDistance = true,
	CanPierceFunction = true, HighFidelityBehavior = true,
	HighFidelitySegmentSize = true, CosmeticBulletTemplate = true,
	CosmeticBulletProvider = true, CosmeticBulletContainer = true,
	AutoIgnoreContainer = true, SolverType = true, Gravity = true,
	Restitution = true,MaxBounces = true,MinSpeed = true,CanBounceFunction = true,MaxPierceCount = true,
}
function BallisticsCommon.newBehavior(config: BallisticsBehavior): BallisticsBehavior
	local Behavior: BallisticsBehavior = {
		RaycastParams           = nil,
		Acceleration            = Vector3.zero,
		MaxDistance             = 1000,
		CanPierceFunction       = nil,
		CanBounceFunction 		= nil,
		HighFidelityBehavior    = 1,
		HighFidelitySegmentSize = 3,
		CosmeticBulletTemplate  = nil,
		CosmeticBulletProvider  = nil,
		CosmeticBulletContainer = nil,
		AutoIgnoreContainer     = false,
		SolverType              = "Hitscan",
		Gravity					= nil,
		Restitution 			= nil,
		MaxBounces				= nil,
	}

	if config then
		for key, value in pairs(config) do
			if validKeys[key] then
				Behavior[key] = value
			else
				warn("newBehavior: unknown key '" .. tostring(key) .. "'")
			end
		end
	end

	return Behavior
end
-- ─── Types ───────────────────────────────────────────────────────────────────

-- BulletContext types are now sourced from Vetra's canonical BulletContext.
local _BulletContextType   = Vetra.BulletContext
local _HitscanSolverModule = HitscanSolver
local _ProjectileModule    = ProjectileSolver

export type BallisticsBehavior = {
	RaycastParams           : RaycastParams,
	Acceleration            : Vector3,
	MaxDistance             : number,
	CanPierceFunction       : (() -> boolean)?,
	CanBounceFunction       : (() -> boolean)?,
	HighFidelityBehavior    : number,
	HighFidelitySegmentSize : number,
	CosmeticBulletTemplate  : Instance?,
	CosmeticBulletProvider  : (() -> Instance)?,
	CosmeticBulletContainer : Instance?,
	AutoIgnoreContainer     : boolean,
	Gravity					: Vector3,
	Restitution				: number,
	MinSpeed				: number,
	SolverType              : "Hitscan"|"Projectile"|"Bounce",	
}

export type BulletContext       = _BulletContextType.BulletContext
export type BulletSnapshot      = _BulletContextType.BulletSnapshot
export type BulletCallbacks     = _BulletContextType.BulletCallbacks
export type HitData             = _BulletContextType.HitData
export type BulletContextConfig = _BulletContextType.BulletContextConfig

export type HitscanSolver    = HitscanSolver.HitscanSolver
export type ProjectileSolver = ProjectileSolver.ProjectileSolver
export type BounceSolver 	 = BounceSolver.BounceSolver
return BallisticsCommon