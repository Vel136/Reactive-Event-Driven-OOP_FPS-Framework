-- GrenadeInstance.lua
--[[
	Base grenade orchestrator following the same modular architecture as GunInstance.
	- Modular controller architecture (State, Inventory, Throw, Fuse, Blast)
	- Signal-based event system
	- Supports multiple grenades in-flight simultaneously
	- BlastController is swappable per grenade type
]]

local Identity = "GrenadeInstance"

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

local StateManager        = require(script.StateManager)
local InventoryController = require(script.InventoryController)
local ThrowController     = require(script.ThrowController)
local FuseController      = require(script.FuseController)
local BlastController     = require(script.BlastController)

local NetworkService    = require(Networking.NetworkService)
local BallisticsService = require(ReplicatedStorage.Client.Modules.FPSSystem.BallisticsSystem.BallisticsService)

-- ─── Module ──────────────────────────────────────────────────────────────────

local GrenadeInstance   = {}
GrenadeInstance.__index = GrenadeInstance
GrenadeInstance.__type  = Identity

-- ─── Private state ───────────────────────────────────────────────────────────

local Logger   = LogService.new(Identity, false)
local IS_DEBUG = game:GetService("RunService"):IsStudio()

-- ─── Signal Type Aliases ─────────────────────────────────────────────────────

type VoidSignal     = Signal.Signal<() -> ()>
type BoolSignal     = Signal.Signal<(value: boolean) -> ()>
type ThrowSignal    = Signal.Signal<(origin: Vector3, velocity: Vector3) -> ()>
type DetonateSignal = Signal.Signal<(position: Vector3) -> ()>
type StackSignal    = Signal.Signal<(current: number, previous: number) -> ()>

-- ─── Validation ──────────────────────────────────────────────────────────────

--- Returns whether the grenade can be thrown, and a reason string if not.
function GrenadeInstance.CanThrow(self: GrenadeInstance): (boolean, string?)
	if not self.StateManager:IsEquipped() then
		return false, "Grenade not equipped"
	end
	if self._IsThrowing then
		return false, "Already throwing"
	end
	if not self.InventoryController:HasStock() then
		return false, "No grenades in stock"
	end

	local rejectReason: string? = nil
	self.Signals.OnCanThrowCheck:Fire(function(reason: string)
		rejectReason = reason
	end)
	if rejectReason then
		return false, rejectReason
	end

	local character = self.StateManager:GetCharacter()
	if not character or not character:FindFirstChild("HumanoidRootPart") then
		return false, "Invalid character"
	end

	return true
end

-- ─── Cook ────────────────────────────────────────────────────────────────────

--- Begins cooking (holding) the grenade. Also starts charge accumulation.
--- Returns success and optional failure reason.
function GrenadeInstance.StartCook(self: GrenadeInstance): (boolean, string?)
	local canThrow, reason = self:CanThrow()
	if not canThrow then return false, reason end

	self.ThrowController:StartCharge()
	self.FuseController:StartCook()
	self.Signals.OnCookStarted:Fire()

	Logger:Print("StartCook: cooking started")
	return true
end

--- Cancels a cook without throwing. Safe to call even if not cooking.
function GrenadeInstance.CancelCook(self: GrenadeInstance)
	if not self.FuseController:IsCooking() then return end

	self.ThrowController:CancelCharge()
	self.FuseController:CancelCook()
	self.Signals.OnCookCancelled:Fire()

	Logger:Print("CancelCook: cook cancelled")
end

--- Returns how many seconds have been cooked so far (0 if not cooking).
function GrenadeInstance.GetCookTime(self: GrenadeInstance): number
	return self.FuseController:GetElapsedCookTime()
end

-- ─── Throw ───────────────────────────────────────────────────────────────────

