-- GrenadeManager.lua
--[[
	Handles multiple GrenadeInstances.
	Follows the same singleton + factory pattern as GunManager.
	- Global signals across all grenade instances
	- Grenade registration and lifecycle management
	- Networking sync support
]]

local Identity = "GrenadeManager"

-- ─── Services ────────────────────────────────────────────────────────────────

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ─── References ──────────────────────────────────────────────────────────────

local Networking = ReplicatedStorage.Shared.Modules.Networking

-- ─── Modules ─────────────────────────────────────────────────────────────────

local LogService = require(ReplicatedStorage.Shared.Modules.Utilities:WaitForChild("Logger"))
local Signal     = require(ReplicatedStorage.Shared.Modules.Utilities:WaitForChild("Signal"))

local Logger = LogService.new(Identity, false)

local SyncTypes      = require(Networking.SyncTypes)
local NetworkService = require(Networking.NetworkService)

local GrenadeInstance = require(script.GrenadeInstance)

-- ─── Module ──────────────────────────────────────────────────────────────────

local GrenadeManager   = {}
GrenadeManager.__type  = Identity

-- ─── Private state ───────────────────────────────────────────────────────────

local ActiveGrenades = {}

-- ─── Global signals ──────────────────────────────────────────────────────────

--[=[
	@prop Signals table
	@within GrenadeManager
	@readonly

	Global signals shared across all grenade instances.
	Contains `OnAnyThrow`, `OnAnyDetonate`, `OnGrenadeCreation`, and `OnGrenadeDestruction` events.
]=]

local Signals = {
	OnAnyThrow           = Signal.new(),
	OnAnyDetonate        = Signal.new(),
	OnGrenadeCreation    = Signal.new(),
	OnGrenadeDestruction = Signal.new(),
}

GrenadeManager.Signals = Signals

-- ─── Networking ──────────────────────────────────────────────────────────────

function GrenadeManager.InitializeNetworking()
	NetworkService.OnSyncEventState:Connect(function(GrenadeId: string, SyncType, SyncAmount)
		local grenade = ActiveGrenades[GrenadeId]
		if not grenade then
			Logger:Warn(`Sync failed: grenade '{GrenadeId}' not active`)
			return false
		end

		if not SyncTypes.IsValid(SyncType) then
			Logger:Warn(`Invalid sync type: {SyncType}`)
			return false
		end

		local syncName = SyncTypes.GetName(SyncType)

		if SyncType == SyncTypes.Stock then
			if grenade.InventoryController then
				grenade.InventoryController:SetStock(SyncAmount)
			else
				Logger:Warn(`{GrenadeId}: InventoryController missing`)
				return false
			end

		else
			Logger:Warn(`{GrenadeId}: unhandled sync type '{syncName}'`)
			return false
		end

		Logger:Print(`{GrenadeId} synced {syncName}: {SyncAmount}`)
		return true
	end)
end

-- ─── Factory ─────────────────────────────────────────────────────────────────

--- Creates a new GrenadeInstance, registers it, and hooks global signals.
--- @param grenadeId any — unique identifier for this grenade instance
--- @param grenadeData any — GrenadeInstance data table
--- @param blastController any — injectable blast controller (BlastController, FlashController, etc.)
--- @param ... any — additional args forwarded to GrenadeInstance.new
function GrenadeManager.new(grenadeId: any, grenadeData: any, blastController: any, ...): GrenadeInstance.GrenadeInstance
	if not grenadeData or not grenadeId then
		Logger:Fatal(`Invalid parameters - Data: {tostring(grenadeData)}, ID: {tostring(grenadeId)}`)
		return nil
	end

	if not blastController then
		Logger:Fatal(`Missing blastController for '{grenadeId}'`)
		return nil
	end

	local success, result = pcall(function(...)
		return GrenadeInstance.new(grenadeData, blastController, ...)
	end, ...)

	if not success then
		Logger:Fatal(`GrenadeInstance creation failed: {result}`)
		return nil
	end

	local instance: GrenadeInstance.GrenadeInstance = result

	-- Hook signals to global
	instance.Signals.OnThrow:Connect(function(...)
		Signals.OnAnyThrow:Fire(grenadeId, ...)
	end)

	instance.Signals.OnDetonate:Connect(function(...)
		Signals.OnAnyDetonate:Fire(grenadeId, ...)
	end)

	ActiveGrenades[grenadeId] = instance
	Signals.OnGrenadeCreation:Fire(instance, grenadeId)

	Logger:Info(`Created grenade: {grenadeId}`)

	return instance
