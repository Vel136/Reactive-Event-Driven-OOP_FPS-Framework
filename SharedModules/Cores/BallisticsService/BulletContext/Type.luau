-- BulletContextType.lua
--[[
	Type definitions for BulletContext
	Provides complete typing for solver-agnostic bullet objects
]]

local ReplicatedStorage = game:GetService('ReplicatedStorage')
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local Utilities = ReplicatedStorage.SharedModules.Utilities
local FastCast = require(Utilities.FastCastRedux)

export type BulletContext = {
	-- Identity
	Id: string,

	-- Ownership
	Weapon: any,

	-- Initial State (immutable)
	Origin: Vector3,
	Direction: Vector3,  -- Always normalized
	Speed: number,
	StartTime: number,

	-- Runtime State (updated by solver)
	Position: Vector3,
	Velocity: Vector3,
	Alive: boolean,
	Length : number,
	LastPoint : Vector3,
	-- Private solver data (internal use only, undocumented)
	__solverData: {
		Cast : FastCast.ActiveCast,
	}?,

	-- Methods
	_UpdateState: (self: BulletContext, position: Vector3, velocity: Vector3) -> (),
	Terminate: (self: BulletContext) -> (),
	GetLifetime: (self: BulletContext) -> number,
	GetDistanceTraveled: (self: BulletContext) -> number,
	IsAlive: (self: BulletContext) -> boolean,
	GetSnapshot: (self: BulletContext) -> BulletSnapshot,
}

export type BulletSnapshot = {
	Id: string,
	Origin: Vector3,
	Direction: Vector3,
	Speed: number,
	Position: Vector3,
	Velocity: Vector3,
	Alive: boolean,
	Lifetime: number,
	DistanceTraveled: number,
}

-- Solver-agnostic hit data structure
export type HitData = {
	Instance: BasePart,
	Position: Vector3,
	Normal: Vector3,
	Material: Enum.Material,
	Distance: number,
}

-- Configuration for creating a BulletContext
export type BulletContextConfig = {
	Weapon: any,
	Origin: Vector3,
	Direction: Vector3,
	Speed: number,
	SolverData: any?,
}

return {
	BulletContext = {} :: BulletContext,
	BulletSnapshot = {} :: BulletSnapshot,
	HitData = {} :: HitData,
	BulletContextConfig = {} :: BulletContextConfig,
}