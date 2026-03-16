--!native
--!optimize 2

--[[
    Lightweight Pathfinding Module
    - Optimized BFS with parent pointers
    - Route caching for repeated queries
    - Flow field support for shared destinations
    - Handles hundreds of AI efficiently
]]
local Pathfinder = {
	graph = {},             -- [nodeID] = {neighbor1, neighbor2, ...}
	routeCache = {},         -- [startNode][endNode] = {path}
	cacheSize = 0,

	flowFields = {},         -- [targetNode] = {[nodeID] = nextNode}
	flowFieldTimestamps = {}, -- [targetNode] = lastUpdateTime
}

-- CONFIG
local CONFIG = {
	StepThreshold = 2,           -- distance to consider node reached (studs)
	MaxCacheSize = 5000,         -- max cached routes before clearing
	FlowFieldUpdateInterval = 1, -- seconds between flow field updates
}


function Pathfinder.new() : PathFinder
	local self = setmetatable({},{__index = Pathfinder})
	
	return self :: PathFinder
end

-- ========================
-- GRAPH SETUP
-- ========================

function Pathfinder.SetGraph(self : PathFinder,graph, positions)
	self.graph = graph
end

function Pathfinder.AddNode(self : PathFinder,nodeID, position, neighbors)
	self.graph[nodeID] = neighbors or {}
end

function Pathfinder.AddEdge(self : PathFinder,nodeA, nodeB, bidirectional)
	self.graph[nodeA] = self.graph[nodeA] or {}
	table.insert(self.graph[nodeA], nodeB)

	if bidirectional ~= false then
		self.graph[nodeB] = self.graph[nodeB] or {}
		table.insert(self.graph[nodeB], nodeA)
	end
end

-- ========================
-- OPTIMIZED BFS PATHFINDING
-- ========================

function Pathfinder.ComputeRoute(self : PathFinder,startNode, endNode)
	-- Check cache first
	if self.routeCache[startNode] and self.routeCache[startNode][endNode] then
		return self.routeCache[startNode][endNode]
	end

	-- Edge case: already at destination
	if startNode == endNode then
		return {startNode}
	end

	-- BFS with parent pointers (avoids path copying)
	local queue = {startNode}
	local queueStart = 1
	local queueEnd = 1
	local parents = {[startNode] = startNode}

	while queueStart <= queueEnd do
		local current = queue[queueStart]
		queueStart = queueStart + 1

		-- Found destination
		if current == endNode then
			local path = self:ReconstructPath(parents, startNode, endNode)
			self:CacheRoute(startNode, endNode, path)
			return path
		end

		-- Explore neighbors
		local neighbors = self.graph[current]
		if neighbors then
			for i = 1, #neighbors do
				local neighbor = neighbors[i]
				if not parents[neighbor] then
					parents[neighbor] = current
					queueEnd = queueEnd + 1
					queue[queueEnd] = neighbor
				end
			end
		end
	end
	
	-- No path found
	return nil
end

function Pathfinder.ReconstructPath(self : PathFinder,parents, startNode, endNode)
	local path = {}
	local node = endNode
	local pathLength = 0

	-- Build path backwards
	while node ~= startNode do
		pathLength = pathLength + 1
		path[pathLength] = node
		node = parents[node]
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

function Pathfinder.CacheRoute(self : PathFinder,startNode, endNode, route)
	self.routeCache[startNode] = self.routeCache[startNode] or {}
	self.routeCache[startNode][endNode] = route

	self.cacheSize = self.cacheSize + 1

	-- Prevent memory bloat
	if self.cacheSize > CONFIG.MaxCacheSize then
		self.routeCache = {}
		self.cacheSize = 0
	end
end

-- ========================
-- FLOW FIELD (for shared destinations)
-- ========================

function Pathfinder.GetOrComputeFlowField(self : PathFinder,targetNode, forceUpdate)
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

function Pathfinder.ComputeFlowField(self : PathFinder,targetNode)
	local field = {}
	local queue = {targetNode}
	local queueStart = 1
	local queueEnd = 1
	local visited = {[targetNode] = true}
	field[targetNode] = targetNode -- target points to itself

	while queueStart <= queueEnd do
		local current = queue[queueStart]
		queueStart = queueStart + 1

		local neighbors = self.graph[current]
		if neighbors then
			for i = 1, #neighbors do
				local neighbor = neighbors[i]
				if not visited[neighbor] then
					visited[neighbor] = true
					field[neighbor] = current -- point toward target
					queueEnd = queueEnd + 1
					queue[queueEnd] = neighbor
				end
			end
		end
	end

	return field
end

function Pathfinder.ClearCache(self : PathFinder)
	self.routeCache = {}
	self.cacheSize = 0
end

function Pathfinder.ClearFlowFields(self : PathFinder)
	self.flowFields = {}
	self.flowFieldTimestamps = {}
end

function Pathfinder.GetStats(self : PathFinder)
	return {
		CachedRoutes = self.cacheSize,
		FlowFields = self:CountFlowFields(),
		Nodes = self:CountNodes(),
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

export type PathFinder = typeof(setmetatable({},{__index = Pathfinder}))

return Pathfinder