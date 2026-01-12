local ReplicatedStorage = game:GetService('ReplicatedStorage')
local Assets = ReplicatedStorage.Assets
local Animations = Assets.Animations.M9
local Sounds = Assets.Sounds.M9
local Data = {
	Name = "M9",
	ID = 1,

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
	BulletSpeed = 1200,
	BulletGravity = Vector3.new(0, -workspace.Gravity, 0),
	SolverType = "Hitscan",
	Spread = {
		Base = {
			Min = 0.5, 
			Max = 8,
			RecoveryTime = 0.15, 
			IncreasePerShot = 1.2, 
			DecreasePerSecond = 4.0,
		},
		Aiming = {
			Min = 0.1, 
			Max = 4, 
			RecoveryTime = 0.1, 
			IncreasePerShot = 0.6,
			DecreasePerSecond = 5.0, 
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

	-- Animations (AnimationId placeholders)
	Animations = {
		Idle = nil,
		Fire = Animations:WaitForChild('Fire'),
		Reload = Animations:WaitForChild('Reload'),
		Equip = nil,
		Sprint = nil,
		Aim = nil,
	},

	-- Sounds
	Sounds = {
		Fire = Sounds:WaitForChild('Fire'),
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

return Data