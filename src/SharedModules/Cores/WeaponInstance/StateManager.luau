-- StateManager.lua
--[[
	Manages all weapon state including:
	- State ValueObjects (Aiming, Shooting, Reloading, Equipped)
	- State observers
	- Character tracking
	- State change signals
]]
-- Services
local ReplicatedStorage = game:GetService('ReplicatedStorage')

-- Utilities module
local Utilities = ReplicatedStorage.SharedModules.Utilities
local Observer = require(Utilities:FindFirstChild("Observer"))
local Signal = require(Utilities:FindFirstChild("Signal"))
local Janitor = require(Utilities:FindFirstChild("Janitor"))
local Logger = require(Utilities:FindFirstChild("LogService"))

local StateManager = {}
StateManager.__index = StateManager

--[[
	Creates a new StateManager
	@param player - The player who owns this weapon
	@return StateManager instance
]]
function StateManager.new(player)
	local self = setmetatable({}, StateManager)

	self.Player = player
	self.Character = nil

	-- Janitor for cleanup
	self._Janitor = Janitor.new()

	-- State ValueObjects
	self.States = {
		Aiming = Instance.new("BoolValue"),
		Shooting = Instance.new("BoolValue"),
		Reloading = Instance.new("BoolValue"),
		Equipped = Instance.new("BoolValue"),
	}

	-- Add states to janitor
	for _, state in pairs(self.States) do
		self._Janitor:Add(state)
	end

	-- Timestamps
	self.LastAimTime = 0
	self.LastShootTime = 0

	-- Signals
	self.Signals = {
		OnAimChanged = Signal.new(),
		OnFireChanged = Signal.new(),
		OnEquipChanged = Signal.new(),
	}

	-- Track character
	self:_TrackCharacter()

	return self
end

--[[
	Sets up state observers (call this after controllers are initialized)
	@param onAimChanged - Callback function for aim state change
	@param OnFireChanged - Callback function for shoot state change
	@param onEquipChanged - Callback function for equip state change
]]
function StateManager:SetupObservers()
	-- Aim observer
	local aimObserver = Observer.observeProperty(self.States.Aiming, "Value", function(isAiming)
		self.Signals.OnAimChanged:Fire(isAiming)
	end)

	-- Shoot observer
	local shootObserver = Observer.observeProperty(self.States.Shooting, "Value", function(isShooting)
		self.Signals.OnFireChanged:Fire(isShooting)
	end)

	-- Equip observer
	local equipObserver = Observer.observeProperty(self.States.Equipped, "Value", function(isEquipped)
		self.Signals.OnEquipChanged:Fire(isEquipped)

	end)

	-- Add observers to janitor
	self._Janitor:Add(aimObserver)
	self._Janitor:Add(shootObserver)
	self._Janitor:Add(equipObserver)
end

--[[
	Internal: Tracks character for the player
]]
function StateManager:_TrackCharacter()
	if not self.Player then return end

	local function onCharacterAdded(character)
		self.Character = character
	end

	if self.Player.Character then
		onCharacterAdded(self.Player.Character)
	end

	-- Auto disconnect when clean-up
	self._Janitor:Add(self.Player.CharacterAdded:Connect(onCharacterAdded))
end

--[[
	Gets the current character
	@return Model|nil - Current character
]]
function StateManager:GetCharacter()
	return self.Character
end

--[[
	Gets the HumanoidRootPart
	@return BasePart|nil - HumanoidRootPart
]]
function StateManager:GetHRP()
	if not self.Character then return nil end
	return self.Character:FindFirstChild("HumanoidRootPart")
end

--[[
	Sets aiming state
	@param isAiming - New aiming state
]]
function StateManager:SetAiming(isAiming: boolean)
	if self.States.Aiming.Value == isAiming then return end
	self.States.Aiming.Value = isAiming
	self.LastAimTime = os.clock()
end

--[[
	Gets aiming state
	@return boolean - Is aiming
]]
function StateManager:IsAiming(): boolean
	return self.States.Aiming.Value
end

--[[
	Sets shooting state
	@param isShooting - New shooting state
]]
function StateManager:SetShooting(isShooting: boolean)
	self.States.Shooting.Value = isShooting
	if isShooting then
		self.LastShootTime = os.clock()
	end
end

--[[
	Gets shooting state
	@return boolean - Is shooting
]]
function StateManager:IsShooting(): boolean
	return self.States.Shooting.Value
end

--[[
	Sets reloading state
	@param isReloading - New reloading state
]]
function StateManager:SetReloading(isReloading: boolean)
	self.States.Reloading.Value = isReloading
end

--[[
	Gets reloading state
	@return boolean - Is reloading
]]
function StateManager:IsReloading(): boolean
	return self.States.Reloading.Value
end

--[[
	Sets equipped state
	@param isEquipped - New equipped state
]]
function StateManager:SetEquipped(isEquipped: boolean)
	self.States.Equipped.Value = isEquipped
end

--[[
	Gets equipped state
	@return boolean - Is equipped
]]
function StateManager:IsEquipped(): boolean
	return self.States.Equipped.Value
end

--[[
	Gets all current states
	@return table - All state values
]]
function StateManager:GetAllStates()
	return {
		Aiming = self.States.Aiming.Value,
		Shooting = self.States.Shooting.Value,
		Reloading = self.States.Reloading.Value,
		Equipped = self.States.Equipped.Value,
	}
end

--[[
	Cleanup
]]
function StateManager:Destroy()
	-- Cleanup signals
	for _, signal in pairs(self.Signals) do
		signal:Destroy()
	end

	-- Cleanup janitor (handles observers, connections, states)
	self._Janitor:Destroy()

	self.Player = nil
	self.Character = nil
end

return StateManager