--- Throws the grenade. Consumes stock and starts an independent fuse per throw.
--- Multiple grenades can be in-flight simultaneously.
--- @param origin    Vector3  — world position to throw from
--- @param direction Vector3  — unit direction of the throw
--- @param force     number?  — optional force override (skips charge)
function GrenadeInstance.Throw(self: GrenadeInstance, origin: Vector3, direction: Vector3, force: number?): (boolean, string?)
	local canThrow, reason = self:CanThrow()
	if not canThrow then return false, reason end

	if IS_DEBUG then
		assert(typeof(direction) == "Vector3", "Invalid direction")
		assert(typeof(origin)    == "Vector3", "Invalid origin")
	end

	direction        = direction.Unit
	self._IsThrowing = true

	local velocity = self.ThrowController:CalculateVelocity(direction, force)
	local speed    = velocity.Magnitude

	self.InventoryController:Consume(1)
	self.Signals.OnPreThrow:Fire({ Origin = origin, Direction = direction, Velocity = velocity })

	-- Fire returns the BulletContext immediately — use it directly as the key.
	-- No pending ids, no migration, no indirection.
	local ctx = BallisticsService:Fire({
		Origin    = origin,
		Direction = velocity.Unit,
		Speed     = speed,
		Behavior  = self.Ballistics.Behavior,
		Callbacks = self._BallisticsCallbacks,
	})

	-- Register the slot now that we have the ctx
	self._ActiveContexts[ctx] = { Position = origin }

	local fuseHandle = self.FuseController:StartFuse(function()
		local slot = self._ActiveContexts[ctx]
		if slot then
			self:_OnDetonate(slot.Position, ctx)
		else
			Logger:Warn(string.format("Throw: fuse expired but context was already cleared for ctx %d", ctx.Id))
		end
	end)

	self._ActiveContexts[ctx]._fuseHandle = fuseHandle

	self.Signals.OnThrow:Fire(origin, velocity)

	task.defer(function()
		self._IsThrowing = false
	end)

	Logger:Print(string.format(
		"Throw: grenade thrown from %s at speed %.1f (in-flight=%d)",
		tostring(origin), speed, self:_CountActiveContexts()
		))

	return true
end

-- ─── State API ───────────────────────────────────────────────────────────────

--- Equips the grenade.
function GrenadeInstance.Equip(self: GrenadeInstance)
	self.StateManager:SetEquipped(true)
end

--- Unequips the grenade. Cancels any in-progress cook.
--- Grenades already in flight are NOT cancelled — they detonate normally.
function GrenadeInstance.Unequip(self: GrenadeInstance)
	self:CancelCook()
	self.StateManager:SetEquipped(false)
end

--- Returns the current equipped state.
function GrenadeInstance.IsEquipped(self: GrenadeInstance): boolean
	return self.StateManager:IsEquipped()
end

--- Returns a full state snapshot.
function GrenadeInstance.GetState(self: GrenadeInstance)
	return {
		Stock      = self.InventoryController:GetStock(),
		IsCooking  = self.FuseController:IsCooking(),
		CookTime   = self.FuseController:GetElapsedCookTime(),
		FuseTime   = self.Data.FuseTime,
		IsThrowing = self._IsThrowing,
		Equipped   = self.StateManager:IsEquipped(),
		InFlight   = self:_CountActiveContexts(),
	}
end

-- ─── Metadata ────────────────────────────────────────────────────────────────

--- Returns the metadata table.
function GrenadeInstance.GetMetadata(self: GrenadeInstance)
	return self._Metadata
end

--- Sets metadata or a specific key within it.
--- Pass (value, key) to set a single field; pass (table) to replace entirely.
function GrenadeInstance.SetMetadata(self: GrenadeInstance, data: any, key: any?): boolean
	if key ~= nil then
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

-- ─── Internal: throw origin ──────────────────────────────────────────────────

--- Override in subclasses to return the correct throw origin (e.g. hand position).
function GrenadeInstance.GetThrowOrigin(self: GrenadeInstance): Vector3?
	Logger:Error("GetThrowOrigin should be overridden by the subclass")
	local hrp = self.StateManager:GetHRP()
	return hrp and hrp.Position or nil
end

-- ─── Internal: detonation ────────────────────────────────────────────────────

--- Called when a specific grenade's fuse expires.
function GrenadeInstance._OnDetonate(self: GrenadeInstance, position: Vector3, ctx: any)
	self._ActiveContexts[ctx] = nil

	Logger:Print(string.format(
		"_OnDetonate: detonating at %s (in-flight=%d)",
		tostring(position), self:_CountActiveContexts()
		))

	self.BlastController:Detonate(position)
	self.Signals.OnDetonate:Fire(position)
end

-- ─── Internal: ballistics overrides ──────────────────────────────────────────

--- Called each frame the projectile is airborne. Override for per-frame effects.
function GrenadeInstance._OnGrenadeTravel(self: GrenadeInstance, ctx, currentPos: Vector3)
end

--- Called when the projectile hits something. Override for impact effects.
function GrenadeInstance._OnGrenadeHit(self: GrenadeInstance, ctx, hitData)
end

