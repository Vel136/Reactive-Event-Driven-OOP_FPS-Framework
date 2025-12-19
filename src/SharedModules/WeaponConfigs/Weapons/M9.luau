local Data = {
	Name = "M9",
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
			Max = 100,
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
	BulletSpeed = 1200,
	BulletGravity = Vector3.new(0, -workspace.Gravity, 0),

	Spread = {
		Base = {
			Min = 0,
			Max = 3,
			RecoveryTime = 2,
			IncreasePerShot = 0.6,
			DecreasePerSecond = 1.0,
		},
		Aiming = {
			Min = 0,
			Max = 2,
			RecoveryTime = 2,
			IncreasePerShot = 0.3,
			DecreasePerSecond = 1.0,
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
		ReloadTime = 2.1,
	},

	-- Timing
	EquipTime = 0.6,
	AimTime = 0.25,
	SprintRecovery = 0.2,

	-- Models + Attach points
	Model = game.ReplicatedStorage.Assets.Viewmodels:WaitForChild('M9'),
	BarrelAttachment = "Muzzle",
	AimAttachment = "Aim",
	ShellEjectAttachment = "Eject",
	AmmoDeduction = 1,
	-- Animations (AnimationId placeholders)
	Animations = {
		Idle = nil,
		Fire = nil,
		Reload = nil,
		Equip = nil,
		Sprint = nil,
		Aim = nil,
	},

	-- Sounds
	Sounds = {
		Fire = nil,
		Reload = nil,
		Equip = nil,
		Empty = nil,
	},

	-- Special behavior toggles
	IsShotgun = false,
	PelletCount = nil,
	Projectile = false,

	-- Client-only cosmetic flags
	MuzzleFlashEnabled = true,
	ShellEjectEnabled = true,
}
local TweenService = game:GetService('TweenService')
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local WeaponInstance = require(ReplicatedStorage.SharedModules.Cores.WeaponInstance)
local InputController = require(ReplicatedStorage.ClientModules.Controllers.InputController)
local M9 = WeaponInstance.new(Data)

local Camera = workspace.CurrentCamera
local CameraZoom = TweenService:Create(Camera,TweenInfo.new(.2,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{FieldOfView = 60})
local CameraShrink = TweenService:Create(Camera,TweenInfo.new(.2,Enum.EasingStyle.Quad,Enum.EasingDirection.In),{FieldOfView = 70})
M9.Signals.OnEquipChanged:Connect(function(NewState)
	InputController.SetFireRate(Data.FireRate)
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