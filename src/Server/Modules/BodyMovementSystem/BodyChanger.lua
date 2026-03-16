-- BodyChanger

--[[
	Change Characters body to blocky by default
]]

local Identity = "BodyChanger"
local BodyChanger = {}
BodyChanger.__type = Identity

-- Services
local Players = game.Players


function BodyChanger.ChangeBodyType(Character : Model)
	local Humanoid = Character:WaitForChild("Humanoid")
	local CurrentDescription = Humanoid:GetAppliedDescription()

	CurrentDescription.Head = 0
	CurrentDescription.Torso = 0
	CurrentDescription.LeftArm = 0
	CurrentDescription.RightArm = 0
	CurrentDescription.LeftLeg = 0
	CurrentDescription.RightLeg = 0
	Humanoid:ApplyDescription(CurrentDescription)	
	
	return Humanoid
end

function BodyChanger._Initialize()
	local ExistingPlayers = Players:GetPlayers()
	local Count = #ExistingPlayers
	
	local Connections = {}
	
	for i = 1, Count do
		local Player = ExistingPlayers[i]
		local Character = Player.Character 
		
		if Character then
			BodyChanger.ChangeBodyType(Character)
		end
		
		local Connection = Player.CharacterAdded:Connect(function(UpdatedCharacter)
			BodyChanger.ChangeBodyType(UpdatedCharacter)		
		end)
		Connections[Player] = Connection
	end
	
	
	Players.PlayerAdded:Connect(function(PlayerJoined)
		local Connection = PlayerJoined.CharacterAdded:Connect(function(UpdatedCharacter)
			BodyChanger.ChangeBodyType(UpdatedCharacter)		
		end)
		Connections[PlayerJoined] = Connection
	end)
	
	Players.PlayerRemoving:Connect(function(PlayerLeft)
		if Connections[PlayerLeft] then
			Connections[PlayerLeft]:Disconnect()
		end
	end)
end



--[[
	Gets or creates the singleton instance
	@return BodyChanger
]]
-- Singleton Pattern
local metatable = {__index = BodyChanger}

local instance

export type BodyChanger = typeof(setmetatable({}, metatable))
local function GetInstance()
	if not instance then
		instance = setmetatable({}, metatable)
		instance:_Initialize()
	end
	return instance
end

-- Export as singleton with read-only access
return setmetatable({}, {
	__index = function(_, key)
		return GetInstance()[key]
	end,
	__newindex = function()
		error("Cannot modify BodyChanger singleton", 2)
	end
}) :: BodyChanger

