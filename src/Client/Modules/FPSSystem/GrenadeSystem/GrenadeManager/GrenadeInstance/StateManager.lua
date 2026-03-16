-- StateManager.lua
--[[
	Manages all weapon state including:
	- State variables (Aiming, Shooting, Reloading, Equipped)
	- Character tracking
	- State change signals
]]

local Identity = "StateManager"

-- ─── Services ────────────────────────────────────────────────────────────────

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ─── References ──────────────────────────────────────────────────────────────

local Utilities = ReplicatedStorage.Shared.Modules.Utilities

-- ─── Modules ─────────────────────────────────────────────────────────────────

local Signal     = require(Utilities:FindFirstChild("Signal"))
local Janitor    = require(Utilities:FindFirstChild("Janitor"))
local LogService = require(Utilities:FindFirstChild("Logger"))

local Configuration = require(ReplicatedStorage.Shared.Modules.FPSSystem.Configuration.Configuration)

-- ─── Constants ───────────────────────────────────────────────────────────────

local States = Configuration.WeaponStates

-- ─── Module ──────────────────────────────────────────────────────────────────

local StateManager   = {}
StateManager.__index = StateManager
StateManager.__type  = Identity

-- ─── Static enums ────────────────────────────────────────────────────────────

local Enums = {}
for StateName, StateEnum in pairs(States) do
	Enums[StateEnum] = StateName
end

StateManager.States = States
StateManager.Enums  = Enums

-- ─── Private state ───────────────────────────────────────────────────────────

local Logger = LogService.new(Identity, false)

-- ─── Getters: entity ─────────────────────────────────────────────────────────

--- Returns the player who owns this StateManager.
function StateManager.GetPlayer(self: StateManager): Player?
	return self.Player
end

--- Returns the player's current character model.
function StateManager.GetCharacter(self: StateManager): Model?
	return self.Character
end

--- Returns the HumanoidRootPart of the current character.
function StateManager.GetHRP(self: StateManager): BasePart?
	local character = self:GetCharacter()
	if not character then return nil end
	return character:FindFirstChild("HumanoidRootPart")
end

-- ─── Getters: state ──────────────────────────────────────────────────────────

--- Returns whether the weapon is currently aiming.
function StateManager.IsAiming(self: StateManager): boolean
	return self._Aiming
end

--- Returns whether the weapon is currently firing.
function StateManager.IsShooting(self: StateManager): boolean
	return self._Shooting
end

--- Returns whether the weapon is currently reloading.
function StateManager.IsReloading(self: StateManager): boolean
	return self._Reloading
end

--- Returns whether the weapon is currently equipped.
function StateManager.IsEquipped(self: StateManager): boolean
	return self._Equipped
end

--- Returns the timestamp of the last aim state change.
function StateManager.GetLastAimTime(self: StateManager): number
	return self.LastAimTime
end

--- Returns the timestamp of the last shot fired.
function StateManager.GetLastShootTime(self: StateManager): number
	return self.LastShootTime
end

-- ─── Setters: state ──────────────────────────────────────────────────────────

--- Sets the aiming state. No-ops if unchanged.
function StateManager.SetAiming(self: StateManager, isAiming: boolean)
	if self._Aiming == isAiming then
		Logger:Debug(string.format("SetAiming: already %s", tostring(isAiming)))
		return
	end

	self._Aiming = isAiming
	self.LastAimTime = os.clock()
	self.Signals.OnAimChanged:Fire(isAiming)

	Logger:Debug(string.format("SetAiming: -> %s", tostring(isAiming)))
end

--- Sets the shooting state.
function StateManager.SetShooting(self: StateManager, isShooting: boolean)
	self._Shooting = isShooting
	self.Signals.OnFireChanged:Fire(isShooting)

	if isShooting then
		self.LastShootTime = os.clock()
		Logger:Debug("SetShooting: started")
	else
		Logger:Debug("SetShooting: stopped")
	end
end

--- Sets the reloading state. No-ops if unchanged.
function StateManager.SetReloading(self: StateManager, isReloading: boolean)
	if self._Reloading == isReloading then
		Logger:Debug(string.format("SetReloading: already %s", tostring(isReloading)))
		return
	end

	self._Reloading = isReloading
	self.Signals.OnReloadChanged:Fire(isReloading)

	Logger:Debug(string.format("SetReloading: -> %s", tostring(isReloading)))
end

--- Sets the equipped state. No-ops if unchanged.
function StateManager.SetEquipped(self: StateManager, isEquipped: boolean)
	if self._Equipped == isEquipped then
		Logger:Debug(string.format("SetEquipped: already %s", tostring(isEquipped)))
		return
	end

	self._Equipped = isEquipped
	self.Signals.OnEquipChanged:Fire(isEquipped)

	Logger:Debug(string.format("SetEquipped: -> %s", tostring(isEquipped)))
end

-- ─── Generic state API ───────────────────────────────────────────────────────

