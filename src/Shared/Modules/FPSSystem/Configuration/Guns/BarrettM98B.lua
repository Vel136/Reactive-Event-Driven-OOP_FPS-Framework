-- ============================================================================
-- BARRETT M98B CONFIGURATION
-- ============================================================================
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local Assets = ReplicatedStorage.Assets
local Animations = Assets.Animations.BarrettM98B
local Model = ReplicatedStorage.Assets.Viewmodels:WaitForChild('BarrettM98B')
local MuzzleAttachment = Model:WaitForChild('Muzzle')

local Data = {
	-- Basic Info
	Name = "BarrettM98B",
	ID = 5,

	-- ========================================================================
	-- DAMAGE CONFIGURATION
	-- ========================================================================
	Damage = {
		Base = 95, -- .338 Lapua Magnum - devastating long-range power
		Multipliers = {
			Head = 2.5, -- One-shot kill to head at almost any range
			UpperTorso = 1.4,
			LowerTorso = 1.2,
			LeftArm = 0.9,
			RightArm = 0.9,
			LeftLeg = 0.85,
			RightLeg = 0.85,
		},
		Range = {
			Min = 0,
			Max = 3500, -- Effective range up to 1500+ meters in reality
			Dropoff = 0.15, -- Minimal damage dropoff due to high ballistic coefficient
		},
		Penetration = {
			Enabled = true,
			MaxCount = 3, -- Can penetrate multiple targets/walls
			LossPerWall = 0.25, -- Excellent penetration
		},
	},

	-- ========================================================================
	-- FIRING CONFIGURATION
	-- ========================================================================
	FireMode = "Semi", -- Bolt-action
	FireRate = 80, -- RPM (bolt-action)
	BulletSpeed = 3200, -- Studs/sec (.338 Lapua has ~915 m/s muzzle velocity)
	BulletGravity = Vector3.new(0, -workspace.Gravity * 0.85, 0), -- Less affected by gravity
	SolverType = "Hitscan",
	BurstCount = 1,
	PelletCount = 1,
	BurstDelay = 0,

	-- ========================================================================
	-- SPREAD CONFIGURATION
	-- ========================================================================
	Spread = {
		Base = {
			Min = 2.5, -- High spread when hip-firing
			Max = 15.0, -- Very inaccurate from hip
			RecoveryTime = 0.5,
			IncreasePerShot = 3.0,
			DecreasePerSecond = 2.0,
		},
		Aiming = {
			Min = 0, -- Surgical precision when scoped
			Max = 0.05, -- Minimal bloom
			RecoveryTime = 0.01,
			IncreasePerShot = 0.02, -- Virtually no bloom
			DecreasePerSecond = 10.0,
		},
	},

	AimTime = 0.55, -- Slower to scope in due to weight
	IdleTime = 0.5,
	EquipTime = 0.65, -- Heavy weapon, slow to equip
	SprintRecovery = 1.5, -- Significant sprint-to-fire penalty

	-- ========================================================================
	-- AMMO CONFIGURATION
	-- ========================================================================
	Ammo = {
		MagazineSize = 10, -- Standard 10-round detachable box magazine
		ReserveSize = 30, -- Limited reserve ammo
		ReloadTime = 3.2, -- Slower reload due to weight
		ReloadEmptyTime = 3.8, -- Even slower when completely empty
	},

	-- ========================================================================
	-- MOVEMENT PENALTIES
	-- ========================================================================
	Movement = {
		WalkSpeedMultiplier = 0.75, -- 25% slower movement
		SprintSpeedMultiplier = 0.8, -- 20% slower sprint
	},

	-- ========================================================================
	-- MODELS & ATTACHMENTS
	-- ========================================================================
	Model = Model,
	BarrelAttachment = Model:WaitForChild('Muzzle'),
	AimAttachment = Model:WaitForChild('Aim'),
	ShellEjectAttachment = Model:WaitForChild('ShellEjectPoint'),
	-- ========================================================================
	-- ANIMATIONS
	-- ========================================================================
	Animations = {
		Idle = Animations:WaitForChild('Idle'),
		Fire = Animations:WaitForChild('Fire'),
		BoltActionController = Animations:WaitForChild('BoltCycling'), -- Bolt cycling animation
		Reload = Animations:WaitForChild('Reload'),
		EmptyReload = nil,
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
		BoltActionController = nil, -- Bolt cycling sound
		Reload = nil,
		Equip = nil,
		Empty = nil,
		Aim = {
			In = nil,
			Out = nil,
		},
	},
	
	AutoEjectShells = false,
}

return Data