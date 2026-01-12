local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Utilities = ReplicatedStorage.SharedModules.Utilities
local Logger = require(Utilities.LogService)
local Identity = "[HitscanSolver]"

-- The name of the folder containing the 3D GUI elements for visualizing casts in debug mode.
local HC_VIS_OBJ_NAME = "HitscanVisualizationObjects"

local HitscanSolver = {}
HitscanSolver.__index = HitscanSolver
HitscanSolver.VisualizeCasts = false
-----------------------------------------------------------
------------------------ UTILITIES ------------------------
-----------------------------------------------------------

-- Looks for a folder within workspace.Terrain that contains elements to visualize casts.
local function GetHitscanVisualizationContainer(): Instance
	local hcVisualizationObjects = workspace.Terrain:FindFirstChild(HC_VIS_OBJ_NAME)
	if hcVisualizationObjects ~= nil then
		return hcVisualizationObjects
	end

	hcVisualizationObjects = Instance.new("Folder")
	hcVisualizationObjects.Name = HC_VIS_OBJ_NAME
	hcVisualizationObjects.Archivable = false
	hcVisualizationObjects.Parent = workspace.Terrain
	return hcVisualizationObjects
end

-----------------------------------------------------------
------------------------ DEBUGGING ------------------------
-----------------------------------------------------------

-- Print that runs only if debug mode is active.
local function PrintDebug(service, message: string)
	if service.DebugLogging == true then
		print(message)
	end
end

-- Visualizes a ray. This will not run if service.VisualizeCasts is false.
local function DbgVisualizeSegment(castStartCFrame: CFrame, castLength: number): ConeHandleAdornment?
	if HitscanSolver.VisualizeCasts == false then return nil end
	local adornment = Instance.new("ConeHandleAdornment")
	adornment.Adornee = workspace.Terrain
	adornment.CFrame = castStartCFrame
	adornment.Height = castLength
	adornment.Color3 = Color3.new(0, 0, 1) -- Cyan for hitscan
	adornment.Radius = 0.15
	adornment.Transparency = 0.3
	adornment.Parent = GetHitscanVisualizationContainer()

	if RunService:IsServer() then
		adornment.Color3 = Color3.fromRGB(255, 0, 0) -- Different color for server
	end
	return adornment
end

-- Visualizes an impact. This will not run if service.VisualizeCasts is false.
local function DbgVisualizeHit(atCF: CFrame, wasHit: boolean): SphereHandleAdornment?
	if HitscanSolver.VisualizeCasts == false then return nil end
	local adornment = Instance.new("SphereHandleAdornment")
	adornment.Adornee = workspace.Terrain
	adornment.CFrame = atCF
	adornment.Radius = 0.4
	adornment.Transparency = 0.25
	-- Green for hit, red for miss
	adornment.Color3 = wasHit and Color3.new(0.2, 1, 0.5) or Color3.new(1, 0.2, 0.2)
	adornment.Parent = GetHitscanVisualizationContainer()
	return adornment
end

-----------------------------------------------------------
---------------------- HITSCAN SOLVER ---------------------
-----------------------------------------------------------

function HitscanSolver.new(ballisticsService)
	local self = setmetatable({}, HitscanSolver)
	self.Service = ballisticsService
	return self
end

--[[
	Instant raycast - perfect for hitscan weapons
]]
function HitscanSolver:Fire(context, behavior)
	local origin = context.Origin
	local direction = context.Direction
	local maxDistance = (behavior and behavior.MaxDistance) or 1000
	
	PrintDebug(self.Service, "Hitscan: Firing from " .. tostring(origin))

	-- Raycast params
	local params = (behavior and behavior.RaycastParams) or RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true

	-- Record trajectory for lag compensation
	context.Trajectory = {origin}

	-- Perform instant raycast
	local rayDirection = direction * maxDistance
	local result = workspace:Raycast(origin, rayDirection, params)

	local hitPos
	local actualDistance

	if result then
		-- Hit something
		hitPos = result.Position
		actualDistance = result.Distance
		context.Trajectory[2] = hitPos
		context.Length = result.Distance
		-- Update context state
		context:_UpdateState(hitPos, direction * context.Speed)

		-- Visualize the ray segment (from origin to hit point)
		DbgVisualizeSegment(
			
			CFrame.new(origin, hitPos),
			actualDistance
		)

		-- Visualize the hit
		DbgVisualizeHit(CFrame.new(hitPos), true)

		Logger.Print(string.format(
			"Hitscan hit: %s at %.1f studs",
			result.Instance.Name,
			actualDistance
			), Identity)
	else
		-- Miss - traveled max distance
		hitPos = origin + rayDirection
		actualDistance = maxDistance
		context.Length = behavior.MaxDistance
		context.Trajectory[2] = hitPos
		
		context:_UpdateState(hitPos, direction * context.Speed)
		
		-- Visualize the full ray segment
		DbgVisualizeSegment(
			
			CFrame.new(origin, hitPos),
			actualDistance
		)

		-- Visualize the miss endpoint
		DbgVisualizeHit(CFrame.new(hitPos), false)

		Logger.Print("Hitscan miss", Identity)
	end

	-- Trigger hit callback
	self.Service:_TriggerHit(context, result)
	-- Hitscan always terminates immediately
	self.Service:_TriggerTermination(context)

	return true
end

function HitscanSolver:Destroy()
	self.Service = nil
end

return HitscanSolver