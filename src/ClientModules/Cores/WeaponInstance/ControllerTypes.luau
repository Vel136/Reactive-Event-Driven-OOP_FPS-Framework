-- ControllerTypes.lua
--[[
	Type definitions for all weapon controllers
	Place this in your WeaponInstance folder
]]

local ReplicatedStorage = game:GetService('ReplicatedStorage')
local Utilities = ReplicatedStorage.SharedModules.Utilities
local Signal = require(Utilities:FindFirstChild("Signal"))
local Janitor = require(Utilities:FindFirstChild("Janitor"))

-- StateManager Type
export type StateManager = {
	Player: Player?,
	Character: Model?,

	States: {
		Aiming: BoolValue,
		Shooting: BoolValue,
		Reloading: BoolValue,
		Equipped: BoolValue,
	},

	LastAimTime: number,
	LastShootTime: number,

	Signals: {
		OnAimChanged: Signal.Signal,
		OnFireChanged: Signal.Signal,
		OnEquipChanged: Signal.Signal,
		OnReloadChanged: Signal.Signal,
	},

	_Janitor: Janitor.Janitor,

	-- Methods
	SetupObservers: (self: StateManager, onAimChanged: any?, onFireChanged: any?, onEquipChanged: any?) -> (),
	GetCharacter: (self: StateManager) -> Model?,
	GetHRP: (self: StateManager) -> BasePart?,

	SetAiming: (self: StateManager, isAiming: boolean) -> (),
	IsAiming: (self: StateManager) -> boolean,

	SetShooting: (self: StateManager, isShooting: boolean) -> (),
	IsShooting: (self: StateManager) -> boolean,

	SetReloading: (self: StateManager, isReloading: boolean) -> (),
	IsReloading: (self: StateManager) -> boolean,

	SetEquipped: (self: StateManager, isEquipped: boolean) -> (),
	IsEquipped: (self: StateManager) -> boolean,
	
	SetEnabled: (self: StateManager,State : any, Enabled : boolean) -> (),
	GetAllStates: (self: StateManager) -> {
		Aiming: boolean,
		Shooting: boolean,
		Reloading: boolean,
		Equipped: boolean,
	},

	Destroy: (self: StateManager) -> (),

	-- Internal
	_TrackCharacter: (self: StateManager) -> (),
}

-- AmmoController Type
export type AmmoController = {
	Data: {
		MagazineSize: number,
		ReserveSize: number,
		ReloadTime: number?,
	},

	StateManager: StateManager,

	Ammo: IntValue,
	Reserve: IntValue,

	ReloadPromise: any?,
	LastReloadTime: number,

	Signals: {
		OnAmmoChanged: Signal.Signal,
		OnReserveChanged: Signal.Signal,
		OnReload: Signal.Signal,
		OnReloadComplete: Signal.Signal,
		OnEmpty: Signal.Signal,
	},

	-- Methods
	HasAmmo: (self: AmmoController) -> boolean,
	IsMagazineFull: (self: AmmoController) -> boolean,
	HasReserve: (self: AmmoController) -> boolean,

	ConsumeAmmo: (self: AmmoController, amount: number?) -> boolean,
	Reload: (self: AmmoController) -> any, -- Returns Promise
	CancelReload: (self: AmmoController) -> (),

	GetState: (self: AmmoController) -> {
		Ammo: number,
		Reserve: number,
	},

	AddReserve: (self: AmmoController, amount: number) -> (),
	Destroy: (self: AmmoController) -> (),
}

-- SpreadController Type
export type SpreadProfile = {
	Min: number,
	Max: number,
	IncreasePerShot: number,
	DecreasePerSecond: number,
	RecoveryTime: number,
}

export type SpreadController = {
	Data: {
		Base: SpreadProfile,
		Aiming: SpreadProfile,
	},

	StateManager: StateManager,

	CurrentSpread: IntValue,
	LastShootTime: number,

	-- Methods
	GetCurrentSpread: (self: SpreadController) -> number,
	ApplySpread: (self: SpreadController, direction: Vector3) -> Vector3,
	SetSpread: (self: SpreadController, amount: number) -> number,
	OnAimChanged: (self: SpreadController, isAiming: boolean) -> (),
	UpdateShootTime: (self: SpreadController) -> (),
	Destroy: (self: SpreadController) -> (),

	-- Internal
	_GetSpreadProfile: (self: SpreadController) -> SpreadProfile,
}

-- DamageCalculator Type
export type DamageCalculator = {
	Data: {
		Min: number,
		Max: number,
		Range: {
			Min: number,
			Max: number,
		},
	},

	-- Methods
	CalculateBaseDamage: (self: DamageCalculator, Context : any) -> number,
	CalculateTotalDamage: (self: DamageCalculator, Context : any) -> number,
	CalculateBonusDamage: (self: DamageCalculator, cast: any?, result: RaycastResult?, velocity: Vector3?, bullet: any?) -> number,
	GetDamageAtRange: (self: DamageCalculator, range: number) -> number,
	GetEffectiveRange: (self: DamageCalculator, minEffectiveDamage: number) -> number,
	Destroy: (self: DamageCalculator) -> (),
}

return {
	StateManager = {} :: StateManager,
	AmmoController = {} :: AmmoController,
	SpreadController = {} :: SpreadController,
	DamageCalculator = {} :: DamageCalculator,
}