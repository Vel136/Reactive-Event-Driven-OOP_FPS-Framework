
-- Services
local TweenService = game:GetService('TweenService')
local ReplicatedStorage = game:GetService('ReplicatedStorage')

-- Required Modules
local WeaponInstance = require(ReplicatedStorage.SharedModules.Cores.WeaponInstance)
local InputController = require(ReplicatedStorage.ClientModules.Controllers.InputController)
local Configuration = require(ReplicatedStorage.SharedModules.WeaponConfigs.Configuration)
-- Cam Setups
local Camera = workspace.CurrentCamera
local CameraZoom = TweenService:Create(Camera,TweenInfo.new(.2,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{FieldOfView = 60})
local CameraShrink = TweenService:Create(Camera,TweenInfo.new(.2,Enum.EasingStyle.Quad,Enum.EasingDirection.In),{FieldOfView = 70})

-- Weapon Setup
local WeaponData = Configuration.WeaponDatas.M9
local M9 = WeaponInstance.new(WeaponData)



M9.Signals.OnEquipChanged:Connect(function(NewState)
	InputController.SetFireRate(WeaponData.FireRate)
	InputController.SetFireMode("Semi")
end)
M9.Signals.OnAimChanged:Connect(function(IsAiming)
	local Tween = IsAiming and CameraZoom or CameraShrink
	Tween:Play()
end)

function M9:_CalculateDamageClient(cast,result : RaycastResult,velocity,bullet)
	return 0
end

return M9