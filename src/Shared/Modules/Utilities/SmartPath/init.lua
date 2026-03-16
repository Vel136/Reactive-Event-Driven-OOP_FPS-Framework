--!native
--!optimize 2

--[[
    Greedy A* Pathfinding Module
    - Weighted A* variant that prioritizes heuristic (greedy) while maintaining optimality
    - Uses f(n) = g(n) + ε·h(n) where ε > 1 makes it greedier
    - Route caching for repeated queries
    - Flow field support for shared destinations
    - Handles hundreds of AI efficiently
    - Configurable greediness factor
]]
local MinHeap = require(script.MinHeap)
local Pathfinder = {
	graph = {},             -- [nodeID] = {neighbor1, neighbor2, ...}
	positions = {},         -- [nodeID] = Vector3 position
	edgeCosts = {},         -- [nodeA][nodeB] = cost (optional, defaults to distance)
	routeCache = {},        -- [startNode][endNode] = {path}
	cacheSize = 0,
	cacheAccess = {},       -- [startNode][endNode] = lastAccessTime (for LRU)

	flowFields = {},         -- [targetNode] = {[nodeID] = nextNode}
	flowFieldTimestamps = {}, -- [targetNode] = lastUpdateTime
}

-- CONFIG
local CONFIG = {
	MaxCacheSize = 5000,         -- max cached routes before clearing
	CacheEvictionRatio = 0.3,    -- remove 30% oldest when full
	FlowFieldUpdateInterval = 1, -- seconds between flow field updates

	-- Greedy A* settings
	GreedyWeight = 2.0,          -- ε (epsilon): weight for heuristic
	-- 1.0 = standard A* (optimal)
	-- 2.0 = greedy A* (faster, near-optimal)
	-- >5.0 = very greedy (fast, suboptimal)
}


function Pathfinder.new() : PathFinder
	local self = setmetatable({},{__index = Pathfinder})
	self.routeCache = {}
	self.cacheAccess = {}
	self.cacheSize = 0
	self.flowFields = {}
	self.flowFieldTimestamps = {}
	self.graph = {}
	self.positions = {}
	self.edgeCosts = {}
	return self :: PathFinder
end

-- ========================
-- GRAPH SETUP
-- ========================

function Pathfinder.SetGraph(self : PathFinder, graph, positions, edgeCosts)
	self.graph = graph
	self.positions = positions
	self.edgeCosts = edgeCosts or {}
end

function Pathfinder.AddNode(self : PathFinder, nodeID, position, neighbors)
	self.graph[nodeID] = neighbors or {}
	self.positions[nodeID] = position
end

function Pathfinder.AddEdge(self : PathFinder, nodeA, nodeB, cost, bidirectional)
	self.graph[nodeA] = self.graph[nodeA] or {}
	table.insert(self.graph[nodeA], nodeB)

	-- Store edge cost if provided
	if cost then
		self.edgeCosts[nodeA] = self.edgeCosts[nodeA] or {}
		self.edgeCosts[nodeA][nodeB] = cost
	end

	if bidirectional ~= false then
		self.graph[nodeB] = self.graph[nodeB] or {}
		table.insert(self.graph[nodeB], nodeA)

		if cost then
			self.edgeCosts[nodeB] = self.edgeCosts[nodeB] or {}
			self.edgeCosts[nodeB][nodeA] = cost
		end
	end
end

-- ========================
-- COST & HEURISTIC FUNCTIONS
-- ========================

function Pathfinder.GetEdgeCost(self : PathFinder, nodeA, nodeB)
	-- Use explicit edge cost if available
	if self.edgeCosts[nodeA] and self.edgeCosts[nodeA][nodeB] then
		return self.edgeCosts[nodeA][nodeB]
	end

	-- Otherwise use Euclidean distance
	local posA = self.positions[nodeA]
	local posB = self.positions[nodeB]

	if not posA or not posB then
		return 1 -- Default cost
	end

	return (posA - posB).Magnitude
end

function Pathfinder.Heuristic(self : PathFinder, nodeA, nodeB)
	-- Euclidean distance heuristic (admissible)
	local posA = self.positions[nodeA]
	local posB = self.positions[nodeB]

	if not posA or not posB then
		return 0
	end

	return (posA - posB).Magnitude
