--!nonstrict

local ReplicatedStorage = game:GetService('ReplicatedStorage')
local Utilities = ReplicatedStorage.SharedModules.Utilities
local TypeCheck = require(Utilities:FindFirstChild("TypeCheck"))

local FastCast = require(Utilities.FastCastRedux)
local Janitor = require(Utilities.Janitor)
local Signal = require(Utilities.Signal)
local Promise = require(Utilities.Promise)
local ControllerTypes = require(script.Parent.ControllerTypes)

local BulletContext = require(ReplicatedStorage.SharedModules.Cores.BallisticsService.BulletContext)
export type StateManager = ControllerTypes.StateManager
export type AmmoController = ControllerTypes.AmmoController
export type SpreadController = ControllerTypes.SpreadController
export type DamageCalculator = ControllerTypes.DamageCalculator

export type SpreadProfile = {
	Min: number,
	Max: number,
	IncreasePerShot: number,
	DecreasePerSecond: number,
	RecoveryTime: number,
}
export type GunData = {
	Name: string,
	ID: number,

	-- Basic stats
	Damage : {
		Base : number,          -- base bullet damage at ideal range

		Multipliers : {     -- hitbox multipliers
			Head : number,
			UpperTorso : number,
			LowerTorso : number,
			LeftArm : number,
			RightArm : number,
			LeftLeg : number,
			RightLeg : number,
		},

		Range : {           -- damage falloff
			Min : number,        -- from 0 to 20 studs = full damage
			Max : number,       -- at 150 studs = lowest damage
			Dropoff : number    -- lowest possible ratio (30% damage reduction)
		},

		Penetration : {
			Enabled : boolean,
			MaxCount : number,       -- can penetrate 2 targets Max
			LossPerWall : number, -- loses 35% damage each penetration
		},
	},
	AmmoDeduction: number?,
	FireMode: "Semi" | "Auto" | "Burst",
	BurstCount: number?,
	FireRate: number,        -- rounds per minute
	BulletSpeed: number,     -- for projectile mode
	BulletGravity: Vector3,
	-- Accuracy
	Spread: {
		Base : SpreadProfile,
		Aiming : SpreadProfile,
	},
	-- Recoil
	Recoil: {
		CameraKick: Vector2,     -- pitch, yaw
		Pattern: {Vector2}?,     -- if pattern exists
		ReturnSpeed: number,
		ADSModifier: number,
	},

	-- Ammo
	Ammo: {
		MagazineSize: number,
		ReserveSize: number,
		ReloadTime: number,
	},

	-- Timing
	EquipTime: number,
	AimTime: number,
	SprintRecovery: number,

	-- Models + Attach points
	Model: Model,
	BarrelAttachment: string?,
	ShellEjectAttachment: string?,
	AimAttachment: string?,
	-- Animations
	Animations: {
		Idle: Animation?,
		Fire: Animation?,
		Reload: Animation?,
		Equip: Animation?,
		Sprint: Animation?,
		Aim: Animation?,
	},

	-- Sounds
	Sounds: {
		Fire : Sound?,
		Reload : Sound?,
		Equip : Sound?,
		Empty : Sound?,
	},

	-- Special behaviour toggles
	IsShotgun: boolean?,
	PelletCount: number?,
	Projectile: boolean?,

	-- Client-only cosmetic flags
	MuzzleFlashEnabled: boolean?,
	ShellEjectEnabled: boolean?,
}

