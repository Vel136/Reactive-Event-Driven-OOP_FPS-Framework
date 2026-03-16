-- MovementInstance.lua
--[[
	Manages character movement speed states including:
	- Dynamic walkspeed control
	- Input-based movement state switching (hold or toggle)
	- Movement state tracking with signals
	- SSOT pattern for all state management
]]

-- Services
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local HttpService = game:GetService('HttpService')
local Players = game:GetService('Players')

-- References
local Utilities = ReplicatedStorage.Shared.Modules.Utilities

-- Modules
local LogService = require(Utilities.Logger)
local InputSystem = require(Utilities.IAS)
local Signal = require(Utilities.Signal)

export type MovementInstanceData = {
	Name: string,
	Walkspeed: number,
	InputKey: Enum.KeyCode,
	Priority: number?,
	Hold: boolean?, -- NEW: Whether input requires holding (default true)
}

type Signal = Signal.Signal
export type MovementSignals = {
	OnMovementActivated: Signal,
	OnMovementDeactivated: Signal,
	OnWalkspeedChanged: Signal,
}

export type MovementState = {
	IsActive: boolean,
	CurrentWalkspeed: number,
	IsEnabled: boolean,
}

--[=[
	@class MovementInstance
	
	Manages a single movement state with walkspeed and input binding.
	Uses Single Source of Truth pattern for all state management.
	Can be used for walking, sprinting, crouching, aiming, etc.
	Supports both hold and toggle modes.
]=]
local Identity = "MovementInstance"
local MovementInstance = {}

local Logger = LogService.new(Identity, false)

--[[
	Gets the active state
	SINGLE SOURCE OF TRUTH for reading active state
	@return boolean - Is movement active
]]
function MovementInstance.IsActive(self: MovementInstance): boolean
	return self._isActive
end

--[[
	Gets the enabled state
	SINGLE SOURCE OF TRUTH for reading enabled state
	@return boolean - Is movement enabled
]]
function MovementInstance.IsEnabled(self: MovementInstance): boolean
	return self._isEnabled
end

--[[
	Gets current walkspeed
	SINGLE SOURCE OF TRUTH for reading walkspeed
	@return number - Current walkspeed
]]
function MovementInstance.GetWalkspeed(self: MovementInstance): number
	return self._currentWalkspeed
end

--[[
	Gets the target walkspeed from data
	@return number - Target walkspeed
]]
function MovementInstance.GetTargetWalkspeed(self: MovementInstance): number
	return self.Data.Walkspeed
end

--[[
	Gets the priority
	@return number - Priority level
]]
function MovementInstance.GetPriority(self: MovementInstance): number
	return self.Data.Priority or 0
end

--[[
	Gets the hold mode
	@return boolean - Whether input requires holding
]]
function MovementInstance.IsHoldMode(self: MovementInstance): boolean
	return self.Data.Hold
end

--[[
	Sets the active state
	SINGLE SOURCE OF TRUTH for writing active state
	@param active - Active state
]]
function MovementInstance.SetActive(self: MovementInstance, active: boolean): ()
	local oldValue = self._isActive
	self._isActive = active

	if oldValue ~= self._isActive then
		if active then
			self.Signals.OnMovementActivated:Fire()
			Logger:Debug(string.format("SetActive: Movement '%s' activated", self.Data.Name))
		else
			self.Signals.OnMovementDeactivated:Fire()
			Logger:Debug(string.format("SetActive: Movement '%s' deactivated", self.Data.Name))
		end
	end
end

--[[
	Sets the enabled state
	SINGLE SOURCE OF TRUTH for writing enabled state
	@param enabled - Enabled state
]]
function MovementInstance.SetEnabled(self: MovementInstance, enabled: boolean): ()
	local oldValue = self._isEnabled
	self._isEnabled = enabled

	if oldValue ~= self._isEnabled then
		Logger:Debug(string.format("SetEnabled: Movement '%s' %s", 
			self.Data.Name, enabled and "enabled" or "disabled"))

		-- Disable input when not enabled
		if self._inputObject then
			self._inputObject:SetEnabled(enabled)
		end

		-- Deactivate if becoming disabled
		if not enabled and self:IsActive() then
			self:SetActive(false)
		end
	end
end

--[[
	Sets the current walkspeed
	SINGLE SOURCE OF TRUTH for writing walkspeed
	@param walkspeed - Walkspeed value
]]
function MovementInstance.SetWalkspeed(self: MovementInstance, walkspeed: number): ()
	local oldValue = self._currentWalkspeed
	self._currentWalkspeed = math.max(0, walkspeed)

	if oldValue ~= self._currentWalkspeed then
		self.Signals.OnWalkspeedChanged:Fire(self._currentWalkspeed, oldValue)
		Logger:Debug(string.format("SetWalkspeed: Walkspeed changed for '%s' (%.1f -> %.1f)", 
			self.Data.Name, oldValue, self._currentWalkspeed))
	end