--- Sets a state by its enum value. Routes through typed setters so signals fire correctly.
function StateManager.SetState(self: StateManager, StateEnum: number, Enabled: boolean): boolean
	local StateName = StateManager.Enums[StateEnum]
	if not StateName then
		Logger:Warn(string.format("SetState: invalid enum %d", StateEnum))
		return false
	end

	if StateName == "Aim" then
		self:SetAiming(Enabled)
	elseif StateName == "Shoot" then
		self:SetShooting(Enabled)
	elseif StateName == "Reload" then
		self:SetReloading(Enabled)
	elseif StateName == "Equip" then
		self:SetEquipped(Enabled)
	else
		Logger:Warn(string.format("SetState: no setter for %s", StateName))
		return false
	end

	Logger:Debug(string.format("SetState: %s = %s", StateName, tostring(Enabled)))
	return true
end

--- Gets a state by its enum value.
function StateManager.GetState(self: StateManager, StateEnum: number): boolean?
	local StateName = StateManager.Enums[StateEnum]
	if not StateName then
		Logger:Warn(string.format("GetState: invalid enum %d", StateEnum))
		return nil
	end

	if StateName == "Aim"    then return self._Aiming
	elseif StateName == "Shoot"  then return self._Shooting
	elseif StateName == "Reload" then return self._Reloading
	elseif StateName == "Equip"  then return self._Equipped
	end

	Logger:Warn(string.format("GetState: no variable for %s", StateName))
	return nil
end

--- Returns a snapshot of all current states.
function StateManager.GetAllStates(self: StateManager)
	return {
		Aiming    = self._Aiming,
		Shooting  = self._Shooting,
		Reloading = self._Reloading,
		Equipped  = self._Equipped,
	}
end

-- ─── Utility queries ─────────────────────────────────────────────────────────

--- Returns true if any combat state (aim/shoot/reload) is active.
function StateManager.IsAnyStateActive(self: StateManager): boolean
	return self._Aiming or self._Shooting or self._Reloading
end

--- Returns true if the weapon is allowed to fire right now.
function StateManager.CanFire(self: StateManager): boolean
	return self._Equipped and not self._Reloading
end

--- Returns true if the weapon is allowed to reload right now.
function StateManager.CanReload(self: StateManager): boolean
	return self._Equipped and not self._Reloading
end

--- Resets aim, shoot, and reload to false. Equipped state is preserved.
function StateManager.ResetAllStates(self: StateManager)
	Logger:Debug("ResetAllStates: resetting combat states")
	self:SetAiming(false)
	self:SetShooting(false)
	self:SetReloading(false)
end

-- ─── Internal ────────────────────────────────────────────────────────────────

--- Tracks character spawns for the owning player.
function StateManager._TrackCharacter(self: StateManager)
	local player = self:GetPlayer()
	if not player then
		Logger:Warn("_TrackCharacter: no player to track")
		return
	end

	local function onCharacterAdded(character)
		self.Character = character
		Logger:Debug(string.format("_TrackCharacter: character added for %s", player.Name))
	end

	if player.Character then
		onCharacterAdded(player.Character)
	end

	self._Janitor:Add(player.CharacterAdded:Connect(onCharacterAdded))
end

-- ─── Lifecycle ───────────────────────────────────────────────────────────────

--- Cleans up all signals, connections, and state.
function StateManager.Destroy(self: StateManager)
	Logger:Debug("Destroy: cleaning up StateManager")

	for signalName, signal in pairs(self.Signals) do
		signal:Destroy()
		Logger:Debug(string.format("Destroy: destroyed signal %s", signalName))
	end

	self._Janitor:Destroy()

	self.Player    = nil
	self.Character = nil

	Logger:Debug("Destroy: complete")
end

-- ─── Constructor ─────────────────────────────────────────────────────────────

local module = {}
module.States = States
module.Enums  = Enums

--- Creates a new StateManager for the given player.
function module.new(player: Player)
	local self: StateManager = setmetatable({}, { __index = StateManager })

	self.Player    = player
	self.Character = nil

	self._Janitor = Janitor.new()

	-- State variables
	self._Aiming    = false
	self._Shooting  = false
	self._Reloading = false
	self._Equipped  = false

	-- Timestamps
	self.LastAimTime   = 0
	self.LastShootTime = 0

	self.Signals = {
		OnAimChanged    = Signal.new(),
		OnFireChanged   = Signal.new(),
		OnEquipChanged  = Signal.new(),
		OnReloadChanged = Signal.new(),
	}

	self:_TrackCharacter()

	Logger:Debug(string.format("new: created StateManager for %s", player.Name))

	return self
end

-- ─── Types ───────────────────────────────────────────────────────────────────

export type StateManager = typeof(setmetatable({}, { __index = StateManager })) & {
	Player         : Player?,
	Character      : Model?,
	_Aiming        : boolean,
	_Shooting      : boolean,
	_Reloading     : boolean,
	_Equipped      : boolean,
	LastAimTime    : number,
	LastShootTime  : number,
	Signals: {
		OnAimChanged    : Signal.Signal<(isAiming: boolean)    -> ()>,
		OnFireChanged   : Signal.Signal<(isShooting: boolean)  -> ()>,
		OnEquipChanged  : Signal.Signal<(isEquipped: boolean)  -> ()>,
		OnReloadChanged : Signal.Signal<(isReloading: boolean) -> ()>,
	},
	_Janitor: Janitor.Janitor,
}

return table.freeze(module)