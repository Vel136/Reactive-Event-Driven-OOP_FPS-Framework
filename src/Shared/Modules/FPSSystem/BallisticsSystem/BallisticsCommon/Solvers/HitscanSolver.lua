-- HitscanSolver.lua
--!native
--!optimize 2
--[[
	Instant raycast solver for hitscan weapons.
	Single-frame raycast with optional multi-hit penetration. No simulation loop.

	Optimizations over original:
	  1. RaycastParams pooling
	        Mirrors ActiveCast's AcquireParams/ReleaseParams pattern exactly.
	        The original created a fresh RaycastParams on every Fire() call —
	        pure GC pressure on a weapon that may fire 20+ times per second.

	  2. Cached globals
	        Standard library functions stored as locals to avoid per-call
	        global table lookups inside the hot penetration loop.

	  3. Parallel-aware Fire()
	        ConnectParallel does not apply here — HitscanSolver has no RunService
	        connection. Fire() is a synchronous function called from user code.
	        However, Fire() is designed to be safely callable from a
	        ConnectParallel context: all workspace:Raycast calls happen before
	        any signal firing or Instance creation. Signals and visualization
	        are deferred to after task.synchronize() so the raycast work can
	        run in parallel if the caller is already in a parallel context.

	        If you want the raycasts themselves to run in parallel across many
	        simultaneous hitscan shots, structure your caller like this:

	            RunService.Heartbeat:ConnectParallel(function()
	                -- batch all pending shots here
	                for _, shot in pendingShots do
	                    solver:Fire(shot.context, shot.behavior)  -- raycasts in parallel
	                end
	            end)

	  4. EMPTY_FILTER constant
	        Reusable empty table for resetting pooled RaycastParams filter lists,
	        avoiding a new table allocation on every ReleaseParams call.
]]

local Identity = "HitscanSolver"

-- ─── Services ────────────────────────────────────────────────────────────────

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

-- ─── References ──────────────────────────────────────────────────────────────

local Utilities = ReplicatedStorage.Shared.Modules.Utilities

-- ─── Modules ─────────────────────────────────────────────────────────────────

local Signal     = require(Utilities.Signal)
local LogService = require(Utilities.Logger)

local Logger = LogService.new(Identity, false)

-- ─── Constants ───────────────────────────────────────────────────────────────

local VIS_FOLDER_NAME = "HitscanVisualizationObjects"
local NUDGE           = 0.01  -- studs past surface to restart ray after a pierce

-- ─── RaycastParams Pool ──────────────────────────────────────────────────────
--[[
	Mirrors ActiveCast's pool exactly.

	The original HitscanSolver called RaycastParams.new() on every Fire() call.
	For a fully-automatic weapon firing at 600 RPM (10/sec), that's 10 allocs
	per second per gun, all of which the GC must eventually collect. Pooling
	eliminates this entirely by recycling params objects between shots.

	AcquireParams: pulls a recycled object from the pool (zero alloc cost)
	or creates a new one if the pool is empty. Copies all fields from the
	source and clones the filter list so mutations during the penetration loop
	never affect the caller's original params.

	ReleaseParams: resets to safe defaults using EMPTY_FILTER (avoids a new
	table allocation just to clear the filter) then returns to pool.
]]

local ParamsPool: { RaycastParams } = {}
local ParamsPoolSize                = 0
local MAX_PARAMS_POOL_SIZE          = 256

-- Shared empty table used to reset filter lists in ReleaseParams.
-- Same pattern as ActiveCast's EMPTY_FILTER — never allocate a new table
-- just to clear a field.
local EMPTY_FILTER: { Instance } = {}

-- ─── Cached globals ──────────────────────────────────────────────────────────
-- Local references to standard library functions avoid a global table lookup
-- on every call. Matters most inside the penetration loop which may execute
-- many times per Fire() call on weapons with high pierce counts.