end

--[[
	Sets the hold mode
	@param hold - Whether input requires holding
]]
function MovementInstance.SetHold(self: MovementInstance, hold: boolean): ()
	local oldValue = self.Data.Hold
	self.Data.Hold = hold

	if self._inputObject then
		self._inputObject:SetHold(hold)
	end

	Logger:Debug(string.format("SetHold: Movement '%s' hold mode changed (%s -> %s)", 
		self.Data.Name, tostring(oldValue), tostring(hold)))
end

--[[
	Initializes input system for this movement state
	INTERNAL - Setup input binding
]]
function MovementInstance._InitializeInput(self: MovementInstance, Priority: number): ()
	local inputId = string.format("Movement_%s_%s", self.Data.Name, HttpService:GenerateGUID(false))
	local input = InputSystem.new(inputId)

	if not input then 
		Logger:Warn(string.format("_InitializeInput: Failed to initialize input for '%s'", self.Data.Name))
		return 
	end

	-- Set hold mode (default true if not specified)
	input:SetHold(self.Data.Hold)
	input:SetBind(self.Data.InputKey)
	input:SetEnabled(self:IsEnabled())
	input:SetPriority(Priority or 0)

	-- Connect to input activation
	input.Activated:Connect(function(active: boolean, wasPressed: boolean)		
		if not self:IsEnabled() then return end

		-- Handle based on hold mode
		if self.Data.Hold then
			-- Hold mode: active when holding, inactive when released
			self:SetActive(active)

			if active then
				self:ApplyWalkspeed()
			end
			-- REMOVED: RestoreDefaultWalkspeed call - let controller handle it
		else
			-- Toggle mode: active state is toggled
			-- The IAS already handles toggle logic, so 'active' reflects current toggle state
			self:SetActive(active)

			if active then
				self:ApplyWalkspeed()
			end
			-- REMOVED: RestoreDefaultWalkspeed call - let controller handle it
		end
	end)

	self._inputObject = input
	Logger:Debug(string.format("_InitializeInput: Input initialized for '%s' (Key: %s, Hold: %s)", 
		self.Data.Name, tostring(self.Data.InputKey), tostring(self.Data.Hold)))
end

--[[
	Applies the walkspeed to the character
	@return boolean - Successfully applied
]]
function MovementInstance.ApplyWalkspeed(self: MovementInstance): boolean
	if not self:IsEnabled() then
		Logger:Debug(string.format("ApplyWalkspeed: Movement '%s' not enabled", self.Data.Name))
		return false
	end

	local character = self:GetCharacter()
	if not character then
		Logger:Warn(string.format("ApplyWalkspeed: No character found for '%s'", self.Data.Name))
		return false
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		Logger:Warn(string.format("ApplyWalkspeed: No humanoid found for '%s'", self.Data.Name))
		return false
	end

	-- Set walkspeed
	local targetSpeed = self:GetTargetWalkspeed()
	humanoid.WalkSpeed = targetSpeed
	self:SetWalkspeed(targetSpeed)

	Logger:Print(string.format("ApplyWalkspeed: Applied walkspeed %.1f for '%s'", 
		targetSpeed, self.Data.Name))

	return true
end

--[[
	Gets the character from the callback or player
	@return Model? - Character model
]]
function MovementInstance.GetCharacter(self: MovementInstance): Model?
	if self.GetCharacterCallback then
		return self.GetCharacterCallback()
	end

	-- Fallback to LocalPlayer
	local player = Players.LocalPlayer
	return player and (player.Character or player.CharacterAdded:Wait())
end

--[[
	Sets the character callback
	@param callback - Function that returns character
]]
function MovementInstance.SetCharacterCallback(self: MovementInstance, callback: () -> Model?): ()
	self.GetCharacterCallback = callback
	Logger:Debug(string.format("SetCharacterCallback: Character callback set for '%s'", self.Data.Name))
end

--[[
	Activates this movement state
	@return boolean - Successfully activated
]]
function MovementInstance.Activate(self: MovementInstance): boolean
	if not self:IsEnabled() then
		Logger:Debug(string.format("Activate: Cannot activate '%s' - not enabled", self.Data.Name))
		return false
	end

	if self:IsActive() then
		Logger:Debug(string.format("Activate: '%s' already active", self.Data.Name))
		return true
	end

	self:SetActive(true)
	return self:ApplyWalkspeed()
end

--[[
	Deactivates this movement state
	NOTE: Does NOT restore walkspeed - MovementController handles that
]]
function MovementInstance.Deactivate(self: MovementInstance): ()
	if not self:IsActive() then return end

	self:SetActive(false)
	-- REMOVED: RestoreDefaultWalkspeed call - MovementController handles walkspeed transitions
	Logger:Print(string.format("Deactivate: '%s' deactivated", self.Data.Name))
end

