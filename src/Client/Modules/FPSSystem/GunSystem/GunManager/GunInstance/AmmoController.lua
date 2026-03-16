-- AmmoController.lua
--[[
	Manages weapon ammunition including:
	- Magazine and reserve ammo tracking
	- Reload system with Promises
	- Ammo consumption
	- Reload cancellation
]]

local Identity = "AmmoController"

-- ─── Services ────────────────────────────────────────────────────────────────

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ─── References ──────────────────────────────────────────────────────────────

local Utilities = ReplicatedStorage.Shared.Modules.Utilities

-- ─── Modules ─────────────────────────────────────────────────────────────────

local Promise    = require(Utilities:FindFirstChild("Promise"))
local Signal     = require(Utilities:FindFirstChild("Signal"))
local LogService = require(Utilities:FindFirstChild("Logger"))

-- ─── Module ──────────────────────────────────────────────────────────────────

local AmmoController   = {}
AmmoController.__index = AmmoController
AmmoController.__type  = Identity

-- ─── Private state ───────────────────────────────────────────────────────────

local Logger = LogService.new(Identity, false)

-- ─── Getters ─────────────────────────────────────────────────────────────────

--- Returns current magazine ammo.
function AmmoController.GetAmmo(self: AmmoController): number
	return self._Ammo
end

--- Returns current reserve ammo.
function AmmoController.GetReserve(self: AmmoController): number
	return self._Reserve
end

--- Returns the magazine size.
function AmmoController.GetMagazineSize(self: AmmoController): number
	return self.Data.MagazineSize
end

--- Returns total ammo (magazine + reserve).
function AmmoController.GetTotalAmmo(self: AmmoController): number
	return self._Ammo + self._Reserve
end

--- Returns magazine fill percentage (0–1).
function AmmoController.GetAmmoPercentage(self: AmmoController): number
	return self._Ammo / self.Data.MagazineSize
end

--- Returns the current ammo state snapshot.
function AmmoController.GetState(self: AmmoController)
	return {
		Ammo         = self._Ammo,
		Reserve      = self._Reserve,
		Total        = self:GetTotalAmmo(),
		Percentage   = self:GetAmmoPercentage(),
		MagazineSize = self.Data.MagazineSize,
		IsReloading  = self:IsReloading(),
	}
end

--- Returns the metadata table.
function AmmoController.GetMetadata(self: AmmoController)
	return self._Metadata
end

-- ─── Queries ─────────────────────────────────────────────────────────────────

--- Returns true if there is ammo in the magazine.
function AmmoController.HasAmmo(self: AmmoController): boolean
	return self._Ammo > 0
end

--- Returns true if the magazine is at full capacity.
function AmmoController.IsMagazineFull(self: AmmoController): boolean
	return self._Ammo >= self.Data.MagazineSize
end

--- Returns true if the magazine is empty.
function AmmoController.IsMagazineEmpty(self: AmmoController): boolean
	return self._Ammo <= 0
end

--- Returns true if there is reserve ammo.
function AmmoController.HasReserve(self: AmmoController): boolean
	return self._Reserve > 0
end

--- Returns true if reserve ammo is depleted.
function AmmoController.IsReserveEmpty(self: AmmoController): boolean
	return self._Reserve <= 0
end

--- Returns true if a reload is currently in progress.
function AmmoController.IsReloading(self: AmmoController): boolean
	return self._ReloadPromise ~= nil
end

--- Returns true if a reload is possible (not full and has reserve).
function AmmoController.CanReload(self: AmmoController): boolean
	return not self:IsMagazineFull() and self:HasReserve()
end

-- ─── Setters ─────────────────────────────────────────────────────────────────

