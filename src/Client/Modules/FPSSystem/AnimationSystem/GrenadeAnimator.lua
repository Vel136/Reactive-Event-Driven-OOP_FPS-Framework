-- GrenadeAnimator.lua
--[[
	Manages grenade animation state with priority-based blending.
	- Standard animation states (Idle, Equip, Cook, CookIdle, Throw, Unequip)
	- Custom animation registration and playback
	- Automatic signal binding to grenade events
	- Idle and CookIdle are looped; all other states are one-shot
]]

local Identity = "GrenadeAnimator"

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
	Idle     = 1,
	Equip    = 2,
	Cook     = 3,
	CookIdle = 4,
	Throw    = 5,
	Unequip  = 6,
	-- Custom animations begin at 100
	Custom   = 100,
}

-- Internal priority levels (higher = more important)
local AnimationPriority = {
	[AnimationState.Idle]     = 1,
	[AnimationState.CookIdle] = 2,
	[AnimationState.Equip]    = 3,
	[AnimationState.Unequip]  = 3,
	[AnimationState.Cook]     = 4,
	[AnimationState.Throw]    = 5,
}

-- Roblox animation priorities per state
local RobloxPriority = {
	[AnimationState.Idle]     = Enum.AnimationPriority.Idle,
	[AnimationState.CookIdle] = Enum.AnimationPriority.Action,
	[AnimationState.Equip]    = Enum.AnimationPriority.Action2,
	[AnimationState.Unequip]  = Enum.AnimationPriority.Action2,
	[AnimationState.Cook]     = Enum.AnimationPriority.Action3,
	[AnimationState.Throw]    = Enum.AnimationPriority.Action4,
}

-- Loop settings per state
-- Idle and CookIdle loop; everything else is a one-shot
local LoopSettings = {
	[AnimationState.Idle]     = true,
	[AnimationState.CookIdle] = true,
	[AnimationState.Equip]    = false,
	[AnimationState.Unequip]  = false,
	[AnimationState.Cook]     = false,
	[AnimationState.Throw]    = false,
}

-- Which states each incoming state is allowed to stop
local CanInterrupt = {
	[AnimationState.Idle]     = {},
	[AnimationState.CookIdle] = {},
	[AnimationState.Equip]    = {},
	[AnimationState.Unequip]  = { AnimationState.CookIdle, AnimationState.Cook },
	[AnimationState.Cook]     = { AnimationState.CookIdle },
	[AnimationState.Throw]    = { AnimationState.CookIdle, AnimationState.Cook },
}

-- ─── Module ──────────────────────────────────────────────────────────────────

local GrenadeAnimator   = {}
GrenadeAnimator.__index = GrenadeAnimator
GrenadeAnimator.__type  = Identity

GrenadeAnimator.State = AnimationState

-- ─── Private state ───────────────────────────────────────────────────────────

local Logger = LogService.new(Identity, true)

-- ─── Constructor ─────────────────────────────────────────────────────────────

--- Creates a new GrenadeAnimator. Returns nil if inputs are invalid.
function GrenadeAnimator.new(grenade: any, viewmodel: Model): GrenadeAnimator?
	if not grenade then
		Logger:Warn("new: invalid grenade provided")
		return nil
	end

	if not viewmodel then
		Logger:Warn("new: invalid viewmodel provided")
		return nil
	end

	local self: GrenadeAnimator = setmetatable({}, GrenadeAnimator)

	self.Grenade   = grenade
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

	Logger:Print(string.format("new: initialized for '%s'", grenade.Data.Name))

	return self
end

-- ─── Getters ─────────────────────────────────────────────────────────────────

--- Returns the current animation state enum value.
function GrenadeAnimator.GetCurrentState(self: GrenadeAnimator): number
	return self.CurrentState
end

--- Returns true if the given animation state is currently playing.
function GrenadeAnimator.IsPlaying(self: GrenadeAnimator, state: number): boolean
	return self.AnimationController:IsPlaying(state)
end

--- Returns the state ID for a custom animation by name, or nil if not found.
function GrenadeAnimator.GetCustomAnimationID(self: GrenadeAnimator, name: string): number?
	for stateId, data in pairs(self.CustomAnimations) do
		if data.Name == name then
			return stateId
		end
	end
	return nil
