-- MaxHeap.lua (OPTIMIZED)
--[[
	Manages a maximum heap data structure including:
	- Insert operations with automatic heapify
	- Extract maximum element
	- Peek at maximum without removal
	- Size tracking and empty checking
	- O(log n) removal with index tracking
]]

local ReplicatedStorage = game:GetService('ReplicatedStorage')
local Utilities = ReplicatedStorage.Shared.Modules.Utilities

local Signal = require(Utilities:FindFirstChild("Signal"))
local LogService = require(Utilities:FindFirstChild("Logger"))

--[=[
	@class MaxHeap
	
	A maximum heap implementation with O(log n) insertion and extraction.
	Elements are ordered such that the largest element is always at the root.
	
	Supports custom comparison functions for complex data types.
	OPTIMIZED: O(log n) removal with element-to-index tracking.
]=]
local Identity = "MaxHeap"
local MaxHeap = {}

local Logger = LogService.new(Identity, false)

--[[
	Gets the current size of the heap
	SINGLE SOURCE OF TRUTH for reading size
	@return number - Current heap size
]]
function MaxHeap.GetSize(self : MaxHeap): number
	return #self._heap
end

--[[
	Checks if heap is empty
	@return boolean - Is empty
]]
function MaxHeap.IsEmpty(self : MaxHeap): boolean
	return self:GetSize() == 0
end

--[[
	Peeks at the maximum element without removing it
	@return any? - Maximum element or nil if empty
]]
function MaxHeap.Peek(self : MaxHeap): any?
	if self:IsEmpty() then
		Logger:Warn("Peek: Heap is empty")
		return nil
	end
	return self._heap[1]
end

--[[
	Gets the parent index of a node
	@param index - Child index
	@return number - Parent index
]]
function MaxHeap.GetParentIndex(self : MaxHeap, index: number): number
	return math.floor(index / 2)
end

--[[
	Gets the left child index of a node
	@param index - Parent index
	@return number - Left child index
]]
function MaxHeap.GetLeftChildIndex(self : MaxHeap, index: number): number
	return index * 2
end

--[[
	Gets the right child index of a node
	@param index - Parent index
	@return number - Right child index
]]
function MaxHeap.GetRightChildIndex(self : MaxHeap, index: number): number
	return index * 2 + 1
end

--[[
	Checks if a node has a parent
	@param index - Node index
	@return boolean - Has parent
]]
function MaxHeap.HasParent(self : MaxHeap, index: number): boolean
	return self:GetParentIndex(index) >= 1
end

--[[
	Checks if a node has a left child
	@param index - Node index
	@return boolean - Has left child
]]
function MaxHeap.HasLeftChild(self : MaxHeap, index: number): boolean
	return self:GetLeftChildIndex(index) <= self:GetSize()
end

--[[
	Checks if a node has a right child
	@param index - Node index
	@return boolean - Has right child
]]
function MaxHeap.HasRightChild(self : MaxHeap, index: number): boolean
	return self:GetRightChildIndex(index) <= self:GetSize()
end

--[[
	Compares two elements using the comparator function
	@param a - First element
	@param b - Second element
	@return boolean - True if a > b (for max heap)
]]
function MaxHeap.Compare(self : MaxHeap, a: any, b: any): boolean
	return self._comparator(a, b)
end

--[[
	OPTIMIZED: Updates index map when swapping
	Swaps two elements in the heap and updates tracking
	@param indexA - First index
	@param indexB - Second index
]]
function MaxHeap.Swap(self : MaxHeap, indexA: number, indexB: number)
	local elementA = self._heap[indexA]
	local elementB = self._heap[indexB]

	-- Swap in heap array
	self._heap[indexA] = elementB
	self._heap[indexB] = elementA

	-- Update index map
	if self._indexMap then
		self._indexMap[elementA] = indexB
		self._indexMap[elementB] = indexA
	end

	Logger:Debug(string.format("Swap: Swapped indices %d and %d", indexA, indexB))
end