--- Sets magazine ammo, clamped to magazine size. Fires OnAmmoChanged if value changed.
function AmmoController.SetAmmo(self: AmmoController, amount: number)
	local old = self._Ammo
	self._Ammo = math.clamp(amount, 0, self.Data.MagazineSize)

	if old ~= self._Ammo then
		self.Signals.OnAmmoChanged:Fire(self._Ammo, old)
		Logger:Debug(string.format("SetAmmo: %d -> %d", old, self._Ammo))
	end
end

--- Sets reserve ammo, clamped to >= 0. Fires OnReserveChanged if value changed.
function AmmoController.SetReserve(self: AmmoController, amount: number)
	local old = self._Reserve
	self._Reserve = math.max(0, amount)

	if old ~= self._Reserve then
		self.Signals.OnReserveChanged:Fire(self._Reserve, old)
		Logger:Debug(string.format("SetReserve: %d -> %d", old, self._Reserve))
	end
end

--- Sets the metadata table.
function AmmoController.SetMetadata(self: AmmoController, metadata: any)
	self._Metadata = metadata
end

-- ─── Ammo operations ─────────────────────────────────────────────────────────

--- Adds ammo to the magazine (clamped). Returns the amount actually added.
function AmmoController.AddAmmo(self: AmmoController, amount: number): number
	local old    = self._Ammo
	local newVal = math.min(old + amount, self.Data.MagazineSize)
	local added  = newVal - old

	if added > 0 then self:SetAmmo(newVal) end
	return added
end

--- Adds ammo to the reserve. Returns the amount added.
function AmmoController.AddReserve(self: AmmoController, amount: number): number
	if amount > 0 then
		self:SetReserve(self._Reserve + amount)
	end
	return amount
end

--- Transfers ammo from reserve into the magazine to fill it. Returns the amount moved.
function AmmoController.FillMagazine(self: AmmoController): number
	local needed = self.Data.MagazineSize - self._Ammo
	local toAdd  = math.min(needed, self._Reserve)

	if toAdd > 0 then
		self:SetAmmo(self._Ammo + toAdd)
		self:SetReserve(self._Reserve - toAdd)
	end

	return toAdd
end

--- Refills both magazine and reserve to their maximums.
function AmmoController.RefillAll(self: AmmoController)
	Logger:Print("RefillAll: refilling all ammo")
	self:SetAmmo(self.Data.MagazineSize)
	self:SetReserve(self.Data.ReserveSize or 120)
end

--- Consumes ammo on fire. Fires OnEmpty if the magazine runs dry. Returns success.
function AmmoController.ConsumeAmmo(self: AmmoController, amount: number?): boolean
	local cost    = amount or 1
	local current = self._Ammo

	Logger:Debug(string.format("ConsumeAmmo: %d requested, %d available", cost, current))

	if current < cost then
		Logger:Warn(string.format("ConsumeAmmo: insufficient ammo (%d/%d)", current, cost))
		self.Signals.OnEmpty:Fire()
		return false
	end

	self:SetAmmo(current - cost)

	if self._Ammo <= 0 then
		Logger:Print("ConsumeAmmo: magazine empty")
		self.Signals.OnEmpty:Fire()
	end

	return true
end

-- ─── Reload ──────────────────────────────────────────────────────────────────

