-- TracerController.lua
--[[
	Manages bullet tracer cosmetics including:
	- Tracer lifecycle (spawn, travel, termination)
	- Object pooling integration
	- Configurable visual properties
]]

local Identity = "TracerController"

-- ─── Services ────────────────────────────────────────────────────────────────

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

-- ─── References ──────────────────────────────────────────────────────────────

local Utilities = ReplicatedStorage.Shared.Modules.Utilities

-- ─── Modules ─────────────────────────────────────────────────────────────────

local Signal     = require(Utilities.Signal)
local LogService = require(Utilities:FindFirstChild("Logger"))

-- ─── Constants ───────────────────────────────────────────────────────────────

local DEFAULT_TRACER_SPEED  = 2000
local DEFAULT_TRACER_WIDTH  = 0.1
local DEFAULT_TRACER_LENGTH = 10
local DEFAULT_FADE_TIME     = 0.1

-- ─── Module ──────────────────────────────────────────────────────────────────

local TracerController   = {}
TracerController.__index = TracerController
TracerController.__type  = Identity

-- ─── Private state ───────────────────────────────────────────────────────────

local Logger = LogService.new(Identity, false)

-- ─── Getters ─────────────────────────────────────────────────────────────────

--- Returns true if tracers are enabled.
function TracerController.IsEnabled(self: TracerController): boolean
	return self._Enabled
end

--- Returns the current state snapshot.
function TracerController.GetState(self: TracerController): TracerControllerState
	return {
		Enabled = self._Enabled,
	}
end

--- Returns the metadata table.
function TracerController.GetMetadata(self: TracerController): any
	return self._Metadata
end

-- ─── Setters ─────────────────────────────────────────────────────────────────

--- Sets the enabled state. Fires OnEnabledChanged if changed.
function TracerController.SetEnabled(self: TracerController, enabled: boolean)
	local old = self._Enabled
	self._Enabled = enabled
	if old ~= enabled then
		self.Signals.OnEnabledChanged:Fire(enabled)
		Logger:Debug(string.format("SetEnabled: %s -> %s", tostring(old), tostring(enabled)))
	end
end

--- Sets the pool provider callback.
function TracerController.SetPoolProvider(self: TracerController, provider: () -> BasePart?)
	self._PoolProvider = provider
	Logger:Debug("SetPoolProvider: provider updated")
end

--- Sets the pool return callback.
function TracerController.SetPoolReturnCallback(self: TracerController, callback: (part: BasePart) -> ())
	self.Data.PoolReturnCallback = callback
	Logger:Debug("SetPoolReturnCallback: callback updated")
end

--- Sets the metadata table.
function TracerController.SetMetadata(self: TracerController, metadata: any)
	self._Metadata = metadata
end

-- ─── Tracer API ──────────────────────────────────────────────────────────────

--- Spawns a single tracer from the given context.
function TracerController.SpawnTracer(self: TracerController, context: TracerSpawnContext)
	if not self._Enabled then
		Logger:Debug("SpawnTracer: disabled, skipping")
		return
	end

	if not context.Origin or not context.Direction then
		Logger:Warn("SpawnTracer: context missing Origin or Direction")
		return
	end

	local tracerPart = self:_GetTracerFromPool()
	if not tracerPart then
		Logger:Warn("SpawnTracer: failed to get tracer part from pool")
		return
	end

	local origin      = context.Origin
	local direction   = context.Direction.Unit
	local length      = context.Length      or self.Data.DefaultLength or DEFAULT_TRACER_LENGTH
	local speed       = context.Speed       or self.Data.DefaultSpeed  or DEFAULT_TRACER_SPEED
	local width       = context.Width       or self.Data.DefaultWidth  or DEFAULT_TRACER_WIDTH
	local maxDistance = context.MaxDistance or 1000

	tracerPart.Size   = Vector3.new(width, width, length)
	tracerPart.CFrame = CFrame.lookAt(origin, origin + direction) * CFrame.new(0, 0, -length / 2)
	tracerPart.Parent = self.Data.Container or workspace

	self.Signals.OnTracerSpawned:Fire({
		Part      = tracerPart,
		Origin    = origin,
		Direction = direction,
		Length    = length,
		Speed     = speed,
		Width     = width,
	} :: TracerSpawnInfo)

	Logger:Debug(string.format("SpawnTracer: length=%.1f speed=%.1f", length, speed))

	local startTime    = tick()
	local maxTravelTime = maxDistance / speed
	local connection: RBXScriptConnection

	connection = RunService.RenderStepped:Connect(function()
		local elapsed         = tick() - startTime
		local currentDistance = elapsed * speed

		if elapsed >= maxTravelTime or currentDistance >= maxDistance then
			connection:Disconnect()

			local travelInfo: TracerTravelInfo = {
				Part             = tracerPart,
				CurrentPosition  = origin + direction * math.min(currentDistance, maxDistance),
				DistanceTraveled = math.min(currentDistance, maxDistance),
				Elapsed          = elapsed,
			}
			self.Signals.OnTracerTravelComplete:Fire(travelInfo)

			task.delay(self.Data.FadeTime or DEFAULT_FADE_TIME, function()
				self.Signals.OnTracerTerminated:Fire({
					Part       = tracerPart,
					Reason     = "Complete",
					TravelTime = tick() - startTime,
				} :: TracerTerminateInfo)

				self:_ReturnTracerToPool(tracerPart)
			end)
			return
		end

		local currentPos = origin + direction * currentDistance
		tracerPart.CFrame = CFrame.lookAt(currentPos, currentPos + direction) * CFrame.new(0, 0, -length / 2)

		self.Signals.OnTracerUpdate:Fire({
			Part             = tracerPart,
			CurrentPosition  = currentPos,
			DistanceTraveled = currentDistance,
			Elapsed          = elapsed,
		} :: TracerTravelInfo)
	end)
