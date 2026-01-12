
-- Services
local TweenService = game:GetService('TweenService')
local ReplicatedStorage = game:GetService('ReplicatedStorage')

-- Required Modules
local WeaponInstance = require(ReplicatedStorage.ClientModules.Cores.WeaponInstance)
local InputController = require(ReplicatedStorage.ClientModules.Controllers.InputController)
local Configuration = require(ReplicatedStorage.SharedModules.WeaponConfigs.Configuration)
local ObjectCache = require(ReplicatedStorage.SharedModules.Utilities.ObjectCache)

-- Cam Setups
local Camera = workspace.CurrentCamera
local CameraZoom = TweenService:Create(Camera,TweenInfo.new(.2,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{FieldOfView = 60})
local CameraShrink = TweenService:Create(Camera,TweenInfo.new(.2,Enum.EasingStyle.Quad,Enum.EasingDirection.In),{FieldOfView = 70})

-- Weapon Setup
local WeaponData = Configuration.WeaponDatas.M9
local M9 = WeaponInstance.new(WeaponData)

M9.Ballistics.Behavior.CosmeticBulletContainer = workspace:WaitForChild('Effects')
local cachedTracers = ObjectCache.new(ReplicatedStorage.Assets.Bullets:WaitForChild('M4A1_Bullet'),30,workspace:WaitForChild('Effects'))
M9.Ballistics.Behavior.CosmeticBulletProvider = function()
	return cachedTracers:GetPart()
end
M9.Signals.OnEquipChanged:Connect(function(NewState)
	InputController.SetFireRate(WeaponData.FireRate)
	InputController.SetFireMode(M9.Data.FireMode)
end)
M9.Signals.OnAimChanged:Connect(function(IsAiming)
	local Tween = IsAiming and CameraZoom or CameraShrink
	Tween:Play()
end)

function M9:_OnBulletTravel(Context)
	local bullet = Context.Bullet
	if not bullet then return false end
	bullet.Size = Vector3.new(0.1, 0.1, Context.Length)

	bullet.Size = Vector3.new(0.1, 0.1, Context.Length)
	bullet.CFrame = CFrame.lookAt(Context.LastPoint, Context.LastPoint + Context.Direction) * CFrame.new(0, 0, -Context.Length / 2)
end

function M9:_OnBulletTerminating(Context)
	local bullet = Context.Bullet
	
	if bullet then
		cachedTracers:ReturnPart(bullet)
	end
end
M9.Signals.OnFire:Connect(function(Origin,Direction)
	if M9.Data.Sounds.Fire then
		M9.Data.Sounds.Fire:Play()
	end
end)
function M9:_CalculateDamageClient(cast,result : RaycastResult,velocity,bullet)
	return 0
end

return M9