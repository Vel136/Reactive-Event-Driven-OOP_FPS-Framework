-- GunEquipReplicator.lua

local Identity = "GunEquipReplicator"
local GunEquipReplicator = {}
GunEquipReplicator.__type = Identity

-- Services
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local Players = game:GetService('Players')

-- References
local LocalPlayer = Players.LocalPlayer
local Utilities = ReplicatedStorage.Shared.Modules.Utilities

-- Modules
local NetworkService = require(ReplicatedStorage.Shared.Modules.Networking.NetworkService)
local Signal = require(Utilities.Signal)
local LogService = require(Utilities.Logger)
local Logger = LogService.new(Identity,false)

local Tools = ReplicatedStorage.Assets.Tools

type OnWeaponEquipped = (Player : Player, GunModel : Model, GunInstanceId : string) -> ()

local EquipSignal = Signal.new() :: Signal.Signal<OnWeaponEquipped>
local UnequipSignal = Signal.new() :: Signal.Signal<(Player : Player, GunInstanceId : string) -> ()>
GunEquipReplicator.Signals = {
	OnWeaponEquipped   = EquipSignal,  -- (Player, weaponClone: Model, GunInstanceId: string)
	OnWeaponUnequipped = UnequipSignal,  -- (Player, GunInstanceId: string)
}

-- Track weapons equipped on other players
local EquippedWeapons = {}

function GunEquipReplicator.AttachWeaponToCharacter(character, weaponModel)
	-- Find the hand to attach to
	local rightHand = character:FindFirstChild("RightHand") -- R15
		or character:FindFirstChild("Right Arm")  -- R6

	if not rightHand then 
		Logger:Warn("Could not find RightHand for character: " .. character.Name)
		return 
	end

	local handle = weaponModel:FindFirstChild("Handle") or weaponModel.PrimaryPart
	if not handle then 
		Logger:Warn("Weapon missing Handle: " .. weaponModel.Name)
		return 
	end

	-- Weld to hand
	local weld = Instance.new("Weld")
	weld.Part0 = rightHand
	weld.Part1 = handle
	weld.C0 = weaponModel.Grip
	weld.Parent = handle

	Logger:Debug("Attached weapon " .. weaponModel.Name .. " to " .. character.Name)
end

function GunEquipReplicator.RemoveWeaponFromCharacter(character)
	local removed = false
	-- Find and destroy any equipped weapon
	for _, obj in character:GetChildren() do
		if obj:IsA("Tool") or (obj:IsA("Model") and obj:FindFirstChild("Handle")) then
			Logger:Debug("Removing weapon " .. obj.Name .. " from " .. character.Name)
			obj:Destroy()
			removed = true
		end
	end
	return removed
end

function GunEquipReplicator._Initialize()
	Logger:Info("Initializing GunEquipReplicator")

	NetworkService.OnEquipReplicated:Connect(function(EquipDatas)
		for _, EquipData in ipairs(EquipDatas) do
			local Player = EquipData.Player
			local GunInstanceId = EquipData.GunInstanceId
			local Equip = EquipData.Equip

			-- Don't replicate our own weapon (we handle that with viewmodel)
			if Player == LocalPlayer then continue end

			local character = Player.Character
			if not character then 
				Logger:Warn("Player " .. Player.Name .. " has no character")
				continue
			end

			if Equip then
				Logger:Info("Player " .. Player.Name .. " equipped: " .. GunInstanceId)
				GunEquipReplicator.RemoveWeaponFromCharacter(character)

				local weaponTemplate = Tools:FindFirstChild(GunInstanceId)
				if not weaponTemplate then 
					Logger:Error("Weapon not found in ReplicatedStorage: " .. GunInstanceId)
					continue
				end

				local weaponClone = weaponTemplate:Clone()
				weaponClone.Parent = character
				GunEquipReplicator.AttachWeaponToCharacter(character, weaponClone)
				EquippedWeapons[Player] = weaponClone

				GunEquipReplicator.Signals.OnWeaponEquipped:Fire(Player, weaponClone, GunInstanceId)
			else
				Logger:Info("Player " .. Player.Name .. " unequipped weapon")
				GunEquipReplicator.RemoveWeaponFromCharacter(character)

				local previousId = EquippedWeapons[Player] -- you'd need to track GunInstanceId too, see note below
				EquippedWeapons[Player] = nil

				GunEquipReplicator.Signals.OnWeaponUnequipped:Fire(Player, GunInstanceId)
			end
		end
	end)

	Logger:Info("GunEquipReplicator initialized successfully")
end

--[[
	Gets or creates the singleton instance
	@return ClienntGunReplicator
]]
-- Singleton Pattern
local metatable = {__index = GunEquipReplicator}
local instance

export type GunEquipReplicator = typeof(setmetatable({}, metatable))

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
		error("Cannot modify GunEquipReplicator singleton", 2)
	end
}) :: GunEquipReplicator