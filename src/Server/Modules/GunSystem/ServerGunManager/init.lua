-- ServerGunManager.lua
--[[
	Server-side weapon manager
	Manages multiple server weapon instances
	Follows the same singleton pattern as client GunManager
]]

local Identity = "ServerGunManager"
local ServerGunManager = {}
ServerGunManager.__type = Identity

-- Services
local ReplicatedStorage = game:GetService('ReplicatedStorage')

-- References
local Networking = ReplicatedStorage.Shared.Modules.Networking

-- Utilities
local LogService = require(ReplicatedStorage.Shared.Modules.Utilities:WaitForChild("Logger"))
local Signal = require(ReplicatedStorage.Shared.Modules.Utilities:WaitForChild("Signal"))

local Logger = LogService.new(Identity, false)

-- Additional Modules
local SyncTypes = require(Networking.SyncTypes)
local NetworkService = require(Networking.NetworkService)

local Configuration = require(ReplicatedStorage.Shared.Modules.FPSSystem.Configuration.Configuration)
local States = Configuration.WeaponStates

-- Require ServerGunInstance for instantiation
local ServerGunInstance = require(script.ServerGunInstance)

-- Active weapon instances per player
local ActiveGuns = {} -- [Player][WeaponName] = ServerGunInstance

--[=[
	@prop Signals table
	@within ServerGunManager
	@readonly
	
	Global signals shared across all weapon instances.
	Contains `OnAnyHit`, `OnAnyFire`, and `OnAnyKill` events.
]=]

local Signals = {
	OnAnyHit = Signal.new(),
	OnAnyFire = Signal.new(),
	OnAnyKill = Signal.new(),
	OnAnyBulletFire = Signal.new(),
	OnWeaponCreation = Signal.new(),
	OnWeaponDestruction = Signal.new(),
}

ServerGunManager.Signals = Signals


--[=[
	Sets up network event handling for weapon actions.
	Handles fire, reload, and state change requests from clients.
	
	@private
]=]
-- In ServerGunManager._InitializeNetworking()
function ServerGunManager._InitializeNetworking()
	-- Handle fire requests from clients
	if NetworkService.OnWeaponFired then
		NetworkService.OnWeaponFired:Connect(function(Player: Player, WeaponName: string, FireData)
			Logger:Debug(`Fire request received from {Player.Name} for weapon '{WeaponName}'`)

			local gun = ServerGunManager.GetPlayerGun(Player, WeaponName)
			if not gun then
				Logger:Warn(`Fire request rejected: {Player.Name} doesn't have weapon '{WeaponName}'`)
				return
			end

			Logger:Info(`Fire request accepted for {Player.Name}'s '{WeaponName}'`)
			local success, reason = gun:Fire(FireData)

			if not success then
				Logger:Warn(`Fire execution failed for {Player.Name}'s '{WeaponName}': {reason or "Unknown"}`)
			else
				Logger:Debug(`Fire executed successfully for {Player.Name}'s '{WeaponName}'`)
			end
		end)
	end

	-- Handle reload requests from clients
	if NetworkService.OnWeaponReload then
		NetworkService.OnWeaponReload:Connect(function(Player: Player, WeaponName: string)
			Logger:Debug(`Reload request received from {Player.Name} for weapon '{WeaponName}'`)

			local gun = ServerGunManager.GetPlayerGun(Player, WeaponName)
			if not gun then
				Logger:Warn(`Reload request rejected: {Player.Name} doesn't have weapon '{WeaponName}'`)
				return
			end

			Logger:Info(`Reload request accepted for {Player.Name}'s '{WeaponName}'`)
			gun:Reload()
			Logger:Debug(`Reload executed for {Player.Name}'s '{WeaponName}'`)
		end)
	end

	-- Handle state change requests from clients
	if NetworkService.OnWeaponStateChanged then
		NetworkService.OnWeaponStateChanged:Connect(function(Player: Player, WeaponName: string, StateType, StateValue)
			Logger:Debug(`State change request received from {Player.Name} for weapon '{WeaponName}' (Type: {StateType}, Value: {StateValue})`)

			local gun = ServerGunManager.GetPlayerGun(Player, WeaponName)
			if not gun then
				Logger:Warn(`State change rejected: {Player.Name} doesn't have weapon '{WeaponName}'`)
				return
			end

			Logger:Info(`State change accepted for {Player.Name}'s '{WeaponName}'`)
			
			if StateType == States.Aim then
				gun:SetAiming(StateValue)
				Logger:Debug(`Aiming state set to {StateValue} for {Player.Name}'s '{WeaponName}'`)
			elseif StateType == States.Equip then
				if StateValue then
					gun:Equip()
					Logger:Debug(`Equipped '{WeaponName}' for {Player.Name}`)
				else
					gun:Unequip()
					Logger:Debug(`Unequipped '{WeaponName}' for {Player.Name}`)
				end
			else
				Logger:Warn(`Unknown state type '{StateType}' for {Player.Name}'s '{WeaponName}'`)
			end
		end)
	end

	Logger:Info("Network handlers registered successfully")
