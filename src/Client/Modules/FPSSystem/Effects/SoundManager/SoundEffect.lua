
local Identity = "SoundEffect"
local SoundEffect = {}
SoundEffect.__type = Identity
-- Services
local ReplicatedStorage = game:GetService('ReplicatedStorage')

-- Modules
local Throttle = require(ReplicatedStorage.Shared.Modules.Utilities.Throttle)
local SoundManager = require(ReplicatedStorage.Client.Modules.SoundSystem.SoundManager)
local GunManager = require(ReplicatedStorage.Client.Modules.FPSSystem.GunSystem.GunManager)
local BallisticsCommon = require(ReplicatedStorage.Shared.Modules.FPSSystem.BallisticsSystem.BallisticsCommon)

-- Used Sounds, check ReplicatedStorage/Assets/BulletSounds
local BulletSounds = ReplicatedStorage.Assets.BulletSounds
local Body = BulletSounds.Body and BulletSounds.Body:GetChildren() or {}
local Glass = BulletSounds.Glass and BulletSounds.Glass:GetChildren() or {}
local Concrete = BulletSounds.Concrete and BulletSounds.Concrete:GetChildren() or {}
local Cracks = BulletSounds.Cracks and BulletSounds.Cracks:GetChildren() or {}
local Grass = BulletSounds.Grass and BulletSounds.Grass:GetChildren() or {}
local Hits = BulletSounds.Criticals and BulletSounds.Criticals:GetChildren() or {}
local Metal = BulletSounds.Metal and BulletSounds.Metal:GetChildren() or {}
local Whizz = BulletSounds.Whizz and BulletSounds.Whizz:GetChildren() or {}
local Wood = BulletSounds.Wood and BulletSounds.Wood:GetChildren() or {}

-- Material to Sound Category Mapping
local Sounds = {
	-- Grass and Natural Ground
	[Enum.Material.Grass.Value] = Grass,
	[Enum.Material.LeafyGrass.Value] = Grass,
	[Enum.Material.Ground.Value] = Grass,
	[Enum.Material.Mud.Value] = Grass,
	[Enum.Material.Sand.Value] = Grass,
	[Enum.Material.Salt.Value] = Grass,

	-- Glass Materials
	[Enum.Material.Glass.Value] = Glass,
	[Enum.Material.ForceField.Value] = Glass,
	[Enum.Material.Neon.Value] = Glass,

	-- Concrete and Stone
	[Enum.Material.Concrete.Value] = Concrete,
	[Enum.Material.Pavement.Value] = Concrete,
	[Enum.Material.Asphalt.Value] = Concrete,
	[Enum.Material.Slate.Value] = Concrete,
	[Enum.Material.Limestone.Value] = Concrete,
	[Enum.Material.Sandstone.Value] = Concrete,
	[Enum.Material.Brick.Value] = Concrete,
	[Enum.Material.Cobblestone.Value] = Concrete,
	[Enum.Material.Rock.Value] = Concrete,
	[Enum.Material.Basalt.Value] = Concrete,
	[Enum.Material.CrackedLava.Value] = Concrete,
	[Enum.Material.Granite.Value] = Concrete,
	[Enum.Material.Marble.Value] = Concrete,

	-- Metal Materials
	[Enum.Material.Metal.Value] = Metal,
	[Enum.Material.DiamondPlate.Value] = Metal,
	[Enum.Material.CorrodedMetal.Value] = Metal,
	[Enum.Material.Foil.Value] = Metal,

	-- Wood Materials
	[Enum.Material.Wood.Value] = Wood,
	[Enum.Material.WoodPlanks.Value] = Wood,

	-- Plastic and Smooth Surfaces
	[Enum.Material.SmoothPlastic.Value] = Cracks,
	[Enum.Material.Plastic.Value] = Cracks,
	[Enum.Material.Fabric.Value] = Cracks,
	[Enum.Material.Cardboard.Value] = Cracks,
	[Enum.Material.Leather.Value] = Cracks,

	-- Ice and Snow
	[Enum.Material.Ice.Value] = Glass,
	[Enum.Material.Snow.Value] = Grass,
	[Enum.Material.Glacier.Value] = Glass,

	-- Special Materials
	[Enum.Material.Pebble.Value] = Concrete,
	[Enum.Material.Air.Value] = Whizz,
}

-- Default fallback sound category
local DefaultSound = Hits

-- Camera reference for whizz sound distance calculation
local Camera = workspace.CurrentCamera

--[[
	Play a random sound from the given category at the specified position
	@param soundCategory - Array of Sound instances to choose from
	@param position - Optional Vector3 world position for 3D sound
]]
local function PlayRandomBulletSound(soundCategory: {Sound}, position: Vector3?)
	-- Throttle to prevent sound spam (max one every 0.05 seconds)
	Throttle("BulletHitSound", 0.05, function()
		-- Validate sound category
		if not soundCategory or #soundCategory == 0 then
			return
		end

		-- Get random sound from category
		local randomSound = SoundManager:GetRandomSound(soundCategory)

		if randomSound then
			-- Use SoundManager to play the sound with optional position
			SoundManager:PlaySound(randomSound, position)
		end
	end)
end

--[[
	Handle bullet whizz sounds (bullets passing near the player's camera)
	@param origin - Starting position of the bullet
	@param position - End position of the bullet
	@param length - Total bullet travel distance
]]
local function HandleWhizzSound(origin: Vector3, position: Vector3, length: number)
	-- Calculate bullet path segment
	local A = origin
	local Direction = (position - origin).Unit
	local B = origin + Direction * length
	local C = Camera.CFrame.Position

	-- Calculate closest distance from camera to bullet path
	local Distance, Point = BallisticsCommon.DistancePointToSegment(A, B, C)

	-- Only play whizz sound if bullet passes within 2 studs of camera
	if Distance <= 2 and Whizz and #Whizz > 0 then
		PlayRandomBulletSound(Whizz)
	end
end

--[[
	Handle bullet impact sounds based on material hit
	@param materialValue - Enum.Material.Value of the surface hit
	@param position - World position where bullet impacted
]]
local function HandleImpactSound(materialValue: number, position: Vector3)
	-- Get sound category for this material
	local soundCategory = Sounds[materialValue]

	-- Use default sound if material not mapped
	if not soundCategory or #soundCategory == 0 then
		soundCategory = DefaultSound
	end

	-- Play random impact sound at hit position
	PlayRandomBulletSound(soundCategory, position)
end

function SoundEffect.PlaySound(Origin,Position,Length, MaterialValue)
	-- Air material means bullet is traveling (no impact yet)
	if MaterialValue == Enum.Material.Air.Value then
		HandleWhizzSound(Origin, Position, Length)
		return
	end

	-- Material hit - play impact sound
	HandleImpactSound(MaterialValue, Position)
end

-- Singleton instance
local metatable = {__index = SoundEffect}
local instance

export type SoundEffect = typeof(setmetatable({} , metatable))

local function GetInstance()
	if not instance then
		instance = setmetatable({}, metatable)
		instance._Initialize()
	end
	return instance
end

return setmetatable({}, {
	__index = function(_, Key)
		return GetInstance()[Key]
	end,
	__newindex = function()
		error("Cannot modify SoundEffect singleton service", 2)
	end
}) :: SoundEffect