--[[
	Bubbles up an element to maintain heap property
	@param index - Starting index (default: last element)
]]
function MaxHeap.HeapifyUp(self : MaxHeap, index: number?)
	local currentIndex = index or self:GetSize()

	while self:HasParent(currentIndex) do
		local parentIndex = self:GetParentIndex(currentIndex)

		if self:Compare(self._heap[currentIndex], self._heap[parentIndex]) then
			self:Swap(currentIndex, parentIndex)
			currentIndex = parentIndex
		else
			break
		end
	end

	Logger:Debug(string.format("HeapifyUp: Complete at index %d", currentIndex))
end

--[[
	Bubbles down an element to maintain heap property
	@param index - Starting index (default: root)
]]
function MaxHeap.HeapifyDown(self : MaxHeap, index: number?)
	local currentIndex = index or 1

	while self:HasLeftChild(currentIndex) do
		local largerChildIndex = self:GetLeftChildIndex(currentIndex)

		if self:HasRightChild(currentIndex) then
			local rightChildIndex = self:GetRightChildIndex(currentIndex)
			if self:Compare(self._heap[rightChildIndex], self._heap[largerChildIndex]) then
				largerChildIndex = rightChildIndex
			end
		end

		if self:Compare(self._heap[currentIndex], self._heap[largerChildIndex]) then
			break
		else
			self:Swap(currentIndex, largerChildIndex)
			currentIndex = largerChildIndex
		end
	end

	Logger:Debug(string.format("HeapifyDown: Complete at index %d", currentIndex))
end

--[[
	OPTIMIZED: Updates index map on insert
	Inserts an element into the heap
	@param element - Element to insert
]]
function MaxHeap.Insert(self : MaxHeap, element: any)
	if element == nil then
		Logger:Warn("Insert: Cannot insert nil element")
		return
	end

	-- Check for duplicates if tracking enabled
	if self._indexMap and self._indexMap[element] ~= nil then
		Logger:Warn("Insert: Element already exists in heap (duplicate elements not supported with index tracking)")
		return
	end

	table.insert(self._heap, element)
	local newIndex = self:GetSize()
	local oldSize = newIndex - 1

	-- Update index map
	if self._indexMap then
		self._indexMap[element] = newIndex
	end

	Logger:Debug(string.format("Insert: Added element at index %d", newIndex))

	self:HeapifyUp()

	self.Signals.OnInsert:Fire(element, self:GetSize())

	Logger:Print(string.format("Insert: Heap size (%d -> %d)", oldSize, self:GetSize()))
end

--[[
	OPTIMIZED: Updates index map on extract
	Extracts and returns the maximum element
	@return any? - Maximum element or nil if empty
]]
function MaxHeap.ExtractMax(self : MaxHeap): any?
	if self:IsEmpty() then
		Logger:Warn("ExtractMax: Heap is empty")
		return nil
	end

	local maxElement = self._heap[1]
	local lastElement = table.remove(self._heap)
	local oldSize = self:GetSize() + 1

	-- Remove from index map
	if self._indexMap then
		self._indexMap[maxElement] = nil
	end

	if not self:IsEmpty() then
		self._heap[1] = lastElement

		-- Update index map for moved element
		if self._indexMap then
			self._indexMap[lastElement] = 1
		end

		self:HeapifyDown()
	end

	self.Signals.OnExtract:Fire(maxElement, self:GetSize())

	Logger:Print(string.format("ExtractMax: Extracted maximum element, heap size (%d -> %d)", oldSize, self:GetSize()))

	return maxElement
end

