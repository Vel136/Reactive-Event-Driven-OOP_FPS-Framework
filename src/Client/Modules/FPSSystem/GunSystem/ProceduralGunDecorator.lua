-- ProceduralGunDecorator.lua
--[[
	Decorates weapon instances with client-side procedural animations,
	weapon animations, and visual effects (bullet ejection, etc.)
	Agnostic to the underlying weapon implementation.
]]
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local GunAnimator = require(ReplicatedStorage.Client.Modules.FPSSystem.AnimationSystem.GunAnimator)
local ProceduralAnimator = require(ReplicatedStorage.Client.Modules.FPSSystem.ProcedularAnimations.ProceduralAnimator)
local BulletEject = require(ReplicatedStorage.Shared.Modules.Utilities.BulletEject)

local ProceduralGunDecorator = {}

--[[
	Enhances a weapon instance with procedural animations and effects
	@param weaponInstance - Any weapon instance with .Data.Model and .Signals.OnFire
	@param proceduralData - Configuration for procedural animations (optional)
	@param bulletEjectData - Configuration for bullet ejection system (optional)
	@return Enhanced weapon instance with Animator, ProceduralAnimator, and BulletEject properties
]]

function ProceduralGunDecorator.new <T>(weaponInstance: T, proceduralData, bulletEjectData): T & EnhancedWeaponInstance
	if not weaponInstance then
		print(weaponInstance)
		error("ProceduralGunDecorator requires a weapon instance", 2)
	end

	-- Create procedural animator
	local proceduralAnimator = ProceduralAnimator.new()

	-- Create weapon animator
	local animator = GunAnimator.new(weaponInstance, weaponInstance.Data.Model)

	-- Configure procedural animations if data provided
	if proceduralData then
		if proceduralData.CameraRecoil then
			proceduralAnimator.CameraRecoil:SetConfig(proceduralData.CameraRecoil)
		end
		if proceduralData.MouseSway then
			proceduralAnimator.WeaponTilt:SetConfig(proceduralData.MouseSway)
		end
		if proceduralData.RotationalSway then
			proceduralAnimator.RotationalSway:SetConfig(proceduralData.RotationalSway)
		end
		if proceduralData.SpringSway then
			proceduralAnimator.SpringSway:SetConfig(proceduralData.SpringSway)
		end
		if proceduralData.WalkBob then
			proceduralAnimator.WalkBob:SetConfig(proceduralData.WalkBob)
		end
		if proceduralData.WalkTilt then
			proceduralAnimator.WalkTilt:SetConfig(proceduralData.WalkTilt)
		end
		if proceduralData.WeaponRecoil then
			proceduralAnimator.WeaponRecoil:SetConfig(proceduralData.WeaponRecoil)
		end
		if proceduralData.WeaponTilt then
			proceduralAnimator.WeaponTilt:SetConfig(proceduralData.WeaponTilt)
		end
		if proceduralData.ProceduralSway then
			proceduralAnimator.ProceduralSway:SetConfig(proceduralData.ProceduralSway)
		end
	end

	-- Setup bullet ejection system if data provided
	if bulletEjectData then
		local bulletEjects = {}
		for bulletType, ejectData in pairs(bulletEjectData.Bullets) do
			local bulletEject = BulletEject.new(
				bulletEjectData.Attachment,
				ejectData.Bullet,
				ejectData.Data
			)
			bulletEjects[bulletType] = bulletEject

			-- Auto-eject shells on fire if configured
			if ejectData.AutoEjectShells and weaponInstance._Janitor and weaponInstance.Signals and weaponInstance.Signals.OnFire then
				weaponInstance._Janitor:Add(weaponInstance.Signals.OnFire:Connect(function()
					bulletEject:Eject()
				end), "Disconnect")
			end
		end
		weaponInstance.BulletEject = bulletEjects
	end

	-- Attach components to weapon instance
	weaponInstance.Animator = animator
	weaponInstance.ProceduralAnimator = proceduralAnimator

	return weaponInstance :: T & EnhancedWeaponInstance
end

export type EnhancedWeaponInstance = {
	Animator: GunAnimator.GunAnimator,
	ProceduralAnimator: ProceduralAnimator.ProceduralAnimator,
	BulletEject: {[any]: BulletEject.BulletEject}?
}

return ProceduralGunDecorator