-- ============================================================================
-- SCAR WEAPON CONFIGURATION
-- ============================================================================
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local Assets = ReplicatedStorage.Assets

-- Asset References
local Animations = Assets.Animations.SCAR

local Model = ReplicatedStorage.Assets.Viewmodels:WaitForChild('SCAR')
local MuzzleAttachment = Model:WaitForChild('Muzzle')
-- ============================================================================
-- WEAPON DATA
-- ============================================================================
local Data = {
	-- Basic Info
	Name = "SCAR",
	ID = 3,

	-- ========================================================================
	-- DAMAGE CONFIGURATION
	-- ========================================================================
	Damage = {
		Base = 34, -- 7.62x51mm NATO round
		Multipliers = {
			Head = 2.2,
			UpperTorso = 1.0,
			LowerTorso = 0.95,
			LeftArm = 0.85,
			RightArm = 0.85,
			LeftLeg = 0.75,
			RightLeg = 0.75,
		},
		Range = {
			Min = 0,
			Max = 1000,
			Dropoff = 0.35,
		},
		Penetration = {
			Enabled = true,
			MaxCount = 1,
			LossPerWall = 0.4,
		},
	},

	-- ========================================================================
	-- FIRING CONFIGURATION
	-- ========================================================================
	FireMode = "Auto",
	FireRate = 625, -- RPM (slower than M4A1 for controllability)
	BulletSpeed = 2400,
	BulletGravity = Vector3.new(0, -workspace.Gravity, 0),
	SolverType = "Projectile",
	BurstCount = 1,
	PelletCount = 1,
	BurstDelay = 0.04,

	-- ========================================================================
	-- SPREAD CONFIGURATION
	-- ========================================================================
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

	-- ========================================================================
	-- RECOIL CONFIGURATION (Camera)
	-- ========================================================================
	Recoil = {
		CameraKick = Vector2.new(2.2, 0.8), -- Higher than M4A1
		Pattern = nil,
		ReturnSpeed = 7,
		ADSModifier = 0.55,
	},

	-- ========================================================================
	-- VIEWMODEL KICK CONFIGURATION
	-- ========================================================================
	-- Visual recoil parameters for procedural animations
	GunKick = {
		Base = {
			KickIntensity = 1.2,
			RecoverySpeed = 7.0,
			RotationRecoverySpeed = 5.5,
			KickSnapSpeed = 28.0,

			-- Rotation ranges (radians)
			Rotation = {
				X = {Min = math.rad(3.5), Max = math.rad(6.5)}, -- Vertical
				Y = {Min = math.rad(-1.2), Max = math.rad(1.2)}, -- Horizontal
				Z = {Min = math.rad(-0.6), Max = math.rad(0.6)}, -- Roll
			},

			-- Position ranges (studs)
			Position = {
				X = {Min = -0.06, Max = 0.06},
				Y = {Min = -0.04, Max = 0.04},
				Z = {Min = 0.15, Max = 0.25}, -- Backward push
			},
		},

		-- ADS multipliers
		Aiming = {
			KickIntensity = 0.1,
			RecoverySpeed = 1.2,
			RotationRecoverySpeed = 1.2,
			
			-- Rotation ranges (radians)
			Rotation = {
				X = {Min = math.rad(.05), Max = math.rad(1.3)}, -- Vertical
				Y = {Min = math.rad(.1), Max = math.rad(.5)}, -- Horizontal
				Z = {Min = math.rad(.01), Max = math.rad(.5)}, -- Roll
			},

			-- Position ranges (studs)
			Position = {
				X = {Min = -0.06, Max = 0.06},
				Y = {Min = -0.04, Max = 0.04},
				Z = {Min = 0.15, Max = 0.25}, -- Backward push
			},
		},
	},
	Sway = {
		
		Base = {
			SwaySpeed = 0.4,      -- Relaxed horizontal movement
			BreathRate = 0.35,    -- Calm breathing (~21 breaths/min)
			SwayAmplitude = 0.022 -- More movement than ADS
		},

		Aiming = {
			SwaySpeed = 0.1,      -- Very controlled
			BreathRate = 0.6,     -- Controlled breathing (~36 breaths/min)
			SwayAmplitude = 0.008 -- Minimal movement
		},
	},
	AimTime = .35,
	IdleTime = 0.45,  
	EquipTime = .25,
	SprintRecovery = 1,
	-- ========================================================================
	-- AMMO CONFIGURATION
	-- ========================================================================
	Ammo = {
		MagazineSize = 20,
		ReserveSize = 60,
		ReloadTime = 2.4,
	},

	-- ========================================================================
	-- MODELS & ATTACHMENTS
	-- ========================================================================
	Model = Model,
	BarrelAttachment = Model:WaitForChild('Muzzle'),
	AimAttachment = Model:WaitForChild('Aim'),
	ShellEjectAttachment = "Eject",

	-- ========================================================================
	-- ANIMATIONS
	-- ========================================================================
	Animations = {
		Idle = nil,
		Fire = nil,
		Reload = Animations:WaitForChild('Reload'),
		Equip = nil,
		Unequip = nil,
		Sprint = nil,
		Aim = nil,
	},

	-- ========================================================================
	-- SOUNDS
	-- ========================================================================
	Sounds = {
		Fire = MuzzleAttachment:WaitForChild('Fire'):GetChildren(),
		Reload = nil,
		Equip = nil,
		Empty = nil,
		Aim = {
			In = nil,
			Out = nil,
		},
	},
}

return Data