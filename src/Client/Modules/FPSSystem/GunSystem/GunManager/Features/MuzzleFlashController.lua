-- MuzzleFlashController.lua
--[[
	Manages muzzle flash visual effects including:
	- Particle emission control
	- Light flash effects
	- Effect synchronization
]]

local Identity = "MuzzleFlashController"

-- ─── Services ────────────────────────────────────────────────────────────────

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ─── References ──────────────────────────────────────────────────────────────

local Utilities = ReplicatedStorage.Shared.Modules.Utilities

-- ─── Modules ─────────────────────────────────────────────────────────────────

local Signal     = require(Utilities.Signal)
local LogService = require(Utilities:FindFirstChild("Logger"))

-- ─── Constants ───────────────────────────────────────────────────────────────

local DEFAULT_PARTICLE_COUNT  = 20
local DEFAULT_LIGHT_DURATION  = 0.1
local DEFAULT_LIGHT_BRIGHTNESS = 10

-- ─── Module ──────────────────────────────────────────────────────────────────

local MuzzleFlashController   = {}
MuzzleFlashController.__index = MuzzleFlashController
MuzzleFlashController.__type  = Identity

-- ─── Private state ───────────────────────────────────────────────────────────

local Logger = LogService.new(Identity, false)

-- ─── Getters ─────────────────────────────────────────────────────────────────

--- Returns true if the controller is enabled.
function MuzzleFlashController.IsEnabled(self: MuzzleFlashController): boolean
	return self._Enabled
end

--- Returns the number of particles emitted per flash.
function MuzzleFlashController.GetParticleCount(self: MuzzleFlashController): number
	return self._ParticleCount
end

--- Returns true if the light flash is enabled.
function MuzzleFlashController.IsLightFlashEnabled(self: MuzzleFlashController): boolean
	return self._LightFlashEnabled
end

--- Returns the current state snapshot.
function MuzzleFlashController.GetState(self: MuzzleFlashController): MuzzleFlashControllerState
	return {
		Enabled              = self._Enabled,
		ParticleCount        = self._ParticleCount,
		LightFlashEnabled    = self._LightFlashEnabled,
		ParticleEmitterCount = #self._ParticleEmitters,
		HasLight             = self._Light ~= nil,
	}
end

--- Returns the metadata table.
function MuzzleFlashController.GetMetadata(self: MuzzleFlashController): any
	return self._Metadata
end

-- ─── Setters ─────────────────────────────────────────────────────────────────

--- Sets the enabled state. Fires OnEnabledChanged if changed.
function MuzzleFlashController.SetEnabled(self: MuzzleFlashController, enabled: boolean)
	local old = self._Enabled
	self._Enabled = enabled
	if old ~= enabled then
		self.Signals.OnEnabledChanged:Fire(enabled)
		Logger:Debug(string.format("SetEnabled: %s -> %s", tostring(old), tostring(enabled)))
	end
end

--- Sets the particle emission count per flash.
function MuzzleFlashController.SetParticleCount(self: MuzzleFlashController, count: number)
	local old = self._ParticleCount
	self._ParticleCount = math.max(1, count)
	if old ~= self._ParticleCount then
		Logger:Debug(string.format("SetParticleCount: %d -> %d", old, self._ParticleCount))
	end
end

--- Sets whether the light flash is active.
function MuzzleFlashController.SetLightFlashEnabled(self: MuzzleFlashController, enabled: boolean)
	local old = self._LightFlashEnabled
	self._LightFlashEnabled = enabled
	if old ~= enabled then
		Logger:Debug(string.format("SetLightFlashEnabled: %s -> %s", tostring(old), tostring(enabled)))
	end
end

--- Sets the light flash duration in seconds.
function MuzzleFlashController.SetLightDuration(self: MuzzleFlashController, duration: number)
	self.Data.LightDuration = math.max(0.01, duration)
	Logger:Debug(string.format("SetLightDuration: %.2fs", self.Data.LightDuration))
end

--- Sets the light flash brightness.
function MuzzleFlashController.SetLightBrightness(self: MuzzleFlashController, brightness: number)
	self.Data.LightBrightness = math.max(0, brightness)
	Logger:Debug(string.format("SetLightBrightness: %.1f", self.Data.LightBrightness))
end

--- Sets the metadata table.
function MuzzleFlashController.SetMetadata(self: MuzzleFlashController, metadata: any)
	self._Metadata = metadata
end

-- ─── Flash API ───────────────────────────────────────────────────────────────

--- Plays the muzzle flash effect with an optional per-call context override.
function MuzzleFlashController.PlayFlash(self: MuzzleFlashController, context: MuzzleFlashContext?)
	if not self._Enabled then
		Logger:Debug("PlayFlash: disabled, skipping")
		return
	end

	context = context or {}

	local particleCount   = context.ParticleCount   or self._ParticleCount
	local lightDuration   = context.LightDuration   or self.Data.LightDuration   or DEFAULT_LIGHT_DURATION
	local lightBrightness = context.LightBrightness or self.Data.LightBrightness or DEFAULT_LIGHT_BRIGHTNESS

	-- Emit particles
	if #self._ParticleEmitters > 0 then
		for _, emitter in ipairs(self._ParticleEmitters) do
			emitter:Emit(particleCount)
		end

		self.Signals.OnParticlesEmitted:Fire({
			Emitters = self._ParticleEmitters,
			Count    = particleCount,
		} :: MuzzleFlashParticleInfo)
	end

	-- Light flash
	if self._LightFlashEnabled and self._Light then
		self._Light.Brightness = lightBrightness
		self._Light.Enabled    = true

		self.Signals.OnLightFlashed:Fire({
			Light      = self._Light,
			Brightness = lightBrightness,
			Duration   = lightDuration,
		} :: MuzzleFlashLightInfo)

		task.delay(lightDuration, function()
			if self._Light then
				self._Light.Enabled    = false
				self._Light.Brightness = self._OriginalLightBrightness
			end
		end)
	end

	self.Signals.OnFlashPlayed:Fire({
		ParticleCount   = particleCount,
		LightEnabled    = self._LightFlashEnabled and self._Light ~= nil,
		LightDuration   = lightDuration,
		LightBrightness = lightBrightness,
	} :: MuzzleFlashInfo)

	Logger:Debug(string.format("PlayFlash: particles=%d light=%s", particleCount, tostring(self._LightFlashEnabled)))
