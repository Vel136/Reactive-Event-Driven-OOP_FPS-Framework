-- init.lua (WeaponInstance Main Module)
--[[
	Main Gun orchestrator - NOW FULLY SOLVER-AGNOSTIC
	Uses BulletContext instead of FastCast objects
]]

local Identity = "[WeaponInstance]"

-- Services
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local RunService = game:GetService('RunService')


-- References
local Utilities = ReplicatedStorage.SharedModules.Utilities
local Cores = ReplicatedStorage.SharedModules.Cores
local Controllers = ReplicatedStorage.ClientModules.Controllers

-- Utilities-modules
local FastCast = require(Utilities.FastCastRedux)
local t = require(Utilities:WaitForChild("TypeCheck"))
local Logger = require(Utilities:WaitForChild("LogService"))
local Janitor = require(Utilities:WaitForChild("Janitor"))
local Signal = require(Utilities:WaitForChild("Signal"))

-- Sub-modules
local StateManager = require(script.StateManager)
local AmmoController = require(script.AmmoController)
local SpreadController = require(script.SpreadController)
local DamageCalculator = require(script.DamageCalculator)
local WeaponType = require(script.WeaponType)

local Player = game.Players.LocalPlayer

-- Additional Modules
local BallisticsService = require(Cores.BallisticsService)
local WeaponAnimator = require(Controllers.WeaponAnimator)

--[=[
	@class Gun
	
	Main gun orchestrator - fully solver-agnostic.
	Uses BulletContext instead of FastCast objects for ballistics simulation.
	
	This class manages all weapon functionality including firing, reloading, aiming,
	and state management through specialized controller sub-systems.
]=]
local Gun = {}
Gun.__index = Gun

--[=[
	@prop Signals table
	@within Gun
	@readonly
	
	Global signals shared across all weapon instances.
	Contains `OnAnyHit` and `OnAnyFire` events.
]=]
Gun.Signals = {
	OnAnyHit = Signal.new(),
	OnAnyFire = Signal.new(),
}
--[=[
	@interface GunSignals
	@external Signal https://sleitnick.github.io/RbxUtil/api/Signal/
	@within Gun
	.OnShoot Signal<BulletContext, Vector3, Vector3> -- Fires when weapon shoots
	.OnHit Signal<Instance, number, BulletContext> -- Fires when bullet hits
	.OnReload Signal<> -- Fires when reload begins
	.OnReloadComplete Signal<> -- Fires when reload completes
	.OnAmmoChanged Signal<number> -- Fires when ammo changes
	.OnReserveChanged Signal<number> -- Fires when reserve ammo changes
	.OnEmpty Signal<> -- Fires when out of ammo
	.OnShootChanged Signal<boolean> -- Fires when shooting state changes
	.OnAimChanged Signal<boolean> -- Fires when aiming state changes
	.OnEquipChanged Signal<boolean> -- Fires when equipped state changes
	.OnEquipCompleted Signal<> -- Fires when equip completes
	.OnDestroyed Signal<> -- Fires when weapon is destroyed

	
]=]

--[=[
	@prop Data table
	@within Gun
	@readonly
	
	Core weapon configuration data containing damage, fire rate, spread, and ammo settings.
]=]

--[=[
	@prop StateManager StateManager
	@within Gun
	@readonly
	
	Manages weapon states including aiming, reloading, shooting, and equipped status.
]=]

--[=[
	@prop AmmoController AmmoController
	@within Gun
	@readonly
	
	Handles ammunition tracking, consumption, and reload logic.
]=]

--[=[
	@prop SpreadController SpreadController
	@within Gun
	@readonly
	
	Manages weapon spread patterns and accuracy calculations.
]=]

--[=[
	@prop DamageCalculator DamageCalculator
	@within Gun
	@readonly
	
	Calculates damage based on distance, modifiers, and hit location.
]=]

--[=[
	@prop Ballistics table
	@within Gun
	
	Ballistics configuration containing behavior settings and raycast parameters.
]=]

