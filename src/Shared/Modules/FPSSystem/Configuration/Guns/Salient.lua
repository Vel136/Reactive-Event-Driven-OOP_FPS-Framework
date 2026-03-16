-- ============================================================================
-- SALIENT WEAPON CONFIGURATION
-- ============================================================================
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local Assets = ReplicatedStorage.Assets

-- Asset References
local Animations = Assets.Animations.Salient

local Model = ReplicatedStorage.Assets.Viewmodels:WaitForChild('Salient')
local MuzzleAttachment = Model:WaitForChild('Muzzle')
-- ============================================================================
-- WEAPON DATA
-- ============================================================================
local Data = {

	-- ─── Must Fill ─────────────────────────────────────────────────────────────────
	Name = "Salient",
	ID = 4,


	-- ─── Damage ─────────────────────────────────────────────────────────────────
	
	Damage = {
		Base = 24.5, 
		Multipliers = {
			Head = 1.25,
			UpperTorso = 1.0,
			LowerTorso = 0.95,
			LeftArm = 0.85,
			RightArm = 0.85,
			LeftLeg = 0.75,
			RightLeg = 0.75,
		},
		Range = {
			Min = 0,
			Max = 800,
			Dropoff = 0.3,
		},
		Penetration = {
			Enabled = true,
			MaxCount = 1,
			LossPerWall = 0.4,
		},
	},


	-- ─── Firing ─────────────────────────────────────────────────────────────────
	
	FireMode = "Auto",
	FireRate = 650, -- RPM
	BulletSpeed = 2800,
	BulletGravity = Vector3.new(0, -workspace.Gravity, 0),
	SolverType = "Hybrid",
	BurstCount = 1,
	PelletCount = 1,
	BurstDelay = 0.04,


	-- ─── Spread ─────────────────────────────────────────────────────────────────
	Spread = {
		Base = {
			Min = 0.4,          -- Hip-fire base spread
			Max = 7.5,          -- High accuracy platform
			RecoveryTime = 0.12, -- Quick recovery
			IncreasePerShot = 1.0, -- Controlled bloom
			DecreasePerSecond = 4.5, -- Fast recovery
		},
		Aiming = {
			Min = 0,            -- Pinpoint accuracy when ADS
			Max = 0,            -- No spread in ADS
			RecoveryTime = 0,   -- Instant
			IncreasePerShot = 0, -- No bloom
			DecreasePerSecond = 0, -- Not needed
		},
	},


	-- ─── State  ─────────────────────────────────────────────────────────────────
	
	AimTime = .35,
	IdleTime = 1.25,  
	EquipTime = 0.22,
	SprintRecovery = 0.9,


	-- ─── Ammo ─────────────────────────────────────────────────────────────────
	
	Ammo = {
		MagazineSize = 30,
		ReserveSize = 90,
		ReloadTime = 2.25,
		ReloadEmptyTime = 2.4,
	},


	-- ─── Model  & Attachment  ─────────────────────────────────────────────────────────────────
	Model = Model,
	BarrelAttachment = Model:WaitForChild('Muzzle'),
	AimAttachment = Model:WaitForChild('Aim'),
	ShellEjectAttachment = Model:WaitForChild('ShellEjectPoint'),
	
	ScopeGUI = Model:WaitForChild('ScopeF'):WaitForChild('ScopeGui'),
	SpotLight = Model:WaitForChild('SpotLight'):WaitForChild('SpotLight'),

	-- ─── Animations ─────────────────────────────────────────────────────────────────
	
	Animations = {
		Idle = nil,
		Fire = Animations:WaitForChild('Fire'),
		Reload = Animations:WaitForChild('Reload'),
		EmptyReload = nil,
		Equip = nil,
		Unequip = nil,
		Sprint = nil,
		Aim = nil,
	},


	-- ─── Sounds ─────────────────────────────────────────────────────────────────
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
	

	-- ─── Additional Attributes ─────────────────────────────────────────────────────────────────
	AutoEjectShells = true,
}

return Data