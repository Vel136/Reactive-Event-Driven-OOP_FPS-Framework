-- GlobalMovementHandler.lua
--[[
	A singleton movement system that weapons can interact with using simple method calls.
	Weapons don't create their own movement instances - they just call methods like:
	- GlobalMovementHandler:SetAimingWalkspeed(5)
	- GlobalMovementHandler:EnableSprint(false)
	- GlobalMovementHandler:IsSprinting()
]]

-- Services
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local Players = game:GetService('Players')

-- References
local Utilities = ReplicatedStorage.Shared.Modules.Utilities

-- Modules
local MovementController = require(script.MovementController)
local LogService = require(Utilities.Logger)

--[=[
	@class GlobalMovementHandler
	
	Singleton service that manages all character movement.
	Weapons and other systems interact with it using simple method calls.
]=]
local Identity = "GlobalMovementHandler"
local GlobalMovementHandler = {}
GlobalMovementHandler.__index = GlobalMovementHandler
GlobalMovementHandler.__type = Identity

local Logger = LogService.new(Identity, false)

-- Singleton instance
local instance = nil


--[[
	Initializes the movement system with default movement states
]]
function GlobalMovementHandler:_Initialize()
	Logger:Print("_Initialize: Setting up GlobalMovementHandler")

	local player = Players.LocalPlayer

	-- Create the underlying movement controller without character initially
	self._controller = MovementController.new({
		DefaultWalkspeed = 16,
		Character = nil, -- Will be set when character loads
	})

	-- Setup default movement states
	self:_SetupDefaultMovements()

	-- Store references to commonly used movements
	self._sprintMovement = self._controller:GetMovement("Sprint")
	self._slowWalkMovement = self._controller:GetMovement("SlowWalk")

	-- Set character if already exists
	if player.Character then
		self._controller:SetCharacter(player.Character)
		Logger:Print("_Initialize: Character already exists, applied immediately")
	end

	-- Listen for character spawns (including first spawn if not loaded yet)
	player.CharacterAdded:Connect(function(newCharacter)
		self._controller:SetCharacter(newCharacter)
		Logger:Print("Character loaded/respawned - movement system updated")
	end)

	Logger:Print("_Initialize: GlobalMovementHandler initialized (non-blocking)")
end

--[[
	Sets up the default movement states (Sprint, SlowWalk)
]]
function GlobalMovementHandler._SetupDefaultMovements(self : GlobalMovementHandler)
	-- Sprint movement (LeftShift)
	self._controller:AddMovement({
		Name = "Sprint",
		Walkspeed = 20,
		InputKey = Enum.KeyCode.LeftShift,
		Priority = 10,
	})
	
	-- Slow walk movement (LeftControl)
	self._controller:AddMovement({
		Name = "SlowWalk",
		Walkspeed = 8,
		InputKey = Enum.KeyCode.LeftControl,
		Priority = 5,
	})
	self._controller:AddMovement({
		Name = "Aiming",
		Walkspeed = 8,
		InputKey = Enum.KeyCode.Unknown, -- No input key, manually activated
		Priority = 10, 
	})
	Logger:Debug("_SetupDefaultMovements: Default movements created")
end

--[[
	Gets the underlying movement controller (for advanced usage)
	@return MovementController
]]
function GlobalMovementHandler:GetController()
	return self._controller
end

-- ========================================
-- WALKSPEED METHODS (for weapons to call)
-- ========================================

--[[
	Sets the base/default walkspeed
	Call this when equipping/unequipping weapons with different base speeds
	@param walkspeed number - Default walkspeed
]]
function GlobalMovementHandler.SetDefaultWalkspeed(self : GlobalMovementHandler,walkspeed: number)
	self._controller:SetDefaultWalkspeed(walkspeed)
	
	Logger:Print(string.format("SetDefaultWalkspeed: Set to %.1f", walkspeed))
end

--[[
	Reset default walkspeed to original configuration
	Call this when equipping/unequipping weapons with different base speeds
	@param walkspeed number - Default walkspeed
]]
function GlobalMovementHandler.ResetDefaultWalkspeed(self : GlobalMovementHandler)
	self._controller:SetDefaultWalkspeed(16)

	Logger:Print(string.format("SetDefaultWalkspeed: Set to %.1f", 16))
end
--[[
	Gets the current walkspeed being applied
	@return number - Current walkspeed
]]
function GlobalMovementHandler.GetCurrentWalkspeed(self : GlobalMovementHandler): number
	return self._controller:GetCurrentWalkspeed()
end

--[[
	Gets the default walkspeed
	@return number - Default walkspeed
]]
function GlobalMovementHandler.GetDefaultWalkspeed(self : GlobalMovementHandler): number
	return self._controller:GetDefaultWalkspeed()
end

-- ========================================
-- SPRINT METHODS (for weapons to call)
-- ========================================

