local ReplicatedStorage = game:GetService('ReplicatedStorage')

local Weapons = {}

for _, Child in pairs(script.Grenades:GetChildren()) do
	if Child:IsA('ModuleScript') then
		local Gun = require(Child)
		Weapons[Child.Name or "Unknown Weapon"] = Gun
	end
end

return Weapons
