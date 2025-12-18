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
	@class WeaponInstance
	
	Main Gun orchestrator - NOW FULLY SOLVER-AGNOSTIC
	Uses BulletContext instead of FastCast objects
]=]
local Gun = {}
Gun.__index = Gun

-- Global signals (shared across all weapon instances)
Gun.Signals = {
	OnAnyHit = Signal.new(),
	OnAnyFire = Signal.new(),
}

--[=[
	Creates a new Gun instance
	
	@param GunData WeaponType.GunData -- Weapon configuration data
	@param UseAnimator boolean? -- Whether to use animator (optional)
	@return Gun -- Gun instance or nil if invalid
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
	if not UseAnimator then
		self.AnimationController = WeaponAnimator.new(self, self.Data.Model)
	end

	return self
end

--[[
	Internal: Sets up ballistics configuration (solver-agnostic)
	This creates behavior config but doesn't depend on FastCast API
]]
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

--[[
	Internal: Sets up cross-controller communication
]]
function Gun:_SetupControllerLinks()
	-- SpreadController needs to know when aiming changes
	self._Janitor:Add(self.StateManager.Signals.OnAimChanged:Connect(function(isAiming)
		self.SpreadController:OnAimChanged(isAiming)
	end))
end

--[[
	Checks if the weapon can fire
	@return boolean - Can fire, string - Reason if cannot
]]
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

--[[
	Fires the weapon
	@param origin - Starting position (optional)
	@param direction - Direction to fire
	@param useHRP_Position - Use HumanoidRootPart position if origin not provided
	@return boolean - Success, any - Result or error reason
]]
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

--[[
	Internal fire logic (can be overridden in subclasses)
	@param origin - Fire origin
	@param direction - Fire direction
	@return BulletContext
]]
function Gun:_FireInternal(origin: Vector3, direction: Vector3)
	local finalDir = self.SpreadController:ApplySpread(direction)
	return self:FireBullet(origin, finalDir)
end

--[[
	Fires a single bullet using BallisticsService
	Returns BulletContext 
	@param origin - Bullet origin
	@param direction - Bullet direction
	@return BulletContext
]]
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

--[[
	Reloads the weapon
	@return Promise - Resolves when reload completes
]]
function Gun:Reload(): any
	return self.AmmoController:Reload()
end

--[[
	Sets the aiming state
	@param aiming - Whether to aim
]]
function Gun:SetAiming(aiming: boolean)
	self.StateManager:SetAiming(aiming)
end

--[[
	Gets the aiming state
	@return boolean - Is aiming
]]
function Gun:IsAiming(): boolean
	return self.StateManager:IsAiming()
end

--[[
	Equips the weapon
]]
function Gun:Equip()
	self.StateManager:SetEquipped(true)
end

--[[
	Unequips the weapon
]]
function Gun:Unequip()
	self.StateManager:SetEquipped(false)
	self.StateManager:SetAiming(false)
	self.StateManager:SetShooting(false)
end

--[[
	Manually sets spread value
	@param amount - Spread amount
	@return number - New spread value
]]
function Gun:SetSpread(amount: number): number
	return self.SpreadController:SetSpread(amount)
end

--[[
	Receives BulletContext instead of FastCast objects
	@param ctx - BulletContext (NOT cast)
	@param hitData - Solver-agnostic hit information
]]
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

--[[
	Receives BulletContext with current position/velocity
	@param ctx - BulletContext (NOT cast)
]]
function Gun:_OnBulletTravel(ctx)
	-- Override for custom visual effects
	-- Example: Create tracer using ctx.Position and ctx.Velocity
	
end

--[[
	@param ctx - BulletContext 
]]
function Gun:_OnBulletTerminating(ctx)
	-- Override for custom effects when bullet dies

end

--[[
	Gets current weapon state
	@return table - Current state information
]]
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

--[[
	Destroys the weapon instance and cleans up
]]
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

-- Validation
function IsValidData(GunData): boolean
	local succ, err = WeaponType.GunDataCheck(GunData)
	if not succ then 
		Logger.Warn(Identity .. err) 
		return false 
	end
	return true
end

return Gun