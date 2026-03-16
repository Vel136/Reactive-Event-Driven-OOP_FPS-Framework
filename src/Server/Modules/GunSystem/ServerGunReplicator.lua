-- ServerGunReplicator.lua
--[[
	Bridges server-side GunInstance signals to client replication.
	- Syncs ammo and reserve changes
	- Syncs hit events for audio/VFX
	- Hooks into ServerGunManager for new weapon creation
]]

local Identity = "ServerGunReplicator"

-- ─── Services ────────────────────────────────────────────────────────────────

local ServerStorage     = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ─── References ──────────────────────────────────────────────────────────────

local Utilities  = ReplicatedStorage.Shared.Modules.Utilities
local Networking = ReplicatedStorage.Shared.Modules.Networking

-- ─── Modules ─────────────────────────────────────────────────────────────────

local Logger         = require(Utilities.Logger)
local Janitor        = require(Utilities.Janitor)
local Signal         = require(Utilities.Signal)

local ServerGunManager = require(ServerStorage.Server.Modules.GunSystem.ServerGunManager)
local SyncTypes        = require(Networking.SyncTypes)
local NetworkService   = require(Networking.NetworkService)

-- ─── Module ──────────────────────────────────────────────────────────────────

local ServerGunReplicator   = {}
ServerGunReplicator.__index = ServerGunReplicator
ServerGunReplicator.__type  = Identity

-- ─── Private state ───────────────────────────────────────────────────────────

local Logger = Logger.new(Identity, false)

-- ─── Internal ────────────────────────────────────────────────────────────────

--- Wires replication signals onto a single GunInstance.
local function _HookGunInstance(gunInstance: any, player: Player, gunInstanceId: string)
	local janitor = gunInstance._Janitor

	janitor:Add(gunInstance.Signals.OnAmmoChanged:Connect(function(ammo: number)
		NetworkService.SyncEventState(player, gunInstanceId, SyncTypes.Ammo, ammo)
	end), "Disconnect")

	janitor:Add(gunInstance.Signals.OnReserveChanged:Connect(function(reserve: number)
		NetworkService.SyncEventState(player, gunInstanceId, SyncTypes.Reserve, reserve)
	end), "Disconnect")

	janitor:Add(gunInstance.Signals.OnHit:Connect(function(context: any, hitData: any)
		NetworkService.SyncSound(
			SyncTypes.Sound,
			context.Origin   or Vector3.new(),
			context.Position or Vector3.new(),
			context.Length   or 0,
			hitData and hitData.Material.Value or Enum.Material.Air.Value
		)
	end), "Disconnect")
end

-- ─── Initialization ──────────────────────────────────────────────────────────

function ServerGunReplicator._Initialize(self: ServerGunReplicator)
	-- Hook all guns that already exist
	local activeGuns = ServerGunManager.GetAllGuns()
	for player, playerGuns in pairs(activeGuns) do
		for gunInstanceId, gunInstance in pairs(playerGuns) do
			_HookGunInstance(gunInstance, player, gunInstanceId)
		end
	end

	-- Hook all future guns as they are created
	ServerGunManager.Signals.OnWeaponCreation:Connect(function(gunInstance: any, player: Player, gunInstanceId: string)
		_HookGunInstance(gunInstance, player, gunInstanceId)
	end)

	Logger:Print("_Initialize: replicator ready")
end

-- ─── Singleton ───────────────────────────────────────────────────────────────

local _instance: ServerGunReplicator

local function GetInstance(): ServerGunReplicator
	if not _instance then
		_instance = setmetatable({}, ServerGunReplicator) :: ServerGunReplicator
		_instance:_Initialize()
	end
	return _instance
end

-- ─── Types ───────────────────────────────────────────────────────────────────

export type ServerGunReplicator = typeof(setmetatable({}, ServerGunReplicator))

return setmetatable({}, {
	__index = function(_, key)
		return GetInstance()[key]
	end,
	__newindex = function()
		error("ServerGunReplicator is read-only")
	end,
}) :: ServerGunReplicator