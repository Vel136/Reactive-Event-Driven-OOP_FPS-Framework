local ReplicatedStorage = game:GetService('ReplicatedStorage')

local WeaponInstance = require(ReplicatedStorage.SharedModules.Cores.WeaponInstance)
local WeaponType = require(ReplicatedStorage.SharedModules.Cores.WeaponInstance.WeaponType)
local M9 : WeaponType.Gun = require(script.M9)
local M4A1 : WeaponType.GunData = require(script.M4A1)
local Player = game.Players.LocalPlayer

local ValidWeapons : {[string] : WeaponType.Gun} = {
	M9 = M9,
	M4A1 = M4A1
}


function GetWeaponData(WeaponName : string)
	return ValidWeapons[WeaponName]
end

return GetWeaponData