local mathMax      = math.max
local tInsert      = table.insert
local tClone       = table.clone
local CFrameNew    = CFrame.new
local Color3New    = Color3.new
local Color3RGB    = Color3.fromRGB
local InstanceNew  = Instance.new
local WorkspaceTerrain = workspace.Terrain
local IS_SERVER    = RunService:IsServer()

-- ─── Module ──────────────────────────────────────────────────────────────────

local HitscanSolver   = {}
HitscanSolver.__index = HitscanSolver
HitscanSolver.__type  = Identity

HitscanSolver.VisualizeCasts = false

-- ─── Pool functions ──────────────────────────────────────────────────────────

local function AcquireParams(src: RaycastParams?): RaycastParams
	local params: RaycastParams

	if ParamsPoolSize > 0 then
		-- Zero allocation cost — reuse an existing object
		params = ParamsPool[ParamsPoolSize]
		ParamsPool[ParamsPoolSize] = nil
		ParamsPoolSize -= 1
	else
		params = RaycastParams.new()
	end

	if src then
		-- Clone the filter list so the penetration loop's mutations
		-- (adding pierced instances to the exclude list) never affect
		-- the caller's original params object.
		params.CollisionGroup             = src.CollisionGroup
		params.FilterType                 = src.FilterType
		params.FilterDescendantsInstances = tClone(src.FilterDescendantsInstances)
		params.IgnoreWater                = src.IgnoreWater
	else
		params.FilterType  = Enum.RaycastFilterType.Exclude
		params.IgnoreWater = true
	end

	return params
end

local function ReleaseParams(params: RaycastParams)
	if ParamsPoolSize >= MAX_PARAMS_POOL_SIZE then return end

	-- Reset to safe defaults. EMPTY_FILTER avoids allocating a new table
	-- here — mirrors ActiveCast's ReleaseParams approach exactly.
	params.FilterDescendantsInstances = EMPTY_FILTER
	params.CollisionGroup             = ""
	params.FilterType                 = Enum.RaycastFilterType.Exclude
	params.IgnoreWater                = false

	ParamsPoolSize += 1
	ParamsPool[ParamsPoolSize] = params
end

-- ─── Visualization ───────────────────────────────────────────────────────────
--[[
	These functions create Instances and are NOT parallel-safe.
	They must only be called after task.synchronize() in Fire().
	The parallel phase of Fire() collects visualization data into a visQueue
	table; these functions are called when draining that queue on the main thread.
]]

local function GetVisContainer(): Instance
	local container = WorkspaceTerrain:FindFirstChild(VIS_FOLDER_NAME)
	if container then return container end

	container            = InstanceNew("Folder")
	container.Name       = VIS_FOLDER_NAME
	container.Archivable = false
	container.Parent     = WorkspaceTerrain
	return container
end

local function VisualizeSegment(startCF: CFrame, length: number)
	if not HitscanSolver.VisualizeCasts then return end

	local a        = InstanceNew("ConeHandleAdornment")
	a.Adornee      = WorkspaceTerrain
	a.CFrame       = startCF
	a.Height       = length
	a.Radius       = 0.15
	a.Transparency = 0.3
	a.Color3       = IS_SERVER
		and Color3RGB(255, 0, 0)
		or  Color3New(0, 0, 1)
	a.Parent = GetVisContainer()
end

local function VisualizeHit(cf: CFrame, wasHit: boolean)
	if not HitscanSolver.VisualizeCasts then return end

	local a        = InstanceNew("SphereHandleAdornment")
	a.Adornee      = WorkspaceTerrain
	a.CFrame       = cf
	a.Radius       = 0.4
	a.Transparency = 0.25
	a.Color3       = wasHit
		and Color3New(0.2, 1,   0.5)
		or  Color3New(1,   0.2, 0.2)
	a.Parent = GetVisContainer()
end

