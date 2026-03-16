-- SoundManager For FPS System
local Identity = "SoundManager"
local SoundManager = {}
SoundManager.__type = Identity

-- Services
local ReplicatedStorage = game:GetService('ReplicatedStorage')

-- References
local Utilities = ReplicatedStorage.Shared.Modules.Utilities


-- Modules
local NetworkService = require(ReplicatedStorage.Shared.Modules.Networking.NetworkService)
local SoundEffect = require(script.SoundEffect)

-- Additional Modules
local LogService = require(Utilities.Logger)

local Logger = LogService.new(Identity,false)

function SoundManager._Initialize()
	NetworkService.OnSoundSync:Connect(function(Origin, Position , Length, MaterialValue)
		if not Origin or not Position or not Length or not MaterialValue then
			
		end
		
		SoundEffect.PlaySound(Origin, Position, Length, MaterialValue)		
	end)
end

local instance
local metatable = {__index = SoundManager}
export type SoundManager = typeof(setmetatable({} , metatable))

local function GetInstance()
	if not instance then
		instance = setmetatable({}, metatable)
		instance._Initialize()
	end
	return instance
end

return setmetatable({}, {
	__index = function(_, Key)
		return GetInstance()[Key]
	end,
	__newindex = function()
		error("Cannot modify SoundManager singleton service", 2)
	end
}) :: SoundManager