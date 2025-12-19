-- WeaponSounds.lua
local module = {}

local SCRIPT_NAME = "WeaponSounds"
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local SoundService = game:GetService('SoundService')

local WeaponType = require(ReplicatedStorage.SharedModules.Cores.WeaponInstance.WeaponType)
local Observer = require(ReplicatedStorage.SharedModules.Utilities.Observer)
local Janitor = require(ReplicatedStorage.SharedModules.Utilities.Janitor)
local Logger = require(ReplicatedStorage.SharedModules.Utilities.LogService)

local mainJanitor = Janitor.new()

function module.BindWeaponSound(Weapon : WeaponType.Gun)
	
end

function module.UnbindWeaponSound()
	mainJanitor:Cleanup()
end






return module