end

-- ========================
-- GREEDY A* PATHFINDING
-- ========================

function Pathfinder.ComputeRoute(self : PathFinder, startNode, endNode, greedyWeight)
	if not self.graph[startNode] or not self.graph[endNode] then
		warn("Invalid start or end node")
		return nil
	end
	-- Check cache first
	if self.routeCache[startNode] and self.routeCache[startNode][endNode] then
		-- Update access time for LRU
		self.cacheAccess[startNode][endNode] = os.clock()
		return self.routeCache[startNode][endNode]
	end

	-- Edge case: already at destination
	if startNode == endNode then
		return {startNode}
	end

	-- Use provided weight or default
	local epsilon = greedyWeight or CONFIG.GreedyWeight

	-- Greedy A* using MinHeap
	-- f(n) = g(n) + ε·h(n)
	local openSet = MinHeap.new(function(a, b)
		return a.f < b.f
	end, nil, true)

	local gScore = {[startNode] = 0}  -- Actual cost from start
	local startHeuristic = self:Heuristic(startNode, endNode)

	openSet:Insert({
		node = startNode,
		g = 0,
		f = epsilon * startHeuristic  -- f = g + ε·h
	})

	local parents = {[startNode] = startNode}
	local closedSet = {}

	while not openSet:IsEmpty() do
		local current = openSet:ExtractMin()
		local currentNode = current.node
		local currentG = current.g
		
		-- Skip stale duplicates (outdated entries with worse g-scores)
		if currentG > (gScore[currentNode] or math.huge) then
			continue
		end
		

		-- Found destination
		if currentNode == endNode then
			local path = self:ReconstructPath(parents, startNode, endNode)
			self:CacheRoute(startNode, endNode, path)
			openSet:Destroy()
			return path
		end

		-- Mark as visited/closed
		closedSet[currentNode] = true

		-- Explore neighbors
		local neighbors = self.graph[currentNode]
		if neighbors then
			for i = 1, #neighbors do
				local neighbor = neighbors[i]

				-- Skip if already evaluated
				if not closedSet[neighbor] then
					local edgeCost = self:GetEdgeCost(currentNode, neighbor)
					local tentativeG = currentG + edgeCost

					if tentativeG < (gScore[neighbor] or math.huge) then
						-- Update best path to this neighbor
						parents[neighbor] = currentNode
						gScore[neighbor] = tentativeG

						local h = self:Heuristic(neighbor, endNode)
						local f = tentativeG + epsilon * h

						-- Always insert better paths (allows duplicates)
						openSet:Insert({
							node = neighbor,
							g = tentativeG,
							f = f
						})
					end
				end
			end
		end
	end

	-- No path found
	openSet:Destroy()
	return nil
end

function Pathfinder.ReconstructPath(self : PathFinder, parents, startNode, endNode)
	local path = {}
	local node = endNode
	local pathLength = 0

	-- Build path backwards
	while node ~= startNode do
		pathLength = pathLength + 1
		path[pathLength] = node
		node = parents[node]

		-- Safety check for corrupted path
		if not node then
			warn("Path reconstruction failed - corrupted parent chain")
			return nil
		end
	end

	-- Add start node
	pathLength = pathLength + 1
	path[pathLength] = startNode

	-- Reverse path in-place
	local left = 1
	local right = pathLength
	while left < right do
		path[left], path[right] = path[right], path[left]
		left = left + 1
		right = right - 1
	end

	return path
end

function Pathfinder.CacheRoute(self : PathFinder, startNode, endNode, route)
	-- Check if we need to evict old entries
	if self.cacheSize >= CONFIG.MaxCacheSize then
		self:EvictOldestCacheEntries()
	end

	self.routeCache[startNode] = self.routeCache[startNode] or {}
	self.cacheAccess[startNode] = self.cacheAccess[startNode] or {}

	self.routeCache[startNode][endNode] = route
	self.cacheAccess[startNode][endNode] = os.clock()

	self.cacheSize = self.cacheSize + 1
end