--[=[
	@prop AnimationController WeaponAnimator?
	@within Gun
	
	Optional weapon animation controller for visual effects.
]=]

--[=[
	Creates a new Gun instance.
	
	Initializes all sub-systems including state management, ammo control,
	spread calculation, and damage computation.
	
	@param GunData table -- Weapon configuration data
	@param UseAnimator boolean? -- Whether to use animator (optional, defaults to false)
	@return Gun? -- Gun instance or nil if invalid data provided
]=]
function Gun.new(GunData: WeaponType.GunData, UseAnimator: boolean?): WeaponType.Gun
	if not IsValidData(GunData) then 
		Logger.Warn(Identity .. " Invalid GunData provided")
		return nil 
	end

	local self = setmetatable({}, Gun)

	-- Core Data
	self.Data = GunData

	-- Janitor for cleanup
	self._Janitor = Janitor.new()

	-- Initialize sub-systems
	self.StateManager = StateManager.new(Player)
	self.AmmoController = AmmoController.new(GunData.Ammo, self.StateManager)
	self.SpreadController = SpreadController.new(GunData.Spread, self.StateManager)
	self.DamageCalculator = DamageCalculator.new(GunData.Damage)
	self.StateManager:SetupObservers()

	-- Add controllers to janitor
	self._Janitor:Add(self.StateManager, "Destroy")
	self._Janitor:Add(self.AmmoController, "Destroy")
	self._Janitor:Add(self.SpreadController, "Destroy")
	self._Janitor:Add(self.DamageCalculator, "Destroy")

	-- Ballistics configuration (solver-agnostic)
	self.Ballistics = {}

	-- Instance Signals
	self.Signals = {
		-- Gun-specific signals
		OnShoot = Signal.new(),
		OnHit = Signal.new(),
		OnDestroyed = Signal.new(),

		-- Direct references to controller signals
		OnReload = self.AmmoController.Signals.OnReload,
		OnReloadComplete = self.AmmoController.Signals.OnReloadComplete,
		OnAmmoChanged = self.AmmoController.Signals.OnAmmoChanged,
		OnReserveChanged = self.AmmoController.Signals.OnReserveChanged,
		OnEmpty = self.AmmoController.Signals.OnEmpty,

		OnShootChanged = self.StateManager.Signals.OnShootChanged,
		OnAimChanged = self.StateManager.Signals.OnAimChanged,
		OnEquipChanged = self.StateManager.Signals.OnEquipChanged,

		OnEquipCompleted = Signal.new()
	}

	-- Setup ballistics
	self:_SetupBallistics()

	-- Setup cross-controller communication
	self:_SetupControllerLinks()

	-- Animator setup
	if UseAnimator ~= false then
		self.AnimationController = WeaponAnimator.new(self, self.Data.Model)
	end

	return self
end

--[=[
	Sets up ballistics configuration including raycast parameters and physics behavior.
	
	@private
]=]
function Gun:_SetupBallistics()
	local behavior = FastCast.newBehavior()
	behavior.MaxDistance = self.Data.Damage.Range.Max or 500
	behavior.Acceleration = self.Data.BulletGravity or Vector3.new(0, -workspace.Gravity, 0)

	-- Raycast params
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true

	-- Set initial character filter
	local character = self.StateManager:GetCharacter()
	if character then
		params.FilterDescendantsInstances = {character}
	end

	behavior.RaycastParams = params
	self.Ballistics.Behavior = behavior
end

--[=[
	Sets up communication links between different controller sub-systems.
	
	@private
]=]
function Gun:_SetupControllerLinks()
	-- SpreadController needs to know when aiming changes
	self._Janitor:Add(self.StateManager.Signals.OnAimChanged:Connect(function(isAiming)
		self.SpreadController:OnAimChanged(isAiming)
	end))
end

