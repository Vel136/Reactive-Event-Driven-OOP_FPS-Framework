-- InventoryController.lua
--[[
	Manages grenade stack inventory:
	- Stock tracking (how many grenades the player carries)
	- Consumption on throw
	- Pickup / resupply
]]

local Identity = "InventoryController"

-- ─── Services ────────────────────────────────────────────────────────────────

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ─── References ──────────────────────────────────────────────────────────────

local Utilities = ReplicatedStorage.Shared.Modules.Utilities

-- ─── Modules ─────────────────────────────────────────────────────────────────

local Signal     = require(Utilities:FindFirstChild("Signal"))
local LogService = require(Utilities:FindFirstChild("Logger"))

-- ─── Module ──────────────────────────────────────────────────────────────────

local InventoryController   = {}
InventoryController.__index = InventoryController
InventoryController.__type  = Identity

-- ─── Private state ───────────────────────────────────────────────────────────

local Logger = LogService.new(Identity, false)

-- ─── Getters ─────────────────────────────────────────────────────────────────

--- Returns current stock count.
function InventoryController.GetStock(self: InventoryController): number
	return self._Stock
end

--- Returns the maximum stock allowed.
function InventoryController.GetMaxStock(self: InventoryController): number
	return self.Data.MaxStock
end

--- Returns stock as a 0–1 percentage.
function InventoryController.GetStockPercentage(self: InventoryController): number
	return self._Stock / self.Data.MaxStock
end

--- Returns the current inventory state snapshot.
function InventoryController.GetState(self: InventoryController)
	return {
		Stock      = self._Stock,
		MaxStock   = self.Data.MaxStock,
		Percentage = self:GetStockPercentage(),
		IsEmpty    = self:IsEmpty(),
	}
end

-- ─── Queries ─────────────────────────────────────────────────────────────────

--- Returns true if there is at least one grenade in stock.
function InventoryController.HasStock(self: InventoryController): boolean
	return self._Stock > 0
end

--- Returns true if stock is fully depleted.
function InventoryController.IsEmpty(self: InventoryController): boolean
	return self._Stock <= 0
end

--- Returns true if stock is at maximum capacity.
function InventoryController.IsFull(self: InventoryController): boolean
	return self._Stock >= self.Data.MaxStock
end

-- ─── Setters ─────────────────────────────────────────────────────────────────

--- Sets stock directly, clamped to [0, MaxStock]. Fires signals if changed.
function InventoryController.SetStock(self: InventoryController, amount: number)
	local old = self._Stock
	self._Stock = math.clamp(amount, 0, self.Data.MaxStock)

	if old ~= self._Stock then
		self.Signals.OnStockChanged:Fire(self._Stock, old)
		Logger:Debug(string.format("SetStock: %d -> %d", old, self._Stock))

		if self._Stock <= 0 then
			self.Signals.OnStockEmpty:Fire()
			Logger:Print("SetStock: stock empty")
		end
	end
end

-- ─── Stock operations ────────────────────────────────────────────────────────

--- Consumes grenades from stock. Returns true if successful.
function InventoryController.Consume(self: InventoryController, amount: number?): boolean
	local cost = amount or 1

	if self._Stock < cost then
		Logger:Warn(string.format("Consume: insufficient stock (%d/%d)", self._Stock, cost))
		self.Signals.OnStockEmpty:Fire()
		return false
	end

	self:SetStock(self._Stock - cost)
	Logger:Debug(string.format("Consume: -%d, remaining %d", cost, self._Stock))
	return true
end

--- Adds grenades to stock, clamped to MaxStock. Returns the amount actually added.
function InventoryController.AddStock(self: InventoryController, amount: number): number
	local old    = self._Stock
	local newVal = math.min(old + amount, self.Data.MaxStock)
	local added  = newVal - old

	if added > 0 then
		self:SetStock(newVal)
		Logger:Debug(string.format("AddStock: +%d (was %d)", added, old))
	end

	return added
end

--- Refills stock to maximum.
function InventoryController.Refill(self: InventoryController)
	Logger:Print("Refill: refilling to max")
	self:SetStock(self.Data.MaxStock)
end

-- ─── Lifecycle ───────────────────────────────────────────────────────────────

--- Cleans up the InventoryController.
function InventoryController.Destroy(self: InventoryController)
	Logger:Print("Destroy: cleaning up InventoryController")

	for _, signal in pairs(self.Signals) do
		signal:Destroy()
	end

	self.Data = nil
	Logger:Debug("Destroy: complete")
end

-- ─── Constructor ─────────────────────────────────────────────────────────────

local module = {}

--- Creates a new InventoryController.
function module.new(inventoryData: InventoryData): InventoryController
	assert(inventoryData,              "InventoryController.new: inventoryData is required")
	assert(inventoryData.MaxStock,     "InventoryController.new: missing MaxStock")
	assert(inventoryData.DefaultStock, "InventoryController.new: missing DefaultStock")

	local self: InventoryController = setmetatable({}, { __index = InventoryController })

	self.Data   = inventoryData
	self._Stock = math.clamp(inventoryData.DefaultStock, 0, inventoryData.MaxStock)

	self.Signals = {
		OnStockChanged = Signal.new(),
		OnStockEmpty   = Signal.new(),
	}

	Logger:Debug(string.format("new: Stock=%d MaxStock=%d",
		self._Stock,
		inventoryData.MaxStock
		))

	return self
end

-- ─── Types ───────────────────────────────────────────────────────────────────

export type InventoryData = {
	MaxStock     : number,
	DefaultStock : number,
}

export type InventoryController = typeof(setmetatable({}, { __index = InventoryController })) & {
	Data    : InventoryData,
	_Stock  : number,
	Signals : {
		OnStockChanged : Signal.Signal<(current: number, previous: number) -> ()>,
		OnStockEmpty   : Signal.Signal<() -> ()>,
	},
}

return table.freeze(module)