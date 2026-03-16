-- GunInputManager.lua
--[[
	Handles all player input and exposes signals for consumers to react to.
	Singleton. Import and listen to GunInputManager.Signals.
]]

local Identity = "GunInputManager"

-- Services
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")

-- References
local Utilities = ReplicatedStorage.Shared.Modules.Utilities

-- Modules
local Signal = require(Utilities.Signal)
local IAS    = require(Utilities.IAS)

-- Types
export type FireMode = "Auto" | "Semi"

-- ─── Module ──────────────────────────────────────────────────────────────────

local GunInputManager   = {}
GunInputManager.__index = GunInputManager
GunInputManager.__type  = Identity

-- ─── Signals ─────────────────────────────────────────────────────────────────

GunInputManager.Signals = {
	FireStarted   = Signal.new(), -- ()         fired once when trigger is pulled
	FireStopped   = Signal.new(), -- ()         fired once when trigger is released
	FirePulse     = Signal.new(), -- ()         fired every frame while auto-firing
	Reloaded      = Signal.new(), -- ()
	AimStarted    = Signal.new(), -- ()
	AimStopped    = Signal.new(), -- ()
	SprintStarted = Signal.new(), -- ()
	SprintStopped = Signal.new(), -- ()
}

-- ─── IAS Actions (public so callers can rebind if needed) ────────────────────

GunInputManager.Actions = {
	Fire   = IAS.new("Fire"),
	Reload = IAS.new("Reload"),
	Aim    = IAS.new("Aim"),
}

-- ─── Private state ───────────────────────────────────────────────────────────

local _fireMode    : FireMode = "Auto"
local _isFiring    : boolean  = false
local _autoThread  : thread?  = nil

-- ─── Private helpers ─────────────────────────────────────────────────────────

local function _startAutoFire()
	if _autoThread then return end

	GunInputManager.Signals.FireStarted:Fire()

	_autoThread = task.spawn(function()
		while _isFiring do
			GunInputManager.Signals.FirePulse:Fire()
			task.wait()
		end
	end)
end

local function _stopAutoFire()
	if _autoThread then
		task.cancel(_autoThread)
		_autoThread = nil
	end

	GunInputManager.Signals.FireStopped:Fire()
end

-- ─── Initialization ───────────────────────────────────────────────────────────

function GunInputManager:_Initialize()
	UserInputService.MouseIconEnabled = false

	local Actions = self.Actions
	local Signals = self.Signals

	-- Binds
	Actions.Fire:AddBind(Enum.KeyCode.MouseLeftButton)
	Actions.Fire:SetHold(true)

	Actions.Reload:AddBind(Enum.KeyCode.R)
	Actions.Reload:SetHold(false)

	Actions.Aim:AddBind(Enum.KeyCode.MouseRightButton)
	Actions.Aim:SetHold(true)

	-- Fire
	Actions.Fire.Activated:Connect(function(active, wasPressed)
		if active and wasPressed then
			_isFiring = true
			if _fireMode == "Auto" then
				_startAutoFire()
			else
				-- Semi: single pulse per press
				Signals.FireStarted:Fire()
				Signals.FirePulse:Fire()
			end

		elseif not active and not wasPressed then
			_isFiring = false
			if _fireMode == "Auto" then
				_stopAutoFire()
			else
				Signals.FireStopped:Fire()
			end
		end
	end)

	-- Reload
	Actions.Reload.Activated:Connect(function(active, wasPressed)
		if active and wasPressed then
			Signals.Reloaded:Fire()
		end
	end)

	-- Aim
	Actions.Aim.Activated:Connect(function(active, wasPressed)
		if active and wasPressed then
			Signals.AimStarted:Fire()
		elseif not active and not wasPressed then
			Signals.AimStopped:Fire()
		end
	end)
end

-- ─── Public API ───────────────────────────────────────────────────────────────

--- Returns the current fire mode.
function GunInputManager.GetFireMode(): FireMode
	return _fireMode
end

--- Switches fire mode. Stops any active auto-fire loop if switching to Semi.
function GunInputManager.SetFireMode(mode: FireMode): boolean
	if mode ~= "Auto" and mode ~= "Semi" then
		warn("[GunInputManager]: Invalid fire mode — expected 'Auto' or 'Semi'")
		return false
	end

	if mode == "Semi" and _autoThread then
		_isFiring = false
		_stopAutoFire()
	end

	_fireMode = mode
	return true
end

--- Enables or disables a named action. Cleans up auto-fire if Fire is disabled mid-burst.
function GunInputManager.SetEnabled(name: "Fire" | "Reload" | "Aim" | "Sprint", enabled: boolean): boolean
	local action = GunInputManager.Actions[name]
	if not action then
		warn("[GunInputManager]: Unknown action '" .. tostring(name) .. "'")
		return false
	end

	action:SetEnabled(enabled)

	if name == "Fire" and not enabled and _isFiring then
		_isFiring = false
		_stopAutoFire()
	end

	return true
end

-- ─── Singleton bootstrap ─────────────────────────────────────────────────────

GunInputManager:_Initialize()

return GunInputManager :: typeof(GunInputManager)