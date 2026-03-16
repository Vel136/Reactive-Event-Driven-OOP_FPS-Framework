-- MovementController.lua
--[[
	Manages multiple MovementInstance states including:
	- Priority-based movement state management
	- Default/base walkspeed handling
	- Movement state activation/deactivation
	- Character integration
	- SSOT pattern for all state management
]]

-- Services
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local Players = game:GetService('Players')

-- References
local Utilities = ReplicatedStorage.Shared.Modules.Utilities

-- Modules
local MovementInstance = require(script.MovementInstance)
local LogService = require(Utilities.Logger)
local Signal = require(Utilities.Signal)

export type MovementInstance = MovementInstance.MovementInstance
--[=[
	@class MovementController
	
	Orchestrates multiple MovementInstance states with priority-based activation.
	Manages walkspeed transitions between default and various movement states.
	Uses Single Source of Truth pattern for all state management.
]=]
local Identity = "MovementController"
local MovementController = {}

local Logger = LogService.new(Identity, false)

--[[
	Gets the current active movement name
	SINGLE SOURCE OF TRUTH for reading active movement
	@return string? - Active movement name
]]
function MovementController.GetActiveMovement(self: MovementController): string?
	return self._activeMovement
end

--[[
	Gets the current applied walkspeed
	SINGLE SOURCE OF TRUTH for reading current walkspeed
	@return number - Current walkspeed
]]
function MovementController.GetCurrentWalkspeed(self: MovementController): number
	return self._currentWalkspeed
end

--[[
	Gets the default walkspeed
	@return number - Default walkspeed
]]
function MovementController.GetDefaultWalkspeed(self: MovementController): number
	return self.Data.DefaultWalkspeed
end

--[[
	Gets the character
	SINGLE SOURCE OF TRUTH for reading character
	@return Model? - Character model
]]
function MovementController.GetCharacter(self: MovementController): Model?
	return self._character
end

--[[
	Sets the active movement
	SINGLE SOURCE OF TRUTH for writing active movement
	@param movementName - Name of active movement (nil for none)
]]
function MovementController.SetActiveMovement(self: MovementController, movementName: string?): ()
	local oldValue = self._activeMovement
	self._activeMovement = movementName

	if oldValue ~= self._activeMovement then
		self.Signals.OnActiveMovementChanged:Fire(movementName, oldValue)
		Logger:Debug(string.format("SetActiveMovement: Active movement changed (%s -> %s)", 
			tostring(oldValue), tostring(movementName)))
	end
end

--[[
	Sets the current walkspeed
	SINGLE SOURCE OF TRUTH for writing current walkspeed
	@param walkspeed - Walkspeed value
]]
function MovementController.SetCurrentWalkspeed(self: MovementController, walkspeed: number): ()
	local oldValue = self._currentWalkspeed
	self._currentWalkspeed = math.max(0, walkspeed)

	if oldValue ~= self._currentWalkspeed then
		Logger:Debug(string.format("SetCurrentWalkspeed: Current walkspeed changed (%.1f -> %.1f)", 
			oldValue, self._currentWalkspeed))
	end
end

--[[
	Sets the character
	SINGLE SOURCE OF TRUTH for writing character
	@param character - Character model
]]
function MovementController.SetCharacter(self: MovementController, character: Model?): ()
	local oldValue = self._character
	self._character = character

	if oldValue ~= self._character then
		Logger:Debug(string.format("SetCharacter: Character changed (%s -> %s)", 
			tostring(oldValue), tostring(character)))

		-- Update all movement instances with new character callback
		for _, movement in self._movements do
			movement:SetCharacterCallback(function()
				return self:GetCharacter()
			end)
		end

		-- Reapply current walkspeed
		self:ApplyCurrentWalkspeed()
	end
end

--[[
	Updates the default walkspeed
	@param walkspeed - New default walkspeed
]]
function MovementController.SetDefaultWalkspeed(self: MovementController, walkspeed: number): ()
	local oldValue = self.Data.DefaultWalkspeed
	self.Data.DefaultWalkspeed = math.max(0, walkspeed)

	Logger:Debug(string.format("SetDefaultWalkspeed: Default walkspeed changed (%.1f -> %.1f)", 
		oldValue, self.Data.DefaultWalkspeed))

	-- Reapply if no active movement
	if not self:GetActiveMovement() then
		self:ApplyDefaultWalkspeed()
	end
end

