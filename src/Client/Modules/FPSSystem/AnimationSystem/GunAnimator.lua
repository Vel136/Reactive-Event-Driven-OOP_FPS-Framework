-- GunAnimator.lua
--[[
	Manages weapon animation state with priority-based blending.
	- Standard animation states (Idle, Equip, Fire, Reload, Aim)
	- Custom animation registration and playback
	- Automatic signal binding to weapon events
]]

local Identity = "GunAnimator"

-- ─── Services ────────────────────────────────────────────────────────────────

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ─── References ──────────────────────────────────────────────────────────────

local Utilities = ReplicatedStorage.Shared.Modules.Utilities

-- ─── Modules ─────────────────────────────────────────────────────────────────

local Janitor             = require(Utilities.Janitor)
local LogService          = require(Utilities.Logger)
local AnimationController = require(script.Parent.AnimationController)

-- ─── Constants ───────────────────────────────────────────────────────────────

-- Animation state enums
local AnimationState = {
	Idle   = 1,
	Equip  = 2,
	Fire   = 3,
	Reload = 4,
	Aim    = 5,
	-- Custom animations begin at 100
	Custom = 100,
}

-- Internal priority levels (higher = more important)
local AnimationPriority = {
	[AnimationState.Idle]   = 1,
	[AnimationState.Aim]    = 2,
	[AnimationState.Equip]  = 3,
	[AnimationState.Fire]   = 4,
	[AnimationState.Reload] = 5,
}

-- Roblox animation priorities per state
local RobloxPriority = {
	[AnimationState.Idle]   = Enum.AnimationPriority.Idle,
	[AnimationState.Aim]    = Enum.AnimationPriority.Action,
	[AnimationState.Equip]  = Enum.AnimationPriority.Action2,
	[AnimationState.Fire]   = Enum.AnimationPriority.Action3,
	[AnimationState.Reload] = Enum.AnimationPriority.Action4,
}

-- Loop settings per state
local LoopSettings = {
	[AnimationState.Idle]   = true,
	[AnimationState.Aim]    = true,
	[AnimationState.Equip]  = false,
	[AnimationState.Fire]   = false,
	[AnimationState.Reload] = false,
}

-- Which states each new state is allowed to stop
local CanInterrupt = {
	[AnimationState.Fire]   = { AnimationState.Aim },
	[AnimationState.Reload] = { AnimationState.Aim, AnimationState.Fire },
	[AnimationState.Equip]  = { AnimationState.Aim, AnimationState.Fire, AnimationState.Reload },
	[AnimationState.Aim]    = {},
	[AnimationState.Idle]   = {},
}

-- ─── Module ──────────────────────────────────────────────────────────────────

local GunAnimator   = {}
GunAnimator.__index = GunAnimator
GunAnimator.__type  = Identity

GunAnimator.State = AnimationState

-- ─── Private state ───────────────────────────────────────────────────────────

local Logger = LogService.new(Identity, false)

-- ─── Constructor ─────────────────────────────────────────────────────────────

--- Creates a new GunAnimator. Returns nil if inputs are invalid.
function GunAnimator.new(weapon: any, viewmodel: Model): GunAnimator?
	if not weapon then
		Logger:Warn("new: invalid weapon provided")
		return nil
	end

	if not viewmodel then
		Logger:Warn("new: invalid viewmodel provided")
		return nil
	end

	local self: GunAnimator = setmetatable({}, GunAnimator)

	self.Weapon    = weapon
	self.Viewmodel = viewmodel
	self._Janitor  = Janitor.new()

	self.AnimationController = AnimationController.new(viewmodel)
	if not self.AnimationController then
		Logger:Warn("new: failed to create AnimationController")
		return nil
	end

	self.CurrentState    = AnimationState.Idle
	self.CurrentPriority = AnimationPriority[AnimationState.Idle]
	self.IsTransitioning = false

	self.CustomAnimations = {} :: { [number]: CustomAnimationData }
	self._NextCustomId    = AnimationState.Custom

	self:_LoadAnimations()
	self:_BindSignals()

	Logger:Print(string.format("new: initialized for '%s'", weapon.Data.Name))

	return self