--[=[
	Checks if the weapon can fire based on current state.
	
	Validates reloading status, ammunition, equipment state, fire rate cooldown,
	and character validity.
	
	@return boolean -- Whether the weapon can fire
	@return string? -- Reason if cannot fire
]=]
function Gun:CanFire(): (boolean, string?)
	if self.StateManager:IsReloading() then
		return false, "Weapon is reloading"
	end

	if not self.AmmoController:HasAmmo() then
		return false, "Out of ammo"
	end

	if not self.StateManager:IsEquipped() then
		return false, "Weapon not equipped"
	end

	-- Fire rate check
	local now = os.clock()
	local fireRate = self.Data.FireRate or 600 -- RPM
	local timeBetweenShots = 60 / fireRate
	local lastShootTime = self.StateManager.LastShootTime

	if now - lastShootTime < timeBetweenShots then
		return false, "Firerate cooldown"
	end

	-- Character check
	local character = self.StateManager:GetCharacter()
	if not character or not character:FindFirstChild("HumanoidRootPart") then
		return false, "Invalid character"
	end

	return true
end

--[=[
	Fires the weapon in the specified direction.
	
	Performs validation checks, applies spread, consumes ammunition,
	and updates weapon states.
	
	@param origin Vector3? -- Starting position (optional, uses HRP if nil)
	@param direction Vector3 -- Direction vector to fire
	@param useHRP_Position boolean? -- Force use of HumanoidRootPart position
	@return boolean -- Success status
	@return any -- Result context or error reason
]=]
function Gun:Fire(origin: Vector3?, direction: Vector3, useHRP_Position: boolean?)
	local canFire, reason = self:CanFire()
	if not canFire then
		return false, reason
	end

	if not t.Vector3(direction) then
		return false, "Invalid direction"
	end

	-- Determine fire origin
	local fireOrigin = origin
	if useHRP_Position or not fireOrigin then
		local HRP = self.StateManager:GetHRP()
		if not HRP then
			return false, "Missing HumanoidRootPart"
		end
		fireOrigin = HRP.Position
	end

	-- Fire internal logic
	local result = self:_FireInternal(fireOrigin, direction)

	-- Update states
	self.StateManager:SetShooting(true)
	self.AmmoController:ConsumeAmmo(self.Data.AmmoDeduction or 1)

	-- Reset shooting state
	task.defer(function()
		self.StateManager:SetShooting(false)
	end)

	return true, result
end

--[=[
	Internal fire logic with spread application.
	Override this for specific/custom firing behaviors.
	
	@param origin Vector3 -- Fire origin position
	@param direction Vector3 -- Fire direction vector
	@return BulletContext -- Bullet simulation context
]=]
function Gun:_FireInternal(origin: Vector3, direction: Vector3)
	local finalDir = self.SpreadController:ApplySpread(direction)
	return self:FireBullet(origin, finalDir)
end

--[=[
	Fires a single bullet using the BallisticsService.
	
	Creates a bullet context and fires weapon signals.
	
	@param origin Vector3 -- Bullet spawn position
	@param direction Vector3 -- Bullet travel direction
	@return BulletContext -- Bullet simulation context
]=]
function Gun:FireBullet(origin: Vector3, direction: Vector3)
	local context = BallisticsService:Fire(
		self,
		origin,
		direction,
		self.Data.BulletSpeed or 1000,
		self.Ballistics.Behavior
	)

	-- Fire signals with context (NOT cast)
	self.Signals.OnShoot:Fire(context, origin, direction)
	Gun.Signals.OnAnyFire:Fire(context, origin, direction)

	return context
end

--[=[
	Initiates a weapon reload.
	
	@external Promise https://eryn.io/roblox-lua-promise/api/Promise
	@return Promise -- Promise that resolves when reload completes
]=]
function Gun:Reload(): any
	return self.AmmoController:Reload()
end

--[=[
	Sets the aiming state of the weapon.
	
	@param aiming boolean -- Whether the weapon should be aiming
]=]
function Gun:SetAiming(aiming: boolean)
	self.StateManager:SetAiming(aiming)
end

--[=[
	Gets the current aiming state.
	
	@return boolean -- Whether the weapon is currently aiming
]=]
function Gun:IsAiming(): boolean
	return self.StateManager:IsAiming()