--[[
	Adds a new movement state
	@param data - Movement configuration
	@return MovementInstance? - Created movement instance
]]
function MovementController.AddMovement(self: MovementController, data: MovementData): MovementInstance.MovementInstance
	assert(data, "AddMovement requires movement data")
	assert(data.Name, "Movement data requires Name")
	assert(data.Walkspeed, "Movement data requires Walkspeed")
	assert(data.InputKey, "Movement data requires InputKey")

	-- Check if movement already exists
	if self._movements[data.Name] then
		Logger:Warn(string.format("AddMovement: Movement '%s' already exists", data.Name))
		return self._movements[data.Name]
	end

	-- Create movement instance
	local movementData = {
		Name = data.Name,
		Walkspeed = data.Walkspeed,
		InputKey = data.InputKey,
		Priority = data.Priority or 0,
	}

	local movement = MovementInstance.new(movementData)

	-- Set character callback
	movement:SetCharacterCallback(function()
		return self:GetCharacter()
	end)

	-- Connect to movement signals
	movement.Signals.OnMovementActivated:Connect(function()
		-- Track activation time
		self._activationTimes[data.Name] = os.clock()

		self:_OnMovementActivated(data.Name)
	end)

	movement.Signals.OnMovementDeactivated:Connect(function()
		-- Clear activation time on deactivation
		self._activationTimes[data.Name] = nil

		self:_OnMovementDeactivated(data.Name)
	end)

	movement.Signals.OnWalkspeedChanged:Connect(function(newSpeed, oldSpeed)
		-- Update current walkspeed if this is the active movement
		if self:GetActiveMovement() == data.Name then
			self:SetCurrentWalkspeed(newSpeed)
		end
	end)

	-- Store movement
	self._movements[data.Name] = movement

	-- Fire signal
	self.Signals.OnMovementAdded:Fire(data.Name, movement)

	Logger:Print(string.format("AddMovement: Added movement '%s' (Walkspeed: %.1f, Priority: %d)", 
		data.Name, data.Walkspeed, data.Priority or 0))

	return movement :: MovementInstance.MovementInstance
end

--[[
	Removes a movement state
	@param name - Movement name to remove
	@return boolean - Successfully removed
]]
function MovementController.RemoveMovement(self: MovementController, name: string): boolean
	local movement = self._movements[name]

	if not movement then
		Logger:Warn(string.format("RemoveMovement: Movement '%s' not found", name))
		return false
	end

	-- Deactivate if currently active
	if self:GetActiveMovement() == name then
		-- Find next best movement before removing
		self._activationTimes[name] = nil  -- Temporarily clear so it won't be found
		local nextMovement = self:_FindBestActiveMovement()
		self._movements[name] = nil  -- Temporarily remove

		if nextMovement then
			self:SetActiveMovement(nextMovement)
			self:ApplyMovementWalkspeed(nextMovement)
		else
			self:SetActiveMovement(nil)
			self:ApplyDefaultWalkspeed()
		end
	else
		-- Clear activation time
		self._activationTimes[name] = nil
	end

	-- Destroy movement
	movement:Destroy()
	self._movements[name] = nil

	-- Fire signal
	self.Signals.OnMovementRemoved:Fire(name)

	Logger:Print(string.format("RemoveMovement: Removed movement '%s'", name))

	return true
end

--[[
	Gets a movement instance by name
	@param name - Movement name
	@return MovementInstance? - Movement instance
]]
function MovementController.GetMovement(self: MovementController, name: string): any?
	return self._movements[name]
end

--[[
	Checks if a movement exists
	@param name - Movement name
	@return boolean - Movement exists
]]
function MovementController.HasMovement(self: MovementController, name: string): boolean
	return self._movements[name] ~= nil
end

--[[
	Gets all movement names
	@return {string} - Array of movement names
]]
function MovementController.GetAllMovementNames(self: MovementController): {string}
	local names = {}
	for name, _ in self._movements do
		table.insert(names, name)
	end
	return names
end

--[[
	Gets the count of registered movements
	@return number - Movement count
]]
function MovementController.GetMovementCount(self: MovementController): number
	local count = 0
	for _, _ in self._movements do
		count += 1
	end
	return count
end

--[[
	Handles movement activation
	INTERNAL - Called when a movement becomes active
	@param name - Movement name
]]
function MovementController._OnMovementActivated(self: MovementController, name: string): ()
	local movement = self._movements[name]
	if not movement then return end

	Logger:Debug(string.format("_OnMovementActivated: Movement '%s' (Priority: %d) activated", 
		name, movement:GetPriority()))

	-- Find the best movement among all active ones
	local bestMovement = self:_FindBestActiveMovement()

	if bestMovement == name then
		-- This movement should be active
		Logger:Print(string.format("_OnMovementActivated: Activating '%s' (Priority: %d)", 
			name, movement:GetPriority()))
		self:SetActiveMovement(name)
		self:ApplyMovementWalkspeed(name)
	else
		-- Another movement has higher priority or is more recent with same priority
		Logger:Debug(string.format("_OnMovementActivated: '%s' activated but '%s' remains active (higher priority or more recent)", 
			name, tostring(bestMovement)))
	end
