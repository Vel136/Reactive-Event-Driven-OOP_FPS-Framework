-- Services
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local Identity = "[Weapons]"
-- Required Modules

local Configuration = require(ReplicatedStorage.SharedModules.WeaponConfigs.Configuration)
local Logger = require(ReplicatedStorage.SharedModules.Utilities.LogService)
local RunService = game:GetService('RunService')
local M9  = nil
local M4A1 = nil

if RunService:IsClient() then
	M9 = require(script.M9)
	M4A1 = require(script.M4A1)
	SCAR = require(script.SCAR)
end

local ValidWeapons = {
	M9 = M9,
	M4A1 = M4A1,
	SCAR = SCAR,
}
local module = {}

function module.GetWeaponInstance(WeaponName : string)
	if not ValidWeapons then 
		Logger.Warn("WeaponInstance doesnt exist for weapon "..WeaponName,Identity)
		return false
	end
	
	return ValidWeapons[WeaponName]
end

local WeaponDatas = Configuration.WeaponDatas
function module.GetWeaponData(WeaponName : string)
	if not WeaponDatas[WeaponName] then 
		Logger.Warn("Weapon data doesnt exist for weapon "..WeaponName,Identity)
		return false 
	end
	
	return WeaponDatas[WeaponName]
end
return module