-- Drain the visQueue produced during the parallel raycast phase.
-- Must be called after task.synchronize() — Instance creation requires main thread.
local function FlushVisQueue(visQueue: { any })
	if not HitscanSolver.VisualizeCasts then
		table.clear(visQueue)
		return
	end
	for _, entry in ipairs(visQueue) do
		if entry.kind == "segment" then
			VisualizeSegment(entry.cf, entry.length)
		elseif entry.kind == "hit" then
			VisualizeHit(entry.cf, entry.wasHit)
		end
	end
	table.clear(visQueue)
end

-- ─── Constructor ─────────────────────────────────────────────────────────────

function HitscanSolver.new()
	local self = setmetatable({}, HitscanSolver)

	self.Signals = {
		OnHit        = Signal.new(),
		OnPierce     = Signal.new(),
		OnTerminated = Signal.new(),
	}

	Logger:Print("new: HitscanSolver initialized", Identity)
	return self
end

-- ─── Fire ────────────────────────────────────────────────────────────────────
--[[
	Performs an instant multi-hit raycast and fires OnHit / OnPierce /
	OnTerminated signals.

	Parallel-aware design:
	  Fire() is structured so it can be safely called from a ConnectParallel
	  context. The penetration loop — all math and workspace:Raycast calls —
	  runs in whatever context the caller is in. Visualization and signal
	  firing are deferred until after task.synchronize(), which is a no-op
	  when called from a serial context (the common case), so there is no
	  overhead when Fire() is called normally from a serial script.

	  This means if you batch Fire() calls inside a ConnectParallel heartbeat,
	  the raycasts genuinely run in parallel. If you call Fire() normally from
	  a serial Script, it behaves exactly as before with zero extra cost.

	Required behavior fields:
	  MaxDistance        : number
	  RaycastParams      : RaycastParams

	Optional behavior fields:
	  CanPierceFunction  : (result: RaycastResult, remainingDistance: number) -> boolean
]]
function HitscanSolver.Fire(self: HitscanSolver, context: any, behavior: any)
	local origin      = context.Origin
	local direction   = context.Direction
	local maxDistance = (behavior and behavior.MaxDistance) or 1000
	local canPierce   = behavior and behavior.CanPierceFunction

	-- AcquireParams: reuses a pooled object if available, copies source fields,
	-- clones the filter list. Mirrors ActiveCast's AcquireParams exactly.
	-- The params object is returned to the pool at the end of this function.
	local params = AcquireParams(behavior and behavior.RaycastParams)

	context.Trajectory = { origin }

	-- ── [PARALLEL PHASE] ─────────────────────────────────────────────────────
	-- Collect raycast results and pending signal/visualization data.
	-- No Instance creation or signal firing happens here — only pure math
	-- and workspace:Raycast, both of which are parallel-safe.

	-- Deferred visualization queue: records are plain Luau values (no Instances).
	-- Drained on the main thread after task.synchronize() below.
	local visQueue: { any } = {}

	-- Pending signals: collected during the parallel phase, fired after sync.
	-- Each entry is { kind, args... } so we replay them in order on main thread.
	local signalQueue: { any } = {}

	local remainingDistance = maxDistance
	local currentOrigin     = origin
	local hitResults: { RaycastResult } = {}
	local pierceCount       = 0
	local finalPos: Vector3 = origin + direction * maxDistance
	local finalUpdatePos: Vector3
	local finalUpdateVel: Vector3
	local didHit            = false

	-- Penetration loop: all workspace:Raycast calls happen here [PARALLEL-SAFE]
	while remainingDistance > 0 do
		local rayDir = direction * remainingDistance
		local result = workspace:Raycast(currentOrigin, rayDir, params)

		if result then
			local hitPos = result.Position

			-- Queue visualization — no Instance.new() here
			tInsert(visQueue, { kind = "segment", cf = CFrameNew(currentOrigin, hitPos), length = result.Distance })
			tInsert(visQueue, { kind = "hit",     cf = CFrameNew(hitPos),                wasHit = true })

			-- Queue signal — no firing here
			tInsert(signalQueue, { kind = "hit", result = result })
			tInsert(hitResults, result)

			finalPos = hitPos
			didHit   = true

			if canPierce and canPierce(result, remainingDistance) then
				pierceCount       += 1
				remainingDistance  = mathMax(0, remainingDistance - result.Distance - NUDGE)

				-- Exclude the pierced instance so the next ray passes through it.
				-- This mutates our cloned filter list — not the caller's original.
				local filter = params.FilterDescendantsInstances
				tInsert(filter, result.Instance)
				params.FilterDescendantsInstances = filter

				currentOrigin = hitPos + direction * NUDGE

				-- Queue pierce signal
				tInsert(signalQueue, { kind = "pierce", result = result, pierceCount = pierceCount, remainingDistance = remainingDistance })
			else
				-- Terminal hit — no more penetration
				finalUpdatePos = hitPos
				finalUpdateVel = direction * context.Speed
				context.Length = maxDistance - remainingDistance + result.Distance
				break
			end
		else
			-- Clean miss or end of penetration chain
			local missPos = currentOrigin + direction * remainingDistance

			-- Queue visualization for the miss segment and endpoint
			tInsert(visQueue, { kind = "segment", cf = CFrameNew(currentOrigin, missPos), length = remainingDistance })
			tInsert(visQueue, { kind = "hit",     cf = CFrameNew(missPos),                wasHit = false })

			finalUpdatePos = missPos
			finalUpdateVel = direction * context.Speed
			context.Length = maxDistance
			break
		end
	end

	-- ── [SERIAL PHASE] ───────────────────────────────────────────────────────
	-- task.synchronize() is a no-op when called from a serial context, so
	-- there is zero overhead for the common case of Fire() being called from
	-- a normal Script or LocalScript.
	-- When called from a ConnectParallel context, this brings us back to the
	-- main thread so we can safely create Instances and fire signals.
	task.synchronize()

	-- Drain the deferred visualization queue (Instance creation — serial only)
	FlushVisQueue(visQueue)

	-- Log and record trajectory endpoint
	if finalUpdatePos then
		tInsert(context.Trajectory, finalUpdatePos)
		context:_UpdateState(finalUpdatePos, finalUpdateVel)
	end

	-- Replay all collected signals in the order they were queued
	for _, entry in ipairs(signalQueue) do
		if entry.kind == "hit" then
			Logger:Print(
				string.format("Fire: hit %s", entry.result.Instance.Name),
				Identity
			)
			self.Signals.OnHit:Fire(context, entry.result)

		elseif entry.kind == "pierce" then
			Logger:Print(
				string.format(
					"Fire: pierced %s (pierce #%d, %.1f studs remaining)",
					entry.result.Instance.Name,
					entry.pierceCount,
					entry.remainingDistance
				),
				Identity
			)
			self.Signals.OnPierce:Fire(context, entry.result, entry.pierceCount, entry.remainingDistance)
		end
	end

	-- Return params to the pool for the next Fire() call.
	-- Mirrors ActiveCast's ReleaseParams call in Terminate().
	ReleaseParams(params)

	self.Signals.OnTerminated:Fire(context, hitResults, pierceCount)
	return true
end

-- ─── Lifecycle ───────────────────────────────────────────────────────────────

function HitscanSolver.Destroy(self: HitscanSolver)
	self.Signals.OnHit:Destroy()
	self.Signals.OnPierce:Destroy()
	self.Signals.OnTerminated:Destroy()
end

-- ─── Types ───────────────────────────────────────────────────────────────────

export type HitscanSolver = typeof(setmetatable({}, HitscanSolver)) & {
	VisualizeCasts : boolean,
	Signals: {
		OnHit        : Signal.Signal<(ctx: any, result: RaycastResult) -> ()>,
		OnPierce     : Signal.Signal<(ctx: any, result: RaycastResult, pierceCount: number, remainingDistance: number) -> ()>,
		OnTerminated : Signal.Signal<(ctx: any, hitResults: {RaycastResult}, pierceCount: number) -> ()>,
	},
}

export type Solver = typeof(setmetatable({}, HitscanSolver))

return HitscanSolver :: Solver