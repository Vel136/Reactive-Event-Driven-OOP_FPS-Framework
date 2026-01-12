-- ClientWeaponInstance.lua
--[[
	Main Gun orchestrator - NOW FULLY SOLVER-AGNOSTIC
	Uses BulletContext instead of FastCast objects
]]

local Identity = "[WeaponInstance]"

-- Services
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local RunService = game:GetService('RunService')
local Players = game:GetService('Players')


-- References
local Utilities = ReplicatedStorage.SharedModules.Utilities
local Cores = ReplicatedStorage.ClientModules.Cores
local Controllers = ReplicatedStorage.ClientModules.Controllers
local Networking = ReplicatedStorage.SharedModules.Networking

-- Utilities-modules
local t = require(Utilities:WaitForChild("TypeCheck"))
local Logger = require(Utilities:WaitForChild("LogService"))
local Janitor = require(Utilities:WaitForChild("Janitor"))
local Signal = require(Utilities:WaitForChild("Signal"))

-- Sub-modules
local StateManager = require(script.StateManager)
local AmmoController = require(script.AmmoController)
local SpreadController = require(script.SpreadController)
local DamageCalculator = require(script.DamageCalculator)


local Player = game.Players.LocalPlayer

-- Additional Modules
local BallisticsService = require(Cores.BallisticsService)
local WeaponAnimator = require(Controllers.WeaponAnimator)
local SyncTypes = require(Networking.SyncTypes)
local NetworkService = require(Networking.NetworkService)
--[=[
	@class Gun
	
	Main gun orchestrator - fully solver-agnostic.
	Uses BulletContext instead of FastCast objects for ballistics simulation.
	
	This class manages all weapon functionality including firing, reloading, aiming,
	and state management through specialized controller sub-systems.
]=]
local Gun = {}
Gun.__index = Gun


