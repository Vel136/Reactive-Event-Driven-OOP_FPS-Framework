local module = {}
-- Services
local ReplicatedStorage = game:GetService('ReplicatedStorage')
-- Required Modules
local Throttle = require(ReplicatedStorage.SharedModules.Utilities.Throttle)
-- Used Sounds, check ReplicatedStorage/Assets/BulletSounds
local BulletSounds = ReplicatedStorage.Assets.BulletSounds
local Body = BulletSounds.Body and BulletSounds.Body:GetChildren() or {}
local Glass = BulletSounds.Glass and BulletSounds.Glass:GetChildren() or {}
local Concrete = BulletSounds.Concrete and BulletSounds.Concrete:GetChildren() or {}
local Cracks = BulletSounds.Cracks and BulletSounds.Cracks:GetChildren() or {}
local Grass = BulletSounds.Grass and BulletSounds.Grass:GetChildren() or {}
local Hits = BulletSounds.Hits and BulletSounds.Hits:GetChildren() or {}
local Metal = BulletSounds.Metal and BulletSounds.Metal:GetChildren() or {}
local Whizz = BulletSounds.Whizz and BulletSounds.Whizz:GetChildren() or {}
local Wood = BulletSounds.Wood and BulletSounds.Wood:GetChildren() or {}
-- Precreate a sound and list categories
local Sound = Instance.new('Sound')
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

-- Required Modules
local WeaponInstance = require(ReplicatedStorage.ClientModules.Cores.WeaponInstance)
local SoundService = game:GetService('SoundService')
local BallisticsCommon = require(ReplicatedStorage.SharedModules.BallisticsCommon)

local Att = Instance.new('Attachment')
function PlaySound(Sound : Sound,Position)
	Throttle("HitSound", .05, function()
		if Position then
			local Att = Instance.new('Attachment')
			Att.Parent = workspace.Terrain
			Att.WorldPosition = Position
			local OriginalParent = Sound.Parent
			Sound.Parent = Att
			Sound:Play()

			Sound.Ended:Once(function()
				Sound.Parent = OriginalParent
				Att:Destroy()
			end)
		else
			Sound:Play()
		end
	end)
end
local Camera = workspace.CurrentCamera
WeaponInstance.Signals.OnSoundSync:Connect(function(Origin,Position,Length,MaterialValue)
	local A = Origin
	local Direction = (Position - Origin).Unit
	local B = Origin + Direction * Length
	local C = Camera.CFrame.Position
	-- No hit data means bullet is traveling through air
	if MaterialValue == Enum.Material.Air.Value then
		local Distance, Point = BallisticsCommon.DistancePointToSegment(A,B,C)
		if Distance <= 2 and Whizz and #Whizz > 0 then
			local Choosed = Whizz[math.random(1, #Whizz)]
			if Choosed then
				PlaySound(Choosed)
			end
		end
		return
	end
	
	local SoundCategory = Sounds[MaterialValue]

	-- Use default sound if material not mapped
	if not SoundCategory or #SoundCategory == 0 then
		SoundCategory = DefaultSound
	end
	
	-- Play random sound from category
	if SoundCategory and #SoundCategory > 0 then
		local Choosed = SoundCategory[math.random(1, #SoundCategory)]

		if Choosed then
			PlaySound(Choosed,Position)
		end
	end
end)

return module