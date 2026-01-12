-- Services
local TweenService = game:GetService('TweenService')
local ReplicatedStorage = game:GetService('ReplicatedStorage')

local WeaponInstance = require(ReplicatedStorage.ClientModules.Cores.WeaponInstance)
local InputController = require(ReplicatedStorage.ClientModules.Controllers.InputController)
local ObjectCache = require(ReplicatedStorage.SharedModules.Utilities.ObjectCache)


-- References
local Configuration = require(ReplicatedStorage.SharedModules.WeaponConfigs.Configuration)
local Camera = workspace.CurrentCamera
-- Tweens Setup
local CameraZoom = TweenService:Create(Camera,TweenInfo.new(.2,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{FieldOfView = 60})
local CameraShrink = TweenService:Create(Camera,TweenInfo.new(.2,Enum.EasingStyle.Quad,Enum.EasingDirection.In),{FieldOfView = 70})

-- Weapon Setup
local WeaponData = Configuration.WeaponDatas.M4A1
local M4A1 = WeaponInstance.new(WeaponData)

M4A1.Signals.OnEquipChanged:Connect(function(NewState)
	InputController.SetFireRate(WeaponData.FireRate)
	InputController.SetFireMode(WeaponData.FireMode)
end)
M4A1.Ballistics.Behavior.CosmeticBulletContainer = workspace:WaitForChild('Effects')
local cachedTracers = ObjectCache.new(ReplicatedStorage.Assets.Bullets:WaitForChild('M4A1_Bullet'),30,workspace:WaitForChild('Effects'))

M4A1.Ballistics.Behavior.CosmeticBulletProvider = function()
	return cachedTracers:GetPart()
end

function M4A1:_OnBulletTravel(Context)
	local bullet = Context.Bullet
	if not bullet then return false end
	
	bullet.Size = Vector3.new(0.1, 0.1, Context.Length)

	bullet.Size = Vector3.new(0.1, 0.1, Context.Length)
	bullet.CFrame = CFrame.lookAt(Context.LastPoint, Context.LastPoint + Context.Direction) * CFrame.new(0, 0, -Context.Length / 2)
end
M4A1.Signals.OnFire:Connect(function(Origin,Direction)
	if M4A1.Data.Sounds.Fire then
		M4A1.Data.Sounds.Fire:Play()
	end
end)
function M4A1:_OnBulletTerminating(Context)
	local bullet = Context.Bullet
	if not bullet then return false end
	
	cachedTracers:ReturnPart(bullet)
end
function M4A1:_CalculateDamageClient(cast,result : RaycastResult,velocity,bullet)
	return 0
end

return M4A1