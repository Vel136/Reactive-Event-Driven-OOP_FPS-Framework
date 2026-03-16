-- GunInstance.lua
--[[
	Main gun orchestrator that provides a fully solver-agnostic weapon system.
	- Modular controller architecture (State, Ammo, Spread, Damage)
	- Signal-based event system for weapon actions
	- Ballistics integration with customizable behavior
	- Burst fire and pellet spread support
]]

local Identity = "GunInstance"

-- ─── Services ────────────────────────────────────────────────────────────────

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")

-- ─── References ──────────────────────────────────────────────────────────────

local Utilities  = ReplicatedStorage.Shared.Modules.Utilities
local Networking = ReplicatedStorage.Shared.Modules.Networking

local Player = Players.LocalPlayer

-- ─── Modules ─────────────────────────────────────────────────────────────────

local LogService = require(Utilities:WaitForChild("Logger"))
local Janitor    = require(Utilities:WaitForChild("Janitor"))
local Signal     = require(Utilities:WaitForChild("Signal"))

local StateManager     = require(script.StateManager)
local AmmoController   = require(script.AmmoController)
local SpreadController = require(script.SpreadController)
local DamageCalculator = require(script.DamageCalculator)

local BallisticsService = require(ReplicatedStorage.Client.Modules.FPSSystem.BallisticsSystem.BallisticsService)
local NetworkService    = require(Networking.NetworkService)

-- ─── Module ──────────────────────────────────────────────────────────────────

local GunInstance   = {}
GunInstance.__index = GunInstance
GunInstance.__type  = Identity

-- ─── Private state ───────────────────────────────────────────────────────────

local Logger    = LogService.new(Identity, true)
local IS_DEBUG  = game:GetService("RunService"):IsStudio()

-- ─── Signal Type Aliases ─────────────────────────────────────────────────────

type CanFireSignal    = Signal.Signal<(reject: (reason: string) -> ()) -> ()>
type PreFireSignal    = Signal.Signal<(fireData: any) -> ()>
type FireSignal       = Signal.Signal<(origin: Vector3, direction: Vector3) -> ()>
type HitSignal        = Signal.Signal<(ctx: any, hitData: any) -> ()>
type VoidSignal       = Signal.Signal<() -> ()>
type BulletFireSignal = Signal.Signal<(ctx: any) -> ()>
type ReloadDoneSignal = Signal.Signal<(ammo: number, reserve: number) -> ()>
type AmmoSignal       = Signal.Signal<(current: number, previous: number) -> ()>
type BoolSignal       = Signal.Signal<(value: boolean) -> ()>

-- ─── Validation ──────────────────────────────────────────────────────────────

--- Returns whether the weapon can fire, and a reason string if not.
function GunInstance.CanFire(self: GunInstance): (boolean, string?)
	if self.StateManager:IsReloading() then
		return false, "Weapon is reloading"
	end

	if not self.AmmoController:HasAmmo() then
		return false, "Out of ammo"
	end

	if not self.StateManager:IsEquipped() then
		return false, "Weapon not equipped"
	end

	if not self.StateManager:CanFire() then
		return false, "Weapon cant fire"
	end

	local validated    = true
	local rejectReason = nil

	self.Signals.OnCanFireCheck:Fire(function(reason: string)
		validated    = false
		rejectReason = reason
	end)

	if not validated then
		return false, rejectReason
	end

	local now              = os.clock()
	local timeBetweenShots = 60 / (self.Data.FireRate or 600)

	if now - self.StateManager.LastShootTime < timeBetweenShots then
		return false, "Firerate cooldown"
	end

	local character = self.StateManager:GetCharacter()
	if not character or not character:FindFirstChild("HumanoidRootPart") then
		return false, "Invalid character"
	end

	return true
end

-- ─── Firing ──────────────────────────────────────────────────────────────────

--- Fires the weapon in the given direction. Returns success and result/reason.
function GunInstance.Fire(self: GunInstance, origin: Vector3?, direction: Vector3, useHRP_Position: boolean?)
	local canFire, reason = self:CanFire()
	if not canFire then return false, reason end

	if IS_DEBUG then
		if typeof(direction) ~= "Vector3" then return false, "Invalid direction" end
		if origin and typeof(origin) ~= "Vector3" then return false, "Invalid origin" end
	end

	direction = direction.Unit

	local fireOrigin = origin
	if useHRP_Position or not fireOrigin then
		local hrp = self.StateManager:GetHRP()
		if not hrp then return false, "Missing HumanoidRootPart" end
		fireOrigin = hrp.Position
	end

	local result = self:_FireInternal(fireOrigin, direction)

	self.StateManager:SetShooting(true)
	task.defer(function()
		self.StateManager:SetShooting(false)
	end)

	return true, result