end

--[=[
	Creates a new server weapon instance for a player.
	
	Hooks global signals and stores the instance.
	
	@param Player Player -- Player who owns the weapon
	@param WeaponName string -- Unique weapon identifier
	@param GunData table -- Weapon configuration data
	@return ServerGunInstance?
]=]
function ServerGunManager.new(Player: Player, GunInstanceId: string, GunInstanceData: any): ServerGunInstance?
	if not Player or not Player:IsA("Player") then
		Logger:Fatal(`Invalid Player parameter`)
		return nil
	end

	if not GunInstanceData or not GunInstanceId then
		Logger:Fatal(`Invalid parameters - Data: {tostring(GunInstanceData)}, Id: {tostring(GunInstanceId)}`)
		return nil
	end

	-- Create player entry if doesn't exist
	if not ActiveGuns[Player] then
		ActiveGuns[Player] = {}
	end

	-- Check if weapon already exists for this player
	if ActiveGuns[Player][GunInstanceId] then
		Logger:Warn(`Weapon '{GunInstanceId}' already exists for {Player.Name}, destroying old instance`)
		ServerGunManager.DestroyGun(Player, GunInstanceId)
	end

	local success, result = pcall(function()
		return ServerGunInstance.new(GunInstanceData, Player)
	end)

	if not success then
		Logger:Fatal(`ServerGunInstance creation failed: {result}`)
		return nil
	end

	local instance: ServerGunInstance = result

	-- Hook signals to global
	instance.Signals.OnFire:Connect(function(...)
		Signals.OnAnyFire:Fire(Player, GunInstanceId, ...)
	end)

	instance.Signals.OnHit:Connect(function(...)
		Signals.OnAnyHit:Fire(Player, GunInstanceId, ...)
	end)

	instance.Signals.OnKill:Connect(function(...)
		Signals.OnAnyKill:Fire(Player, GunInstanceId, ...)
	end)

	instance.Signals.OnBulletFire:Connect(function(...)
		Signals.OnAnyBulletFire:Fire(Player, GunInstanceId, ...)
	end)

	-- Store instance
	ActiveGuns[Player][GunInstanceId] = instance
	Signals.OnWeaponCreation:Fire(instance, Player, GunInstanceId)

	Logger:Info(`Created weapon '{GunInstanceId}' for {Player.Name}`)

	return instance :: ServerGunInstance
end

--[=[
	Gets a specific weapon instance for a player.
	
	@param Player Player -- Player who owns the weapon
	@param WeaponName string -- Weapon identifier
	@return ServerGunInstance?
]=]
function ServerGunManager.GetPlayerGun(Player: Player, WeaponName: string): ServerGunInstance?
	if not ActiveGuns[Player] then
		return nil
	end

	local gun = ActiveGuns[Player][WeaponName]
	if not gun then
		Logger:Warn(`Weapon '{WeaponName}' not found for {Player.Name}`)
	end
	return gun
end

--[=[
	Gets all weapons for a specific player.
	
	@param Player Player -- Player to get weapons for
	@return {[string]: ServerGunInstance}
]=]
function ServerGunManager.GetPlayerGuns(Player: Player): {[string]: ServerGunInstance}
	return ActiveGuns[Player] or {}
end

--[=[
	Gets all active weapons across all players.
	
	@return {[Player]: {[string]: ServerGunInstance}}
]=]
function ServerGunManager.GetAllGuns(): {[Player]: {[string]: ServerGunInstance}}
	return ActiveGuns
end

--[=[
	Checks if a player has a specific weapon.
	
	@param Player Player -- Player to check
	@param WeaponName string -- Weapon identifier
	@return boolean
]=]
function ServerGunManager.HasGun(Player: Player, WeaponName: string): boolean
	return ActiveGuns[Player] and ActiveGuns[Player][WeaponName] ~= nil
end