end

--- Returns an array of all registered custom animation names.
function GrenadeAnimator.GetCustomAnimationNames(self: GrenadeAnimator): { string }
	local names = {}
	for _, data in pairs(self.CustomAnimations) do
		table.insert(names, data.Name)
	end
	return names
end

-- ─── Standard animation API ──────────────────────────────────────────────────

--- Plays an animation state with priority checking and conflict resolution.
function GrenadeAnimator.PlayAnimation(self: GrenadeAnimator, state: number, fadeTime: number?)
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
function GrenadeAnimator.StopAnimation(self: GrenadeAnimator, state: number, fadeTime: number?)
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
function GrenadeAnimator.StopAllAnimations(self: GrenadeAnimator)
	self.AnimationController:StopAllAnimations(0.3)
	self.CurrentState    = AnimationState.Idle
	self.CurrentPriority = AnimationPriority[AnimationState.Idle]
	self.IsTransitioning = false
	Logger:Print("StopAllAnimations: complete")
end

-- ─── Custom animation API ────────────────────────────────────────────────────

--- Registers a custom animation and returns its assigned state ID.
function GrenadeAnimator.RegisterCustomAnimation(
	self                 : GrenadeAnimator,
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
function GrenadeAnimator.PlayCustomAnimation(self: GrenadeAnimator, name: string, fadeTime: number?): boolean
	local stateId = self:GetCustomAnimationID(name)
	if not stateId then
		Logger:Warn(string.format("PlayCustomAnimation: '%s' not found", name))
		return false
	end
	self:PlayAnimation(stateId, fadeTime)
	return true
end

--- Stops a custom animation by name. Returns true on success.
function GrenadeAnimator.StopCustomAnimation(self: GrenadeAnimator, name: string, fadeTime: number?): boolean
	local stateId = self:GetCustomAnimationID(name)
	if not stateId then
		Logger:Warn(string.format("StopCustomAnimation: '%s' not found", name))
		return false
	end
	self:StopAnimation(stateId, fadeTime)
	return true
end

--- Unregisters a custom animation by name. Returns true on success.
function GrenadeAnimator.UnregisterCustomAnimation(self: GrenadeAnimator, name: string): boolean
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

--- Loads all standard animations from grenade data into the AnimationController.
function GrenadeAnimator._LoadAnimations(self: GrenadeAnimator)
	local animations = self.Grenade.Data.Animations
	if not animations then
		Logger:Warn("_LoadAnimations: no animations found on grenade")
		return
	end

	local animTable   = {}
	local priorityMap = {}
	local loopMap     = {}

	local stateNames = { "Idle", "Equip", "Cook", "CookIdle", "Throw", "Unequip" }
	local stateIds   = {
		Idle     = AnimationState.Idle,
		Equip    = AnimationState.Equip,
		Cook     = AnimationState.Cook,
		CookIdle = AnimationState.CookIdle,
		Throw    = AnimationState.Throw,
		Unequip  = AnimationState.Unequip,
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

--- Connects grenade signals to animation playback.
function GrenadeAnimator._BindSignals(self: GrenadeAnimator)
	local signals = self.Grenade.Signals

	-- Equip / Unequip
	if signals.OnEquipChanged then
		self._Janitor:Add(signals.OnEquipChanged:Connect(function(isEquipped: boolean)
			if isEquipped then
				self:_EnsureIdlePlaying()
				if self.AnimationController:GetTrack(AnimationState.Equip) then
					self:PlayAnimation(AnimationState.Equip)
				end
			else
				-- Play unequip animation if available, otherwise stop everything
				if self.AnimationController:GetTrack(AnimationState.Unequip) then
					self:PlayAnimation(AnimationState.Unequip)
				else
					self:StopAllAnimations()
				end
			end
		end), "Disconnect")
	end

	-- Cook started → play Cook then transition to CookIdle
	if signals.OnCookStarted then
		self._Janitor:Add(signals.OnCookStarted:Connect(function()
			if self.AnimationController:GetTrack(AnimationState.Cook) then
				self:PlayAnimation(AnimationState.Cook)
			elseif self.AnimationController:GetTrack(AnimationState.CookIdle) then
				-- No separate cook wind-up; go straight to loop
				self:PlayAnimation(AnimationState.CookIdle)
			end
		end), "Disconnect")
	end

	-- Cook cancelled → stop CookIdle and return to Idle
	if signals.OnCookCancelled then
		self._Janitor:Add(signals.OnCookCancelled:Connect(function()
			self:StopAnimation(AnimationState.CookIdle)
			self:StopAnimation(AnimationState.Cook)
			self:_EnsureIdlePlaying()
		end), "Disconnect")
	end

	-- Throw
	if signals.OnThrow then
		self._Janitor:Add(signals.OnThrow:Connect(function()
			self:PlayAnimation(AnimationState.Throw)
		end), "Disconnect")
	end

	Logger:Print("_BindSignals: signals bound")
end

--- Starts idle if it is not already playing.
function GrenadeAnimator._EnsureIdlePlaying(self: GrenadeAnimator)
	if not self.AnimationController:IsPlaying(AnimationState.Idle) then
		local idleTrack = self.AnimationController:GetTrack(AnimationState.Idle)
		if idleTrack then
			self.AnimationController:PlayAnimation(AnimationState.Idle, 0.3)
		end
	end
end

--- Stops animations that the incoming state is allowed to interrupt.
function GrenadeAnimator._StopConflictingAnimations(self: GrenadeAnimator, newState: number)
	-- Custom animations stop all non-idle states
	if newState >= AnimationState.Custom then
		for state in pairs(AnimationPriority) do
			if state ~= AnimationState.Idle and state ~= newState then
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
function GrenadeAnimator._OnAnimationComplete(self: GrenadeAnimator, state: number)
	self.IsTransitioning = false
	self._Janitor:Remove("AnimationComplete_" .. state)

	Logger:Print(string.format("_OnAnimationComplete: state %d finished", state))

	-- Cook wind-up finished → start CookIdle loop
	if state == AnimationState.Cook then
		if self.AnimationController:GetTrack(AnimationState.CookIdle) then
			self:PlayAnimation(AnimationState.CookIdle)
		else
			self:_EnsureIdlePlaying()
		end

		-- Equip finished → settle into Idle
	elseif state == AnimationState.Equip then
		self.CurrentState    = AnimationState.Idle
		self.CurrentPriority = AnimationPriority[AnimationState.Idle]
		self:_EnsureIdlePlaying()

		-- Throw finished → return to Idle (grenade is gone)
	elseif state == AnimationState.Throw then
		self.CurrentState    = AnimationState.Idle
		self.CurrentPriority = AnimationPriority[AnimationState.Idle]
		self:_EnsureIdlePlaying()

		-- Unequip finished → stop everything cleanly
	elseif state == AnimationState.Unequip then
		self:StopAllAnimations()

		-- Custom one-shot finished → fall back to Idle
	elseif state >= AnimationState.Custom then
		self.CurrentState    = AnimationState.Idle
		self.CurrentPriority = AnimationPriority[AnimationState.Idle]
		self:_EnsureIdlePlaying()
	end
end

-- ─── Lifecycle ───────────────────────────────────────────────────────────────

--- Destroys the GrenadeAnimator and cleans up all resources.
function GrenadeAnimator.Destroy(self: GrenadeAnimator)
	local grenadeName = self.Grenade and self.Grenade.Data.Name or "Unknown"
	Logger:Print(string.format("Destroy: cleaning up animator for '%s'", grenadeName))

	self._Janitor:Destroy()

	if self.AnimationController then
		self.AnimationController:Destroy()
	end

	self.Grenade              = nil
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

export type GrenadeAnimator = typeof(setmetatable({}, GrenadeAnimator)) & {
	Grenade              : any,
	Viewmodel            : Model,
	AnimationController  : any,
	CurrentState         : number,
	CurrentPriority      : number,
	IsTransitioning      : boolean,
	CustomAnimations     : { [number]: CustomAnimationData },
	_NextCustomId        : number,
	_Janitor             : any,
}

return GrenadeAnimator