--- Called when the projectile bounces. Override for bounce sounds/decals.
function GrenadeInstance._OnGrenadeBounce(self: GrenadeInstance, ctx, hitData, bounceCount: number, remainingDistance: number)
end

--- Called when the ballistics solver removes the projectile from simulation.
function GrenadeInstance._OnGrenadeTerminating(self: GrenadeInstance, ctx)
end

-- ─── Internal: helpers ───────────────────────────────────────────────────────

function GrenadeInstance._CountActiveContexts(self: GrenadeInstance): number
	local n = 0
	for _ in pairs(self._ActiveContexts) do
		n += 1
	end
	return n
end

-- ─── Internal: initialization ────────────────────────────────────────────────

function GrenadeInstance._InitializeBallistics(self: GrenadeInstance)
	assert(self.Data.Projectile, "GrenadeInstance: Data.Projectile is required")

	local behavior = BallisticsService.Common.newBehavior({
		RaycastParams           = RaycastParams.new(),
		Acceleration            = self.Data.BulletGravity or Vector3.new(0, -workspace.Gravity, 0),
		MaxDistance             = self.Data.Projectile.MaxDistance      or 500,
		MaxBounces              = self.Data.Projectile.MaxBounces       or 10,
		Gravity                 = self.Data.Projectile.Gravity,
		MinSpeed                = self.Data.Projectile.MinSpeed         or 1.0,
		Restitution             = self.Data.Projectile.Restitution,
		CanBounceFunction       = nil,
		HighFidelityBehavior    = 3,
		HighFidelitySegmentSize = 0.5,
		CosmeticBulletTemplate  = nil,
		CosmeticBulletProvider  = nil,
		CosmeticBulletContainer = nil,
		SolverType              = "Hybrid",
	})

	local rayParams          = behavior.RaycastParams
	rayParams.FilterType     = Enum.RaycastFilterType.Exclude
	rayParams.IgnoreWater    = true

	local character = self.StateManager:GetCharacter()
	if character then
		rayParams.FilterDescendantsInstances = { character }
	end

	behavior.RaycastParams   = rayParams
	self.Ballistics.Behavior = behavior
	return behavior
end
function GrenadeInstance._InitializeCallbacks(self: GrenadeInstance)
	self._BallisticsCallbacks = {
		OnTravel = function(ctx, currentPos: Vector3)
			local slot = self._ActiveContexts[ctx]
			if slot then
				slot.Position = currentPos
			end
			self:_OnGrenadeTravel(ctx, currentPos)
		end,

		OnHit = function(ctx, hitData)
			self:_OnGrenadeHit(ctx, hitData)
		end,

		OnBounce = function(ctx, hitData, bounceCount: number, remainingDistance: number)
			self:_OnGrenadeBounce(ctx, hitData, bounceCount, remainingDistance)
		end,

		OnTerminating = function(ctx)
			self:_OnGrenadeTerminating(ctx)
		end,
	}
end
function GrenadeInstance._InitializeControllers(self: GrenadeInstance)
	self._Janitor:Add(self.StateManager.Signals.OnEquipChanged:Connect(function(isEquipped: boolean)
		if not isEquipped then
			self:CancelCook()
		end
	end), "Disconnect")
end

-- ─── Lifecycle ───────────────────────────────────────────────────────────────

--- Destroys the GrenadeInstance and all sub-systems.
--- Cancels all in-flight fuse handles so nothing fires after destruction.
function GrenadeInstance.Destroy(self: GrenadeInstance)
	self:CancelCook()

	for ctx, slot in pairs(self._ActiveContexts) do
		if slot._fuseHandle then
			self.FuseController:CancelFuse(slot._fuseHandle)
		end
		self._ActiveContexts[ctx] = nil
	end

	self.Signals.OnDestroyed:Fire()

	for _, signal in pairs(self.Signals) do
		if typeof(signal) == "table" and signal.Destroy then
			signal:Destroy()
		end
	end

	self._Janitor:Destroy()

	self.Data                = nil
	self.StateManager        = nil
	self.InventoryController = nil
	self.ThrowController     = nil
	self.FuseController      = nil
	self.BlastController     = nil

	Logger:Print("Destroy: GrenadeInstance destroyed")
end

-- ─── Constructor ─────────────────────────────────────────────────────────────

local module = {}

