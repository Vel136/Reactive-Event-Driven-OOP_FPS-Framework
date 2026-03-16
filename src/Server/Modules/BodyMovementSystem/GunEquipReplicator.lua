-- GunEquipReplicator.lua

-- Services
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local ServerStorage = game:GetService('ServerStorage')
local Players = game:GetService('Players')

-- Modules
local ServerGunManager = require(ServerStorage.Server.Modules.GunSystem.ServerGunManager)
local NetworkService = require(ReplicatedStorage.Shared.Modules.Networking.NetworkService)

-- Initialization
local Identity = "GunEquipReplicator"
local GunEquipReplicator = {}
GunEquipReplicator.__type = Identity

--[[
struct  EquipDatas {
	Player : Instance(Player),
	GunInstanceId : u16,
	Equip : boolean,
}
]]
local ActiveEquips = {} -- [Player] = {[GunInstanceId] = Equip}

local function TrackGun(Player, GunInstanceId, GunInstance)
	GunInstance.Signals.OnEquipChanged:Connect(function(Equip)
		if Equip ~= nil then
			-- Track state
			if not ActiveEquips[Player] then
				ActiveEquips[Player] = {}
			end
			ActiveEquips[Player][GunInstanceId] = Equip

			NetworkService.ReplicateGunEquip(Player, {
				{
					Player = Player,
					GunInstanceId = GunInstanceId,
					Equip = Equip,
				}
			})
		end
	end)
end
function GunEquipReplicator._Initialize()
	local ActiveGuns = ServerGunManager.GetAllGuns()

	for Player, PlayerGuns in pairs(ActiveGuns) do
		for GunInstanceId, GunInstance in pairs(PlayerGuns) do
			TrackGun(Player, GunInstanceId, GunInstance)
		end
	end

	ServerGunManager.Signals.OnWeaponCreation:Connect(function(GunInstance, Player, GunInstanceId)
		TrackGun(Player, GunInstanceId, GunInstance)
	end)

	-- Clean up when a player leaves
	Players.PlayerRemoving:Connect(function(Player)
		ActiveEquips[Player] = nil
	end)

	Players.PlayerAdded:Connect(function(JoinedPlayer)
		local EquipBatch = {}

		for Player, GunInstanceId in pairs(ActiveEquips) do
			table.insert(EquipBatch, {
				Player = Player,
				GunInstanceId = GunInstanceId,
				Equip = true,
			})
		end

		if #EquipBatch > 0 then
			NetworkService.ReplicateGunEquipForClient(JoinedPlayer, EquipBatch)
		end
	end)
end



--[[
	Gets or creates the singleton instance
	@return ServerGunManager
]]
-- Singleton Pattern
local metatable = {__index = GunEquipReplicator}

local instance

export type ServerGunReplicator = typeof(setmetatable({}, metatable))
local function GetInstance()
	if not instance then
		instance = setmetatable({}, metatable)
		instance:_Initialize()
	end
	return instance
end

-- Export as singleton with read-only access
return setmetatable({}, {
	__index = function(_, key)
		return GetInstance()[key]
	end,
	__newindex = function()
		error("Cannot modify ServerGunReplicator singleton", 2)
	end
}) :: ServerGunReplicator
