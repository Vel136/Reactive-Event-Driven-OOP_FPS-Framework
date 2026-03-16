-- GunManager.lua'
--[[
	Handles Multiple Gun.
]]
local Identity = "GunManager"
local GunManager = {}
GunManager.__type = Identity

-- Services
local ReplicatedStorage = game:GetService('ReplicatedStorage')

-- References
local Networking = ReplicatedStorage.Shared.Modules.Networking

-- Utilities-modules
local LogService = require(ReplicatedStorage.Shared.Modules.Utilities:WaitForChild("Logger"))
local Signal = require(ReplicatedStorage.Shared.Modules.Utilities:WaitForChild("Signal"))

local Logger = LogService.new(Identity, true)

-- Additional Modules
local SyncTypes = require(Networking.SyncTypes)
local NetworkService = require(Networking.NetworkService)

-- Require GunInstance for instantiation
local GunInstance = require(script.GunInstance) 

GunManager.Features = {
	BoltActionController = require(script.Features.BoltActionController),
	TracerController = require(script.Features.TracerController),
	MuzzleFlashController = require(script.Features.MuzzleFlashController),
}

local ActiveGuns = {}

--[=[
	@prop Signals table
	@within Gun
	@readonly
	
	Global signals shared across all weapon instances.
	Contains `OnAnyHit`, `OnAnyFire`, `OnAnyBulletFire`, `OnWeaponCreation`, and `OnWeaponDestruction` events.
]=]

local Signals = {
	OnAnyHit = Signal.new(),
	OnAnyFire = Signal.new(),
	OnAnyBulletFire = Signal.new(),
	OnWeaponCreation = Signal.new(),
	OnWeaponDestruction = Signal.new(),
}

GunManager.Signals = Signals

function GunManager.InitializeNetworking()
	-- Hook Signals For Networking.
	NetworkService.OnSyncEventState:Connect(function(WeaponName : string, SyncType, SyncAmount)
		local Gun = ActiveGuns[WeaponName]
		if not Gun then 
			Logger:Warn(`Sync failed: weapon '{WeaponName}' not active`)
			return false 
		end

		-- Validate sync type
		if not SyncTypes.IsValid(SyncType) then
			Logger:Warn(`Invalid sync type: {SyncType}`)
			return false
		end

		local syncName = SyncTypes.GetName(SyncType)

		-- Handle sync
		if SyncType == SyncTypes.Ammo then
			if Gun.ChangeAmmo then
				Gun:ChangeAmmo(SyncAmount)
			else
				Logger:Warn(`{WeaponName}: ChangeAmmo method missing`)
				return false
			end

		elseif SyncType == SyncTypes.Reserve then
			if Gun.ChangeReserve then
				Gun:ChangeReserve(SyncAmount)
			else
				Logger:Warn(`{WeaponName}: ChangeReserve method missing`)
				return false
			end

		elseif SyncType == SyncTypes.Spread then
			if Gun.SpreadController then
				Gun.SpreadController:SetSpread(SyncAmount)
			else
				Logger:Warn(`{WeaponName}: SpreadController missing`)
				return false
			end

		elseif SyncType == SyncTypes.ShotIndex then
			if Gun.SpreadController then
				Gun.SpreadController:SetShotIndex(SyncAmount)
			else
				Logger:Warn(`{WeaponName}: SpreadController missing for ShotIndex`)
				return false
			end
		end

		Logger:Print(`{WeaponName} synced {syncName}: {SyncAmount}`)
		return true
	end)
end