end

--[[
	Handles movement deactivation
	INTERNAL - Called when a movement becomes inactive
	@param name - Movement name
]]
function MovementController._OnMovementDeactivated(self: MovementController, name: string): ()
	Logger:Debug(string.format("_OnMovementDeactivated: Movement '%s' deactivated", name))

	-- Find the next best movement
	local nextMovement = self:_FindBestActiveMovement()

	if nextMovement then
		Logger:Print(string.format("_OnMovementDeactivated: Switching to '%s'", nextMovement))
		self:SetActiveMovement(nextMovement)
		self:ApplyMovementWalkspeed(nextMovement)
	else
		-- No active movements, return to default
		Logger:Print("_OnMovementDeactivated: Returning to default walkspeed")
		self:SetActiveMovement(nil)
		self:ApplyDefaultWalkspeed()
	end
end

--[[
	Finds the best active movement considering both priority and recency
	INTERNAL
	Priority rules:
	1. Higher priority always wins
	2. Same priority: most recently activated wins
	@return string? - Movement name
]]
function MovementController._FindBestActiveMovement(self: MovementController): string?
	local bestMovement = nil
	local bestPriority = -math.huge
	local bestTime = -math.huge

	Logger:Debug("_FindBestActiveMovement: Evaluating active movements")

	for name, movement in self._movements do
		if movement:IsActive() and movement:IsEnabled() then
			local priority = movement:GetPriority()
			local activationTime = self._activationTimes[name] or -math.huge

			Logger:Debug(string.format("  - %s: Priority=%d, Time=%.3f", 
				name, priority, activationTime))

			-- Higher priority always wins
			if priority > bestPriority then
				bestMovement = name
				bestPriority = priority
				bestTime = activationTime
				Logger:Debug(string.format("    → New best (higher priority)"))
				-- Same priority: most recent wins
			elseif priority == bestPriority and activationTime > bestTime then
				bestMovement = name
				bestTime = activationTime
				Logger:Debug(string.format("    → New best (same priority, more recent)"))
			end
		end
	end

	Logger:Debug(string.format("_FindBestActiveMovement: Best movement is '%s' (Priority: %d, Time: %.3f)", 
		tostring(bestMovement), bestPriority, bestTime))

	return bestMovement
end

--[[
	Applies the default walkspeed to character
	@return boolean - Successfully applied
]]
function MovementController.ApplyDefaultWalkspeed(self: MovementController): boolean
	local character = self:GetCharacter()
	if not character then
		Logger:Warn("ApplyDefaultWalkspeed: No character found")
		return false
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		Logger:Warn("ApplyDefaultWalkspeed: No humanoid found")
		return false
	end

	local defaultSpeed = self:GetDefaultWalkspeed()
	humanoid.WalkSpeed = defaultSpeed
	self:SetCurrentWalkspeed(defaultSpeed)

	self.Signals.OnWalkspeedApplied:Fire(defaultSpeed, nil)

	Logger:Print(string.format("ApplyDefaultWalkspeed: Applied default walkspeed (%.1f)", defaultSpeed))

	return true
end

--[[
	Applies a specific movement's walkspeed to character
	@param name - Movement name
	@return boolean - Successfully applied
]]
function MovementController.ApplyMovementWalkspeed(self: MovementController, name: string): boolean
	local movement = self._movements[name]
	if not movement then
		Logger:Warn(string.format("ApplyMovementWalkspeed: Movement '%s' not found", name))
		return false
	end

	local character = self:GetCharacter()
	if not character then
		Logger:Warn("ApplyMovementWalkspeed: No character found")
		return false
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		Logger:Warn("ApplyMovementWalkspeed: No humanoid found")
		return false
	end

	local walkspeed = movement:GetTargetWalkspeed()
	humanoid.WalkSpeed = walkspeed
	self:SetCurrentWalkspeed(walkspeed)

	self.Signals.OnWalkspeedApplied:Fire(walkspeed, name)

	Logger:Print(string.format("ApplyMovementWalkspeed: Applied walkspeed %.1f for '%s'", walkspeed, name))

	return true
end

--[[
	Applies the current walkspeed (either active movement or default)
	@return boolean - Successfully applied
]]
function MovementController.ApplyCurrentWalkspeed(self: MovementController): boolean
	local activeMovement = self:GetActiveMovement()

	if activeMovement then
		return self:ApplyMovementWalkspeed(activeMovement)
	else
		return self:ApplyDefaultWalkspeed()
	end
end