end

-- ─── Registry ────────────────────────────────────────────────────────────────

--- Returns the active GrenadeInstance by ID.
function GrenadeManager.GetGrenade(grenadeId: string): GrenadeInstance.GrenadeInstance?
	local grenade = ActiveGrenades[grenadeId]
	if not grenade then
		Logger:Warn(`Grenade '{grenadeId}' not found`)
	end
	return grenade
end

--- Returns the full active grenade table.
function GrenadeManager.GetActiveGrenades(): { [string]: GrenadeInstance.GrenadeInstance }
	return ActiveGrenades
end

--- Returns true if a grenade with the given ID is currently active.
function GrenadeManager.IsGrenadeActive(grenadeId: string): boolean
	return ActiveGrenades[grenadeId] ~= nil
end

--- Returns the number of currently active grenade instances.
function GrenadeManager.GetActiveCount(): number
	local count = 0
	for _ in pairs(ActiveGrenades) do
		count += 1
	end
	return count
end

-- ─── Lifecycle ───────────────────────────────────────────────────────────────

--- Destroys and deregisters a grenade instance by ID.
function GrenadeManager.DestroyGrenade(grenadeId: string): boolean
	local grenade = ActiveGrenades[grenadeId]
	if not grenade then
		Logger:Warn(`Cannot destroy '{grenadeId}': not active`)
		return false
	end

	if grenade.Destroy then
		pcall(function()
			grenade:Destroy()
		end)
	end

	ActiveGrenades[grenadeId] = nil
	Signals.OnGrenadeDestruction:Fire(grenadeId)

	Logger:Info(`Destroyed grenade: {grenadeId}`)
	return true
end

--- Destroys all active grenade instances and clears the registry.
function GrenadeManager.ClearAllGrenades()
	local count = GrenadeManager.GetActiveCount()

	for id, grenade in pairs(ActiveGrenades) do
		if grenade.Destroy then
			pcall(function()
				grenade:Destroy()
			end)
		end
	end

	table.clear(ActiveGrenades)
	Logger:Info(`Cleared {count} grenade(s)`)
end

-- ─── Initialization ──────────────────────────────────────────────────────────

function GrenadeManager._Initialize()
	GrenadeManager.InitializeNetworking()
	Logger:Debug("GrenadeManager ready")
	return true
end

-- ─── Singleton ───────────────────────────────────────────────────────────────

local metatable = {__index = GrenadeManager}

local instance

local function GetInstance()
	if not instance then
		instance = setmetatable({}, metatable)
		instance:_Initialize()
	end
	return instance
end

-- ─── Types ───────────────────────────────────────────────────────────────────

type Signal = Signal.Signal

type OnGrenadeCreation = {
	Connect : (self: OnGrenadeCreation, callback: (grenadeInstance: GrenadeInstance.GrenadeInstance, grenadeId: any) -> ()) -> (),
	Fire    : (self: OnGrenadeCreation, grenadeInstance: GrenadeInstance.GrenadeInstance, grenadeId: any) -> (),
}

type OnGrenadeDestruction = {
	Connect : (self: OnGrenadeDestruction, callback: (grenadeId: any) -> ()) -> (),
	Fire    : (self: OnGrenadeDestruction, grenadeId: any) -> (),
}

export type GrenadeManagerSignals = {
	OnAnyThrow           : Signal,
	OnAnyDetonate        : Signal,
	OnGrenadeCreation    : OnGrenadeCreation,
	OnGrenadeDestruction : OnGrenadeDestruction,
}

export type GrenadeManager = typeof(setmetatable({} :: {
	Signals        : GrenadeManagerSignals,
	ActiveGrenades : { [string]: GrenadeInstance.GrenadeInstance },
}, { __index = GrenadeManager }))

-- Export as singleton with read-only access
return setmetatable({}, {
	__index = function(_, key)
		return GetInstance()[key]
	end,
	__newindex = function()
		error("Cannot modify GrenadeManager singleton", 2)
	end
}) :: GrenadeManager