--- Starts a reload. Returns a cached Promise if already reloading.
function AmmoController.Reload(self: AmmoController): any
	if self._ReloadPromise then
		Logger:Debug("Reload: already reloading, returning cached promise")
		return self._ReloadPromise
	end

	if self:IsMagazineFull() then
		Logger:Warn(string.format("Reload: magazine full (%d/%d)", self._Ammo, self.Data.MagazineSize))
		return Promise.reject("Magazine full")
	end

	if not self:HasReserve() then
		Logger:Warn("Reload: no reserve ammo")
		return Promise.reject("No reserve ammo")
	end

	Logger:Print(string.format("Reload: starting (%d/%d, reserve %d)",
		self._Ammo, self.Data.MagazineSize, self._Reserve))

	self._ReloadPromise = Promise.new(function(resolve, _, onCancel)
		self.LastReloadTime = os.clock()
		self.Signals.OnReloadStarted:Fire()

		local cancelled = false
		onCancel(function()
			cancelled = true
			self.LastReloadTime = os.clock() - 2
			self._ReloadPromise = nil
			self.Signals.OnReloadCancelled:Fire()
			Logger:Print("Reload: cancelled")
		end)

		task.delay(self.Data.ReloadTime or 2, function()
			if cancelled then return end

			local needed   = self.Data.MagazineSize - self._Ammo
			local toReload = math.min(needed, self._Reserve)

			self._ReloadPromise = nil
			self:SetAmmo(self._Ammo + toReload)
			self:SetReserve(self._Reserve - toReload)

			self.Signals.OnReloadComplete:Fire(self._Ammo, self._Reserve)

			Logger:Print(string.format("Reload: complete (%d/%d, reserve %d)",
				self._Ammo, self.Data.MagazineSize, self._Reserve))

			resolve({ Ammo = self._Ammo, Reserve = self._Reserve })
		end)
	end)

	return self._ReloadPromise
end

--- Cancels an in-progress reload.
function AmmoController.CancelReload(self: AmmoController)
	if self._ReloadPromise then
		Logger:Debug("CancelReload: cancelling active reload")
		self._ReloadPromise:cancel()
		self._ReloadPromise = nil
	end
end

-- ─── Lifecycle ───────────────────────────────────────────────────────────────

--- Cleans up the AmmoController.
function AmmoController.Destroy(self: AmmoController)
	Logger:Print("Destroy: cleaning up AmmoController")

	self:CancelReload()

	for _, signal in pairs(self.Signals) do
		signal:Destroy()
	end

	self.Data = nil

	Logger:Debug("Destroy: complete")
end

-- ─── Constructor ─────────────────────────────────────────────────────────────

local module = {}

--- Creates a new AmmoController.
function module.new(ammoData: AmmoData, metadata: any?)
	local self: AmmoController = setmetatable({}, { __index = AmmoController })

	self.Data = ammoData

	self._Ammo    = ammoData.MagazineSize or 30
	self._Reserve = ammoData.ReserveSize  or 120

	self._ReloadPromise = nil
	self.LastReloadTime = 0

	self._Metadata = metadata or {}

	self.Signals = {
		OnAmmoChanged     = Signal.new(),
		OnReserveChanged  = Signal.new(),
		OnReloadStarted   = Signal.new(),
		OnReloadComplete  = Signal.new(),
		OnReloadCancelled = Signal.new(),
		OnEmpty           = Signal.new(),
	}

	Logger:Debug(string.format("new: Magazine=%d Reserve=%d ReloadTime=%.1fs",
		ammoData.MagazineSize or 30,
		ammoData.ReserveSize  or 120,
		ammoData.ReloadTime   or 2
		))

	return self
end

-- ─── Types ───────────────────────────────────────────────────────────────────

export type AmmoData = {
	MagazineSize    : number,
	ReserveSize     : number,
	ReloadTime      : number,
	ReloadEmptyTime : number,
}

export type AmmoController = typeof(setmetatable({}, { __index = AmmoController })) & {
	Data            : AmmoData,
	_Ammo           : number,
	_Reserve        : number,
	_ReloadPromise  : any,
	_Metadata       : any,
	LastReloadTime  : number,
	Signals: {
		OnAmmoChanged     : Signal.Signal<(current: number, previous: number) -> ()>,
		OnReserveChanged  : Signal.Signal<(current: number, previous: number) -> ()>,
		OnReloadStarted   : Signal.Signal<() -> ()>,
		OnReloadComplete  : Signal.Signal<(ammo: number, reserve: number) -> ()>,
		OnReloadCancelled : Signal.Signal<() -> ()>,
		OnEmpty           : Signal.Signal<() -> ()>,
	},
}

return table.freeze(module)