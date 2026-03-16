-- HitboxService.lua
--[[
	You register your hitbox, here, perhaps multiplier also?
	Each of the hitbox name you add, are captured to snapshot for lag compensation
]]
-- Services
local ServerStorage = game:GetService('ServerStorage')
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local Players = game:GetService('Players')
local Identity = "[HitboxService]"
-- Required Modules
local Signal = require(ReplicatedStorage.Shared.Modules.Utilities.Signal)
local t = require(ReplicatedStorage.Shared.Modules.Utilities.TypeCheck)
local Logger = require(ReplicatedStorage.Shared.Modules.Utilities.LogService)

local module = {}
module.__index = module
export type Hitboxes = {
	[string] : boolean,
}

function module:_Initialize()
	-- We track and save players registered hitboxes
	self._players = {}
	
	Players.PlayerAdded:Connect(function(Player)
		self._players[Player] = {}
		self:RegisterHitbox(Player,"HumanoidRootPart")
	end)
	Players.PlayerRemoving:Connect(function(Player)
		self._players[Player] = nil
	end)
end

function module:RegisterHitbox(Player,HitboxName)
	if not self._players[Player] or not Player:IsA('Player') then Logger:Warn('Invalid Param for player',Identity) return false end
	
	if self._players[Player][HitboxName] then Logger:Warn("Hitbox already registed for player "..Player.Name,Identity) return false end
	
	self._players[Player][HitboxName] = true
end

function module:UnregisterHitbox(Player,HitboxName)
	if not self._players[Player] or not Player:IsA('Player') then Logger:Warn('Invalid Param for player',Identity) return false end
	
	self._players[Player][HitboxName] = nil
end
function module:GetHitboxes(Player)
	if not self._players[Player] or not Player:IsA('Player') then Logger:Warn('Invalid Param for player',Identity) return false end
	
	return self._players[Player]
end
function module:UnregisterAll(Player)
	if not self._players[Player] or not Player:IsA('Player') then Logger:Warn('Invalid Param for player',Identity) return false end
	
end

local instance
local function GetInstance()
	if not instance then
		instance = setmetatable({}, module)
		instance:_Initialize()
	end
	return instance
end
GetInstance()
-- Singleton pattern
return setmetatable({}, {
	__index = function(_, key)
		return GetInstance()[key]
	end,
	__newindex = function()
		error("Cannot modify singleton service", Identity)
	end
})
