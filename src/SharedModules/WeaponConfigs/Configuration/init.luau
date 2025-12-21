local ReplicatedStorage = game:GetService('ReplicatedStorage')
local module = {
	
	FiringMode = {
		Semi = 1,
		Auto = 2,
		Burst = 3,
		
		
		
	},
	WeaponStates = {
		Aiming = 1,
		Equip = 2,
		
	},
	WeaponDatas = {
		M9 = require(script.M9_Data),
		M4A1 = require(script.M4A1_Data),
		
		
	}
	
	
	
	
}

return module
