local ReplicatedStorage = game:GetService('ReplicatedStorage')

local module = {
	FiringMode = {
		Semi = 1,
		Auto = 2,
		Burst = 3,	
	},
	WeaponStates = {
		Aim = 1,
		Equip = 2,
		Shoot = 3,
		Reload = 4,
	},
}

return module
