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
	if not Weapon then Logger.Warn("Missing Weapon",SCRIPT_NAME) return false end
	mainJanitor:Cleanup()
	
	local emptyObserver = Weapon.Signals.OnEmpty:Connect(function()
		SoundService:PlayLocalSound(Weapon.Data.Sounds.Empty)
	end)
	
	local fireConnection = Weapon.Signals.OnShoot:Connect(function()
		SoundService:PlayLocalSound(Weapon.Data.Sounds.Fire)
	end)
	
	mainJanitor:Add(emptyObserver)
end

function module.UnbindWeaponSound()
	mainJanitor:Cleanup()
end






return module