--[[
	Enables a specific movement
	@param name - Movement name
	@return boolean - Successfully enabled
]]
function MovementController.EnableMovement(self: MovementController, name: string): boolean
	local movement = self._movements[name]

	if not movement then
		Logger:Warn(string.format("EnableMovement: Movement '%s' not found", name))
		return false
	end

	movement:SetEnabled(true)
	Logger:Print(string.format("EnableMovement: Enabled movement '%s'", name))

	return true
end

--[[
	Disables a specific movement
	@param name - Movement name
	@return boolean - Successfully disabled
]]
function MovementController.DisableMovement(self: MovementController, name: string): boolean
	local movement = self._movements[name]

	if not movement then
		Logger:Warn(string.format("DisableMovement: Movement '%s' not found", name))
		return false
	end

	movement:SetEnabled(false)
	Logger:Print(string.format("DisableMovement: Disabled movement '%s'", name))

	return true
end

--[[
	Enables all movements
]]
function MovementController.EnableAllMovements(self: MovementController): ()
	Logger:Print("EnableAllMovements: Enabling all movements")

	for name, movement in self._movements do
		movement:SetEnabled(true)
	end
end

--[[
	Disables all movements
]]
function MovementController.DisableAllMovements(self: MovementController): ()
	Logger:Print("DisableAllMovements: Disabling all movements")

	for name, movement in self._movements do
		movement:SetEnabled(false)
	end

	-- Return to default walkspeed
	self:ApplyDefaultWalkspeed()
end

--[[
	Gets current state snapshot
	@return MovementControllerState - Current state
]]
function MovementController.GetState(self: MovementController): MovementControllerState
	return {
		ActiveMovement = self:GetActiveMovement(),
		CurrentWalkspeed = self:GetCurrentWalkspeed(),
		MovementCount = self:GetMovementCount(),
		DefaultWalkspeed = self:GetDefaultWalkspeed(),
	}
end

--[[
	Gets metadata
	@return any - Metadata table
]]
function MovementController.GetMetadata(self: MovementController): any
	return self._metadata
end

--[[
	Sets metadata
	@param metadata - Metadata to set
]]
function MovementController.SetMetadata(self: MovementController, metadata: any): ()
	self._metadata = metadata
	Logger:Debug("SetMetadata: Metadata updated")
end

--[[
	Cleanup
]]
function MovementController.Destroy(self: MovementController): ()
	Logger:Print("Destroy: Cleaning up MovementController")

	-- Destroy all movements
	for name, movement in self._movements do
		movement:Destroy()
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
	self._movements = {}
	self._activationTimes = {}
	self.Data = nil :: any
	self._metadata = nil

	Logger:Debug("Destroy: Cleanup complete")
end

local module = {}

local metatable = {__index = MovementController}

--[[
	Creates a new MovementController
	@param data - Controller configuration
	@param metadata - Optional metadata
	@return MovementController instance
]]
function module.new(data: MovementControllerData?, metadata: any?)
	local self: MovementController = setmetatable({}, metatable)

	-- Core references
	self.Data = data or {}

	-- Default values
	self.Data.DefaultWalkspeed = self.Data.DefaultWalkspeed or 16
	self.Data.Character = self.Data.Character

	-- Metadata
	self._metadata = metadata or {}

	-- Signals
	self.Signals = {
		OnMovementAdded = Signal.new(),
		OnMovementRemoved = Signal.new(),
		OnActiveMovementChanged = Signal.new(),
		OnWalkspeedApplied = Signal.new(),
	}

	-- State tracking (SSOT using direct values)
	self._activeMovement = nil
	self._currentWalkspeed = self.Data.DefaultWalkspeed
	self._character = self.Data.Character

	-- Movement storage
	self._movements = {}

	-- Activation time tracking (for finding most recent)
	self._activationTimes = {}

	Logger:Debug(string.format("Created new MovementController (DefaultWalkspeed: %.1f)", 
		self.Data.DefaultWalkspeed))

	return self
end
export type MovementControllerData = {
	DefaultWalkspeed: number,
	Character: Model?,
}

type Signal = Signal.Signal
export type MovementControllerSignals = {
	OnMovementAdded: Signal,
	OnMovementRemoved: Signal,
	OnActiveMovementChanged: Signal,
	OnWalkspeedApplied: Signal,
}

export type MovementControllerState = {
	ActiveMovement: string?,
	CurrentWalkspeed: number,
	MovementCount: number,
	DefaultWalkspeed: number,
}

export type MovementData = {
	Name: string,
	Walkspeed: number,
	InputKey: Enum.KeyCode,
	Priority: number?,
}
export type MovementController = typeof(setmetatable({} :: {
	Data: MovementControllerData,
	_activeMovement: string?,
	_currentWalkspeed: number,
	_character: Model?,
	_movements: {[string]: any},
	_activationTimes: {[string]: number},
	_metadata: any,
	Signals: MovementControllerSignals,
}, metatable))

return table.freeze(module)