end

--- Fires a single bullet through the BallisticsService. Returns the BulletContext.
function GunInstance.FireBullet(self: GunInstance, origin: Vector3, direction: Vector3)
	local context = BallisticsService:Fire({
		Origin    = origin,
		Direction = direction,
		Speed     = self.Data.BulletSpeed or 1000,
		Behavior  = self.Ballistics.Behavior,
		Callbacks = self._BulletCallbacks,
	})

	self.Signals.OnBulletFire:Fire(context)
	return context
end

-- ─── Reload ──────────────────────────────────────────────────────────────────

--- Starts a reload. Returns a Promise that resolves when complete.
function GunInstance.Reload(self: GunInstance): any
	return self.AmmoController:Reload()
end

-- ─── State API ───────────────────────────────────────────────────────────────

--- Sets the aiming state.
function GunInstance.SetAiming(self: GunInstance, aiming: boolean)
	self.StateManager:SetAiming(aiming)
end

--- Returns the current aiming state.
function GunInstance.IsAiming(self: GunInstance): boolean
	return self.StateManager:IsAiming()
end

--- Returns the current equipped state.
function GunInstance.IsEquipped(self: GunInstance): boolean
	return self.StateManager:IsEquipped()
end

--- Equips the weapon.
function GunInstance.Equip(self: GunInstance)
	self.StateManager:SetEquipped(true)
end

--- Unequips the weapon and clears active states.
function GunInstance.Unequip(self: GunInstance)
	self.StateManager:SetEquipped(false)
	self.StateManager:SetAiming(false)
	self.StateManager:SetShooting(false)
end

--- Returns the full weapon state snapshot.
function GunInstance.GetState(self: GunInstance)
	local ammoState = self.AmmoController:GetState()
	local stateSnap = self.StateManager:GetAllStates()

	return {
		Ammo      = ammoState.Ammo,
		Reserve   = ammoState.Reserve,
		Aiming    = stateSnap.Aiming,
		Reloading = stateSnap.Reloading,
		Shooting  = stateSnap.Shooting,
		Equipped  = stateSnap.Equipped,
		Spread    = self.SpreadController:GetCurrentSpread(),
	}
end

--- Directly sets the magazine ammo count.
function GunInstance.ChangeAmmo(self: GunInstance, ammoValue: number)
	if self.AmmoController then
		self.AmmoController:SetAmmo(ammoValue)
	end
	return true
end

--- Directly sets the reserve ammo count.
function GunInstance.ChangeReserve(self: GunInstance, reserveValue: number)
	if self.AmmoController then
		self.AmmoController:SetReserve(reserveValue)
	end
	return true
end

--- Directly sets the spread value.
function GunInstance.SetSpread(self: GunInstance, amount: number): number
	return self.SpreadController:SetSpread(amount)
end

-- ─── Metadata ────────────────────────────────────────────────────────────────

--- Returns the metadata table.
function GunInstance.GetMetadata(self: GunInstance)
	return self._Metadata
end

--- Sets metadata, or a specific key within it.
function GunInstance.SetMetadata(self: GunInstance, data: any, key: any?)
	if key then
		if IS_DEBUG and type(self._Metadata) ~= "table" then
			Logger:Warn("SetMetadata: _Metadata is not a table")
			return false
		end
		self._Metadata[key] = data
		return true
	end

	self._Metadata = data
	return true
end

-- ─── Internal: firing ────────────────────────────────────────────────────────

--- Fires all pellets for a single shot, each with independent spread.
function GunInstance._FirePellets(self: GunInstance, origin: Vector3, direction: Vector3, count: number)
	for i = 1, count do
		local finalDir = self.SpreadController:ApplySpread(direction)
		Logger:Print(string.format("_FirePellets: pellet %d", i))
		self:FireBullet(origin, finalDir)
	end
	return true
end

--- Executes a full burst fire sequence with timing and ammo management.
function GunInstance._FireBurst(self: GunInstance, origin: Vector3, direction: Vector3)
	local burstCount  = self.Data.BurstCount  or 1
	local burstDelay  = self.Data.BurstDelay  or 0.04
	local pelletCount = self.Data.PelletCount or 1

	self.Signals.OnPreFire:Fire({
		Origin        = origin,
		Direction     = direction,
		Time          = os.time(),
		ShotIndex     = self.SpreadController:GetShotIndex(),
		LastShootTime = self.StateManager.LastShootTime,
	})

	task.spawn(function()
		for i = 1, burstCount do
			if not self.AmmoController:HasAmmo() then break end

			self:_FirePellets(origin, direction, pelletCount)
			self.Signals.OnFire:Fire(origin, direction)
			self.AmmoController:ConsumeAmmo(1)

			if i < burstCount then
				task.wait(burstDelay)
			end
		end
	end)

	return true
