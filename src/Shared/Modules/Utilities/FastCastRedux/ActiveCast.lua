--!native
--!optimize 2

-- ActiveCast.lua
--[[
	Represents a single in-flight projectile cast.
	Owns the per-frame simulation loop, trajectory math,
	pierce resolution, and high-fidelity resimulation.

	Architecture note:
		All active casts share a SINGLE RunService connection via a central
		registry. This eliminates the per-cast connection overhead that was
		the primary bottleneck at scale (N connections firing N closures
		every frame → 1 connection iterating N casts).
]]

local Identity = "ActiveCast"

-- ─── Services ───────────────────── ───────────────────── ─────────────────────

local RunService = game:GetService("RunService")

-- ─── Modules ─────────────────────────────────────────────────────────────────

local TypeDefs = require(script.Parent.TypeDefinitions)
local table    = require(script.Parent.Table)
local typeof   = require(script.Parent.TypeMarshaller)

-- ─── Types ───────────────────────────────────────────────────────────────────

type CanPierceFunction = TypeDefs.CanPierceFunction
type GenericTable      = TypeDefs.GenericTable
type Caster            = TypeDefs.Caster
type FastCastBehavior  = TypeDefs.FastCastBehavior
type CastTrajectory    = TypeDefs.CastTrajectory
type CastStateInfo     = TypeDefs.CastStateInfo
type CastRayInfo       = TypeDefs.CastRayInfo
type ActiveCast        = TypeDefs.ActiveCast

-- ─── Cached Globals ──────────────────────────────────────────────────────────

local mathMax        = math.max
local mathFloor      = math.floor
local stringFormat   = string.format
local tableInsert    = table.insert
local tableFind      = table.find
local CFrameNew      = CFrame.new
local Color3New      = Color3.new
local Color3FromRGB  = Color3.fromRGB
local InstanceNew    = Instance.new
local WorkspaceTerrain = workspace.Terrain

local IS_SERVER = RunService:IsServer()
local IS_CLIENT = RunService:IsClient()

-- ─── Module ──────────────────────────────────────────────────────────────────

local ActiveCast          = {}
ActiveCast.__index        = ActiveCast
ActiveCast.__type         = Identity

-- ─── Constants ───────────────────────────────────────────────────────────────

local VIS_FOLDER_NAME = "FastCastVisualizationObjects"

local MAX_PIERCE_TEST_COUNT = 100

local ZERO_VECTOR    = Vector3.new()
local EMPTY_FILTER: { Instance } = {}

local ERR_NOT_INSTANCE  = "Cannot statically invoke '%s' — call it on an instance created via ActiveCast.new()"
local ERR_INVALID_TYPE  = "Invalid type for '%s' (expected %s, got %s)"
local ERR_DISPOSED      = "This ActiveCast has been terminated and can no longer be used."
local ERR_CASCADE_LAG   = "Cascading cast lag detected! A high-fidelity cast started before the previous one finished. Increase HighFidelitySegmentSize."
local ERR_PIERCE_YIELD  = "CanPierceCallback took too long — avoid yielding inside it."
local ERR_INVALID_HFB   = "Invalid HighFidelityBehavior value: "

-- ─── Static Reference ────────────────────────────────────────────────────────

local FastCast = nil

-- ─── Central Registry ────────────────────────────────────────────────────────
--[[
	Instead of one RunService connection per cast, all active casts live in
	this table. A single shared connection steps every cast each frame.
	Terminated casts are marked dead and swept out at the end of each frame.
]]

local Registry: { ActiveCast } = {}
local RegistrySize             = 0

-- Deferred removal list — casts that terminated mid-frame.
-- We don't remove inline to avoid corrupting the iteration index.
local PendingRemoval: { ActiveCast } = {}
local PendingRemovalSize             = 0

local function RegisterCast(cast: ActiveCast)
	RegistrySize += 1
	cast._registryIndex = RegistrySize
	Registry[RegistrySize] = cast
