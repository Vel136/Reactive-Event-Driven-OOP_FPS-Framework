--[[
	Weighted RNG Module for Roblox
	Allows selection of items based on their assigned weights
	
	Usage:
		local WeightedRNG = require(script.WeightedRNG)
		local rng = WeightedRNG.new()
		
		rng:AddItem("Common", 70)
		rng:AddItem("Rare", 25)
		rng:AddItem("Legendary", 5)
		
		local result = rng:Pick()
		print(result) -- More likely to be "Common"
--]]

local WeightedRNG = {}
WeightedRNG.__index = WeightedRNG

-- Creates a new WeightedRNG instance
function WeightedRNG.new()
	local self = setmetatable({}, WeightedRNG)
	self.items = {}
	self.totalWeight = 0
	self.random = Random.new()
	return self
end

-- Add a single item with its weight
function WeightedRNG:AddItem(item, weight)
	assert(type(weight) == "number", "Weight must be a number")
	assert(weight > 0, "Weight must be greater than 0")

	table.insert(self.items, {
		item = item,
		weight = weight
	})
	self.totalWeight = self.totalWeight + weight

	return self
end

-- Add multiple items at once
-- items should be a table like: {{item = "Common", weight = 70}, {item = "Rare", weight = 25}}
function WeightedRNG:AddItems(items)
	for _, data in ipairs(items) do
		self:AddItem(data.Item, data.Weight)
	end
	return self
end

-- Remove all items
function WeightedRNG:Clear()
	self.items = {}
	self.totalWeight = 0
	return self
end

-- Pick a random item based on weights
function WeightedRNG:Pick()
	assert(#self.items > 0, "No items to pick from")

	local rand = self.random:NextNumber(0, self.totalWeight)
	local sum = 0

	for _, data in ipairs(self.items) do
		sum = sum + data.weight
		if rand <= sum then
			return data.item
		end
	end

	-- Fallback (shouldn't reach here)
	return self.items[#self.items].item
end

-- Pick multiple items (with replacement)
function WeightedRNG:PickMultiple(count)
	local results = {}
	for i = 1, count do
		table.insert(results, self:Pick())
	end
	return results
end

-- Pick multiple unique items (without replacement)
function WeightedRNG:PickUnique(count)
	assert(count <= #self.items, "Cannot pick more unique items than available")

	local tempRNG = WeightedRNG.new()
	tempRNG.random = self.random

	for _, data in ipairs(self.items) do
		tempRNG:AddItem(data.item, data.weight)
	end

	local results = {}
	for i = 1, count do
		local picked = tempRNG:Pick()
		table.insert(results, picked)
		tempRNG:RemoveItem(picked)
	end

	return results
end

-- Remove a specific item
function WeightedRNG:RemoveItem(item)
	for i, data in ipairs(self.items) do
		if data.item == item then
			self.totalWeight = self.totalWeight - data.weight
			table.remove(self.items, i)
			return true
		end
	end
	return false
end

-- Get the probability of an item (0-1)
function WeightedRNG:GetProbability(item)
	for _, data in ipairs(self.items) do
		if data.item == item then
			return data.weight / self.totalWeight
		end
	end
	return 0
end

-- Set a custom Random object (useful for seeding)
function WeightedRNG:SetRandom(randomObj)
	self.random = randomObj
	return self
end


return WeightedRNG