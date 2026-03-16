-- ServerGunInstance.lua
--[[
	Server-authoritative weapon instance
	- Delegates validation to WeaponValidationService
	- Mirrors GunInstance architecture on the server
	- Handles damage application and kill detection
]]

local Identity = "ServerGunInstance"

-- ─── Services ────────────────────────────────────────────────────────────────

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage     = game:GetService("ServerStorage")

-- ─── References ──────────────────────────────────────────────────────────────

local Utilities  = ReplicatedStorage.Shared.Modules.Utilities
local Networking = ReplicatedStorage.Shared.Modules.Networking

-- ─── Modules ─────────────────────────────────────────────────────────────────

local LogService = require(Utilities.Logger)
local Janitor    = require(Utilities.Janitor)
local Signal     = require(Utilities.Signal)

local StateManager     = require(script.StateManager)
local AmmoController   = require(script.AmmoController)
local SpreadController  = require(script.SpreadController)
local DamageCalculator  = require(script.DamageCalculator)

local ServerBallistics = require(ServerStorage.Server.Modules.BallisticsSystem.ServerBallisticsService)
local SyncTypes        = require(Networking.SyncTypes)

-- ─── Constants ───────────────────────────────────────────────────────────────

local MAX_LATENCY_COMPENSATION = 200 -- ms

-- ─── Module ──────────────────────────────────────────────────────────────────

local ServerGunInstance   = {}
ServerGunInstance.__index = ServerGunInstance
ServerGunInstance.__type  = Identity

-- ─── Private state ───────────────────────────────────────────────────────────

local Logger = LogService.new(Identity, false)

-- ─── Validation ──────────────────────────────────────────────────────────────

--- Returns whether the weapon can fire, and a reason string if not.
function ServerGunInstance.CanFire(self: ServerGunInstance): (boolean, string?)
	if self.StateManager:IsReloading() then
		return false, "Weapon is reloading"
	end

	if not self.AmmoController:HasAmmo() then
		return false, "Out of ammo"
	end

	if not self.StateManager:IsEquipped() then
		return false, "Weapon not equipped"
	end

	local character = self.StateManager:GetCharacter()
	if not character then
		return false, "No character"
	end

	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return false, "Player is dead"
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

	return true
end

-- ─── Firing ──────────────────────────────────────────────────────────────────

--- Fires the weapon using validated FireData from the client.
function ServerGunInstance.Fire(self: ServerGunInstance, fireData: any): (boolean, string?)
	local canFire, reason = self:CanFire()
	if not canFire then return false, reason end

	local origin       = fireData.Origin
	local baseDir      = fireData.Direction
	local shotIndex    = fireData.ShotIndex or self.SpreadController:GetShotIndex()

	self.Signals.OnPreFire:Fire(fireData)

	if fireData.LastShootTime then
		self.StateManager.LastShootTime = fireData.LastShootTime
	end

	self.SpreadController._ShotIndex = shotIndex

	self:_FireBurst(origin, baseDir)

	self.StateManager.LastShootTime = os.clock()

	Logger:Print(string.format("Fire: %s | ShotIndex: %d",
		self.Player.Name, self.SpreadController:GetShotIndex()))

	return true
end

--- Fires all pellets for a single shot, each with independent spread.
function ServerGunInstance._FirePellets(self: GunInstance, origin: Vector3, direction: Vector3, count: number)
	for i = 1, count do
		local finalDir = self.SpreadController:ApplySpread(direction)
		Logger:Print(string.format("_FirePellets: pellet %d", i))
		self:FireBullet(origin, finalDir)
	end
	return true
end

function ServerGunInstance._FireBurst(self: ServerGunInstance, origin: Vector3, direction: Vector3)
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

--- Fires a single bullet, with optional latency compensation.
function ServerGunInstance.FireBullet(self: ServerGunInstance, origin: Vector3, direction: Vector3, fireTime: number?)
	local fireParams = {
		Origin    = origin,
		Direction = direction,
		Speed     = self.Data.BulletSpeed or 1000,
		Behavior  = self.BallisticsSystem.Behavior,
		Callbacks = self._BulletCallbacks,
	}

	local context
	if fireTime then
		fireParams.FireTime = fireTime
		context = ServerBallistics:FireWithCompensation(fireParams)
	else
		context = ServerBallistics:Fire(fireParams)
	end

	self.Signals.OnFire:Fire(origin, direction, fireTime)
	self.Signals.OnBulletFire:Fire(context)

	return context
end

-- ─── Reload ──────────────────────────────────────────────────────────────────

--- Starts a reload. Returns the AmmoController Promise.
function ServerGunInstance.Reload(self: ServerGunInstance): any
	return self.AmmoController:Reload()