end

--- Internal fire entry point. Override for custom firing behaviour.
function GunInstance._FireInternal(self: GunInstance, origin: Vector3, direction: Vector3)
	return self:_FireBurst(origin, direction)
end

-- ─── Internal: bullet callbacks ──────────────────────────────────────────────

--- Called when a bullet hits a target.
function GunInstance._OnBulletHit(self: GunInstance, ctx: any, hitData: any)
	self.Signals.OnHit:Fire(ctx, hitData)
	Logger:Print("_OnBulletHit: " .. (hitData and hitData.Instance.Name or ""))
end

--- Called when the bullet penetrates something. Override for advanced behaviour.
function GunInstance._OnBulletPenetrate(self: GunInstance)
end

--- Called each frame as the bullet travels. Override for tracer/VFX.
function GunInstance._OnBulletTravel(self: GunInstance)
end

--- Called when the bullet terminates. Override for impact effects.
function GunInstance._OnBulletTerminating(self: GunInstance)
end

--- Override in subclasses to return the current muzzle world position.
function GunInstance.GetCurrentMuzzlePosition(self: GunInstance)
	Logger:Error("GetCurrentMuzzlePosition should be overridden")
	return nil
end

-- ─── Internal: initialization ────────────────────────────────────────────────

--- Builds the shared bullet callback table (allocated once, reused per shot).
function GunInstance._InitializeCallbacks(self: GunInstance)
	self._BulletCallbacks = {
		OnHit = function(ctx, hitData)
			self.Signals.OnHit:Fire(ctx, hitData)
			self:_OnBulletHit(ctx, hitData)
		end,
		OnTravel = function(ctx, currentPos)
			self:_OnBulletTravel(ctx, currentPos)
		end,
		OnTerminating = function(ctx)
			self:_OnBulletTerminating(ctx)
		end,
		OnPierce = function(context, hitData, pierceCount, remainingDistance)
			self:_OnBulletPenetrate(context, hitData, pierceCount, remainingDistance)
		end,
	}
end

--- Configures ballistics behavior and raycast parameters.
function GunInstance._InitializeBallistics(self: GunInstance)
	local behavior = BallisticsService.Common.newBehavior({
		RaycastParams           = RaycastParams.new(),
		Acceleration            = self.Data.BulletGravity or Vector3.new(0, -workspace.Gravity, 0),
		MaxDistance             = self.Data.Damage.Range.Max or 500,
		CanPierceFunction       = nil,
		HighFidelityBehavior    = 0,
		HighFidelitySegmentSize = 0,
		CosmeticBulletTemplate  = nil,
		CosmeticBulletProvider  = nil,
		CosmeticBulletContainer = nil,
		AutoIgnoreContainer     = true,
		SolverType              = self.Data.SolverType,
	})

	local RayParams = behavior.RaycastParams
	RayParams.FilterType  = Enum.RaycastFilterType.Exclude
	RayParams.IgnoreWater = true
	
	local character = self.StateManager:GetCharacter()
	if character then
		RayParams.FilterDescendantsInstances = { character }
	end

	behavior.RaycastParams   = RayParams
	self.Ballistics.Behavior = behavior
	return behavior
end

--- Wires cross-controller signal connections.
function GunInstance._InitializeControllers(self: GunInstance)
	self._Janitor:Add(self.StateManager.Signals.OnAimChanged:Connect(function(isAiming)
		self.SpreadController:OnAimChanged(isAiming)
	end), "Disconnect")

	self._Janitor:Add(self.AmmoController.Signals.OnReloadStarted:Connect(function()
		self.StateManager:SetReloading(true)
	end), "Disconnect")

	self._Janitor:Add(self.AmmoController.Signals.OnReloadCancelled:Connect(function()
		self.StateManager:SetReloading(false)
	end), "Disconnect")

	self._Janitor:Add(self.AmmoController.Signals.OnReloadComplete:Connect(function()
		self.StateManager:SetReloading(false)
	end), "Disconnect")
end

-- ─── Lifecycle ───────────────────────────────────────────────────────────────

--- Destroys the GunInstance and all sub-systems.
function GunInstance.Destroy(self: GunInstance)
	self.Signals.OnDestroyed:Fire()

	self.Signals.OnCanFireCheck:Destroy()
	self.Signals.OnPreFire:Destroy()
	self.Signals.OnFire:Destroy()
	self.Signals.OnHit:Destroy()
	self.Signals.OnDestroyed:Destroy()
	self.Signals.OnBulletFire:Destroy()

	self._Janitor:Destroy()

	self.Data             = nil
	self.StateManager     = nil
	self.AmmoController   = nil
	self.SpreadController = nil
	self.DamageCalculator = nil