end

local function UnregisterCast(cast: ActiveCast)
	-- Just queue it. SweepRegistry does the actual O(1) removal.
	PendingRemovalSize += 1
	PendingRemoval[PendingRemovalSize] = cast
end

local function SweepRegistry()
	if PendingRemovalSize == 0 then return end
	for pi = 1, PendingRemovalSize do
		local dead = PendingRemoval[pi]
		local i = dead._registryIndex
		-- Swap the last entry into this slot
		local last = Registry[RegistrySize]
		Registry[i] = last
		if last then
			last._registryIndex = i  -- update moved cast's index
		end
		Registry[RegistrySize] = nil
		RegistrySize -= 1
		PendingRemoval[pi] = nil
	end
	PendingRemovalSize = 0
end

-- ─── RaycastParams Pool ──────────────────────────────────────────────────────

local ParamsPool: { RaycastParams }   = {}
local ParamsPoolSize                  = 0
local MAX_PARAMS_POOL_SIZE            = 256

local function AcquireParams(src: RaycastParams?): RaycastParams
	local params: RaycastParams

	if ParamsPoolSize > 0 then
		params = ParamsPool[ParamsPoolSize]
		ParamsPool[ParamsPoolSize] = nil
		ParamsPoolSize -= 1
	else
		params = RaycastParams.new()
	end

	if src then
		params.CollisionGroup             = src.CollisionGroup
		params.FilterType                 = src.FilterType
		params.FilterDescendantsInstances = src.FilterDescendantsInstances
		params.IgnoreWater                = src.IgnoreWater
	end

	return params
end

local function ReleaseParams(params: RaycastParams)
	if ParamsPoolSize >= MAX_PARAMS_POOL_SIZE then return end

	params.FilterDescendantsInstances = EMPTY_FILTER
	params.CollisionGroup             = ""
	params.FilterType                 = Enum.RaycastFilterType.Exclude
	params.IgnoreWater                = false

	ParamsPoolSize += 1
	ParamsPool[ParamsPoolSize] = params
end

-- ─── Utilities ───────────────────────────────────────────────────────────────

local function GetVisualizationFolder(): Folder
	local folder = WorkspaceTerrain:FindFirstChild(VIS_FOLDER_NAME)
	if folder then return folder end

	folder            = InstanceNew("Folder")
	folder.Name       = VIS_FOLDER_NAME
	folder.Archivable = false
	folder.Parent     = WorkspaceTerrain
	return folder
end

-- ─── Debug Helpers ───────────────────────────────────────────────────────────

local function DebugPrint(msg: string)
	if FastCast.DebugLogging then print(msg) end
end

local function VisualizeSegment(origin: CFrame, length: number): ConeHandleAdornment?
	if not FastCast.VisualizeCasts then return nil end

	local a           = InstanceNew("ConeHandleAdornment")
	a.Adornee         = WorkspaceTerrain
	a.CFrame          = origin
	a.Height          = length
	a.Radius          = 0.25
	a.Transparency    = 0.5
	a.Color3          = IS_SERVER
		and Color3FromRGB(255, 145, 11)
		or  Color3New(1, 0, 0)
	a.Parent          = GetVisualizationFolder()
	return a
end

local function VisualizeHit(cf: CFrame, isPierce: boolean): SphereHandleAdornment?
	if not FastCast.VisualizeCasts then return nil end

	local a           = InstanceNew("SphereHandleAdornment")
	a.Adornee         = WorkspaceTerrain
	a.CFrame          = cf
	a.Radius          = 0.4
	a.Transparency    = 0.25
	a.Color3          = isPierce
		and Color3New(1,   0.2, 0.2)
		or  Color3New(0.2, 1,   0.5)
	a.Parent          = GetVisualizationFolder()
	return a
end

-- ─── Physics ─────────────────────────────────────────────────────────────────

local function PositionAtTime(t: number, origin: Vector3, v0: Vector3, accel: Vector3): Vector3
	return origin + v0 * t + accel * (t ^ 2 / 2)
