-- ============================================================================
-- M67 FRAGMENTATION GRENADE CONFIGURATION
-- ============================================================================
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Assets = ReplicatedStorage.Assets

-- Asset References
local Model      = ReplicatedStorage.Assets.Viewmodels:WaitForChild("M67")
local Sounds     = ReplicatedStorage.Assets.Sounds:WaitForChild('M67')
local Animations = ReplicatedStorage.Assets.Animations:WaitForChild('M67')
-- ============================================================================
-- GRENADE DATA
-- ============================================================================
local Data = {

	-- ─── Must Fill ───────────────────────────────────────────────────────────

	Name = "M67",
	ID   = 5,
	Type = "HE", -- "HE" | "Flash" | "Smoke" (used by GrenadeManager to pick BlastController)


	-- ─── Fuse ────────────────────────────────────────────────────────────────

	FuseTime = 3.5, -- Total fuse duration in seconds (cook time is subtracted on throw)


	-- ─── Inventory ───────────────────────────────────────────────────────────

	Inventory = {
		MaxStock     = 2,  -- Maximum grenades the player can carry
		DefaultStock = 2,  -- How many they start with
	},

	-- ─── Throw ───────────────────────────────────────────────────────────────

	Throw = {
		MinForce      = 35,   -- Force when thrown instantly (no charge)
		MaxForce      = 150,   -- Force at full charge
		MaxChargeTime = 1.5,  -- Seconds to reach full charge
		ArcBias       = 0.25, -- Upward angle bias applied to throw direction
	},


	-- ─── Blast ───────────────────────────────────────────────────────────────

	Blast = {
		Radius             = 18,   -- Outer kill/damage radius in studs
		InnerRadius        = 5,    -- Full damage radius in studs
		MaxDamage          = 100,  -- Damage at point blank / inner radius
		RequireLineOfSight = true, -- Walls block damage
	},


	-- ─── State ───────────────────────────────────────────────────────────────

	EquipTime  = 0.35, -- Seconds to pull out the grenade
	ThrowTime  = 0.55, -- Animation time for the throw motion


	-- ─── Model & Attachments ─────────────────────────────────────────────────

	Model            = Model,
	PinAttachment    = nil,   
	ThrowAttachment = Model:WaitForChild('Handle'),

	-- ─── Animations ──────────────────────────────────────────────────────────

	Animations = {
		Equip    = nil,
		Cook     = Animations:WaitForChild('Cook'),   
		CookIdle = Animations:WaitForChild('CookIdle'),
		Idle     = Animations:WaitForChild('Idle'),
		Throw    = Animations:WaitForChild('Throw'),
		Unequip  = nil,
	},


	-- ─── Sounds ──────────────────────────────────────────────────────────────

	Sounds = {
		PinPull  = Sounds:WaitForChild('PinPull'),
		Throw    = Sounds:WaitForChild('Throw'),
		Bounce   = Sounds:WaitForChild('Bounce'),   
		Explode  = Sounds:WaitForChild('Explode'),
	},


	-- ─── Projectile ──────────────────────────────────────────────────────────

	Projectile = {
		Model       = Model,
		Restitution = 0.3,
		MaxDistance = 100,
		MaxBounces  = 10,
		Gravity     = Vector3.new(0, -workspace.Gravity, 0),
		MinSpeed    = 1.0,
	},

}

return Data