-- Factory function to create new GunInstance and hook global signals
function GunManager.new(GunInstanceId : any,GunInstanceData : any, ...) : GunInstance
	if not GunInstanceData or not GunInstanceId then
		Logger:Fatal(`Invalid parameters - Data: {tostring(GunInstanceData)}, ID: {tostring(GunInstanceId)}`)
		return nil
	end

	local success, result = pcall(function(...)
		return GunInstance.new(GunInstanceData,...)
	end,...)

	if not success then
		Logger:Fatal(`GunInstance creation failed: {result}`)
		return nil
	end

	local instance : GunInstance = result

	-- Hook signals to global
	instance.Signals.OnFire:Connect(function(...)
		Signals.OnAnyFire:Fire(...)
	end)

	instance.Signals.OnHit:Connect(function(...)
		Signals.OnAnyHit:Fire(...)
	end)

	instance.Signals.OnBulletFire:Connect(function(...)
		Signals.OnAnyBulletFire:Fire(...)
	end)

	ActiveGuns[GunInstanceId] = instance
	Signals.OnWeaponCreation:Fire(instance, GunInstanceId)

	Logger:Info(`Created weapon: {GunInstanceId}`)

	return instance :: GunInstance
end

-- Get active gun instance by ID
function GunManager.GetGun(GunInstanceId : string) : GunInstance?
	local gun = ActiveGuns[GunInstanceId]
	if not gun then
		Logger:Warn(`Weapon '{GunInstanceId}' not found`)
	end
	return gun
end

-- Get all active guns
function GunManager.GetActiveGuns() : {[string]: GunInstance}
	return ActiveGuns
end

-- Check if a gun is active
function GunManager.IsGunActive(GunInstanceId : string) : boolean
	return ActiveGuns[GunInstanceId] ~= nil
end

-- Remove/destroy a gun instance
function GunManager.DestroyGun(GunInstanceId : string) : boolean
	local gun = ActiveGuns[GunInstanceId]
	if not gun then
		Logger:Warn(`Cannot destroy '{GunInstanceId}': not active`)
		return false
	end

	-- Clean up gun instance if it has a Destroy method
	if gun.Destroy then
		pcall(function()
			gun:Destroy()
		end)
	end

	ActiveGuns[GunInstanceId] = nil
	Signals.OnWeaponDestruction:Fire(GunInstanceId)
	Logger:Info(`Destroyed weapon: {GunInstanceId}`)
	return true
end

-- Get count of active guns
function GunManager.GetActiveCount() : number
	local count = 0
	for _ in pairs(ActiveGuns) do
		count += 1
	end
	return count
end

-- Clear all active guns
function GunManager.ClearAllGuns()
	local count = GunManager.GetActiveCount()

	for id, gun in pairs(ActiveGuns) do
		if gun.Destroy then
			pcall(function()
				gun:Destroy()
			end)
		end
	end

	table.clear(ActiveGuns)
	Logger:Info(`Cleared {count} weapon(s)`)
end

export type GunInstance = GunInstance.GunInstance

function GunManager._Initialize()
	GunManager.InitializeNetworking()
	Logger:Debug("GunManager ready")
	return true
end

-- Single Ton Pattern
local metatable = {__index = GunManager}

--[[
	Gets or creates the singleton instance
	@return GunManager
]]
local instance

local function GetInstance()
	if not instance then
		instance = setmetatable({}, metatable)
		instance:_Initialize()
	end
	return instance
end

type Signal = Signal.Signal

type OnWeaponCreation = {
	Connect: (self: OnWeaponCreation, callback: (gunInstance: GunInstance, weaponId: any) -> ()) -> (),
	Fire: (self: OnWeaponCreation, gunInstance: GunInstance, weaponId: any) -> (),
}

type OnWeaponDestruction = {
	Connect: (self: OnWeaponDestruction, callback: (weaponId: any) -> ()) -> (),
	Fire: (self: OnWeaponDestruction, weaponId: any) -> (),
}

export type GunManagerSignals = {
	OnAnyHit : Signal,
	OnAnyFire : Signal,
	OnAnyBulletFire : Signal,
	OnWeaponCreation : OnWeaponCreation,
	OnWeaponDestruction : OnWeaponDestruction,
}

export type GunManager = typeof(setmetatable({} :: {
	Signals : GunManagerSignals,
	ActiveGuns : {[string]: GunInstance},
}
, {__index = GunManager}))

-- Export as singleton with read-only access
return setmetatable({}, {
	__index = function(_, key)
		return GetInstance()[key]
	end,
	__newindex = function()
		error("Cannot modify GunManager singleton", 2)
	end
}) :: GunManager