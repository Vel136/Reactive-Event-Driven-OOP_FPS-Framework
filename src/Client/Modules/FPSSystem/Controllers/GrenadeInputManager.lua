-- GrenadeInputManager.lua
--[[
	Handles all grenade-related player input and exposes signals for consumers to react to.
	Singleton. Import and listen to GrenadeInputManager.Signals.

	Default binds:
	  G          — equip/unequip grenade slot (toggle)
	  Hold LMB   — cook grenade while held
	  Release LMB — throw
	  Q          — cancel cook without throwing
]]

local Identity = "GrenadeInputManager"

-- ─── Services ────────────────────────────────────────────────────────────────

local UserInputService  = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ─── References ──────────────────────────────────────────────────────────────

local Utilities = ReplicatedStorage.Shared.Modules.Utilities

-- ─── Modules ─────────────────────────────────────────────────────────────────

local Signal = require(Utilities.Signal)
local IAS    = require(Utilities.IAS)

-- ─── Module ──────────────────────────────────────────────────────────────────

local GrenadeInputManager   = {}
GrenadeInputManager.__index = GrenadeInputManager
GrenadeInputManager.__type  = Identity

-- ─── Signals ─────────────────────────────────────────────────────────────────

GrenadeInputManager.Signals = {
	GrenadeHeld       = Signal.new(), -- ()                     fired when cook input is held
	GrenadeReleased   = Signal.new(), -- ()                     fired when cook input is released (throw)
	GrenadeCancelled  = Signal.new(), -- ()                     fired when player cancels a cook
}

-- ─── IAS Actions ─────────────────────────────────────────────────────────────

GrenadeInputManager.Actions = {
	Cook   = IAS.new("GrenadeCook"),   -- Hold to cook, release to throw
	Cancel = IAS.new("GrenadeCancel"), -- Cancel cook without throwing
}

-- ─── Private state ───────────────────────────────────────────────────────────

local _isCooking  : boolean = false

-- ─── Initialization ──────────────────────────────────────────────────────────

function GrenadeInputManager:_Initialize()
	local Actions = self.Actions
	local Signals = self.Signals

	Actions.Cook:AddBind(Enum.KeyCode.MouseLeftButton)
	Actions.Cook:SetHold(true)

	Actions.Cancel:AddBind(Enum.KeyCode.Q)
	Actions.Cancel:SetHold(false)

	-- Cook (hold) / Throw (release)
	Actions.Cook.Activated:Connect(function(active, wasPressed)
		if active and wasPressed then
			_isCooking = true
			Signals.GrenadeHeld:Fire()
		elseif not active and not wasPressed then
			if _isCooking then
				_isCooking = false
				Signals.GrenadeReleased:Fire()
			end
		end
	end)

	-- Cancel cook
	Actions.Cancel.Activated:Connect(function(active, wasPressed)
		if not active or not wasPressed then return end
		if not _isCooking then return end

		_isCooking = false
		Signals.GrenadeCancelled:Fire()
	end)
end

-- ─── Public API ──────────────────────────────────────────────────────────────

--- Returns whether the grenade is currently being cooked.
function GrenadeInputManager.IsCooking(): boolean
	return _isCooking
end

--- Force-clears cooking state. Called externally if grenade throws or unequips mid-cook.
function GrenadeInputManager.ClearCookState()
	_isCooking = false
end

--- Enables or disables a named action.
function GrenadeInputManager.SetEnabled(name: "Equip" | "Cook" | "Cancel", enabled: boolean): boolean
	local action = GrenadeInputManager.Actions[name]
	if not action then
		warn("[GrenadeInputManager]: Unknown action '" .. tostring(name) .. "'")
		return false
	end

	action:SetEnabled(enabled)

	-- If cook is disabled mid-cook, clean up state
	if name == "Cook" and not enabled and _isCooking then
		_isCooking = false
		GrenadeInputManager.Signals.GrenadeCancelled:Fire()
	end

	return true
end

-- ─── Singleton bootstrap ─────────────────────────────────────────────────────

GrenadeInputManager:_Initialize()

return GrenadeInputManager :: typeof(GrenadeInputManager)