--[=[
	Destroys a specific weapon instance for a player.
	
	@param Player Player -- Player who owns the weapon
	@param WeaponName string -- Weapon identifier
	@return boolean -- Success status
]=]
function ServerGunManager.DestroyGun(Player: Player, GunInstanceId: string): boolean
	if not ActiveGuns[Player] then
		Logger:Warn(`Cannot destroy '{GunInstanceId}': {Player.Name} has no weapons`)
		return false
	end

	local gun = ActiveGuns[Player][GunInstanceId]
	if not gun then
		Logger:Warn(`Cannot destroy '{GunInstanceId}': not found for {Player.Name}`)
		return false
	end

	-- Clean up gun instance
	if gun.Destroy then
		pcall(function()
			gun:Destroy()
		end)
	end

	ActiveGuns[Player][GunInstanceId] = nil
	Signals.OnWeaponDestruction:Fire(Player, GunInstanceId)

	Logger:Info(`Destroyed weapon '{GunInstanceId}' for {Player.Name}`)
	return true
end

--[=[
	Destroys all weapons for a specific player.
	
	@param Player Player -- Player whose weapons to destroy
	@return number -- Number of weapons destroyed
]=]
function ServerGunManager.DestroyPlayerGuns(Player: Player): number
	if not ActiveGuns[Player] then
		return 0
	end

	local count = 0
	for weaponName, gun in pairs(ActiveGuns[Player]) do
		if gun.Destroy then
			pcall(function()
				gun:Destroy()
			end)
		end
		count += 1
	end

	ActiveGuns[Player] = nil
	Logger:Info(`Destroyed {count} weapon(s) for {Player.Name}`)
	return count
end

--[=[
	Gets the total count of active weapons across all players.
	
	@return number
]=]
function ServerGunManager.GetTotalWeaponCount(): number
	local count = 0
	for player, weapons in pairs(ActiveGuns) do
		for _ in pairs(weapons) do
			count += 1
		end
	end
	return count
end

--[=[
	Gets the count of weapons for a specific player.
	
	@param Player Player -- Player to count weapons for
	@return number
]=]
function ServerGunManager.GetPlayerWeaponCount(Player: Player): number
	if not ActiveGuns[Player] then
		return 0
	end

	local count = 0
	for _ in pairs(ActiveGuns[Player]) do
		count += 1
	end
	return count
end

--[=[
	Clears all weapons for all players.
]=]
function ServerGunManager.ClearAllGuns()
	local totalCount = ServerGunManager.GetTotalWeaponCount()

	for player, weapons in pairs(ActiveGuns) do
		for weaponName, gun in pairs(weapons) do
			if gun.Destroy then
				pcall(function()
					gun:Destroy()
				end)
			end
		end
	end

	table.clear(ActiveGuns)
	Logger:Info(`Cleared {totalCount} weapon(s) across all players`)
end

--[=[
	Handles player cleanup when they leave.
	Should be connected to Players.PlayerRemoving.
	
	@param Player Player -- Player who is leaving
]=]
function ServerGunManager.OnPlayerRemoving(Player: Player)
	local count = ServerGunManager.DestroyPlayerGuns(Player)
	if count > 0 then
		Logger:Debug(`Cleaned up {count} weapon(s) for leaving player {Player.Name}`)
	end
end

--[=[
	Initializes the ServerGunManager.
	Sets up networking and player cleanup.
	
	@private
]=]
function ServerGunManager._Initialize()
	ServerGunManager._InitializeNetworking()

	-- Auto-cleanup on player leave
	game.Players.PlayerRemoving:Connect(ServerGunManager.OnPlayerRemoving)

	Logger:Debug("ServerGunManager ready")
	return true
end

-- Singleton Pattern
local metatable = {__index = ServerGunManager}

--[[
	Gets or creates the singleton instance
	@return ServerGunManager
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
	Connect: (self: OnWeaponCreation, callback: (gunInstance: ServerGunInstance, player: Player, weaponId: any) -> ()) -> (),
	Fire: (self: OnWeaponCreation, gunInstance: ServerGunInstance, player: Player, weaponId: any) -> (),
}

type OnWeaponDestruction = {
	Connect: (self: OnWeaponDestruction, callback: (gunInstance: ServerGunInstance, player: Player, weaponId: any) -> ()) -> (),
	Fire: (self: OnWeaponDestruction, gunInstance: ServerGunInstance, player: Player, weaponId: any) -> (),
}

export type ServerGunManagerSignals = {
	OnAnyHit: Signal,
	OnAnyFire: Signal,
	OnAnyKill: Signal,
	OnAnyBulletFire: Signal,
	OnWeaponCreation: OnWeaponCreation,
	OnWeaponDestruction: OnWeaponDestruction,
}

export type ServerGunInstance = ServerGunInstance.ServerGunInstance
export type ServerGunManager = typeof(setmetatable({} :: {
	Signals: ServerGunManagerSignals,
}, {__index = ServerGunManager}))

-- Export as singleton with read-only access
return setmetatable({}, {
	__index = function(_, key)
		return GetInstance()[key]
	end,
	__newindex = function()
		error("Cannot modify ServerGunManager singleton", 2)
	end
}) :: ServerGunManager