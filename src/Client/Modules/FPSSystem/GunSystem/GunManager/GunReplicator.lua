-- GunReplicator.lua
local Identity = "GunReplicator"
local GunReplicator = {}
GunReplicator.__type = Identity

-- Services
local ReplicatedStorage = game:GetService('ReplicatedStorage')

-- References

local Utilities = ReplicatedStorage.Shared.Modules.Utilities

-- Modules
local GunManager = require(script.Parent)


-- Additional Modules
local LogService = require(Utilities.Logger)
local NetworkService = require(ReplicatedStorage.Shared.Modules.Networking.NetworkService)

local Logger = LogService.new(Identity, false)

-- Configurations
local Configuration = require(ReplicatedStorage.Shared.Modules.FPSSystem.Configuration.Configuration)
local States = Configuration.WeaponStates

function GunReplicator._Initialize()
	-- Hook Signals
	GunManager.Signals.OnWeaponCreation:Connect(function(GunInstance, GunInstanceId)
		if not GunInstance then
			Logger:Warn('No GunInstance Provided to be hooked')
			return false
		end
		
		GunInstance._Janitor:Add(GunInstance.Signals.OnPreFire:Connect(function(FireData)
			NetworkService.FireWeapon(GunInstanceId,FireData)
		end),"Disconnect")

		GunInstance._Janitor:Add(GunInstance.Signals.OnReloadStarted:Connect(function()
			NetworkService.ReloadWeapon(GunInstanceId)
		end),"Disconnect")

		GunInstance._Janitor:Add(GunInstance.Signals.OnAimChanged:Connect(function(IsAiming)
			if not NetworkService.ChangeStateWeapon then Logger:Warn("ChangeStateWeapon doesnt exist in NetworkService") return false end
			NetworkService.ChangeStateWeapon(GunInstanceId,States.Aim,IsAiming)
		end),"Disconnect")

		GunInstance._Janitor:Add(GunInstance.Signals.OnEquipChanged:Connect(function(IsEquip)
			if not NetworkService.ChangeStateWeapon then Logger:Warn("ChangeStateWeapon doesnt exist in NetworkService") return false end
			NetworkService.ChangeStateWeapon(GunInstanceId,States.Equip,IsEquip)
		end),"Disconnect")
	end)
	
	local ActiveGuns = GunManager.GetActiveGuns()
	
	for GunInstanceId, GunInstance in pairs(ActiveGuns) do
		GunInstance._Janitor:Add(GunInstance.Signals.OnPreFire:Connect(function(FireData)
			NetworkService.FireWeapon(GunInstanceId,FireData)
		end),"Disconnect")

		GunInstance._Janitor:Add(GunInstance.Signals.OnReloadStarted:Connect(function()
			NetworkService.ReloadWeapon(GunInstanceId)
		end),"Disconnect")

		GunInstance._Janitor:Add(GunInstance.Signals.OnAimChanged:Connect(function(IsAiming)
			if not NetworkService.ChangeStateWeapon then Logger:Warn("ChangeStateWeapon doesnt exist in NetworkService") return false end
			NetworkService.ChangeStateWeapon(GunInstanceId,States.Aim,IsAiming)
		end),"Disconnect")

		GunInstance._Janitor:Add(GunInstance.Signals.OnEquipChanged:Connect(function(IsEquip)
			if not NetworkService.ChangeStateWeapon then Logger:Warn("ChangeStateWeapon doesnt exist in NetworkService") return false end
			NetworkService.ChangeStateWeapon(GunInstanceId,States.Equip,IsEquip)
		end),"Disconnect")
	end
	
	Logger:Debug("GunReplicator Initialized")
	return true
end


local instance

local metatable = {__index = GunReplicator}
local function GetInstance()
	if not instance then
		instance = setmetatable({}, metatable)
		instance:_Initialize()
	end
	return instance
end

export type GunReplicator = typeof(setmetatable({}, metatable))
-- Export as singleton with read-only access
return setmetatable({}, {
	__index = function(_, key)
		return GetInstance()[key]
	end,
	__newindex = function()
		error("Cannot modify GunReplicator singleton", 2)
	end
}) :: GunReplicator