--- Creates a new GrenadeInstance with the provided configuration.
--- @param data            GrenadeData — weapon configuration
--- @param blastController any         — injectable BlastController (swappable per grenade type)
--- @param metadata        any?        — optional metadata table
function module.new(data: GrenadeData, blastController: any, metadata: any?): GrenadeInstance
	assert(data,            "GrenadeInstance.new: data is required")
	assert(data.Inventory,  "GrenadeInstance.new: missing Inventory configuration")
	assert(data.Throw,      "GrenadeInstance.new: missing Throw configuration")
	assert(data.FuseTime,   "GrenadeInstance.new: missing FuseTime")
	assert(blastController, "GrenadeInstance.new: blastController is required")

	local self: GrenadeInstance = setmetatable({}, { __index = GrenadeInstance }) :: GrenadeInstance

	self.Data            = data
	self._Metadata       = metadata or {}
	self._Janitor        = Janitor.new()
	self._IsThrowing     = false
	self._ActiveContexts = {} -- [BulletContext] -> { Position: Vector3, _fuseHandle: FuseHandle }

	self.Ballistics = { Behavior = nil }

	self.StateManager        = StateManager.new(Player)
	self.InventoryController = InventoryController.new(data.Inventory)
	self.ThrowController     = ThrowController.new(data.Throw)
	self.FuseController      = FuseController.new(data.FuseTime)
	self.BlastController     = blastController

	self._Janitor:Add(self.StateManager,       "Destroy")
	self._Janitor:Add(self.InventoryController, "Destroy")
	self._Janitor:Add(self.ThrowController,    "Destroy")
	self._Janitor:Add(self.FuseController,     "Destroy")

	self.Signals = {
		OnCanThrowCheck = Signal.new(),
		OnPreThrow      = Signal.new(),
		OnThrow         = Signal.new(),
		OnCookStarted   = Signal.new(),
		OnCookCancelled = Signal.new(),
		OnDetonate      = Signal.new(),
		OnDestroyed     = Signal.new(),
		OnStockChanged  = self.InventoryController.Signals.OnStockChanged,
		OnStockEmpty    = self.InventoryController.Signals.OnStockEmpty,
		OnFuseStarted   = self.FuseController.Signals.OnFuseStarted,
		OnFuseExpired   = self.FuseController.Signals.OnFuseExpired,
		OnEquipChanged  = self.StateManager.Signals.OnEquipChanged,
	} :: GrenadeInstanceSignals

	self:_InitializeControllers()
	self:_InitializeBallistics()
	self:_InitializeCallbacks()
	Logger:Debug(string.format("new: GrenadeInstance created for %s", Player.Name))
	return self :: GrenadeInstance
end

-- ─── Types ───────────────────────────────────────────────────────────────────

export type GrenadeData = {
	FuseTime   : number,
	Inventory  : any,
	Throw      : any,
	Blast      : any,
	Projectile : any,
}

export type GrenadeInstanceSignals = {
	OnCanThrowCheck : Signal.Signal<(reject: (reason: string) -> ()) -> ()>,
	OnPreThrow      : Signal.Signal<(throwData: any) -> ()>,
	OnThrow         : Signal.Signal<(origin: Vector3, velocity: Vector3) -> ()>,
	OnCookStarted   : Signal.Signal<() -> ()>,
	OnCookCancelled : Signal.Signal<() -> ()>,
	OnDetonate      : Signal.Signal<(position: Vector3) -> ()>,
	OnDestroyed     : Signal.Signal<() -> ()>,
	OnStockChanged  : Signal.Signal<(current: number, previous: number) -> ()>,
	OnStockEmpty    : Signal.Signal<() -> ()>,
	OnFuseStarted   : Signal.Signal<() -> ()>,
	OnFuseExpired   : Signal.Signal<() -> ()>,
	OnEquipChanged  : Signal.Signal<(isEquipped: boolean) -> ()>,
}

export type GrenadeInstance = {
	Data             : GrenadeData,
	_Janitor         : any,
	_Metadata        : any,
	_IsThrowing      : boolean,
	_ActiveContexts  : { [any]: { Position: Vector3, _fuseHandle: any } },

	Ballistics : {
		Behavior : BallisticsService.BallisticsBehavior,
	},

	StateManager        : any,
	InventoryController : any,
	ThrowController     : any,
	FuseController      : any,
	BlastController     : any,

	Signals : GrenadeInstanceSignals,
}

return table.freeze(module)