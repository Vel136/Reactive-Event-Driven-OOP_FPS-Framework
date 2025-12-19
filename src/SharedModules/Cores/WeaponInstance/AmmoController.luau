-- AmmoController.lua
--[[
	Manages weapon ammunition including:
	- Magazine and reserve ammo tracking
	- Reload system with Promises
	- Ammo consumption
	- Reload cancellation
]]

local ReplicatedStorage = game:GetService('ReplicatedStorage')
local Utilities = ReplicatedStorage.SharedModules.Utilities
local Promise = require(Utilities:FindFirstChild("Promise"))
local Signal = require(Utilities:FindFirstChild("Signal"))
local Logger = require(Utilities:FindFirstChild("LogService"))

--[=[
	@class Ammo
	
	Main gun orchestrator - fully solver-agnostic.
	Uses BulletContext instead of FastCast objects for ballistics simulation.
	
	This class manages all weapon functionality including firing, reloading, aiming,
	and state management through specialized controller sub-systems.
]=]
local AmmoController = {}
AmmoController.__index = AmmoController

--[[
	Creates a new AmmoController
	@param ammoData - Ammo configuration from weapon data
	@param stateManager - Reference to StateManager
	@return AmmoController instance
]]
function AmmoController.new(ammoData, stateManager)
	local self = setmetatable({}, AmmoController)

	self.Data = ammoData
	self.StateManager = stateManager

	-- Tracking
	self.Ammo = Instance.new("IntValue")
	self.Reserve = Instance.new("IntValue")
	self.Ammo.Value = ammoData.MagazineSize or 30
	self.Reserve.Value = ammoData.ReserveSize or 120

	-- Reload Promise cache
	self.ReloadPromise = nil
	self.LastReloadTime = 0

	-- Signals
	self.Signals = {
		OnAmmoChanged = Signal.new(),
		OnReserveChanged = Signal.new(),
		OnReload = Signal.new(),
		OnReloadComplete = Signal.new(),
		OnEmpty = Signal.new(),
	}

	return self
end

--[[
	Checks if there's ammo available to fire
	@return boolean - Has ammo
]]
function AmmoController:HasAmmo(): boolean
	return self.Ammo.Value > 0
end

--[[
	Checks if magazine is full
	@return boolean - Is full
]]
function AmmoController:IsMagazineFull(): boolean
	return self.Ammo.Value >= self.Data.MagazineSize
end

--[[
	Checks if there's reserve ammo
	@return boolean - Has reserve
]]
function AmmoController:HasReserve(): boolean
	return self.Reserve.Value > 0
end

--[[
	Consumes ammo when firing
	@param amount - Amount to consume (default: 1)
	@return boolean - Successfully consumed
]]
function AmmoController:ConsumeAmmo(amount: number?): boolean
	local amountToConsume = amount or 1
	
	if self.Ammo.Value < amountToConsume then
		self.Signals.OnEmpty:Fire()
		return false
	end

	local oldValue = self.Ammo.Value
	self.Ammo.Value -= amountToConsume
	self.Signals.OnAmmoChanged:Fire(self.Ammo.Value, oldValue)

	-- Fire empty signal if we just ran out
	if self.Ammo.Value <= 0 then
		self.Signals.OnEmpty:Fire()
	end

	return true
end

--[[
	Starts reload process
	@return Promise - Resolves when reload completes
]]
function AmmoController:Reload(): any
	-- Return cached Promise if already reloading
	if self.ReloadPromise then
		return self.ReloadPromise
	end

	-- Validation
	if self:IsMagazineFull() then
		return Promise.reject("Magazine full")
	end

	if not self:HasReserve() then
		return Promise.reject("No reserve ammo")
	end

	-- Create and cache Promise
	self.ReloadPromise = Promise.new(function(resolve, reject, onCancel)
		-- Start reload
		self.StateManager:SetReloading(true)
		self.LastReloadTime = os.clock()
		self.Signals.OnReload:Fire()

		-- Setup cancellation
		local cancelled = false
		onCancel(function()
			cancelled = true
			self.LastReloadTime = os.clock() - 2
			self.StateManager:SetReloading(false)
			self.ReloadPromise = nil
		end)

		-- Schedule reload completion
		task.delay(self.Data.ReloadTime or 2, function()
			if cancelled then return end

			-- Calculate and apply ammo
			local needed = self.Data.MagazineSize - self.Ammo.Value
			local toReload = math.min(needed, self.Reserve.Value)

			local oldAmmo = self.Ammo.Value
			local oldReserve = self.Reserve.Value

			self.Ammo.Value += toReload
			self.Reserve.Value -= toReload

			-- Complete reload
			self.StateManager:SetReloading(false)
			self.ReloadPromise = nil

			self.Signals.OnAmmoChanged:Fire(self.Ammo.Value, oldAmmo)
			self.Signals.OnReserveChanged:Fire(self.Reserve.Value, oldReserve)
			self.Signals.OnReloadComplete:Fire(self.Ammo.Value, self.Reserve.Value)

			resolve({
				Ammo = self.Ammo.Value,
				Reserve = self.Reserve.Value
			})
		end)
	end)

	return self.ReloadPromise
end

--[[
	Cancels ongoing reload
]]
function AmmoController:CancelReload()
	if self.ReloadPromise then
		self.ReloadPromise:cancel()
		self.ReloadPromise = nil
	end
end

--[[
	Gets current ammo state
	@return table - {Ammo, Reserve}
]]
function AmmoController:GetState()
	return {
		Ammo = self.Ammo.Value,
		Reserve = self.Reserve.Value,
	}
end

--[[
	Adds ammo to reserve
	@param amount - Amount to add
]]
function AmmoController:AddReserve(amount: number)
	local oldValue = self.Reserve.Value
	self.Reserve.Value += amount
	self.Signals.OnReserveChanged:Fire(self.Reserve.Value, oldValue)
end

--[[
	Cleanup
]]
function AmmoController:Destroy()
	-- Cancel any ongoing reload
	self:CancelReload()

	-- Cleanup signals
	for _, signal in pairs(self.Signals) do
		signal:Destroy()
	end

	-- Cleanup values
	if self.Ammo then self.Ammo:Destroy() end
	if self.Reserve then self.Reserve:Destroy() end

	self.StateManager = nil
	self.Data = nil
end

return AmmoController