local GunDataCheck = TypeCheck.interface({
	Name = TypeCheck.string,
	ID = TypeCheck.number,
	
	Damage = TypeCheck.interface({
		Base = TypeCheck.number,
		Multipliers = TypeCheck.interface({
			Head = TypeCheck.number,
			UpperTorso = TypeCheck.number,
			LowerTorso = TypeCheck.number,
			LeftArm = TypeCheck.number,
			RightArm = TypeCheck.number,
			LeftLeg = TypeCheck.number,
			RightLeg = TypeCheck.number,
		}),
		
		Range = TypeCheck.interface({
			Min = TypeCheck.number,
			Max = TypeCheck.number,
			Dropoff = TypeCheck.number,
		}),
		
		Penetration = TypeCheck.interface({
			Enabled = TypeCheck.boolean,
			MaxCount = TypeCheck.number,
			LossPerWall = TypeCheck.number,
		}),
		
	}),
	FireMode = TypeCheck.union(TypeCheck.literal("Semi"), TypeCheck.literal("Auto"), TypeCheck.literal("Burst")),
	AmmoDeduction = TypeCheck.optional(TypeCheck.number),
	BurstCount = TypeCheck.optional(TypeCheck.number),
	
	FireRate = TypeCheck.number,
	
	BulletSpeed = TypeCheck.number,
	
	BulletGravity = TypeCheck.Vector3,
	Spread = TypeCheck.interface({
		Base = TypeCheck.interface({
			Min = TypeCheck.number,
			Max = TypeCheck.number,
			RecoveryTime = TypeCheck.number,
			IncreasePerShot = TypeCheck.number,
			DecreasePerSecond = TypeCheck.number,
		}),
		Aiming = TypeCheck.interface({
			Min = TypeCheck.number,
			Max = TypeCheck.number,
			RecoveryTime = TypeCheck.number,
			IncreasePerShot = TypeCheck.number,
			DecreasePerSecond = TypeCheck.number,
		}),
	}),
	Recoil = TypeCheck.interface({
		CameraKick = TypeCheck.Vector2,
		Pattern = TypeCheck.optional(TypeCheck.array(TypeCheck.Vector2)),
		ReturnSpeed = TypeCheck.number,
		ADSModifier = TypeCheck.number,
	}),
	Ammo = TypeCheck.interface({
		MagazineSize = TypeCheck.number,
		ReserveSize = TypeCheck.number,
		ReloadTime = TypeCheck.number,
	}),
	EquipTime = TypeCheck.number,
	AimTime = TypeCheck.number,
	SprintRecovery = TypeCheck.number,
	Model = TypeCheck.instanceIsA("Model"),
	BarrelAttachment = TypeCheck.optional(TypeCheck.string),
	ShellEjectAttachment = TypeCheck.optional(TypeCheck.string),
	AimAttachment = TypeCheck.optional(TypeCheck.string),
	Animations = TypeCheck.interface({
		Idle = TypeCheck.optional(TypeCheck.instanceIsA("Animation")),
		Fire = TypeCheck.optional(TypeCheck.instanceIsA("Animation")),
		Reload = TypeCheck.optional(TypeCheck.instanceIsA("Animation")),
		Equip = TypeCheck.optional(TypeCheck.instanceIsA("Animation")),
		Sprint = TypeCheck.optional(TypeCheck.instanceIsA("Animation")),
		Aim = TypeCheck.optional(TypeCheck.instanceIsA("Animation")),
	}),
	Sounds = TypeCheck.interface({
		Fire = TypeCheck.optional(TypeCheck.instanceIsA("Sound")),
		Reload = TypeCheck.optional(TypeCheck.instanceIsA("Sound")),
		Equip = TypeCheck.optional(TypeCheck.instanceIsA("Sound")),
		Empty = TypeCheck.optional(TypeCheck.instanceIsA("Sound")),
	}),
	IsShotgun = TypeCheck.optional(TypeCheck.boolean),
	PelletCount = TypeCheck.optional(TypeCheck.number),
	Projectile = TypeCheck.optional(TypeCheck.boolean),
	MuzzleFlashEnabled = TypeCheck.optional(TypeCheck.boolean),
	ShellEjectEnabled = TypeCheck.optional(TypeCheck.boolean),
})
export type Gun = {
	-- Core Data
	Data: GunData,

	-- Sub-systems (Controllers)
	StateManager: StateManager,
	AmmoController: AmmoController,
	SpreadController: SpreadController,
	DamageCalculator: DamageCalculator,

	-- Ballistics
	Ballistics: {
		Behavior: FastCast.FastCastBehavior?,
	},

	-- Cleanup
	_Janitor: Janitor.Janitor,

	-- Signals (mix of Gun-owned and controller references)
	Signals: {
		-- Gun-owned signals
		OnFire: Signal.Signal,
		OnHit: Signal.Signal,
		OnDestroyed: Signal.Signal,

		-- Direct references to controller signals
		OnReload: Signal.Signal, -- From AmmoController
		OnReloadComplete: Signal.Signal, -- From AmmoController
		OnAmmoChanged: Signal.Signal, -- From AmmoController
		OnReserveChanged: Signal.Signal, -- From AmmoController
		OnEmpty: Signal.Signal, -- From AmmoController

		OnFireChanged: Signal.Signal, -- From StateManager
		OnAimChanged: Signal.Signal, -- From StateManager
		OnEquipChanged: Signal.Signal, -- From StateManager
	},

	-- Public Methods
	CanFire: (self: Gun) -> (boolean, string?),
	Fire: (self: Gun, origin: Vector3?, direction: Vector3, useHRP_Position: boolean?) -> (boolean, any),
	FireBullet: (self: Gun, origin: Vector3, direction: Vector3) -> BulletContext.BulletContext,
	Reload: (self: Gun) -> any, -- Returns Promise
	SetAiming: (self: Gun, aiming: boolean) -> (),
	IsAiming: (self: Gun) -> boolean,
	Equip: (self: Gun) -> (),
	Unequip: (self: Gun) -> (),
	SetSpread: (self: Gun, amount: number) -> number,
	GetState: (self: Gun) -> {
		Ammo: number,
		Reserve: number,
		Aiming: boolean,
		Reloading: boolean,
		Shooting: boolean,
		Equipped: boolean,
		Spread: number,
	},
	Destroy: (self: Gun) -> (),

	-- Internal Methods (still in Gun)
	_SetupBallistics: (self: Gun) -> (),
	_SetupControllerLinks: (self: Gun) -> (),
	_FireInternal: (self: Gun, origin: Vector3, direction: Vector3) -> any,

	-- Ballistics Callbacks (can be overridden)
	_OnBulletHit: (self: Gun, BulletContext : BulletContext.BulletContext,HitData : RaycastResult) -> (),
	_OnBulletTravel: (self: Gun, BulletContext : BulletContext.BulletContext) -> (),
	_OnBulletTerminating: (self: Gun,BulletContext : BulletContext.BulletContext) -> ()
}

return {GunDataCheck = GunDataCheck}