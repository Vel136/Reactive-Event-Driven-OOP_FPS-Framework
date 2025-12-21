local Data = {
	Name = "M4A1",
	ID = 2,

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
		Reload = nil,
		Equip = nil,
		Unequip = nil,
		Sprint = nil,
		Aim = nil,
	},

	-- Sounds
	Sounds = {
		Fire = nil,
		Reload = nil,
		Equip = nil,
		Empty = nil,
		Aim = {
			In = nil,
			Out = nil,
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
return Data