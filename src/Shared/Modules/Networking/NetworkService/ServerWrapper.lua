local module = {}
module.__index = module

local ReplicatedStorage = game:GetService('ReplicatedStorage')
local Signal = require(ReplicatedStorage.Shared.Modules.Utilities.Signal)
local ServerBlink = require(script.Parent.Blink.Server)

-- Outgoing server events
module.SyncEventState = ServerBlink.SyncEventState.Fire
module.SyncSound = ServerBlink.FireSound.FireAll
module.RegisterWeapon = ServerBlink.RegisterWeapon.Fire
module.ReplicateGunEquip = ServerBlink.ReplicateEquipWeapon.FireExcept
module.ReplicateGunEquipForClient = ServerBlink.ReplicateEquipWeapon.Fire
-- Incoming client events
module.OnWeaponStateChanged = Signal.new()
module.OnWeaponFired = Signal.new()
module.OnWeaponReload = Signal.new()

ServerBlink.FireWeapon.On(function(Player, ...)
	module.OnWeaponFired:Fire(Player, ...)
end)

ServerBlink.ChangeStateWeapon.On(function(Player, ...)
	module.OnWeaponStateChanged:Fire(Player, ...)
end)

ServerBlink.ReloadWeapon.On(function(Player, ...)
	module.OnWeaponReload:Fire(Player, ...)
end)

return module