--[[
	Enables or disables sprint
	Call this to prevent sprinting while reloading, aiming, etc.
	@param enabled boolean - Whether sprint is enabled
]]
function GlobalMovementHandler.EnableSprint(self : GlobalMovementHandler, enabled: boolean)
	if enabled then
		self._controller:EnableMovement("Sprint")
		Logger:Debug("EnableSprint: Sprint enabled")
	else
		self._controller:DisableMovement("Sprint")
		Logger:Debug("EnableSprint: Sprint disabled")
	end
end

--[[
	Checks if the player is currently sprinting
	@return boolean - Is sprinting
]]
function GlobalMovementHandler.IsSprinting(self : GlobalMovementHandler): boolean
	local sprintMovement = self._controller:GetMovement("Sprint")
	return sprintMovement and sprintMovement:IsActive() or false
end

--[[
	Gets the sprint movement state for signal connections
	@return MovementInstance?
]]
function GlobalMovementHandler.GetSprintMovement(self : GlobalMovementHandler)
	return self._controller:GetMovement("Sprint")
end

--[[
	Updates the sprint speed
	@param walkspeed number - New sprint speed
]]
function GlobalMovementHandler.SetSprintSpeed(self : GlobalMovementHandler,walkspeed: number)
	local sprintMovement = self._controller:GetMovement("Sprint")
	if sprintMovement then
		sprintMovement:UpdateTargetWalkspeed(walkspeed)
		Logger:Debug(string.format("SetSprintSpeed: Updated to %.1f", walkspeed))
	end
end

-- ========================================
-- SLOW WALK METHODS (for weapons to call)
-- ========================================

--[[
	Enables or disables slow walk
	@param enabled boolean - Whether slow walk is enabled
]]
function GlobalMovementHandler.EnableSlowWalk(self : GlobalMovementHandler,enabled: boolean)
	if enabled then
		self._controller:EnableMovement("SlowWalk")
		Logger:Debug("EnableSlowWalk: Slow walk enabled")
	else
		self._controller:DisableMovement("SlowWalk")
		Logger:Debug("EnableSlowWalk: Slow walk disabled")
	end
end

--[[
	Checks if the player is currently slow walking
	@return boolean - Is slow walking
]]
function GlobalMovementHandler.IsSlowWalking(self : GlobalMovementHandler): boolean
	local slowWalkMovement = self._controller:GetMovement("SlowWalk")
	return slowWalkMovement and slowWalkMovement:IsActive() or false
end

--[[
	Gets the slow walk movement state for signal connections
	@return MovementInstance?
]]
function GlobalMovementHandler.GetSlowWalkMovement(self : GlobalMovementHandler)
	return self._controller:GetMovement("SlowWalk")
end

--[[
	Updates the slow walk speed
	@param walkspeed number - New slow walk speed
]]
function GlobalMovementHandler.SetSlowWalkSpeed(self : GlobalMovementHandler,walkspeed: number)
	local slowWalkMovement = self._controller:GetMovement("SlowWalk")
	if slowWalkMovement then
		slowWalkMovement:UpdateTargetWalkspeed(walkspeed)
		Logger:Debug(string.format("SetSlowWalkSpeed: Updated to %.1f", walkspeed))
	end
end

-- ========================================
-- AIMING METHODS (for weapons to call)
-- ========================================

--[[
	Sets the walkspeed while aiming
	Automatically creates/updates an "Aiming" movement state
	@param walkspeed number - Aiming walkspeed
]]
function GlobalMovementHandler.SetAimingWalkspeed(self : GlobalMovementHandler,walkspeed: number)
	-- Check if Aiming movement exists
	if not self._controller:HasMovement("Aiming") then
		-- Create it (manual activation, high priority)
		self._controller:AddMovement({
			Name = "Aiming",
			Walkspeed = walkspeed,
			InputKey = Enum.KeyCode.Unknown, -- No input key, manually activated
			Priority = 10, 
		})
		Logger:Debug(string.format("SetAimingWalkspeed: Created Aiming movement (%.1f)", walkspeed))
	else
		-- Update existing
		local aimingMovement = self._controller:GetMovement("Aiming")
		aimingMovement:UpdateTargetWalkspeed(walkspeed)
		Logger:Debug(string.format("SetAimingWalkspeed: Updated to %.1f", walkspeed))
	end
end

--[[
	Activates aiming movement state
	Call this when the player starts aiming
]]
function GlobalMovementHandler.StartAiming(self : GlobalMovementHandler)
	local aimingMovement = self._controller:GetMovement("Aiming")
	aimingMovement:Activate()
end

--[[
	Deactivates aiming movement state
	Call this when the player stops aiming
]]
function GlobalMovementHandler.StopAiming(self : GlobalMovementHandler)
	local aimingMovement = self._controller:GetMovement("Aiming")
	aimingMovement:Deactivate()