end

-- ─── Getters ─────────────────────────────────────────────────────────────────

--- Returns the current animation state enum value.
function GunAnimator.GetCurrentState(self: GunAnimator): number
	return self.CurrentState
end

--- Returns true if the given animation state is currently playing.
function GunAnimator.IsPlaying(self: GunAnimator, state: number): boolean
	return self.AnimationController:IsPlaying(state)
end

--- Returns the state ID for a custom animation by name, or nil if not found.
function GunAnimator.GetCustomAnimationID(self: GunAnimator, name: string): number?
	for stateId, data in pairs(self.CustomAnimations) do
		if data.Name == name then
			return stateId
		end
	end
	return nil
end

--- Returns an array of all registered custom animation names.
function GunAnimator.GetCustomAnimationNames(self: GunAnimator): { string }
	local names = {}
	for _, data in pairs(self.CustomAnimations) do
		table.insert(names, data.Name)
	end
	return names
end

-- ─── Standard animation API ──────────────────────────────────────────────────

--- Plays an animation state with priority checking and conflict resolution.
function GunAnimator.PlayAnimation(self: GunAnimator, state: number, fadeTime: number?)
	local priority = AnimationPriority[state]
	if not priority then
		Logger:Warn(string.format("PlayAnimation: invalid state %d", state))
		return
	end

	if state ~= AnimationState.Idle then
		self:_EnsureIdlePlaying()
	end

	if priority < self.CurrentPriority and self.IsTransitioning then
		Logger:Print(string.format("PlayAnimation: blocked by priority (%d < %d)", priority, self.CurrentPriority))
		return
	end

	if state ~= AnimationState.Idle then
		self:_StopConflictingAnimations(state)
	end

	local track: AnimationTrack = self.AnimationController:PlayAnimation(state, fadeTime or 0.3)
	if not track then return end

	self.CurrentState    = state
	self.CurrentPriority = priority
	self.IsTransitioning = true

	if not track.Looped then
		self._Janitor:Add(track.Stopped:Connect(function()
			self:_OnAnimationComplete(state)
		end), "Disconnect", "AnimationComplete_" .. state)
	else
		self.IsTransitioning = false
	end
end

--- Stops a specific animation state. Idle is never stopped via this method.
function GunAnimator.StopAnimation(self: GunAnimator, state: number, fadeTime: number?)
	if state == AnimationState.Idle then return end

	self.AnimationController:StopAnimation(state, fadeTime or 0.3)

	if self.CurrentState == state then
		self.CurrentState    = AnimationState.Idle
		self.CurrentPriority = AnimationPriority[AnimationState.Idle]
		self.IsTransitioning = false
		self:_EnsureIdlePlaying()
	end
end

--- Stops all animations including idle.
function GunAnimator.StopAllAnimations(self: GunAnimator)
	self.AnimationController:StopAllAnimations(0.3)
	self.CurrentState    = AnimationState.Idle
	self.CurrentPriority = AnimationPriority[AnimationState.Idle]
	self.IsTransitioning = false
	Logger:Print("StopAllAnimations: complete")
end

-- ─── Custom animation API ────────────────────────────────────────────────────

--- Registers a custom animation and returns its assigned state ID.
function GunAnimator.RegisterCustomAnimation(
	self                 : GunAnimator,
	name                 : string,
	animation            : Animation | string,
	priority             : number?,
	loop                 : boolean?,
	robloxAnimPriority   : Enum.AnimationPriority?
): number?
	if not name or name == "" then
		Logger:Warn("RegisterCustomAnimation: name is required")
		return nil
	end

	local existing = self:GetCustomAnimationID(name)
	if existing then
		Logger:Warn(string.format("RegisterCustomAnimation: '%s' already registered", name))
		return existing
	end

	local stateId          = self._NextCustomId
	self._NextCustomId    += 1

	local customPriority   = priority           or 3
	local customLoop       = loop               or false
	local customRobloxPrio = robloxAnimPriority or Enum.AnimationPriority.Action

	self.CustomAnimations[stateId] = {
		Name     = name,
		Priority = customPriority,
		Loop     = customLoop,
	}

	AnimationPriority[stateId] = customPriority

	self.AnimationController:LoadAnimations(
		{ [stateId] = animation },
		{ [stateId] = customRobloxPrio },
		{ [stateId] = customLoop }
	)

	Logger:Print(string.format("RegisterCustomAnimation: '%s' registered as id %d", name, stateId))
	return stateId
