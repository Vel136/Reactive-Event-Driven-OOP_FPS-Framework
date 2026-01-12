local module = {}

-- Services
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local WeaponInstance = require(ReplicatedStorage.ClientModules.Cores.WeaponInstance)

local ObjectCache = require(ReplicatedStorage.SharedModules.Utilities.ObjectCache)
-- Used VFX
local Assets = ReplicatedStorage.Assets
local VFX = Assets:WaitForChild('VFX')
local Effects = VFX:WaitForChild('OnHit')
local OnHitHumanoid = Effects:WaitForChild('OnHitHumanoid')
local OnHit = Effects:WaitForChild('OnHit')

local CachedOnHit = ObjectCache.new(OnHit)
local CachedOnHitHumanoid = ObjectCache.new(OnHitHumanoid)
WeaponInstance.Signals.OnAnyHit:Connect(function(ctx,hitdata,damage)
	if not hitdata then return false end
	local Position = hitdata.Position
	
	local HitCFrame = CFrame.lookAt(Position, Position + hitdata.Normal)
	local Part = CachedOnHit:GetPart(HitCFrame)
	if not Part then return false end
	local Att = Part:FindFirstChildOfClass('Attachment')
	if not Att then return false end
	for _,Child in pairs(Att:GetDescendants()) do
		if Child:IsA("ParticleEmitter") then
			local EmitCount = Child:GetAttribute('EmitCount') or 25
			Child:Emit(EmitCount)
			
			task.delay(.1,function()
				CachedOnHit:ReturnPart(Part)
			end)
		end
	end
end) 
-- Used VFX
local OnFire = VFX:WaitForChild('OnFire')
local CachedTracers = ObjectCache.new(OnFire:WaitForChild('Part'),10)
WeaponInstance.Signals.OnAnyFire:Connect(function(origin,direction)
	local HitCFrame = CFrame.lookAt(origin, origin + direction)
	local Part = CachedTracers:GetPart(HitCFrame)
	
	task.delay(.1,function()
		CachedTracers:ReturnPart(Part)
	end)
end)
return module