end

--[[
	Checks if the player is currently aiming
	@return boolean - Is aiming
]]
function GlobalMovementHandler.IsAiming(self : GlobalMovementHandler): boolean
	local aimingMovement = self._controller:GetMovement("Aiming")
	return aimingMovement and aimingMovement:IsActive() or false
end

-- ========================================
-- CUSTOM MOVEMENT METHODS
-- ========================================

--[[
	Creates a custom movement state
	Use this for weapon-specific movements (e.g., heavy weapon penalty)
	@param name string - Movement name
	@param walkspeed number - Walkspeed for this state
	@param priority number? - Priority (default: 0)
	@return MovementInstance
]]
function GlobalMovementHandler.CreateCustomMovement(self : GlobalMovementHandler,name: string, walkspeed: number, inputkey, priority: number?) :  MovementController.MovementInstance
	if self._controller:HasMovement(name) then
		Logger:Warn(string.format("CreateCustomMovement: Movement '%s' already exists", name))
		return self._controller:GetMovement(name)
	end

	local movement = self._controller:AddMovement({
		Name = name,
		Walkspeed = walkspeed,
		InputKey = inputkey or Enum.KeyCode.Unknown, -- Manual activation
		Priority = priority or 0,
	})

	Logger:Print(string.format("CreateCustomMovement: Created '%s' (%.1f walkspeed, priority %d)", 
		name, walkspeed, priority or 0))

	return movement :: MovementController.MovementInstance
end

--[[
	Removes a custom movement state
	@param name string - Movement name
]]
function GlobalMovementHandler.RemoveCustomMovement(self : GlobalMovementHandler,name: string)
	if self._controller:RemoveMovement(name) then
		Logger:Print(string.format("RemoveCustomMovement: Removed '%s'", name))
	end
end

--[[
	Activates a custom movement state
	@param name string - Movement name
]]
function GlobalMovementHandler.ActivateCustomMovement(self : GlobalMovementHandler,name: string)
	local movement = self._controller:GetMovement(name)
	if movement then
		movement:Activate()
		Logger:Debug(string.format("ActivateCustomMovement: Activated '%s'", name))
	else
		Logger:Warn(string.format("ActivateCustomMovement: Movement '%s' not found", name))
	end
end

--[[
	Deactivates a custom movement state
	@param name string - Movement name
]]
function GlobalMovementHandler.DeactivateCustomMovement(self : GlobalMovementHandler,name: string)
	local movement = self._controller:GetMovement(name)
	if movement then
		movement:Deactivate()
		Logger:Debug(string.format("DeactivateCustomMovement: Deactivated '%s'", name))
	else
		Logger:Warn(string.format("DeactivateCustomMovement: Movement '%s' not found", name))
	end
end

-- ========================================
-- STATE QUERY METHODS
-- ========================================

--[[
	Gets the name of the currently active movement
	@return string? - Active movement name (nil if using default)
]]
function GlobalMovementHandler:GetActiveMovementName(): string?
	return self._controller:GetActiveMovement()
end

--[[
	Checks if any movement state is active
	@return boolean - Has active movement
]]
function GlobalMovementHandler:HasActiveMovement(): boolean
	return self._controller:GetActiveMovement() ~= nil
end

--[[
	Gets all registered movement names
	@return {string} - Array of movement names
]]
function GlobalMovementHandler:GetAllMovementNames(): {string}
	return self._controller:GetAllMovementNames()
end


function GlobalMovementHandler:GetSignals()
	return self._controller.Signals
end


--[[
	Disables all movement states
	Useful when the player is stunned, dead, etc.
]]
function GlobalMovementHandler:DisableAllMovements()
	self._controller:DisableAllMovements()
	Logger:Print("DisableAllMovements: All movements disabled")
end

--[[
	Enables all movement states
]]
function GlobalMovementHandler:EnableAllMovements()
	self._controller:EnableAllMovements()
	Logger:Print("EnableAllMovements: All movements enabled")
end

-- ========================================
-- SINGLETON PATTERN
-- ========================================

local metatable = {__index = GlobalMovementHandler}

--[[
	Gets or creates the singleton instance
	@return GlobalMovementHandler
]]
local function GetInstance()
	if not instance then
		instance = setmetatable({}, metatable)
		instance:_Initialize()
	end
	return instance
end

export type GlobalMovementHandler = typeof(setmetatable({} :: {
	_controller: MovementController.MovementController,
	_sprintMovement: any,
	_slowWalkMovement: any,
}, metatable))

-- Export as singleton with read-only access
return setmetatable({}, {
	__index = function(_, key)
		return GetInstance()[key]
	end,
	__newindex = function()
		error("Cannot modify GlobalMovementHandler singleton", 2)
	end
}) :: GlobalMovementHandler

