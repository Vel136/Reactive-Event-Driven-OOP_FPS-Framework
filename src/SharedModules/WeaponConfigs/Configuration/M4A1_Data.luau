local ReplicatedStorage = game:GetService('ReplicatedStorage')
local Assets = ReplicatedStorage.Assets
local Animations = Assets.Animations.M4A1
local Sounds = Assets.Sounds.M4A1
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

	FireMode = "Auto",
	FireRate = 857, -- RPM
	BulletSpeed = 2200,
	BulletGravity = Vector3.new(0,-workspace.Gravity,0),

	Spread = {
		Base = {
			Min = 0.5,          -- Hip-fire always has some spread
			Max = 8,            -- M4A1 is accurate even from hip
			RecoveryTime = 0.15, -- Quick recovery between bursts
			IncreasePerShot = 1.2, -- Controlled bloom
			DecreasePerSecond = 4.0, -- Fast recovery (controllable weapon)
		},
		Aiming = {
			Min = 0.1,          -- Near-pinpoint accuracy when ADS
			Max = 2.5,          -- Stays tight even during full-auto
			RecoveryTime = 0.1,  -- Very quick recovery
			IncreasePerShot = 0.2, -- Minimal bloom per shot
			DecreasePerSecond = 3.0, -- Quick recovery
		},
	},
	SolverType = "Hitscan",
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

	-- Animations (AnimationId placeholders)
	Animations = {
		Idle = nil,
		Fire = Animations:WaitForChild('Fire'),
		Reload = Animations:WaitForChild('Reload'),
		Equip = nil,
		Unequip = nil,
		Sprint = nil,
		Aim = nil,
	},

	-- Sounds
	Sounds = {
		Fire = Sounds:WaitForChild('Fire'),
		Reload = nil,
		Equip = nil,
		Empty = nil,
		Aim = {
			In = nil,
			Out = nil,
		},
	},

	-- Special Behaviors
	BurstCount = 1,
	PelletCount = 1,
	BurstDelay = .04,

	-- Client Behaviors 
	
	-- Viewmodel Kick
}
return Data