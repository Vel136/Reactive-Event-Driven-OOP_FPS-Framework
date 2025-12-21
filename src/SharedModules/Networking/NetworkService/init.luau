--[=[
	@class NetworkService
	Singleton wrapper around NetRay for weapon framework networking.
	Provides abstraction and type-safe event handling.
]=]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local Signal = require(ReplicatedStorage.SharedModules.Utilities.Signal)
local Logger = require(ReplicatedStorage.SharedModules.Utilities.LogService) -- Adjust path as needed
local Identity = "[NetworkService]"

local module = {}
module.__index = module
local instance

--[[
	Gets or creates the singleton instance
]]
local function GetInstance()
	if not instance then
		instance = setmetatable({}, module)
		instance:_Initialize()
	end
	return instance
end
local IsServer = RunService:IsServer()

local Blink 
if not IsServer then
	Blink = require(script.Blink.Client)
else
	Blink = require(script.Blink.Server)
end

function module:_Initialize()
	if not IsServer then
		function module.FireWeapon(...)
			Blink.FireWeapon.Fire(...)
		end
		
		function module.ReloadWeapon(...)
			Blink.ReloadWeapon.Fire(...)
		end
		
		function module.ChangeStateWeapon(...)
			Blink.ChangeStateWeapon.Fire(...)
		end
	else
		module.OnWeaponStateChanged = Signal.new()
		module.OnWeaponFired = Signal.new()
		module.OnWeaponReload = Signal.new()
		Blink.FireWeapon.On(function(Player,...)
			module.OnWeaponFired:Fire(Player,...)
		end)
		
		function module.RegisterWeapon(Player,...)
			Blink.RegisterWeapon.Fire(Player,...)
		end
		
		Blink.ChangeStateWeapon.On(function(Player,...)
			module.OnWeaponStateChanged:Fire(Player,...)
		end)
		Blink.ReloadWeapon.On(function(Player,...)
			module.OnWeaponReload:Fire(Player,...)
		end)
	end
end



-- Singleton pattern
return setmetatable({}, {
	__index = function(_, key)
		return GetInstance()[key]
	end,
	__newindex = function()
		error("Cannot modify singleton service", Identity)
	end
})