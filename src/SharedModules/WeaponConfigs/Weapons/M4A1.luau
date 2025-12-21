-- Services
local TweenService = game:GetService('TweenService')
local ReplicatedStorage = game:GetService('ReplicatedStorage')

local WeaponInstance = require(ReplicatedStorage.SharedModules.Cores.WeaponInstance)
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
	InputController.SetFireMode("Semi")
end)

local cachedTracers = ObjectCache.new(ReplicatedStorage.Assets.Bullets:WaitForChild('M4A1_Bullet'),30,workspace:WaitForChild('Effects'))

M4A1.Ballistics.Behavior.CosmeticBulletProvider = cachedTracers

function M4A1:_OnBulletTravel(Context)
	-- Create tracer for this segment
	local bullet = Context.Bullet
	bullet.Size = Vector3.new(0.1, 0.1, Context.Length)
	bullet.CFrame = CFrame.lookAt(Context.LastPoint, Context.LastPoint + Context.Direction) * CFrame.new(0, 0, -Context.Length / 2)
end
function M4A1:_FireInternal(origin: Vector3, direction: Vector3)

    for i = 1, WeaponData.PelletCount do
        local finalDir = self.SpreadController:ApplySpread(direction)
		self:FireBullet(origin, finalDir, true)
		task.wait(.04)
    end
 
    return true
end
function M4A1:_OnBulletTerminating(Context)
	local bullet = Context.Bullet

	cachedTracers:ReturnPart(bullet)
end
function M4A1:_CalculateDamageClient(cast,result : RaycastResult,velocity,bullet)
	return 0
end

return M4A1