end

--[=[
	Equips the weapon for use.
]=]
function Gun:Equip()
	self.StateManager:SetEquipped(true)
end

--[=[
	Unequips the weapon and resets all active states.
]=]
function Gun:Unequip()
	self.StateManager:SetEquipped(false)
	self.StateManager:SetAiming(false)
	self.StateManager:SetShooting(false)
end

--[=[
	Manually sets the weapon spread value.
	
	@param amount number -- Spread amount to set
	@return number -- The new spread value
]=]
function Gun:SetSpread(amount: number): number
	return self.SpreadController:SetSpread(amount)
end

--[=[
	Internal callback when a bullet hits a target.
	
	Calculates damage and fires hit signals.
	
	@private
	@param ctx BulletContext -- Bullet simulation context
	@param hitData table -- Hit information from solver
]=]
function Gun:_OnBulletHit(ctx, hitData)
	if not hitData then return end

	-- Calculate damage using gameplay data (NOT solver objects)
	local damage = self.DamageCalculator:CalculateTotalDamage(
		hitData.Distance,
		ctx,      -- Context contains gameplay data
		hitData,  -- Solver-agnostic hit info
		ctx.Velocity,
		nil       -- No bullet visual object needed
	)

	-- Fire signals
	self.Signals.OnHit:Fire(hitData.Instance, damage, ctx)
	Gun.Signals.OnAnyHit:Fire(hitData.Instance, damage, ctx)
	Logger.Print(Identity .. " Hit: " .. hitData.Instance.Name .. " Damage: " .. damage)
end

--[=[
	Internal callback during bullet travel.
	
	Override this for custom visual effects like tracers.
	
	@client
	@param ctx BulletContext -- Bullet simulation context with position and velocity
]=]
function Gun:_OnBulletTravel(ctx)
	-- Override for custom visual effects
	-- Example: Create tracer using ctx.Position and ctx.Velocity
end

--[=[
	Internal callback when a bullet terminates (hits max distance or stopped).
	
	Override this for custom termination effects.
	
	@client
	@param ctx BulletContext -- Bullet simulation context
]=]
function Gun:_OnBulletTerminating(ctx)
	-- Override for custom effects when bullet dies
end

--[=[
	Gets the current complete state of the weapon.
	
	Returns a table containing ammo, aiming, reloading, shooting, equipped states,
	and current spread value.
	
	@return table -- Current weapon state information
]=]
function Gun:GetState()
	local ammoState = self.AmmoController:GetState()
	local stateManagerState = self.StateManager:GetAllStates()

	return {
		Ammo = ammoState.Ammo,
		Reserve = ammoState.Reserve,
		Aiming = stateManagerState.Aiming,
		Reloading = stateManagerState.Reloading,
		Shooting = stateManagerState.Shooting,
		Equipped = stateManagerState.Equipped,
		Spread = self.SpreadController:GetCurrentSpread(),
	}
end

--[=[
	Destroys the weapon instance and cleans up all resources.
	
	Fires destruction signals, cleans up sub-systems via Janitor,
	and clears all references.
]=]
function Gun:Destroy()
	self.Signals.OnDestroyed:Fire()

	-- Clean up only Gun-owned signals
	self.Signals.OnShoot:Destroy()
	self.Signals.OnHit:Destroy()
	self.Signals.OnDestroyed:Destroy()

	-- Clean up janitor (handles all controllers)
	self._Janitor:Destroy()

	-- Clear references
	self.Data = nil
	self.StateManager = nil
	self.AmmoController = nil
	self.SpreadController = nil
	self.DamageCalculator = nil

	setmetatable(self, nil)
end

--[=[
	Validates weapon configuration data.
	
	@private
	@within Gun
	@param GunData table -- Weapon data to validate
	@return boolean -- Whether the data is valid
]=]
function IsValidData(GunData): boolean
	local succ, err = WeaponType.GunDataCheck(GunData)
	if not succ then 
		Logger.Warn(Identity .. err) 
		return false 
	end
	return true
end

return Gun