local module = {}
module.__index = module

local ReplicatedStorage = game:GetService('ReplicatedStorage')
local Signal = require(ReplicatedStorage.Shared.Modules.Utilities.Signal)
local ClientBlink = require(script.Parent.Blink.Client)

-- Outgoing client requests
module.FireWeapon = ClientBlink.FireWeapon.Fire
module.ReloadWeapon = ClientBlink.ReloadWeapon.Fire

module.ChangeStateWeapon = ClientBlink.ChangeStateWeapon.Fire

-- Incoming server events
module.OnSyncEventState = Signal.new()
module.OnSoundSync = Signal.new()

module.OnEquipReplicated = Signal.new()

ClientBlink.ReplicateEquipWeapon.On(function(...)
	module.OnEquipReplicated:Fire(...)
end)

ClientBlink.SyncEventState.On(function(...)
	module.OnSyncEventState:Fire(...)
end)

ClientBlink.FireSound.On(function(...)
	module.OnSoundSync:Fire(...)
end)

return module