end

--- Plays a custom animation by name. Returns true on success.
function GunAnimator.PlayCustomAnimation(self: GunAnimator, name: string, fadeTime: number?): boolean
	local stateId = self:GetCustomAnimationID(name)
	if not stateId then
		Logger:Warn(string.format("PlayCustomAnimation: '%s' not found", name))
		return false
	end
	self:PlayAnimation(stateId, fadeTime)
	return true
end

--- Stops a custom animation by name. Returns true on success.
function GunAnimator.StopCustomAnimation(self: GunAnimator, name: string, fadeTime: number?): boolean
	local stateId = self:GetCustomAnimationID(name)
	if not stateId then
		Logger:Warn(string.format("StopCustomAnimation: '%s' not found", name))
		return false
	end
	self:StopAnimation(stateId, fadeTime)
	return true
end

--- Unregisters a custom animation by name. Returns true on success.
function GunAnimator.UnregisterCustomAnimation(self: GunAnimator, name: string): boolean
	local stateId = self:GetCustomAnimationID(name)
	if not stateId then
		Logger:Warn(string.format("UnregisterCustomAnimation: '%s' not found", name))
		return false
	end

	if self:IsPlaying(stateId) then
		self:StopAnimation(stateId, 0.2)
	end

	self.CustomAnimations[stateId] = nil
	AnimationPriority[stateId]     = nil

	Logger:Print(string.format("UnregisterCustomAnimation: '%s' removed", name))
	return true
end

-- ─── Internal ────────────────────────────────────────────────────────────────

--- Loads all standard animations from weapon data into the AnimationController.
function GunAnimator._LoadAnimations(self: GunAnimator)
	local animations = self.Weapon.Data.Animations
	if not animations then
		Logger:Warn("_LoadAnimations: no animations found on weapon")
		return
	end

	local animTable   = {}
	local priorityMap = {}
	local loopMap     = {}

	local stateNames = { "Idle", "Equip", "Fire", "Reload", "Aim" }
	local stateIds   = {
		Idle   = AnimationState.Idle,
		Equip  = AnimationState.Equip,
		Fire   = AnimationState.Fire,
		Reload = AnimationState.Reload,
		Aim    = AnimationState.Aim,
	}

	for _, name in ipairs(stateNames) do
		local stateId = stateIds[name]
		if animations[name] then
			animTable[stateId]   = animations[name]
			priorityMap[stateId] = RobloxPriority[stateId]
			loopMap[stateId]     = LoopSettings[stateId]
		end
	end

	self.AnimationController:LoadAnimations(animTable, priorityMap, loopMap)
end

--- Connects weapon signals to animation playback.
function GunAnimator._BindSignals(self: GunAnimator)
	local signals = self.Weapon.Signals

	if signals.OnFire then
		self._Janitor:Add(signals.OnFire:Connect(function()
			self:PlayAnimation(AnimationState.Fire)
		end), "Disconnect")
	end

	if signals.OnAimChanged then
		self._Janitor:Add(signals.OnAimChanged:Connect(function(isAiming: boolean)
			if isAiming then
				self:PlayAnimation(AnimationState.Aim)
			else
				self:StopAnimation(AnimationState.Aim)
			end
		end), "Disconnect")
	end

	if signals.OnReloadStarted then
		self._Janitor:Add(signals.OnReloadStarted:Connect(function()
			self:PlayAnimation(AnimationState.Reload)
		end), "Disconnect")
	end

	if signals.OnEquipChanged then
		self._Janitor:Add(signals.OnEquipChanged:Connect(function(isEquipped: boolean)
			if isEquipped then
				self:_EnsureIdlePlaying()
				if self.AnimationController:GetTrack(AnimationState.Equip) then
					self:PlayAnimation(AnimationState.Equip)
				end
			else
				self:StopAllAnimations()
			end
		end), "Disconnect")
	end

	Logger:Print("_BindSignals: signals bound")
