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
	WeaponDatas = {
		M9 = require(script.M9_Data),
		M4A1 = require(script.M4A1_Data),
		SCAR = require(script.SCAR_Data)
		
	}
	
	
	
	
}

return module