end

-- ─── State API ───────────────────────────────────────────────────────────────

--- Sets the aiming state.
function ServerGunInstance.SetAiming(self: ServerGunInstance, aiming: boolean)
	self.StateManager:SetAiming(aiming)
end

--- Returns the current aiming state.
function ServerGunInstance.IsAiming(self: ServerGunInstance): boolean
	return self.StateManager:IsAiming()
end

--- Equips the weapon.
function ServerGunInstance.Equip(self: ServerGunInstance)
	self.StateManager:SetEquipped(true)
end

--- Unequips the weapon and clears active states.
function ServerGunInstance.Unequip(self: ServerGunInstance)
	self.StateManager:SetEquipped(false)
	self.StateManager:SetAiming(false)
	self.StateManager:SetShooting(false)
end

--- Returns the full weapon state snapshot.
function ServerGunInstance.GetState(self: ServerGunInstance)
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

-- ─── Internal: bullet callbacks ──────────────────────────────────────────────

--- Called when a bullet hits a target. Applies damage and fires OnKill if lethal.
function ServerGunInstance._OnBulletHit(self: ServerGunInstance, ctx: any, hitData: any)
	self.Signals.OnHit:Fire(ctx, hitData)

	if not hitData or not hitData.Instance then return end

	local humanoid = hitData.Instance.Parent:FindFirstChild("Humanoid")
	if not humanoid then return end

	local damage = self.DamageCalculator:CalculateTotalDamage(ctx, hitData)
	humanoid:TakeDamage(damage)

	Logger:Print(string.format("_OnBulletHit: %.1f damage to %s", damage, humanoid.Parent.Name))

	if humanoid.Health <= 0 then
		self.Signals.OnKill:Fire(humanoid.Parent, damage)
	end
end
--- Called when the bullet penetrates something. Override for advanced behaviour.
function ServerGunInstance._OnBulletPenetrate(self: ServerGunInstance)
end

--- Called each frame as the bullet travels. Override for server-side effects.
function ServerGunInstance._OnBulletTravel(self: ServerGunInstance, ctx: any)
end

--- Called when the bullet terminates. Override for server-side effects.
function ServerGunInstance._OnBulletTerminating(self: ServerGunInstance, ctx: any)
end

-- ─── Internal: initialization ────────────────────────────────────────────────
--- Builds the shared bullet callback table (allocated once, reused per shot).
function ServerGunInstance._InitializeCallbacks(self: ServerGunInstance)
	self._BulletCallbacks = {
		OnHit = function(ctx, hitData)
			self:_OnBulletHit(ctx, hitData)
		end,
		OnTravel = function(ctx, currentPos)
			self:_OnBulletTravel(ctx,currentPos)
		end,
		OnTerminating = function(ctx)
			self:_OnBulletTerminating(ctx)
		end,
		OnPierce = function(context, hitData, pierceCount, remainingDistance)
			self:_OnBulletPenetrate(context, hitData, pierceCount, remainingDistance)
		end,
	}
end
--- Configures BallisticsSystem behavior and raycast parameters.
function ServerGunInstance._InitializeBallistics(self: ServerGunInstance)
	local behavior = ServerBallistics.Common.newBehavior({
		RaycastParams           = RaycastParams.new(),
		Acceleration            = self.Data.BulletGravity or Vector3.new(0, -workspace.Gravity, 0),
		MaxDistance             = self.Data.Damage.Range.Max or 500,
		CanPierceFunction       = nil,
		HighFidelityBehavior    = 1,
		HighFidelitySegmentSize = 3,
		CosmeticBulletTemplate  = nil,
		CosmeticBulletProvider  = nil,
		CosmeticBulletContainer = nil,
		AutoIgnoreContainer     = true,
		SolverType              = self.Data.SolverType,
	})

	local RayParams = behavior.RaycastParams
	RayParams.FilterType   = Enum.RaycastFilterType.Exclude
	RayParams.IgnoreWater  = true

	local character = self.StateManager:GetCharacter()
	if character then
		RayParams.FilterDescendantsInstances = { character }
	end

	behavior.RaycastParams   = RayParams
	self.Ballistics.Behavior = behavior
	return behavior
end

--- Wires cross-controller signal connections.
function ServerGunInstance._InitializeControllers(self: ServerGunInstance)
	self._Janitor:Add(self.StateManager.Signals.OnAimChanged:Connect(function(isAiming)
		self.SpreadController:OnAimChanged(isAiming)
	end), "Disconnect")
end

--- Initializes network synchronization (extend as needed).
function ServerGunInstance._InitializeNetworking(self: ServerGunInstance)
end

-- ─── Lifecycle ───────────────────────────────────────────────────────────────