end

--- Starts idle if it is not already playing.
function GunAnimator._EnsureIdlePlaying(self: GunAnimator)
	if not self.AnimationController:IsPlaying(AnimationState.Idle) then
		local idleTrack = self.AnimationController:GetTrack(AnimationState.Idle)
		if idleTrack then
			self.AnimationController:PlayAnimation(AnimationState.Idle, 0.3)
		end
	end
end

--- Stops animations that the incoming state is allowed to interrupt.
function GunAnimator._StopConflictingAnimations(self: GunAnimator, newState: number)
	-- Custom animations stop all non-idle, non-aim states
	if newState >= AnimationState.Custom then
		for state in pairs(AnimationPriority) do
			if state ~= AnimationState.Idle and state ~= AnimationState.Aim and state ~= newState then
				if self.AnimationController:IsPlaying(state) then
					self.AnimationController:StopAnimation(state, 0.2)
				end
			end
		end
		return
	end

	for _, state in ipairs(CanInterrupt[newState] or {}) do
		if self.AnimationController:IsPlaying(state) then
			self.AnimationController:StopAnimation(state, 0.2)
		end
	end
end

--- Called when a non-looped animation finishes. Handles state transitions.
function GunAnimator._OnAnimationComplete(self: GunAnimator, state: number)
	self.IsTransitioning = false
	self._Janitor:Remove("AnimationComplete_" .. state)

	Logger:Print(string.format("_OnAnimationComplete: state %d finished", state))

	self:_EnsureIdlePlaying()

	if state == AnimationState.Equip or state == AnimationState.Reload then
		if self.Weapon.Signals.OnEquipCompleted then
			self.Weapon.Signals.OnEquipCompleted:Fire()
		end

		if self.Weapon:IsAiming() and self.AnimationController:GetTrack(AnimationState.Aim) then
			self:PlayAnimation(AnimationState.Aim)
		else
			self.CurrentState    = AnimationState.Idle
			self.CurrentPriority = AnimationPriority[AnimationState.Idle]
		end

	elseif state == AnimationState.Fire then
		if self.AnimationController:IsPlaying(AnimationState.Aim) then
			self.CurrentState    = AnimationState.Aim
			self.CurrentPriority = AnimationPriority[AnimationState.Aim]
		else
			self.CurrentState    = AnimationState.Idle
			self.CurrentPriority = AnimationPriority[AnimationState.Idle]
		end

	elseif state >= AnimationState.Custom then
		if self.AnimationController:IsPlaying(AnimationState.Aim) then
			self.CurrentState    = AnimationState.Aim
			self.CurrentPriority = AnimationPriority[AnimationState.Aim]
		else
			self.CurrentState    = AnimationState.Idle
			self.CurrentPriority = AnimationPriority[AnimationState.Idle]
		end
	end
end

-- ─── Lifecycle ───────────────────────────────────────────────────────────────

--- Destroys the GunAnimator and cleans up all resources.
function GunAnimator.Destroy(self: GunAnimator)
	local weaponName = self.Weapon and self.Weapon.Data.Name or "Unknown"
	Logger:Print(string.format("Destroy: cleaning up animator for '%s'", weaponName))

	self._Janitor:Destroy()

	if self.AnimationController then
		self.AnimationController:Destroy()
	end

	self.Weapon               = nil
	self.Viewmodel            = nil
	self.AnimationController  = nil
	self.CustomAnimations     = nil

	setmetatable(self, nil)

	Logger:Print("Destroy: complete")
end

-- ─── Types ───────────────────────────────────────────────────────────────────

type CustomAnimationData = {
	Name     : string,
	Priority : number,
	Loop     : boolean,
}

export type GunAnimator = typeof(setmetatable({}, GunAnimator)) & {
	Weapon               : any,
	Viewmodel            : Model,
	AnimationController  : any,
	CurrentState         : number,
	CurrentPriority      : number,
	IsTransitioning      : boolean,
	CustomAnimations     : { [number]: CustomAnimationData },
	_NextCustomId        : number,
	_Janitor             : any,
}

return GunAnimator