--[[
	Updates the target walkspeed
	@param walkspeed - New walkspeed value
]]
function MovementInstance.UpdateTargetWalkspeed(self: MovementInstance, walkspeed: number): ()
	local oldSpeed = self.Data.Walkspeed
	self.Data.Walkspeed = math.max(0, walkspeed)

	Logger:Debug(string.format("UpdateTargetWalkspeed: Target walkspeed for '%s' changed (%.1f -> %.1f)", 
		self.Data.Name, oldSpeed, self.Data.Walkspeed))

	-- Apply immediately if active
	if self:IsActive() then
		self:ApplyWalkspeed()
	end
end

--[[
	Updates the priority
	@param priority - New priority value
]]
function MovementInstance.UpdatePriority(self: MovementInstance, priority: number): ()
	local oldPriority = self.Data.Priority or 0
	self.Data.Priority = priority

	if self._inputObject then
		self._inputObject:SetPriority(priority)
	end

	Logger:Debug(string.format("UpdatePriority: Priority for '%s' changed (%d -> %d)", 
		self.Data.Name, oldPriority, priority))
end

--[[
	Gets current state snapshot
	@return MovementState - Current state
]]
function MovementInstance.GetState(self: MovementInstance): MovementState
	return {
		IsActive = self:IsActive(),
		CurrentWalkspeed = self:GetWalkspeed(),
		IsEnabled = self:IsEnabled(),
	}
end

--[[
	Gets metadata
	@return any - Metadata table
]]
function MovementInstance.GetMetadata(self: MovementInstance): any
	return self._metadata
end

--[[
	Sets metadata
	@param metadata - Metadata to set
]]
function MovementInstance.SetMetadata(self: MovementInstance, metadata: any): ()
	self._metadata = metadata
	Logger:Debug(string.format("SetMetadata: Metadata updated for '%s'", self.Data.Name))
end

--[[
	Cleanup
]]
function MovementInstance.Destroy(self: MovementInstance): ()
	if self.Destroyed then Logger:Warn('MovementInstance has been destroyed') return false end

	self.Destroyed = true

	Logger:Print(string.format("Destroy: Cleaning up MovementInstance '%s'", self.Data.Name))

	-- Deactivate if active
	if self:IsActive() then
		self:Deactivate()
	end

	-- Cleanup input
	if self._inputObject then
		self._inputObject:Destroy()
	end

	-- Cleanup signals
	if self.Signals then
		for _, signal in self.Signals do
			if signal and signal.Destroy then
				signal:Destroy()
			end
		end
	end

	-- Clear data
	self.Data = nil :: any
	self.GetCharacterCallback = nil
	self._metadata = nil

	Logger:Debug(string.format("Destroy: Cleanup complete for '%s'", self.Data.Name or "Unknown"))
end

local module = {}

local metatable = {__index = MovementInstance}

--[[
	Creates a new MovementInstance
	@param data - Movement configuration
	@param metadata - Optional metadata
	@return MovementInstance instance
]]
function module.new(data: MovementInstanceData, metadata: any?)
	assert(data, "MovementInstance requires a Data table")
	assert(data.Name, "MovementInstance Data requires Name")
	assert(data.Walkspeed, "MovementInstance Data requires Walkspeed")
	assert(data.InputKey, "MovementInstance Data requires InputKey")

	local self: MovementInstance = setmetatable({}, metatable)

	-- Core references
	self.Data = data

	-- Default values
	self.Data.Priority = self.Data.Priority or 0
	self.Data.Hold = if self.Data.Hold ~= nil then self.Data.Hold else true -- Default to hold mode

	-- Metadata
	self._metadata = metadata or {}

	-- Signals
	self.Signals = {
		OnMovementActivated = Signal.new(),
		OnMovementDeactivated = Signal.new(),
		OnWalkspeedChanged = Signal.new(),
	}

	-- State tracking (SSOT using direct values)
	self._isActive = false
	self._isEnabled = true
	self._currentWalkspeed = 0

	-- Character callback (public, set via SetCharacterCallback)
	self.GetCharacterCallback = nil

	-- Input reference
	self._inputObject = nil

	-- Setup input
	self:_InitializeInput(self.Data.Priority)

	Logger:Debug(string.format("Created new MovementInstance (Name: %s, Walkspeed: %.1f, InputKey: %s, Priority: %d, Hold: %s)", 
		data.Name,
		data.Walkspeed,
		tostring(data.InputKey),
		data.Priority or 0,
		tostring(data.Hold)))

	return self
end

export type MovementInstance = typeof(setmetatable({} :: {
	Data: MovementInstanceData,
	_isActive: boolean,
	_isEnabled: boolean,
	_currentWalkspeed: number,
	_metadata: any,
	_inputObject: any,
	GetCharacterCallback: (() -> Model?)?,
	Signals: MovementSignals,
}, metatable))

return table.freeze(module)