--[[
	OPTIMIZED: O(log n) removal using index map
	Removes a specific element from the heap
	@param element - Element to remove
	@return boolean - Successfully removed
]]
function MaxHeap.Remove(self : MaxHeap, element: any): boolean
	-- O(1) lookup with index map, O(n) fallback without
	local elementIndex = nil

	if self._indexMap then
		elementIndex = self._indexMap[element]
		if not elementIndex then
			Logger:Warn("Remove: Element not found in heap")
			return false
		end
	else
		-- Fallback to linear search if no index map
		for i = 1, self:GetSize() do
			if self._heap[i] == element then
				elementIndex = i
				break
			end
		end

		if not elementIndex then
			Logger:Warn("Remove: Element not found in heap")
			return false
		end
	end

	-- Remove from index map
	if self._indexMap then
		self._indexMap[element] = nil
	end

	-- If it's the last element, just remove it
	if elementIndex == self:GetSize() then
		table.remove(self._heap)
		self.Signals.OnRemove:Fire(element, self:GetSize())
		Logger:Debug(string.format("Remove: Removed last element at index %d", elementIndex))
		return true
	end

	-- Replace with last element
	local lastElement = table.remove(self._heap)
	self._heap[elementIndex] = lastElement

	-- Update index map for moved element
	if self._indexMap then
		self._indexMap[lastElement] = elementIndex
	end

	-- OPTIMIZED: Only heapify in the necessary direction
	-- Compare with parent to determine direction
	if self:HasParent(elementIndex) then
		local parentIndex = self:GetParentIndex(elementIndex)
		if self:Compare(lastElement, self._heap[parentIndex]) then
			-- Element is larger than parent, bubble up
			self:HeapifyUp(elementIndex)
		else
			-- Element is smaller than or equal to parent, bubble down
			self:HeapifyDown(elementIndex)
		end
	else
		-- Root node, only bubble down
		self:HeapifyDown(elementIndex)
	end

	self.Signals.OnRemove:Fire(element, self:GetSize())

	Logger:Debug(string.format("Remove: Removed element at index %d", elementIndex))
	return true
end

--[[
	Clears all elements from the heap
]]
function MaxHeap.Clear(self : MaxHeap)
	local oldSize = self:GetSize()
	table.clear(self._heap)

	-- Clear index map
	if self._indexMap then
		table.clear(self._indexMap)
	end

	self.Signals.OnClear:Fire(oldSize)

	Logger:Print(string.format("Clear: Cleared heap (Size: %d -> 0)", oldSize))
end

--[[
	Gets all elements as an array (not sorted)
	@return table - Array of elements
]]
function MaxHeap.GetElements(self : MaxHeap): {any}
	local elements = {}
	for i = 1, self:GetSize() do
		elements[i] = self._heap[i]
	end
	return elements
end

--[[
	OPTIMIZED: Proper heap cloning for sorted extraction
	Gets elements in sorted order (descending, non-destructive)
	@return table - Sorted array of elements (largest to smallest)
]]
function MaxHeap.GetSortedElements(self : MaxHeap): {any}
	-- Create a proper heap copy
	local tempHeap = {}
	for i = 1, self:GetSize() do
		tempHeap[i] = self._heap[i]
	end

	-- Temporarily disable index map for the copy
	local originalHeap = self._heap
	local originalIndexMap = self._indexMap

	self._heap = tempHeap
	self._indexMap = nil -- Don't track indices in temporary heap

	local sorted = {}
	while not self:IsEmpty() do
		table.insert(sorted, self:ExtractMax())
	end

	-- Restore original heap and index map
	self._heap = originalHeap
	self._indexMap = originalIndexMap

	return sorted
end

--[[
	Validates the heap property (for debugging)
	@return boolean - Is valid heap
]]
function MaxHeap.ValidateHeap(self : MaxHeap): boolean
	-- Validate heap property
	for i = 1, self:GetSize() do
		if self:HasLeftChild(i) then
			local leftIndex = self:GetLeftChildIndex(i)
			if self:Compare(self._heap[leftIndex], self._heap[i]) then
				Logger:Warn(string.format("ValidateHeap: Invalid heap at index %d (left child)", i))
				return false
			end
		end

		if self:HasRightChild(i) then
			local rightIndex = self:GetRightChildIndex(i)
			if self:Compare(self._heap[rightIndex], self._heap[i]) then
				Logger:Warn(string.format("ValidateHeap: Invalid heap at index %d (right child)", i))
				return false
			end
		end
	end

	-- Validate index map if enabled
	if self._indexMap then
		for element, index in pairs(self._indexMap) do
			if self._heap[index] ~= element then
				Logger:Warn(string.format("ValidateHeap: Index map mismatch at index %d", index))
				return false
			end
		end

		-- Check all heap elements are in index map
		for i = 1, self:GetSize() do
			if self._indexMap[self._heap[i]] ~= i then
				Logger:Warn(string.format("ValidateHeap: Missing index map entry for element at %d", i))
				return false
			end
		end
	end

	Logger:Debug("ValidateHeap: Heap is valid")
	return true
