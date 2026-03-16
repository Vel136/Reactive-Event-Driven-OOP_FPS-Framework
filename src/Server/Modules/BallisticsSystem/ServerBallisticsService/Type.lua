local module = {}

local ReplicatedStorage = game:GetService('ReplicatedStorage')
local t = require(ReplicatedStorage.Shared.Modules.Utilities.TypeCheck)

export type LagCompensationData = {
	Origin : Vector3,
	Direction : Vector3,
	Speed : number,
	Behavior : any,
	FireTime : number	
}
export type DefaultData = {
	Origin : Vector3,
	Direction : Vector3,
	Speed : number,
	Behavior : any,	
}
module.LagDataCheck = t.interface(
	{
		Origin = t.Vector3,
		Direction = t.Vector3,
		Speed = t.number,
		Behavior = t.any,
		FireTime = t.number,
	}
)
module.FireDataCheck = t.interface(
	{
		Origin = t.Vector3,
		Direction = t.Vector3,
		Speed = t.number,
		Behavior = t.any,
	}
)

return module
