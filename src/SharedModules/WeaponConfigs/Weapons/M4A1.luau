local Data = {
	Name = "M4A1",
	ID = "M9_01",

	-- Basic stats
	Damage = {
		Base = 25,
		Multipliers = {
			Head = 2.0,
			UpperTorso = 1.0,
			LowerTorso = 0.9,
			LeftArm = 0.8,
			RightArm = 0.8,
			LeftLeg = 0.7,
			RightLeg = 0.7,
		},
		Range = {
			Min = 0,
			Max = 800,
			Dropoff = 0.3, -- lowest 30% damage at max range
		},
		Penetration = {
			Enabled = false,
			MaxCount = 0,
			LossPerWall = 0,
		},
	},

	FireMode = "Semi",
	FireRate = 1200, -- RPM
	BulletSpeed = 2200,
	BulletGravity = Vector3.new(0,-workspace.Gravity,0),

	Spread = {
		Base = {
			Min = 0,
			Max = 12,
			RecoveryTime = 2,
			IncreasePerShot = 2.1,
			DecreasePerSecond = .6,
		},
		Aiming = {
			Min = 0,
			Max = 12,
			RecoveryTime = 2,
			IncreasePerShot = 1.3,
			DecreasePerSecond = 1,
		},
	},

	Recoil = {
		CameraKick = Vector2.new(1.5, 0.5),
		Pattern = nil,
		ReturnSpeed = 8,
		ADSModifier = 0.5,
	},

	Ammo = {
		MagazineSize = 15,
		ReserveSize = 30,
		ReloadTime = 2.5,
	},

	-- Timing
	EquipTime = 0.6,
	AimTime = 0.25,
	SprintRecovery = 0.2,

	-- Models + Attach points
	Model = game.ReplicatedStorage.Assets.Viewmodels:WaitForChild('M4A1'),
	BarrelAttachment = "Muzzle",
	AimAttachment = "Aim",
	ShellEjectAttachment = "Eject",
	AmmoDeduction = 3,
	-- Animations (AnimationId placeholders)
	Animations = {
		Idle = nil,
		Fire = nil,
		Reload = script:WaitForChild('Anim_Reload'),
		Equip = script:WaitForChild('Anim_Equip'),
		Unequip = script:WaitForChild('Anim_Unequip'),
		Sprint = nil,
		Aim = nil,
	},

	-- Sounds
	Sounds = {
		Fire = script:WaitForChild('Fire'),
		Reload = nil,
		Equip = nil,
		Empty = script:WaitForChild('Empty'),
		Aim = {
			In = script:WaitForChild('Aim_In'),
			Out = script:WaitForChild('Aim_Out'),
		},
	},

	-- Special behavior toggles
	IsShotgun = false,
	PelletCount = 3,
	Projectile = false,

	-- Client-only cosmetic flags
	MuzzleFlashEnabled = true,
	ShellEjectEnabled = true,
}
local TweenService = game:GetService('TweenService')
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local WeaponInstance = require(ReplicatedStorage.SharedModules.Cores.WeaponInstance)
local InputController = require(ReplicatedStorage.ClientModules.Controllers.InputController)
local ObjectCache = require(ReplicatedStorage.SharedModules.Utilities.ObjectCache)
local M4A1 = WeaponInstance.new(Data)

local Camera = workspace.CurrentCamera
local CameraZoom = TweenService:Create(Camera,TweenInfo.new(.2,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{FieldOfView = 60})
local CameraShrink = TweenService:Create(Camera,TweenInfo.new(.2,Enum.EasingStyle.Quad,Enum.EasingDirection.In),{FieldOfView = 70})
M4A1.Signals.OnEquipChanged:Connect(function(NewState)
	InputController.SetFireRate(Data.FireRate)
	InputController.SetFireMode("Semi")
end)
M4A1.Signals.OnAimChanged:Connect(function(IsAiming)
	local Tween = IsAiming and CameraZoom or CameraShrink
	Tween:Play()
	
	local sound = IsAiming and Data.Sounds.Aim.In or Data.Sounds.Aim.Out
	if not sound.IsPlaying then
		sound:Play()
	end
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
	for i = 1,self.Data.PelletCount do
		local finalDir = self.SpreadController:ApplySpread(direction)
		self:FireBullet(origin, finalDir,true)
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