function Pathfinder.EvictOldestCacheEntries(self : PathFinder)
	-- Build list of all cache entries with access times
	local entries = {}
	for startNode, destinations in pairs(self.cacheAccess) do
		for endNode, accessTime in pairs(destinations) do
			table.insert(entries, {
				start = startNode,
				finish = endNode,
				time = accessTime
			})
		end
	end

	-- Sort by access time (oldest first)
	table.sort(entries, function(a, b)
		return a.time < b.time
	end)

	-- Remove oldest entries
	local toRemove = math.floor(#entries * CONFIG.CacheEvictionRatio)
	for i = 1, toRemove do
		local entry = entries[i]
		self.routeCache[entry.start][entry.finish] = nil
		self.cacheAccess[entry.start][entry.finish] = nil
		self.cacheSize = self.cacheSize - 1
	end
end

-- ========================
-- FLOW FIELD (for shared destinations)
-- ========================

function Pathfinder.GetOrComputeFlowField(self : PathFinder, targetNode, forceUpdate)
	local currentTime = os.clock()
	local lastUpdate = self.flowFieldTimestamps[targetNode] or 0

	-- Return cached flow field if recent
	if not forceUpdate and self.flowFields[targetNode] and 
		(currentTime - lastUpdate) < CONFIG.FlowFieldUpdateInterval then
		return self.flowFields[targetNode]
	end

	-- Compute new flow field
	local field = self:ComputeFlowField(targetNode)
	self.flowFields[targetNode] = field
	self.flowFieldTimestamps[targetNode] = currentTime

	return field
end

function Pathfinder.ComputeFlowField(self : PathFinder, targetNode)
	-- Flow field uses Dijkstra's algorithm for optimal paths to target
	-- This ensures all agents following the field take shortest paths
	local field = {}
	local costs = {[targetNode] = 0}

	local openSet = MinHeap.new(function(a, b)
		return a.cost < b.cost
	end, nil, true)

	openSet:Insert({
		node = targetNode,
		cost = 0
	})

	field[targetNode] = targetNode -- target points to itself
	local visited = {}

	while not openSet:IsEmpty() do
		local current = openSet:ExtractMin()
		local currentNode = current.node
		local currentCost = current.cost

		if visited[currentNode] then
			continue
		end
		visited[currentNode] = true

		local neighbors = self.graph[currentNode]
		if neighbors then
			for i = 1, #neighbors do
				local neighbor = neighbors[i]

				if not visited[neighbor] then
					local edgeCost = self:GetEdgeCost(currentNode, neighbor)
					local newCost = currentCost + edgeCost

					if newCost < (costs[neighbor] or math.huge) then
						costs[neighbor] = newCost
						field[neighbor] = currentNode -- point toward target

						openSet:Insert({
							node = neighbor,
							cost = newCost
						})
					end
				end
			end
		end
	end

	openSet:Destroy()
	return field
end

function Pathfinder.ClearCache(self : PathFinder)
	table.clear(self.routeCache)
	table.clear(self.cacheAccess)
	self.cacheSize = 0
end

function Pathfinder.ClearFlowFields(self : PathFinder)
	table.clear(self.flowFields)
	table.clear(self.flowFieldTimestamps)
end

function Pathfinder.GetStats(self : PathFinder)
	return {
		CachedRoutes = self.cacheSize,
		FlowFields = self:CountFlowFields(),
		Nodes = self:CountNodes(),
		GreedyWeight = CONFIG.GreedyWeight,
	}
end

function Pathfinder.CountFlowFields(self : PathFinder)
	local count = 0
	for _ in pairs(self.flowFields) do
		count = count + 1
	end
	return count
end

function Pathfinder.CountNodes(self : PathFinder)
	local count = 0
	for _ in pairs(self.graph) do
		count = count + 1
	end
	return count
end

-- Set greedy weight dynamically
function Pathfinder.SetGreedyWeight(self : PathFinder, weight)
	CONFIG.GreedyWeight = weight
	-- Clear cache since paths may differ with new weight
	self:ClearCache()
end

export type PathFinder = typeof(setmetatable({},{__index = Pathfinder}))

return Pathfinder