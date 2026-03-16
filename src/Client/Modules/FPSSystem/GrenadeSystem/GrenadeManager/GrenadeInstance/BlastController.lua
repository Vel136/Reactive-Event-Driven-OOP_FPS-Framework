-- BlastController.lua
--[[
	Handles HE grenade blast logic:
	- Radius-based target detection
	- Line-of-sight validation per target
	- Distance-based damage falloff
	- Designed to be swapped out per grenade type (e.g. FlashController for flashbangs)
]]

local Identity = "BlastController"

-- ─── Services ────────────────────────────────────────────────────────────────

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")

-- ─── References ──────────────────────────────────────────────────────────────

local Utilities = ReplicatedStorage.Shared.Modules.Utilities

-- ─── Modules ─────────────────────────────────────────────────────────────────

local Signal     = require(Utilities:FindFirstChild("Signal"))
local LogService = require(Utilities:FindFirstChild("Logger"))

-- ─── Module ──────────────────────────────────────────────────────────────────

local BlastController   = {}
BlastController.__index = BlastController
BlastController.__type  = Identity

-- ─── Private state ───────────────────────────────────────────────────────────

local Logger = LogService.new(Identity, false)

-- ─── Getters ─────────────────────────────────────────────────────────────────

--- Returns the blast data configuration.
function BlastController.GetData(self: BlastController): BlastData
	return self.Data
end

--- Returns the blast state snapshot.
function BlastController.GetState(self: BlastController)
	return {
		LastDetonatePosition = self._LastDetonatePosition,
		LastDetonateTime     = self._LastDetonateTime,
	}
end

-- ─── Internal: target detection ──────────────────────────────────────────────

--- Returns all characters within blast radius of the given position.
function BlastController._GetTargetsInRadius(self: BlastController, position: Vector3): { Model }
	local targets = {}

	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		if not character then continue end

		local hrp = character:FindFirstChild("HumanoidRootPart")
		if not hrp then continue end

		local distance = (hrp.Position - position).Magnitude
		if distance <= self.Data.Radius then
			table.insert(targets, character)
		end
	end

	Logger:Debug(string.format("_GetTargetsInRadius: %d targets found within %.1f studs", #targets, self.Data.Radius))
	return targets
end

--- Returns true if there is a clear line of sight from position to the target's HRP.
function BlastController._HasLineOfSight(self: BlastController, position: Vector3, character: Model): boolean
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return false end

	local direction = (hrp.Position - position)
	local distance  = direction.Magnitude

	local rayParams = RaycastParams.new()
	rayParams.FilterType                 = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { character }
	rayParams.IgnoreWater                = true

	local result = workspace:Raycast(position, direction.Unit * distance, rayParams)

	-- No hit means nothing is blocking LoS
	return result == nil
end

-- ─── Internal: damage falloff ────────────────────────────────────────────────

--- Calculates damage for a target at a given distance using linear falloff.
--- Full damage within InnerRadius, zero damage at or beyond Radius.
function BlastController._CalculateDamage(self: BlastController, distance: number): number
	local innerRadius = self.Data.InnerRadius or (self.Data.Radius * 0.3)
	local outerRadius = self.Data.Radius

	if distance <= innerRadius then
		return self.Data.MaxDamage
	end

	if distance >= outerRadius then
		return 0
	end

	-- Linear falloff between inner and outer radius
	local alpha = (distance - innerRadius) / (outerRadius - innerRadius)
	return self.Data.MaxDamage * (1 - alpha)
end

-- ─── Detonation ──────────────────────────────────────────────────────────────

--- Executes the blast at the given world position.
--- Detects targets, validates LoS, calculates damage, fires signals.
function BlastController.Detonate(self: BlastController, position: Vector3)
	self._LastDetonatePosition = position
	self._LastDetonateTime     = os.clock()

	Logger:Print(string.format("Detonate: blasting at %s (radius=%.1f)", tostring(position), self.Data.Radius))

	local targets = self:_GetTargetsInRadius(position)
	local hits    = {}

	for _, character in ipairs(targets) do
		local hrp = character:FindFirstChild("HumanoidRootPart")
		if not hrp then continue end

		local distance = (hrp.Position - position).Magnitude
		local hasLos   = self.Data.RequireLineOfSight == false or self:_HasLineOfSight(position, character)

		if not hasLos then
			Logger:Debug(string.format("Detonate: no LoS to %s, skipping", character.Name))
			continue
		end

		local damage = self:_CalculateDamage(distance)

		if damage <= 0 then continue end

		local hitData = {
			Character = character,
			Distance  = distance,
			Damage    = damage,
			HasLoS    = hasLos,
		}

		table.insert(hits, hitData)
		self.Signals.OnTargetHit:Fire(hitData)

		Logger:Debug(string.format("Detonate: hit %s — distance=%.1f damage=%.1f",
			character.Name, distance, damage))
	end

	self.Signals.OnDetonated:Fire(position, hits)

	Logger:Print(string.format("Detonate: complete — %d targets hit", #hits))
	return hits
end

-- ─── Lifecycle ───────────────────────────────────────────────────────────────

--- Cleans up the BlastController.
function BlastController.Destroy(self: BlastController)
	Logger:Print("Destroy: cleaning up BlastController")

	for _, signal in pairs(self.Signals) do
		signal:Destroy()
	end

	self.Data = nil
	Logger:Debug("Destroy: complete")
end

-- ─── Constructor ─────────────────────────────────────────────────────────────

local module = {}

--- Creates a new BlastController.
function module.new(blastData: BlastData): BlastController
	assert(blastData,            "BlastController.new: blastData is required")
	assert(blastData.Radius,     "BlastController.new: missing Radius")
	assert(blastData.MaxDamage,  "BlastController.new: missing MaxDamage")

	local self: BlastController = setmetatable({}, { __index = BlastController })

	self.Data = blastData

	self._LastDetonatePosition = nil
	self._LastDetonateTime     = 0

	self.Signals = {
		OnDetonated  = Signal.new(),
		OnTargetHit  = Signal.new(),
	}

	Logger:Debug(string.format("new: Radius=%.1f MaxDamage=%.1f InnerRadius=%.1f LoS=%s",
		blastData.Radius,
		blastData.MaxDamage,
		blastData.InnerRadius       or (blastData.Radius * 0.3),
		tostring(blastData.RequireLineOfSight ~= false)
		))

	return self
end

-- ─── Types ───────────────────────────────────────────────────────────────────

export type BlastData = {
	Radius             : number,  -- Outer blast radius in studs
	InnerRadius        : number?, -- Full damage radius (defaults to 30% of Radius)
	MaxDamage          : number,  -- Damage at point blank / inner radius
	RequireLineOfSight : boolean?, -- Whether walls block damage (default true)
}

export type HitData = {
	Character : Model,
	Distance  : number,
	Damage    : number,
	HasLoS    : boolean,
}

export type BlastController = typeof(setmetatable({}, { __index = BlastController })) & {
	Data                   : BlastData,
	_LastDetonatePosition  : Vector3?,
	_LastDetonateTime      : number,
	Signals : {
		OnDetonated : Signal.Signal<(position: Vector3, hits: { HitData }) -> ()>,
		OnTargetHit : Signal.Signal<(hitData: HitData) -> ()>,
	},
}

return table.freeze(module)