end

-- ─── Internal ────────────────────────────────────────────────────────────────

function MuzzleFlashController._InitializeEffects(self: MuzzleFlashController)
	self._ParticleEmitters = {}

	if self.Data.Particles then
		for _, particle in ipairs(self.Data.Particles) do
			if particle:IsA("ParticleEmitter") then
				table.insert(self._ParticleEmitters, particle)
			else
				Logger:Warn(string.format("_InitializeEffects: '%s' is not a ParticleEmitter", particle.Name))
			end
		end
	end

	self._Light                  = nil
	self._OriginalLightBrightness = 0

	if self.Data.Light then
		if self.Data.Light:IsA("Light") then
			self._Light                   = self.Data.Light
			self._OriginalLightBrightness = self._Light.Brightness
			self._Light.Enabled           = false
		else
			Logger:Warn("_InitializeEffects: provided Light is not a Light instance")
		end
	end

	Logger:Debug(string.format("_InitializeEffects: emitters=%d light=%s",
		#self._ParticleEmitters, tostring(self._Light ~= nil)))
end

-- ─── Lifecycle ───────────────────────────────────────────────────────────────

--- Destroys the MuzzleFlashController and cleans up all resources.
function MuzzleFlashController.Destroy(self: MuzzleFlashController)
	Logger:Print("Destroy: cleaning up")

	self:SetEnabled(false)

	for _, signal in self.Signals do
		signal:Destroy()
	end

	self.Data              = nil
	self._Metadata         = nil
	self._Light            = nil
	table.clear(self._ParticleEmitters)
end

-- ─── Constructor ─────────────────────────────────────────────────────────────

local module = {}

--- Creates a new MuzzleFlashController.
function module.new(data: MuzzleFlashControllerData, metadata: any?): MuzzleFlashController
	assert(data,       "MuzzleFlashController.new: data is required")
	assert(data.Name,  "MuzzleFlashController.new: data.Name is required")

	local self: MuzzleFlashController = setmetatable({}, { __index = MuzzleFlashController })

	self.Data                  = data
	self.Data.LightDuration    = data.LightDuration    or DEFAULT_LIGHT_DURATION
	self.Data.LightBrightness  = data.LightBrightness  or DEFAULT_LIGHT_BRIGHTNESS

	self._Metadata           = metadata or {}
	self._Enabled            = true
	self._ParticleCount      = data.ParticleCount or DEFAULT_PARTICLE_COUNT
	self._LightFlashEnabled  = if data.LightFlashEnabled ~= nil then data.LightFlashEnabled else true
	self._ParticleEmitters   = {}
	self._Light              = nil
	self._OriginalLightBrightness = 0

	self.Signals = {
		OnFlashPlayed      = Signal.new(),
		OnParticlesEmitted = Signal.new(),
		OnLightFlashed     = Signal.new(),
		OnEnabledChanged   = Signal.new(),
	}

	self:_InitializeEffects()

	Logger:Debug(string.format("new: '%s' particles=%d lightFlash=%s",
		data.Name, self._ParticleCount, tostring(self._LightFlashEnabled)))

	return self
end

-- ─── Types ───────────────────────────────────────────────────────────────────

export type MuzzleFlashControllerData = {
	Name               : string,
	Particles          : { ParticleEmitter }?,
	Light              : Light?,
	ParticleCount      : number?,
	LightDuration      : number?,
	LightBrightness    : number?,
	LightFlashEnabled  : boolean?,
}

export type MuzzleFlashContext = {
	ParticleCount  : number?,
	LightDuration  : number?,
	LightBrightness: number?,
}

export type MuzzleFlashInfo = {
	ParticleCount   : number,
	LightEnabled    : boolean,
	LightDuration   : number,
	LightBrightness : number,
}

export type MuzzleFlashParticleInfo = {
	Emitters : { ParticleEmitter },
	Count    : number,
}

export type MuzzleFlashLightInfo = {
	Light      : Light,
	Brightness : number,
	Duration   : number,
}

export type MuzzleFlashControllerState = {
	Enabled              : boolean,
	ParticleCount        : number,
	LightFlashEnabled    : boolean,
	ParticleEmitterCount : number,
	HasLight             : boolean,
}

export type MuzzleFlashController = typeof(setmetatable({}, { __index = MuzzleFlashController })) & {
	Data                  : MuzzleFlashControllerData,
	_Enabled              : boolean,
	_ParticleCount        : number,
	_LightFlashEnabled    : boolean,
	_ParticleEmitters     : { ParticleEmitter },
	_Light                : Light?,
	_OriginalLightBrightness : number,
	_Metadata             : any,
	Signals: {
		OnFlashPlayed      : Signal.Signal<(info: MuzzleFlashInfo) -> ()>,
		OnParticlesEmitted : Signal.Signal<(info: MuzzleFlashParticleInfo) -> ()>,
		OnLightFlashed     : Signal.Signal<(info: MuzzleFlashLightInfo) -> ()>,
		OnEnabledChanged   : Signal.Signal<(enabled: boolean) -> ()>,
	},
}

return table.freeze(module)