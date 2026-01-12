-- WeaponSyncTypes.lua
-- Place in ReplicatedStorage.SharedModules
--[[
    Centralized sync type constants for weapon networking
    Ensures server and client use identical sync codes
]]

local SyncTypes = {
	Ammo = 1,
	Reserve = 2,
	Spread = 3,
	ShotIndex = 4,
	Sound = 5,
}

-- Reverse lookup for debugging
local SyncTypeNames = {}
for name, id in pairs(SyncTypes) do
	SyncTypeNames[id] = name
end

-- Helper function to get readable name from ID
function SyncTypes.GetName(syncId: number): string?
	return SyncTypeNames[syncId]
end

-- Validation helper
function SyncTypes.IsValid(syncId: number): boolean
	return SyncTypeNames[syncId] ~= nil
end

return SyncTypes