--- Destroys the ServerGunInstance and all sub-systems.
function ServerGunInstance.Destroy(self: ServerGunInstance)
	self.Signals.OnDestroyed:Fire()

	self.Signals.OnCanFireCheck:Destroy()
	self.Signals.OnPreFire:Destroy()
	self.Signals.OnFire:Destroy()
	self.Signals.OnHit:Destroy()
	self.Signals.OnDestroyed:Destroy()
	self.Signals.OnKill:Destroy()
	self.Signals.OnBulletFire:Destroy()

	self._Janitor:Destroy()

	self.Data           = nil
	self.Player         = nil
	self.StateManager   = nil
	self.AmmoController  = nil
	self.SpreadController = nil
	self.DamageCalculator = nil

	setmetatable(self, nil)
end

-- ─── Constructor ─────────────────────────────────────────────────────────────

local module = {}

--- Creates a new ServerGunInstance for the given player.
function module.new(gunData: any, player: Player): ServerGunInstance
	assert(gunData, "ServerGunInstance.new: gunData is required")
	assert(player,  "ServerGunInstance.new: player is required")

	local self: ServerGunInstance = setmetatable({}, { __index = ServerGunInstance })

	self.Data    = gunData
	self.Player  = player
	self._Janitor = Janitor.new()

	-- Sub-systems
	self.StateManager     = StateManager.new(player)
	self.AmmoController   = AmmoController.new(gunData.Ammo, self.StateManager)
	self.SpreadController  = SpreadController.new(gunData.Spread, self.StateManager)
	self.DamageCalculator  = DamageCalculator.new(gunData.Damage)

	self._Janitor:Add(self.StateManager,    "Destroy")
	self._Janitor:Add(self.AmmoController,  "Destroy")
	self._Janitor:Add(self.SpreadController, "Destroy")
	self._Janitor:Add(self.DamageCalculator, "Destroy")

	self.BallisticsSystem = {}

	-- Gun-owned signals
	self.Signals = {
		OnCanFireCheck = Signal.new(),
		OnPreFire      = Signal.new(),
		OnFire         = Signal.new(),
		OnHit          = Signal.new(),
		OnDestroyed    = Signal.new(),
		OnKill         = Signal.new(),
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
	}

	self:_InitializeBallistics()
	self:_InitializeNetworking()
	self:_InitializeControllers()
	self:_InitializeCallbacks()
	Logger:Debug(string.format("new: ServerGunInstance created for %s", player.Name))

	return self
end

-- ─── Types ───────────────────────────────────────────────────────────────────

type StateManager     = StateManager.StateManager
type AmmoController   = AmmoController.AmmoController
type SpreadController  = SpreadController.SpreadController
type DamageCalculator  = DamageCalculator.DamageCalculator

export type ServerGunInstance = typeof(setmetatable({}, { __index = ServerGunInstance })) & {
	Data              : any,
	Player            : Player,
	StateManager      : StateManager,
	AmmoController    : AmmoController,
	SpreadController   : SpreadController,
	DamageCalculator   : DamageCalculator,
	_BulletCallbacks : any,
	_Janitor           : any,
	BallisticsSystem: {
		Behavior: any,
	},
	Signals: {
		OnCanFireCheck    : Signal.Signal<(reject: (reason: string) -> ()) -> ()>,
		OnPreFire         : Signal.Signal<(fireData: any) -> ()>,
		OnFire            : Signal.Signal<(origin: Vector3, direction: Vector3, fireTime: number?) -> ()>,
		OnHit             : Signal.Signal<(ctx: any, hitData: any) -> ()>,
		OnDestroyed       : Signal.Signal<() -> ()>,
		OnKill            : Signal.Signal<(character: Model, damage: number) -> ()>,
		OnBulletFire      : Signal.Signal<(ctx: any) -> ()>,
		OnReloadStarted   : Signal.Signal<() -> ()>,
		OnReloadComplete  : Signal.Signal<(ammo: number, reserve: number) -> ()>,
		OnReloadCancelled : Signal.Signal<() -> ()>,
		OnAmmoChanged     : Signal.Signal<(current: number, previous: number) -> ()>,
		OnReserveChanged  : Signal.Signal<(current: number, previous: number) -> ()>,
		OnEmpty           : Signal.Signal<() -> ()>,
		OnFireChanged     : Signal.Signal<(isShooting: boolean) -> ()>,
		OnAimChanged      : Signal.Signal<(isAiming: boolean) -> ()>,
		OnEquipChanged    : Signal.Signal<(isEquipped: boolean) -> ()>,
		OnReloadChanged   : Signal.Signal<(isReloading: boolean) -> ()>,
	},
}

return table.freeze(module)