Gun.ActiveGuns = {}
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
	OnAnyBulletFire = Signal.new(),
	
	-- Networking.
	
	OnSoundSync = Signal.new()
}
--[=[
	@interface GunSignals
	@external Signal https://sleitnick.github.io/RbxUtil/api/Signal/
	@within Gun
	.OnFire Signal<Vector3, Vector3> -- Fires when weapon shoots
	.OnHit Signal<Instance, number, BulletContext> -- Fires when bullet hits
	.OnReload Signal<> -- Fires when reload begins
	.OnReloadComplete Signal<> -- Fires when reload completes
	.OnAmmoChanged Signal<number> -- Fires when ammo changes
	.OnReserveChanged Signal<number> -- Fires when reserve ammo changes
	.OnEmpty Signal<> -- Fires when out of ammo
	.OnFireChanged Signal<boolean> -- Fires when shooting state changes
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
function Gun.new(GunData, UseAnimator: boolean?)
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
		OnPreFire = Signal.new(),
		OnFire = Signal.new(),
		OnHit = Signal.new(),
		OnDestroyed = Signal.new(),
		OnBulletFire = Signal.new(),
		-- Direct references to controller signals
		OnReload = self.AmmoController.Signals.OnReload,
		OnReloadComplete = self.AmmoController.Signals.OnReloadComplete,
		OnAmmoChanged = self.AmmoController.Signals.OnAmmoChanged,
		OnReserveChanged = self.AmmoController.Signals.OnReserveChanged,
		OnEmpty = self.AmmoController.Signals.OnEmpty,

		OnFireChanged = self.StateManager.Signals.OnFireChanged,
		OnAimChanged = self.StateManager.Signals.OnAimChanged,
		OnEquipChanged = self.StateManager.Signals.OnEquipChanged,
		OnReloadChanged = self.StateManager.Signals.OnReloadChanged,
		OnEquipCompleted = Signal.new()
	}

	-- Setup ballistics
	self:_SetupBallistics()
	
	-- Setup networking communication
	self:_SetupNetworking()
	-- Setup cross-controller communication
	self:_SetupControllerLinks()

	-- Animator setup
	if UseAnimator ~= false then
		self.AnimationController = WeaponAnimator.new(self, self.Data.Model)
	end
	
	Gun.ActiveGuns[GunData.Name] = self
	return self
end

function Gun:_SetupNetworking()
	local States = StateManager.States
	
	self._Janitor:Add(self.Signals.OnPreFire:Connect(function(FireData)
		NetworkService.FireWeapon(self.Data.Name,FireData)
	end),"Disconnect")
	
	self._Janitor:Add(self.Signals.OnReload:Connect(function()
		NetworkService.ReloadWeapon(self.Data.Name)
	end),"Disconnect")
	
	self._Janitor:Add(self.Signals.OnAimChanged:Connect(function(IsAiming)
		if not NetworkService.ChangeStateWeapon then Logger.Warn("ChangeStateWeapon doesnt exist in NetworkService",Identity) return false end
		NetworkService.ChangeStateWeapon(self.Data.Name,States.Aim,IsAiming)
	end),"Disconnect")
	
	self._Janitor:Add(self.Signals.OnEquipChanged:Connect(function(IsEquip)
		if not NetworkService.ChangeStateWeapon then Logger.Warn("ChangeStateWeapon doesnt exist in NetworkService",Identity) return false end
		NetworkService.ChangeStateWeapon(self.Data.Name,States.Equip,IsEquip)
	end),"Disconnect")
	
end
function Gun.SetupNetworking()
	NetworkService.OnSyncEventState:Connect(function(WeaponName : string, SyncType, SyncAmount)
		local Weapon = Gun.ActiveGuns[WeaponName]
		if not Weapon then 
			Logger.Warn(string.format("No active weapon '%s' for sync", WeaponName), Identity)
			return false 
		end

		-- Validate sync type
		if not SyncTypes.IsValid(SyncType) then
			Logger.Warn(string.format("Invalid sync type: %d", SyncType), Identity)
			return false
		end

		-- Handle sync
		if SyncType == SyncTypes.Ammo then
			if Weapon.ChangeAmmo then
				Weapon:ChangeAmmo(SyncAmount)
			else
				Logger.Warn("Failed to sync ammo - method missing", Identity)
				return false
			end

		elseif SyncType == SyncTypes.Reserve then
			if Weapon.ChangeReserve then
				Weapon:ChangeReserve(SyncAmount)
			else
				Logger.Warn("Failed to sync reserve - method missing", Identity)
				return false
			end

		elseif SyncType == SyncTypes.Spread then
			if Weapon.SpreadController then
				Weapon.SpreadController.CurrentSpread.Value = SyncAmount
			else
				Logger.Warn("Failed to sync spread - controller missing", Identity)
				return false
			end
		elseif SyncType == SyncTypes.ShotIndex then
			if Weapon.SpreadController then
				Weapon.SpreadController.ShotIndex = SyncAmount
			else
				Logger.Warn("Failed to sync shot_index - controller missing", Identity)
			end
		
		end

		Logger.Print(string.format(
			"Synced %s: %s",
			SyncTypes.GetName(SyncType),
			tostring(SyncAmount)
			), Identity)

		return true
	end)
	
	NetworkService.OnSoundSync:Connect(function(...)
		if Gun.Signals.OnSoundSync then
			Gun.Signals.OnSoundSync:Fire(...)
		end
	end)
end
--[=[
	Sets up ballistics configuration including raycast parameters and physics behavior.
	
	@private
]=]
function Gun:_SetupBallistics()
	
	local behavior = {
		RaycastParams = nil,
		Acceleration = Vector3.new(),
		MaxDistance = 1000,
		CanPierceFunction = nil,
		HighFidelityBehavior = 1,
		HighFidelitySegmentSize = 0.5,
		CosmeticBulletTemplate = nil,
		CosmeticBulletProvider = nil,
		CosmeticBulletContainer = nil,
		AutoIgnoreContainer = true
	}
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
	behavior.SolverType = self.Data.SolverType
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
function Gun:_FireInternal(Origin: Vector3, Direction: Vector3)
	local BurstCount = self.Data.BurstCount or 1
	local BurstDelay = self.Data.BurstDelay or 0.04
	
	local PelletCount = self.Data.PelletCount or 1
	
	local FireData = {
		Origin = Origin,
		Direction = Direction,
		Time = os.clock(),
		ShotIndex = self.SpreadController:GetShotIndex(),
		LastShootTime = self.StateManager.LastShootTime,
	}
	if self.Signals.OnPreFire then
		self.Signals.OnPreFire:Fire(FireData)
	end
	-- Auto-handle burst/pellets
	for i = 1, BurstCount do
		for i = 1,PelletCount do
			local FinalDirection = self.SpreadController:ApplySpread(Direction)
			Logger.Print(string.format("Client: Fire in pellet with spread applied direction of: %s, Shot Index of %i, Spread of  %d", tostring(FinalDirection),self.SpreadController:GetShotIndex(),self.SpreadController.CurrentSpread.Value), Identity)

			local context = self:FireBullet(Origin, FinalDirection)
		end

		self.Signals.OnFire:Fire(Origin, Direction)
		Gun.Signals.OnAnyFire:Fire(Origin, Direction)
		self.AmmoController:ConsumeAmmo(1)
		
		if i < BurstCount then
			task.wait(BurstDelay)
		end
	end
	return true
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
		{
			Origin = origin,
			Direction = direction,
			Speed = self.Data.BulletSpeed or 1000,
			Behavior = self.Ballistics.Behavior,
			Callbacks = {
				OnHit = function(context,hitData)
					self:_OnBulletHit(context, hitData)
				end,

				OnLengthChanged = function(context,currentPos)
					self:_OnBulletTravel(context)
				end,

				OnTerminating = function(context)
					self:_OnBulletTerminating(context)
				end,
			}
		}
	)
	Gun.Signals.OnAnyBulletFire:Fire(context)
	self.Signals.OnBulletFire:Fire(context)

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

	-- Fire signals
	self.Signals.OnHit:Fire(ctx,hitData)
	Gun.Signals.OnAnyHit:Fire(ctx,hitData)

	Logger.Print("Hit: " .. (hitData and hitData.Instance.Name or ""),Identity)
end

--[=[
	Override this to get muzzle position
]=]
function Gun.GetCurrentMuzzlePosition()
	return Vector3.new()
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
		Ammo = ammoState.Ammo.Value,
		Reserve = ammoState.Reserve.Value,
		Aiming = stateManagerState.Aiming.Value,
		Reloading = stateManagerState.Reloading.Value,
		Shooting = stateManagerState.Shooting.Value,
		Equipped = stateManagerState.Equipped.Value,
		Spread = self.SpreadController:GetCurrentSpread(),
	}
end

function Gun:ChangeAmmo(AmmoValue)
	if self.AmmoController then
		self.AmmoController:SetAmmo(AmmoValue)
	end
	return true
end

function Gun:ChangeReserve(ReserveValue)
	if self.AmmoController then
		self.AmmoController:SetReserve(ReserveValue)
	end
	return true
end

--[=[
	Destroys the weapon instance and cleans up all resources.
	
	Fires destruction signals, cleans up sub-systems via Janitor,
	and clears all references.
]=]
function Gun:Destroy()
	self.Signals.OnDestroyed:Fire()

	-- Clean up only Gun-owned signals
	self.Signals.OnFire:Destroy()
	self.Signals.OnHit:Destroy()
	self.Signals.OnDestroyed:Destroy()
	self.Signals.OnBulletFire:Destroy()
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

Gun.SetupNetworking()
return Gun