end

--- Spawns multiple tracers from an array of contexts.
function TracerController.SpawnTracers(self: TracerController, contexts: { TracerSpawnContext })
	for _, context in ipairs(contexts) do
		self:SpawnTracer(context)
	end
end

-- ─── Internal ────────────────────────────────────────────────────────────────

function TracerController._GetTracerFromPool(self: TracerController): BasePart?
	if self._PoolProvider then
		local part = self._PoolProvider()
		if part then return part end
	end
	Logger:Warn("_GetTracerFromPool: pool returned nil")
	return nil
end

function TracerController._ReturnTracerToPool(self: TracerController, part: BasePart)
	if self.Data.PoolReturnCallback then
		self.Data.PoolReturnCallback(part)
	else
		part:Destroy()
	end
end

function TracerController._InitializePool(self: TracerController)
	if not self.Data.PoolProvider then
		Logger:Warn("_InitializePool: no pool provider, tracers will not be pooled")
		return
	end
	self._PoolProvider = self.Data.PoolProvider
	Logger:Debug(string.format("_InitializePool: pool ready for '%s'", self.Data.Name))
end

-- ─── Lifecycle ───────────────────────────────────────────────────────────────

--- Destroys the TracerController and cleans up all resources.
function TracerController.Destroy(self: TracerController)
	Logger:Print("Destroy: cleaning up")

	self:SetEnabled(false)

	for _, signal in self.Signals do
		signal:Destroy()
	end

	self.Data          = nil
	self._PoolProvider = nil
	self._Metadata     = nil
end

-- ─── Constructor ─────────────────────────────────────────────────────────────

local module = {}

--- Creates a new TracerController.
function module.new(data: TracerControllerData, metadata: any?): TracerController
	assert(data,       "TracerController.new: data is required")
	assert(data.Name,  "TracerController.new: data.Name is required")

	local self: TracerController = setmetatable({}, { __index = TracerController })

	self.Data                = data
	self.Data.DefaultSpeed   = data.DefaultSpeed   or DEFAULT_TRACER_SPEED
	self.Data.DefaultWidth   = data.DefaultWidth   or DEFAULT_TRACER_WIDTH
	self.Data.DefaultLength  = data.DefaultLength  or DEFAULT_TRACER_LENGTH
	self.Data.FadeTime       = data.FadeTime       or DEFAULT_FADE_TIME
	self.Data.Container      = data.Container      or workspace

	self._Metadata     = metadata or {}
	self._Enabled      = true
	self._PoolProvider = nil

	self.Signals = {
		OnTracerSpawned       = Signal.new(),
		OnTracerUpdate        = Signal.new(),
		OnTracerTravelComplete = Signal.new(),
		OnTracerTerminated    = Signal.new(),
		OnEnabledChanged      = Signal.new(),
	}

	self:_InitializePool()

	Logger:Debug(string.format("new: '%s' speed=%.1f width=%.2f length=%.1f",
		data.Name,
		self.Data.DefaultSpeed,
		self.Data.DefaultWidth,
		self.Data.DefaultLength))

	return self
end

-- ─── Types ───────────────────────────────────────────────────────────────────

export type TracerControllerData = {
	Name               : string,
	DefaultSpeed       : number?,
	DefaultWidth       : number?,
	DefaultLength      : number?,
	FadeTime           : number?,
	Container          : Instance?,
	PoolProvider       : (() -> BasePart?)?,
	PoolReturnCallback : ((part: BasePart) -> ())?,
}

export type TracerSpawnContext = {
	Origin      : Vector3,
	Direction   : Vector3,
	Length      : number?,
	Speed       : number?,
	Width       : number?,
	MaxDistance : number?,
}

export type TracerSpawnInfo = {
	Part      : BasePart,
	Origin    : Vector3,
	Direction : Vector3,
	Length    : number,
	Speed     : number,
	Width     : number,
}

export type TracerTravelInfo = {
	Part             : BasePart,
	CurrentPosition  : Vector3,
	DistanceTraveled : number,
	Elapsed          : number,
}

export type TracerTerminateInfo = {
	Part       : BasePart,
	Reason     : string,
	TravelTime : number,
}

export type TracerControllerState = {
	Enabled : boolean,
}

export type TracerController = typeof(setmetatable({}, { __index = TracerController })) & {
	Data           : TracerControllerData,
	_Enabled       : boolean,
	_PoolProvider  : (() -> BasePart?)?,
	_Metadata      : any,
	Signals: {
		OnTracerSpawned        : Signal.Signal<(info: TracerSpawnInfo) -> ()>,
		OnTracerUpdate         : Signal.Signal<(info: TracerTravelInfo) -> ()>,
		OnTracerTravelComplete : Signal.Signal<(info: TracerTravelInfo) -> ()>,
		OnTracerTerminated     : Signal.Signal<(info: TracerTerminateInfo) -> ()>,
		OnEnabledChanged       : Signal.Signal<(enabled: boolean) -> ()>,
	},
}

return table.freeze(module)