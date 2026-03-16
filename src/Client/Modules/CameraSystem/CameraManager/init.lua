-- CameraManager.lua

local Identity = "CameraManager"
local CameraManager = {}
CameraManager.__type = Identity

-- Services
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local RunService = game:GetService('RunService')

-- References
local Player = game.Players.LocalPlayer
local Character = Player.Character or Player.CharacterAdded:Wait()
local HumanoidRootPart = Character:WaitForChild('HumanoidRootPart')
local Humanoid = Character:WaitForChild('Humanoid')
-- Modules
local CameraBobbing = require(script.CameraBobbing)
local MotionBlur = require(script.MotionBlur)



function CameraManager._Initialize()

	local MotionBlurEffect = MotionBlur.new({
		BlurMultiplier = 3.5,
		MaxBlur = 50,
	})
		
	local CameraBobbingEffect = CameraBobbing.new(
		{
			VerticalFrequency = 10,       -- How fast the head bobs up and down
			VerticalIntensity = 0.05,     -- How much the camera moves vertically

			-- Horizontal Bobbing (Side-to-Side Motion)
			HorizontalFrequency = 8,      -- How fast the head sways left and right
			HorizontalIntensity = 0.03,   -- How much the camera moves horizontally

			-- Velocity Settings
			VelocityMultiplier = 100,     -- Scales bobbing based on movement speed
			VelocitySmoothness = 0.2,     -- How smoothly velocity changes affect bobbing (0-1)
			UseWalkSpeedScale = true,
			BaseWalkSpeed = 16,           -- Reference WalkSpeed for default bobbing (default Roblox WalkSpeed)
		},
		HumanoidRootPart,
		Humanoid
	)
	
	Player.CharacterAdded:Connect(function(Character)
		local HumanoidRootPart = Character:WaitForChild("HumanoidRootPart")
		CameraBobbingEffect:SetHumanoidRootPart(HumanoidRootPart)
		local Humanoid = Character:WaitForChild("Humanoid")
		CameraBobbingEffect:SetHumanoid(Humanoid)
	end)
	
	RunService.RenderStepped:Connect(function(deltatime)
		CameraBobbingEffect:Update(deltatime)
		MotionBlurEffect:Update(deltatime)
	end)
end



local metatable = {__index = CameraManager}
local instance
--[[
	Gets or creates the singleton instance
	@return GlobalMovementHandler
]]
local function GetInstance()
	if not instance then
		instance = setmetatable({}, metatable)
		instance:_Initialize()
	end
	return instance
end

export type CameraManager = typeof(setmetatable({}, metatable))

-- Export as singleton with read-only access
return setmetatable({}, {
	__index = function(_, key)
		return GetInstance()[key]
	end,
	__newindex = function()
		error("Cannot modify GlobalMovementHandler singleton", 2)
	end
}) :: CameraManager

