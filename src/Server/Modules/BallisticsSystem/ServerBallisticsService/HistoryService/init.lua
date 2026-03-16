-- HistoryService.lua
local Identity = "HistoryService"
local HistoryService = {}
HistoryService.__index = HistoryService

-- Services
local RunService = game:GetService('RunService')
local PlayerService = game:GetService('Players')
local ReplicatedStorage = game:GetService('ReplicatedStorage')

-- References
local Utilities = ReplicatedStorage.Shared.Modules.Utilities
-- Modules
local HitboxService = require(script.Parent.HitboxService)
local SnapshotDatas = require(script.SnapshotDatas)



-- Additional modules
local t = require(Utilities.TypeCheck)
local LogService = require(Utilities.Logger)


local Logger = LogService.new(Identity, true)

local MaxSnapshot = 30
local Frequency = 0.1

function HistoryService:_InitializeHistoryTracking()
	local Accumulated = 0

	RunService.Heartbeat:Connect(function(dt)
		Accumulated += dt

		if Accumulated >= Frequency then
			Accumulated = 0
		else 
			return 
		end

		self:CaptureSnapshot()
	end)
end

function HistoryService:CaptureSnapshot()
	local activePlayers = SnapshotDatas.Players
	local currentTime = os.clock()

	-- Track players with hitboxes
	for _, player in ipairs(activePlayers) do
		if not player or not player:IsA("Player") then continue end

		local character = player.Character
		if not character then continue end

		local hitboxes = HitboxService:GetHitboxes(player)
		if not hitboxes then continue end

		for hitboxName, _ in pairs(hitboxes) do
			if not character or not character.Parent then break end

			local hitbox = character:FindFirstChild(hitboxName)

			if hitbox and hitbox:IsA("BasePart") then
				if not SnapshotDatas.Snapshots[player][hitboxName] then
					SnapshotDatas.Snapshots[player][hitboxName] = {}
				end

				table.insert(SnapshotDatas.Snapshots[player][hitboxName], {
					CFrame = hitbox.CFrame,
					Size = hitbox.Size,
					Time = currentTime,
				})

				if #SnapshotDatas.Snapshots[player][hitboxName] > MaxSnapshot then
					table.remove(SnapshotDatas.Snapshots[player][hitboxName], 1)
				end
			end
		end
	end
end

-- Helper function: Binary search to find snapshots around shotTime
function HistoryService:_FindSnapshotBracket(snapshots, shotTime)
	if #snapshots == 0 then return nil, nil end

	local left, right = 1, #snapshots
	local beforeSnapshot, afterSnapshot

	-- Binary search for the bracket
	while left <= right do
		local mid = math.floor((left + right) / 2)
		local snapshot = snapshots[mid]

		if snapshot.Time <= shotTime then
			beforeSnapshot = snapshot
			left = mid + 1
		else
			afterSnapshot = snapshot
			right = mid - 1
		end
	end

	return beforeSnapshot, afterSnapshot
end

function HistoryService:GetMovementData(target, shotTime, hitboxName)
	-- Validate inputs
	if not target then 
		Logger:Error("Invalid target", Identity)
		return nil 
	end

	if not t.number(shotTime) then 
		Logger:Error("Shot time must be a number", Identity)
		return nil 
	end

	-- Check if we have snapshot data for this target
	if not SnapshotDatas.Snapshots[target] then
		Logger:Warn("No snapshot data for target: " .. tostring(target), Identity)
		return nil
	end

	local currentTime = os.clock()
	local timeDifference = currentTime - shotTime

	-- Optional: Limit how far back we can rewind
	local maxRewindTime = 5.0
	if timeDifference > maxRewindTime then
		Logger:Warn("Shot time too old: " .. timeDifference .. "s ago", Identity)
		return nil
	end

	if timeDifference < 0 then
		Logger:Warn("Shot time is in the future", Identity)
		return nil
	end

	-- If specific hitbox requested, only process that one
	if hitboxName then
		local snapshots = SnapshotDatas.Snapshots[target][hitboxName]
		if not snapshots or #snapshots == 0 then
			Logger:Warn("No snapshots for hitbox: " .. hitboxName, Identity)
			return nil
		end

		local beforeSnapshot, afterSnapshot = self:_FindSnapshotBracket(snapshots, shotTime)
		return self:_InterpolateSnapshot(beforeSnapshot, afterSnapshot, shotTime)
	end

	-- Otherwise, get data for all hitboxes
	local movementData = {}

	for hitboxName, snapshots in pairs(SnapshotDatas.Snapshots[target]) do
		if #snapshots == 0 then continue end

		local beforeSnapshot, afterSnapshot = self:_FindSnapshotBracket(snapshots, shotTime)
		local interpolatedData = self:_InterpolateSnapshot(beforeSnapshot, afterSnapshot, shotTime)

		if interpolatedData then
			movementData[hitboxName] = interpolatedData
		end
	end

	if next(movementData) == nil then
		Logger:Warn("No movement data found for shot time", Identity)
		return nil
	end

	return movementData
end

-- Helper function: Interpolate between snapshots
function HistoryService:_InterpolateSnapshot(beforeSnapshot, afterSnapshot, shotTime)
	if not beforeSnapshot then
		if afterSnapshot then
			-- Use oldest available
			return {
				CFrame = afterSnapshot.CFrame,
				Size = afterSnapshot.Size,
				Time = afterSnapshot.Time
			}
		end
		return nil
	end

	if not afterSnapshot or math.abs(beforeSnapshot.Time - shotTime) < 0.001 then
		-- Exact match or close enough
		return {
			CFrame = beforeSnapshot.CFrame,
			Size = beforeSnapshot.Size,
			Time = beforeSnapshot.Time
		}
	end

	-- Interpolate
	local alpha = (shotTime - beforeSnapshot.Time) / (afterSnapshot.Time - beforeSnapshot.Time)
	alpha = math.clamp(alpha, 0, 1)

	return {
		CFrame = beforeSnapshot.CFrame:Lerp(afterSnapshot.CFrame, alpha),
		Size = beforeSnapshot.Size,
		Time = shotTime
	}
end

function HistoryService:SetMaxSnapshot(number)
	if not t.number(number) or number <= 0 then 
		Logger:Error("MaxSnapshot must be positive number", Identity)
		return false 
	end

	MaxSnapshot = number
	return true
end

function HistoryService:SetFrequency(number)
	if not t.number(number) or number <= 0 then 
		Logger:Error("Frequency must be positive number", Identity)
		return false 
	end
	Frequency = number
	return true
end

function HistoryService:_Initialize()
	self:_InitializeHistoryTracking()

	PlayerService.PlayerAdded:Connect(function(Player)
		table.insert(SnapshotDatas.Players, Player)
		SnapshotDatas.Snapshots[Player] = {}
	end)

	PlayerService.PlayerRemoving:Connect(function(Player)
		-- Clean up player data
		local index = table.find(SnapshotDatas.Players, Player)
		if index then
			table.remove(SnapshotDatas.Players, index)
		end
		SnapshotDatas.Snapshots[Player] = nil
	end)

	return true
end

local instance

local function GetInstance()
	if not instance then
		instance = setmetatable({}, HistoryService)
		instance:_Initialize()
	end
	return instance
end

GetInstance()

return setmetatable({}, {
	__index = function(_, key)
		return GetInstance()[key]
	end,
	__newindex = function()
		error("Cannot modify singleton service [HistoryService]")
	end
})