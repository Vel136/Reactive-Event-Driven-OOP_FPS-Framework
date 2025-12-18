local module = {}

local ReplicatedStorage = game:GetService('ReplicatedStorage')
local WeaponInstance = require(ReplicatedStorage.SharedModules.Cores.WeaponInstance)

local Assets = ReplicatedStorage.Assets
local VFX = Assets.VFX
local OnHitVFX = VFX.OnHit:GetChildren()

local OnHit = WeaponInstance.Signals.OnAnyHit

for _,vfx in pairs(OnHitVFX) do
	vfx.Parent = workspace
end
OnHit:Connect(function(hitpart,damage)
	local target = hitpart
	if not target.Parent:FindFirstChild("Humanoid") then return false end
	
	local Position = target.Parent.PrimaryPart.Position
	script["TF2 Critical Hit Sound"]:Play()
	for _,vfx in pairs(OnHitVFX) do
		vfx.Position = Position
		for _,child in pairs(vfx:GetDescendants()) do
			if child:IsA("ParticleEmitter") then
				child:Emit(5)
			end
		end
	end
end)
return module
