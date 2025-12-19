--[=[
	@class Events
	Event name constants for NetworkService.
	Centralized event naming to prevent typos.
]=]

return {
	-- Weapon actions
	Fire = "WeaponFire",
	Reload = "WeaponReload",
	Equip = "WeaponEquip",
	Unequip = "WeaponUnequip",

	-- Hit replication
	Hit = "BulletHit",

	-- Player events
	Damage = "PlayerDamage",
	Kill = "PlayerKill",

	-- Game events (if needed later)
	RoundStart = "RoundStart",
	RoundEnd = "RoundEnd",
}