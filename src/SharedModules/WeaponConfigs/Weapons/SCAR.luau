-- Services
local TweenService = game:GetService('TweenService')
local ReplicatedStorage = game:GetService('ReplicatedStorage')

-- Required Modules
local WeaponInstance = require(ReplicatedStorage.ClientModules.Cores.WeaponInstance)
local InputController = require(ReplicatedStorage.ClientModules.Controllers.InputController)
local Configuration = require(ReplicatedStorage.SharedModules.WeaponConfigs.Configuration)
local ObjectCache = require(ReplicatedStorage.SharedModules.Utilities.ObjectCache)

-- Constants
local Camera = workspace.CurrentCamera
local ZOOM_FOV = 60
local DEFAULT_FOV = 70
local TWEEN_DURATION = 0.2
local ShrinkFOV = 100
local CameraZoom = TweenService:Create(
	Camera,
	TweenInfo.new(TWEEN_DURATION, Enum.EasingStyle.Linear, Enum.EasingDirection.Out),
	{FieldOfView = ZOOM_FOV}
)

local CameraNormal = TweenService:Create(
	Camera,
	TweenInfo.new(TWEEN_DURATION, Enum.EasingStyle.Linear, Enum.EasingDirection.In),
	{FieldOfView = DEFAULT_FOV}
)


-- Gun Setups
local WeaponData = Configuration.WeaponDatas.SCAR
local Gun = WeaponInstance.new(WeaponData)

-- Setup bullet cosmetics container
Gun.Ballistics.Behavior.CosmeticBulletContainer = workspace:WaitForChild('Effects')

-- Initialize tracer cache
local TRACER_POOL_SIZE = 30
local cachedTracers = ObjectCache.new(
	ReplicatedStorage.Assets.Bullets:WaitForChild('M4A1_Bullet'),
	TRACER_POOL_SIZE,
	workspace:WaitForChild('Effects')
)

-- Setup bullet provider
Gun.Ballistics.Behavior.CosmeticBulletProvider = function()
	return cachedTracers:GetPart()
end

-- Handle weapon equip state changes
Gun.Signals.OnEquipChanged:Connect(function(NewState)
	InputController.SetFireRate(WeaponData.FireRate)
	InputController.SetFireMode(Gun.Data.FireMode)
end)

-- Handle aiming state changes
Gun.Signals.OnAimChanged:Connect(function(IsAiming)
	local Tween = IsAiming and CameraZoom or CameraNormal
	Tween:Play()
end)

Gun.Signals.OnReloadComplete:Connect(function()
	CameraNormal:Play()
end)

-- Handle firing events
Gun.Signals.OnFire:Connect(function(Origin, Direction)
	if Gun.Data.Sounds and #Gun.Data.Sounds.Fire > 0 then
		local Choosen = math.random(1,#Gun.Data.Sounds.Fire)
		Gun.Data.Sounds.Fire[Choosen]:Play()
	end
	
	local Barrel = Gun.Data.BarrelAttachment
	if Barrel then
		local MuzzleFlash = Barrel:FindFirstChild("MuzzleFlash")
		MuzzleFlash:Emit(20)
		
		local Light = Barrel:FindFirstChild("Light")
		Light.Enabled = true
		
		task.delay(.1,function()
			if Light.Enabled then
				Light.Enabled = false
			end
		end)
	end
end)


-- Update bullet appearance during travel
function Gun:_OnBulletTravel(Context)
	local bullet = Context.Bullet
	if not bullet then return false end

	local bulletSize = Vector3.new(0.1, 0.1, Context.Length)
	bullet.Size = bulletSize
	bullet.CFrame = CFrame.lookAt(Context.LastPoint, Context.LastPoint + Context.Direction) 
		* CFrame.new(0, 0, -Context.Length / 2)
end

-- Clean up bullet when it terminates
function Gun:_OnBulletTerminating(Context)
	local bullet = Context.Bullet
	if bullet then
		cachedTracers:ReturnPart(bullet)
	end
end

return Gun