end

local function VelocityAtTime(t: number, v0: Vector3, accel: Vector3): Vector3
	return v0 + accel * t
end

local function TrajectoryEndInfo(cast: ActiveCast, index: number): (Vector3, Vector3)
	local traj     = cast.StateInfo.Trajectories[index]
	local duration = traj.EndTime - traj.StartTime
	return
		PositionAtTime(duration, traj.Origin, traj.InitialVelocity, traj.Acceleration),
	VelocityAtTime(duration, traj.InitialVelocity, traj.Acceleration)
end

local function LatestTrajectoryEndInfo(cast: ActiveCast): (Vector3, Vector3)
	return TrajectoryEndInfo(cast, #cast.StateInfo.Trajectories)
end

-- ─── Signal Wrappers ─────────────────────────────────────────────────────────

local function FireRayHit(cast: ActiveCast, result: RaycastResult, vel: Vector3)
	cast.Caster.RayHit:Fire(cast, result, vel, cast.RayInfo.CosmeticBulletObject)
end

local function FireRayPierced(cast: ActiveCast, result: RaycastResult, vel: Vector3)
	cast.StateInfo.PierceCount += 1
	local remaining = cast.RayInfo.MaxDistance - cast.StateInfo.DistanceCovered
	cast.Caster.RayPierced:Fire(cast, result, vel, cast.RayInfo.CosmeticBulletObject, cast.StateInfo.PierceCount, remaining)
end

local function FireLengthChanged(cast: ActiveCast, lastPoint: Vector3, dir: Vector3, displacement: number, vel: Vector3)
	cast.Caster.LengthChanged:Fire(cast, lastPoint, dir, displacement, vel, cast.RayInfo.CosmeticBulletObject)
end

-- ─── Simulation: Pierce Resolution ───────────────────────────────────────────

local function ResolvePierce(cast: ActiveCast, firstResult: RaycastResult, lastPoint: Vector3, rayDir: Vector3, segVel: Vector3): (boolean, RaycastResult?)
	local RayInfo        = cast.RayInfo
	local params         = RayInfo.Parameters
	local originalFilter = params.FilterDescendantsInstances
	local filter         = originalFilter
	local pierceCount    = 0
	local result         = firstResult
	local solidHit       = false
	local isExclude      = params.FilterType == Enum.RaycastFilterType.Exclude
	local worldRoot      = RayInfo.WorldRoot
	local canPierceCb    = RayInfo.CanPierceCallback
	local bulletObj      = RayInfo.CosmeticBulletObject

	while true do
		local hitInstance = result.Instance

		if hitInstance:IsA("Terrain") then
			if result.Material == Enum.Material.Water then
				params.FilterDescendantsInstances = originalFilter
				cast.StateInfo.IsActivelySimulatingPierce = false
				cast:Terminate()
				error("Do not pierce Water — set RaycastParams.IgnoreWater = true instead", 0)
			end
			warn("Pierce callback returned true on Terrain — this may cause issues.")
		end

		if isExclude then
			filter[#filter + 1] = hitInstance
		else
			local idx = tableFind(filter, hitInstance)
			if idx then
				filter[idx] = filter[#filter]
				filter[#filter] = nil
			end
		end

		params.FilterDescendantsInstances = filter
		FireRayPierced(cast, result, segVel)

		result = worldRoot:Raycast(lastPoint, rayDir, params)
		if result == nil then break end

		if pierceCount >= MAX_PIERCE_TEST_COUNT then
			warn("Exceeded max pierce tests (" .. MAX_PIERCE_TEST_COUNT .. ") for one segment.")
			break
		end
		pierceCount += 1

		if canPierceCb(cast, result, segVel, bulletObj) == false then
			solidHit = true
			break
		end
	end

	params.FilterDescendantsInstances = originalFilter
	cast.StateInfo.IsActivelySimulatingPierce = false
	return solidHit, result
end

-- ─── Simulation: High-Fidelity Resimulation ──────────────────────────────────

local function ResimulateHighFidelity(cast: ActiveCast, traj: any, lastDelta: number, delta: number, rayDisplacement: number): boolean
	if cast.StateInfo.IsActivelyResimulating then
		cast:Terminate()
		error(ERR_CASCADE_LAG)
	end
	cast.StateInfo.IsActivelyResimulating = true
	cast.StateInfo.CancelHighResCast = false

	local numSegments   = mathMax(mathFloor(rayDisplacement / cast.StateInfo.HighFidelitySegmentSize), 1)
	local timeIncrement = delta / numSegments
	local hitConfirmed  = false

	local StateInfo  = cast.StateInfo
	local RayInfo    = cast.RayInfo
	local worldRoot  = RayInfo.WorldRoot
	local params     = RayInfo.Parameters
	local canPierceCb = RayInfo.CanPierceCallback
	local bulletObj  = RayInfo.CosmeticBulletObject
	local trajOrigin = traj.Origin
	local trajVel    = traj.InitialVelocity
	local trajAccel  = traj.Acceleration

	for i = 1, numSegments do
		if StateInfo.CancelHighResCast then
			StateInfo.CancelHighResCast = false
			break
		end

		local t         = lastDelta + timeIncrement * i
		local subPos    = PositionAtTime(t, trajOrigin, trajVel, trajAccel)
		local subVel    = VelocityAtTime(t, trajVel, trajAccel)
		local subDir    = subVel * delta
		local subResult = worldRoot:Raycast(subPos, subDir, params)

		if subResult then
			local subDisp = (subPos - subResult.Position).Magnitude
			local dbgSeg  = VisualizeSegment(CFrameNew(subPos, subPos + subVel), subDisp)
			local canPierce = canPierceCb and canPierceCb(cast, subResult, subVel, bulletObj)

			if not canPierce then
				cast.StateInfo.IsActivelyResimulating = false
				FireRayHit(cast, subResult, subVel)
				cast:Terminate()
				local vis = VisualizeHit(CFrameNew(subResult.Position), false)
				if vis then vis.Color3 = Color3FromRGB(15, 223, 255) end
				hitConfirmed = true
				break
			else
				FireRayPierced(cast, subResult, subVel)
				VisualizeHit(CFrameNew(subResult.Position), true)
				if dbgSeg then dbgSeg.Color3 = Color3FromRGB(78, 62, 84) end
			end
		else
			VisualizeSegment(CFrameNew(subPos, subPos + subVel), subVel.Magnitude * delta)
		end
	end

	StateInfo.IsActivelyResimulating = false
	return hitConfirmed
end

-- ─── Simulation: Core ────────────────────────────────────────────────────────

local function SimulateCast(cast: ActiveCast, delta: number, expectingShortCall: boolean)
	assert(cast.StateInfo ~= nil, ERR_DISPOSED)
	DebugPrint("Simulating frame.")

	local stateInfo  = cast.StateInfo
	local rayInfo    = cast.RayInfo
	local traj       = stateInfo.ActiveTrajectory
	local elapsed    = stateInfo.TotalRuntime - traj.StartTime

	local trajOrigin = traj.Origin
	local trajVel    = traj.InitialVelocity
	local trajAccel  = traj.Acceleration

	local lastPoint  = PositionAtTime(elapsed, trajOrigin, trajVel, trajAccel)
	local lastDelta  = elapsed

	stateInfo.TotalRuntime += delta
	elapsed = stateInfo.TotalRuntime - traj.StartTime

	local currentTarget   = PositionAtTime(elapsed, trajOrigin, trajVel, trajAccel)
	local segVel          = VelocityAtTime(elapsed, trajVel, trajAccel)
	local displacement    = currentTarget - lastPoint

	local rayDir          = displacement.Unit * segVel.Magnitude * delta
	local worldRoot       = rayInfo.WorldRoot
	local params          = rayInfo.Parameters
	local result          = worldRoot:Raycast(lastPoint, rayDir, params)

	local hitPoint        = result and result.Position or currentTarget
	local rayDisplacement = (hitPoint - lastPoint).Magnitude

	FireLengthChanged(cast, lastPoint, rayDir.Unit, rayDisplacement, segVel)
	stateInfo.DistanceCovered += rayDisplacement

	if delta > 0 then
		VisualizeSegment(CFrameNew(lastPoint, lastPoint + rayDir), rayDisplacement)
	end

	local bulletObj   = rayInfo.CosmeticBulletObject
	local canPierceCb = rayInfo.CanPierceCallback

	if result and result.Instance ~= bulletObj then
		DebugPrint("Hit detected: " .. result.Instance.Name)

		if canPierceCb then
			if not expectingShortCall and stateInfo.IsActivelySimulatingPierce then
				cast:Terminate()
				error(ERR_PIERCE_YIELD)
			end
			stateInfo.IsActivelySimulatingPierce = true
		end

		local canPierce = canPierceCb and canPierceCb(cast, result, segVel, bulletObj)

		if not canPierce then
			stateInfo.IsActivelySimulatingPierce = false

			local hfb           = stateInfo.HighFidelityBehavior
			local hasAccel      = traj.HasAcceleration
			local hasHFSegments = stateInfo.HighFidelitySegmentSize ~= 0

			if hfb == 2 and hasAccel and hasHFSegments then
				DebugPrint("Suspected hit — verifying via high-fidelity resimulation.")
				local confirmed = ResimulateHighFidelity(cast, traj, lastDelta, delta, rayDisplacement)
				if confirmed then return end

			elseif hfb == 1 or hfb == 3 then
				DebugPrint("Hit confirmed. Terminating.")
				FireRayHit(cast, result, segVel)
				cast:Terminate()
				VisualizeHit(CFrameNew(hitPoint), false)
			else
				cast:Terminate()
				error(ERR_INVALID_HFB .. hfb)
			end
			return

		else
			DebugPrint("Piercing.")
			VisualizeHit(CFrameNew(hitPoint), true)

			local solidHit, solidResult = ResolvePierce(cast, result, lastPoint, rayDir, segVel)
			if solidHit and solidResult then
				DebugPrint("Pierce chain ended on solid: " .. solidResult.Instance.Name)
				FireRayHit(cast, solidResult, segVel)
				cast:Terminate()
				VisualizeHit(CFrameNew(solidResult.Position), false)
				return
			end
		end
	end

	if stateInfo.DistanceCovered >= rayInfo.MaxDistance then
		FireRayHit(cast, nil, segVel)
		cast:Terminate()
		VisualizeHit(CFrameNew(currentTarget), false)
	end
end

-- ─── Simulation: High-Fidelity Frame Loop ────────────────────────────────────

local function SimulateHighFidelityFrame(cast: ActiveCast, delta: number)
	if cast.StateInfo.IsActivelyResimulating then
		cast:Terminate()
		error(ERR_CASCADE_LAG)
	end
	cast.StateInfo.IsActivelyResimulating = true

	local stateInfo    = cast.StateInfo
	local traj         = stateInfo.ActiveTrajectory
	local elapsed      = stateInfo.TotalRuntime - traj.StartTime
	local trajOrigin   = traj.Origin
	local trajVel      = traj.InitialVelocity
	local trajAccel    = traj.Acceleration

	local lastPoint    = PositionAtTime(elapsed, trajOrigin, trajVel, trajAccel)

	stateInfo.TotalRuntime += delta
	elapsed = stateInfo.TotalRuntime - traj.StartTime

	local currentPoint    = PositionAtTime(elapsed, trajOrigin, trajVel, trajAccel)
	local currentVel      = VelocityAtTime(elapsed, trajVel, trajAccel)
	local totalDisplace   = currentPoint - lastPoint

	local rayDir          = totalDisplace.Unit * currentVel.Magnitude * delta
	local preResult       = cast.RayInfo.WorldRoot:Raycast(lastPoint, rayDir, cast.RayInfo.Parameters)
	local hitPoint        = preResult and preResult.Position or currentPoint
	local rayDisplacement = (hitPoint - lastPoint).Magnitude

	stateInfo.TotalRuntime -= delta

	local numSegments = mathMax(mathFloor(rayDisplacement / stateInfo.HighFidelitySegmentSize), 1)
	local timeStep    = delta / numSegments

	for i = 1, numSegments do
		if stateInfo.Alive == false then return end
		if stateInfo.CancelHighResCast then
			stateInfo.CancelHighResCast = false
			break
		end
		DebugPrint(stringFormat("[HF %d/%d] step=%.4f", i, numSegments, timeStep))
		SimulateCast(cast, timeStep, true)
	end

	if stateInfo.Alive == false then return end
	stateInfo.IsActivelyResimulating = false
end

-- ─── Shared Frame Loop ───────────────────────────────────────────────────────
--[[
	One connection for all casts. Steps every live cast, then sweeps
	terminated casts out of the registry at the end of the frame.
]]

local UpdateEvent = IS_CLIENT and RunService.RenderStepped or RunService.Heartbeat

UpdateEvent:Connect(function(delta: number)
	-- Step all live casts.
	for i = 1, RegistrySize do
		local cast = Registry[i]

		-- Cast may have been terminated by a previous cast's simulation
		-- this same frame (e.g. a signal handler fired Terminate).
		if cast.StateInfo == nil or cast.StateInfo.Alive == false then
			continue
		end

		if cast.StateInfo.Paused then
			continue
		end

		local traj = cast.StateInfo.ActiveTrajectory

		if cast.StateInfo.IsHighFidelityMode
			and traj.HasAcceleration
			and cast.StateInfo.HighFidelitySegmentSize > 0
		then
			SimulateHighFidelityFrame(cast, delta)
		else
			SimulateCast(cast, delta, false)
		end
	end

	-- Sweep terminated casts out of the registry.
	SweepRegistry()
end)

-- ─── Constructor ─────────────────────────────────────────────────────────────

function ActiveCast.new(caster: Caster, origin: Vector3, direction: Vector3, velocity: Vector3 | number, behavior: FastCastBehavior): ActiveCast
	if typeof(velocity) == "number" then
		velocity = direction.Unit * velocity
	end

	assert(behavior.HighFidelitySegmentSize > 0, "FastCastBehavior.HighFidelitySegmentSize must be > 0")

	local cast = setmetatable({
		Caster = caster,

		StateInfo = {
			-- Alive flag is checked by the frame loop to skip terminated casts
			-- that haven't been swept yet.
			Alive                      = true,
			Paused                     = false,
			PierceCount                = 0, 
			TotalRuntime               = 0,
			DistanceCovered            = 0,
			HighFidelitySegmentSize    = behavior.HighFidelitySegmentSize,
			HighFidelityBehavior       = behavior.HighFidelityBehavior,
			-- Cached here so the frame loop doesn't recompute it every tick.
			IsHighFidelityMode         = behavior.HighFidelityBehavior == 3,
			IsActivelySimulatingPierce = false,
			IsActivelyResimulating     = false,
			CancelHighResCast          = false,
			ActiveTrajectory           = nil,
			Trajectories = {
				{
					StartTime       = 0,
					EndTime         = -1,
					Origin          = origin,
					InitialVelocity = velocity,
					Acceleration    = behavior.Acceleration,
					HasAcceleration = behavior.Acceleration ~= ZERO_VECTOR,
				}
			},
		},

		RayInfo = {
			Parameters           = AcquireParams(behavior.RaycastParams),
			WorldRoot            = workspace,
			MaxDistance          = behavior.MaxDistance or 1000,
			CosmeticBulletObject = behavior.CosmeticBulletTemplate,
			CanPierceCallback    = behavior.CanPierceFunction,
		},

		UserData = {},
	}, ActiveCast)

	cast.StateInfo.ActiveTrajectory = cast.StateInfo.Trajectories[1]

	-- ── Cosmetic Bullet ──────────────────────────────────────────────────

	local usingProvider = false

	if behavior.CosmeticBulletProvider ~= nil then
		if typeof(behavior.CosmeticBulletProvider) == "function" then
			if cast.RayInfo.CosmeticBulletObject ~= nil then
				warn("Do not set both CosmeticBulletTemplate and CosmeticBulletProvider — provider wins.")
				cast.RayInfo.CosmeticBulletObject = nil
				behavior.CosmeticBulletTemplate   = nil
			end
			cast.RayInfo.CosmeticBulletObject = behavior.CosmeticBulletProvider()
			usingProvider = true
		else
			warn("CosmeticBulletProvider must be a function — ignoring.")
			behavior.CosmeticBulletProvider = nil
		end
	elseif cast.RayInfo.CosmeticBulletObject ~= nil then
		cast.RayInfo.CosmeticBulletObject = cast.RayInfo.CosmeticBulletObject:Clone()
		cast.RayInfo.CosmeticBulletObject.Parent = behavior.CosmeticBulletContainer
	end

	-- ── Auto-Ignore Container ────────────────────────────────────────────

	if usingProvider and behavior.AutoIgnoreContainer and behavior.CosmeticBulletContainer then
		local ignoreList = cast.RayInfo.Parameters.FilterDescendantsInstances
		if not tableFind(ignoreList, behavior.CosmeticBulletContainer) then
			tableInsert(ignoreList, behavior.CosmeticBulletContainer)
			cast.RayInfo.Parameters.FilterDescendantsInstances = ignoreList
		end
	elseif usingProvider and not behavior.CosmeticBulletContainer then
		warn("CosmeticBulletContainer should be provided when using a CosmeticBulletProvider.")
	end

	-- ── Register ─────────────────────────────────────────────────────────
	-- No per-cast connection. Just add to the shared registry.
	RegisterCast(cast)

	return cast
end

function ActiveCast.SetStaticFastCastReference(ref: any)
	FastCast = ref
end

-- ─── Getters ─────────────────────────────────────────────────────────────────

function ActiveCast:GetPosition(): Vector3
	assert(getmetatable(self) == ActiveCast, ERR_NOT_INSTANCE:format("GetPosition"))
	assert(self.StateInfo ~= nil, ERR_DISPOSED)
	local traj = self.StateInfo.ActiveTrajectory
	return PositionAtTime(self.StateInfo.TotalRuntime - traj.StartTime, traj.Origin, traj.InitialVelocity, traj.Acceleration)
end

function ActiveCast:GetVelocity(): Vector3
	assert(getmetatable(self) == ActiveCast, ERR_NOT_INSTANCE:format("GetVelocity"))
	assert(self.StateInfo ~= nil, ERR_DISPOSED)
	local traj = self.StateInfo.ActiveTrajectory
	return VelocityAtTime(self.StateInfo.TotalRuntime - traj.StartTime, traj.InitialVelocity, traj.Acceleration)
end

function ActiveCast:GetAcceleration(): Vector3
	assert(getmetatable(self) == ActiveCast, ERR_NOT_INSTANCE:format("GetAcceleration"))
	assert(self.StateInfo ~= nil, ERR_DISPOSED)
	return self.StateInfo.ActiveTrajectory.Acceleration
end

-- ─── Setters ─────────────────────────────────────────────────────────────────

local function ModifyTrajectory(cast: ActiveCast, velocity: Vector3?, acceleration: Vector3?, position: Vector3?)
	local trajectories = cast.StateInfo.Trajectories
	local last         = cast.StateInfo.ActiveTrajectory

	if last.StartTime == cast.StateInfo.TotalRuntime then
		last.Origin          = position     or last.Origin
		last.InitialVelocity = velocity     or last.InitialVelocity
		local newAccel       = acceleration or last.Acceleration
		last.Acceleration    = newAccel
		last.HasAcceleration = newAccel ~= ZERO_VECTOR
	else
		last.EndTime = cast.StateInfo.TotalRuntime

		local endPos, endVel = LatestTrajectoryEndInfo(cast)
		local newAccel       = acceleration or last.Acceleration

		local newTraj = {
			StartTime       = cast.StateInfo.TotalRuntime,
			EndTime         = -1,
			Origin          = position or endPos,
			InitialVelocity = velocity or endVel,
			Acceleration    = newAccel,
			HasAcceleration = newAccel ~= ZERO_VECTOR,
		}
		tableInsert(trajectories, newTraj)
		cast.StateInfo.ActiveTrajectory  = newTraj
		cast.StateInfo.CancelHighResCast = true
	end
end

function ActiveCast:SetPosition(position: Vector3)
	assert(getmetatable(self) == ActiveCast, ERR_NOT_INSTANCE:format("SetPosition"))
	assert(self.StateInfo ~= nil, ERR_DISPOSED)
	ModifyTrajectory(self, nil, nil, position)
end

function ActiveCast:SetVelocity(velocity: Vector3)
	assert(getmetatable(self) == ActiveCast, ERR_NOT_INSTANCE:format("SetVelocity"))
	assert(self.StateInfo ~= nil, ERR_DISPOSED)
	ModifyTrajectory(self, velocity, nil, nil)
end

function ActiveCast:SetAcceleration(acceleration: Vector3)
	assert(getmetatable(self) == ActiveCast, ERR_NOT_INSTANCE:format("SetAcceleration"))
	assert(self.StateInfo ~= nil, ERR_DISPOSED)
	ModifyTrajectory(self, nil, acceleration, nil)
end

-- ─── Arithmetic ──────────────────────────────────────────────────────────────

function ActiveCast:AddPosition(offset: Vector3)
	self:SetPosition(self:GetPosition() + offset)
end

function ActiveCast:AddVelocity(delta: Vector3)
	self:SetVelocity(self:GetVelocity() + delta)
end

function ActiveCast:AddAcceleration(delta: Vector3)
	self:SetAcceleration(self:GetAcceleration() + delta)
end

-- ─── State ───────────────────────────────────────────────────────────────────

function ActiveCast:Pause()
	assert(getmetatable(self) == ActiveCast, ERR_NOT_INSTANCE:format("Pause"))
	assert(self.StateInfo ~= nil, ERR_DISPOSED)
	self.StateInfo.Paused = true
end

function ActiveCast:Resume()
	assert(getmetatable(self) == ActiveCast, ERR_NOT_INSTANCE:format("Resume"))
	assert(self.StateInfo ~= nil, ERR_DISPOSED)
	self.StateInfo.Paused = false
end

function ActiveCast:Terminate()
	assert(getmetatable(self) == ActiveCast, ERR_NOT_INSTANCE:format("Terminate"))
	assert(self.StateInfo ~= nil, ERR_DISPOSED)

	local params = self.RayInfo.Parameters

	local last   = self.StateInfo.ActiveTrajectory
	last.EndTime = self.StateInfo.TotalRuntime

	-- Mark dead BEFORE firing CastTerminating so the frame loop skips this
	-- cast if any signal handler somehow triggers another frame step.
	self.StateInfo.Alive = false

	-- Queue removal from registry. Actual swap-remove happens at end of frame
	-- in SweepRegistry() so we don't corrupt the frame loop's iteration.
	UnregisterCast(self)

	self.Caster.CastTerminating:FireSync(self)

	self.Caster    = nil
	self.StateInfo = nil
	self.RayInfo   = nil
	self.UserData  = nil
	setmetatable(self, nil)

	ReleaseParams(params)
end

-- ─── Export ──────────────────────────────────────────────────────────────────

return ActiveCast