end

--[[
	Gets current heap state
	@return table - {Size, Max, IsEmpty}
]]
function MaxHeap.GetState(self : MaxHeap)
	return {
		Size = self:GetSize(),
		Max = self:Peek(),
		IsEmpty = self:IsEmpty(),
		Elements = self:GetElements(),
		IndexTrackingEnabled = self._indexMap ~= nil,
	}
end

--[[
	Enables index tracking for O(log n) removal
	WARNING: Does not support duplicate elements when enabled
]]
function MaxHeap.EnableIndexTracking(self : MaxHeap)
	if self._indexMap then
		Logger:Warn("EnableIndexTracking: Index tracking already enabled")
		return
	end

	self._indexMap = {}

	-- Build index map from current heap
	for i = 1, self:GetSize() do
		local element = self._heap[i]
		if self._indexMap[element] then
			Logger:Warn("EnableIndexTracking: Duplicate elements detected, index tracking may not work correctly")
		end
		self._indexMap[element] = i
	end

	Logger:Print("EnableIndexTracking: Index tracking enabled")
end

--[[
	Disables index tracking (frees memory, makes removal O(n))
]]
function MaxHeap.DisableIndexTracking(self : MaxHeap)
	if not self._indexMap then
		Logger:Warn("DisableIndexTracking: Index tracking already disabled")
		return
	end

	self._indexMap = nil
	Logger:Print("DisableIndexTracking: Index tracking disabled")
end

--[[
	Cleanup
]]
function MaxHeap.Destroy(self : MaxHeap)
	Logger:Print("Destroy: Cleaning up MaxHeap")

	-- Clear heap
	table.clear(self._heap)

	-- Clear index map
	if self._indexMap then
		table.clear(self._indexMap)
	end

	-- Cleanup signals
	for _, signal in pairs(self.Signals) do
		signal:Destroy()
	end

	self._heap = nil
	self._indexMap = nil
	self._comparator = nil
	self._metadata = nil

	Logger:Debug("Destroy: Cleanup complete")
end

-- Metadata handling for advanced use
function MaxHeap.GetMetadata(self : MaxHeap)
	return self._metadata
end

function MaxHeap.SetMetadata(self : MaxHeap, metadata)
	self._metadata = metadata
end

local module = {}

local metatable = {__index = MaxHeap}

--[[
	Default comparator for numbers (max heap)
	@param a - First value
	@param b - Second value
	@return boolean - True if a > b
]]
local function defaultComparator(a: any, b: any): boolean
	return a > b
end

--[[
	Creates a new MaxHeap
	@param comparator - Optional comparison function (default: a > b)
	@param metadata - Optional metadata table
	@param enableIndexTracking - Optional: Enable O(log n) removal (default: false)
	@return MaxHeap instance
]]
function module.new(comparator: ((any, any) -> boolean)?, metadata: any, enableIndexTracking: boolean?)
	local self : MaxHeap = setmetatable({}, metatable)

	self._heap = {}
	self._comparator = comparator or defaultComparator
	self._metadata = metadata or {}
	self._indexMap = if enableIndexTracking then {} else nil

	-- Signals
	self.Signals = {
		OnInsert = Signal.new(),
		OnExtract = Signal.new(),
		OnRemove = Signal.new(),
		OnClear = Signal.new(),
	}


	Logger:Debug("Created new MaxHeap" .. (enableIndexTracking and " with index tracking" or ""))
	return self
end

type Signal = Signal.Signal

export type MaxHeap = typeof(setmetatable({}, metatable)) & {
	_heap: {any},
	_comparator: (any, any) -> boolean,
	_metadata: any,
	_indexMap: {[any]: number}?,
	Signals: {
		OnInsert: Signal,
		OnExtract: Signal,
		OnRemove: Signal,
		OnClear: Signal,
	}
}

return table.freeze(module)