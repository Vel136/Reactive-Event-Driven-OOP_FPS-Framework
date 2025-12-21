-- Services
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local Identity = "[Weapons]"
-- Required Modules
local WeaponType = require(ReplicatedStorage.SharedModules.Cores.WeaponInstance.WeaponType)
local Configuration = require(ReplicatedStorage.SharedModules.WeaponConfigs.Configuration)
local Logger = require(ReplicatedStorage.SharedModules.Utilities.LogService)

local M9 : WeaponType.Gun = require(script.M9)
local M4A1 : WeaponType.GunData = require(script.M4A1)

local ValidWeapons = {
	M9 = M9,
	M4A1 = M4A1
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