end

-- ─── Constructor ─────────────────────────────────────────────────────────────

local module = {}

--- Creates a new GunInstance with the provided configuration.
function module.new(data: any, metadata: any?): GunInstance
	assert(data,            "GunInstance.new: data is required")
	assert(data.Ammo,       "GunInstance.new: missing Ammo configuration")
	assert(data.Spread,     "GunInstance.new: missing Spread configuration")
	assert(data.Damage,     "GunInstance.new: missing Damage configuration")
	assert(data.SolverType, "GunInstance.new: missing SolverType configuration")

	local self: GunInstance = setmetatable({}, { __index = GunInstance }) :: GunInstance

	self.Data      = data :: any
	self._Metadata = metadata or {} :: any
	self._Janitor  = Janitor.new() :: Janitor.Janitor

	-- Sub-systems
	self.StateManager     = StateManager.new(Player) :: StateManagerType
	self.AmmoController   = AmmoController.new(data.Ammo) :: AmmoControllerType
	self.SpreadController = SpreadController.new(data.Spread, self.StateManager) :: SpreadControllerType
	self.DamageCalculator = DamageCalculator.new(data.Damage) :: DamageCalculatorType

	self._Janitor:Add(self.StateManager,     "Destroy") 
	self._Janitor:Add(self.AmmoController,   "Destroy")
	self._Janitor:Add(self.SpreadController, "Destroy")
	self._Janitor:Add(self.DamageCalculator, "Destroy")

	self.Ballistics = {}

	-- Gun-owned signals
	self.Signals = {
		OnCanFireCheck = Signal.new(),
		OnPreFire      = Signal.new(),
		OnFire         = Signal.new(),
		OnHit          = Signal.new(),
		OnDestroyed    = Signal.new(),
		OnBulletFire   = Signal.new(),
		-- Forwarded controller signals
		OnReloadStarted   = self.AmmoController.Signals.OnReloadStarted,
		OnReloadComplete  = self.AmmoController.Signals.OnReloadComplete,
		OnReloadCancelled = self.AmmoController.Signals.OnReloadCancelled,
		OnAmmoChanged     = self.AmmoController.Signals.OnAmmoChanged,
		OnReserveChanged  = self.AmmoController.Signals.OnReserveChanged,
		OnEmpty           = self.AmmoController.Signals.OnEmpty,
		OnFireChanged     = self.StateManager.Signals.OnFireChanged,
		OnAimChanged      = self.StateManager.Signals.OnAimChanged,
		OnEquipChanged    = self.StateManager.Signals.OnEquipChanged,
		OnReloadChanged   = self.StateManager.Signals.OnReloadChanged,
	} :: GunInstanceSignals

	self:_InitializeBallistics()
	self:_InitializeControllers()
	self:_InitializeCallbacks()
	
	Logger:Debug(string.format("new: GunInstance created for %s", Player.Name))
	
	return self :: GunInstance
end

-- ─── Types ───────────────────────────────────────────────────────────────────

type StateManagerType     = StateManager.StateManager
type AmmoControllerType   = AmmoController.AmmoController
type SpreadControllerType = SpreadController.SpreadController
type DamageCalculatorType = DamageCalculator.DamageCalculator

export type GunInstanceSignals = {
		OnCanFireCheck    : CanFireSignal,
		OnPreFire         : PreFireSignal,
		OnFire            : FireSignal,
		OnHit             : HitSignal,
		OnDestroyed       : VoidSignal,
		OnBulletFire      : BulletFireSignal,
		OnReloadStarted   : VoidSignal,
		OnReloadComplete  : ReloadDoneSignal,
		OnReloadCancelled : VoidSignal,
		OnAmmoChanged     : AmmoSignal,
		OnReserveChanged  : AmmoSignal,
		OnEmpty           : VoidSignal,
		OnFireChanged     : BoolSignal,
		OnAimChanged      : BoolSignal,
		OnEquipChanged    : BoolSignal,
		OnReloadChanged   : BoolSignal,
}
export type GunInstance = {
	Data             : any,
	_Janitor         : any,
	_Metadata        : any,
	_BulletCallbacks : any,
	Ballistics       : { Behavior: any },

	StateManager     : StateManagerType,
	AmmoController   : AmmoControllerType,
	SpreadController : SpreadControllerType,
	DamageCalculator : DamageCalculatorType,
	Signals : GunInstanceSignals,
}

return table.freeze(module)