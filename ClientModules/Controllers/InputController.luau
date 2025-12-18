local module = {}
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local RunService = game:GetService('RunService')
local Utilities = ReplicatedStorage.SharedModules.Utilities
local Signal = require(Utilities.Signal)
local IAS = require(Utilities.IAS)

-- Create Input Actions
local FireInput = IAS.new("Fire")
local ReloadInput = IAS.new("Reload")
local AimInput = IAS.new("Aim")

local Inputs = {
	Fire = FireInput,
	Reload = ReloadInput,
	Aim = AimInput,
}

-- Create Signals
local FireSignal = Signal.new()
local ReloadSignal = Signal.new()
local AimSignal = Signal.new()

local Signals = {
	Fire = FireSignal,
	Reload = ReloadSignal,
	Aim = AimSignal,
}

module.Signals = Signals

-- Fire mode settings
local FireMode = "Auto" -- "Auto" or "Semi"
local FireRate = 0.1 -- Time between shots in auto mode (10 shots per second)

-- Internal state for firing
local isFiring = false
local fireConnection = nil
local lastFireTime = 0

-- Function to handle a single shot
local function fireSingleShot()
	local currentTime = tick()

	-- Check fire rate cooldown
	if currentTime - lastFireTime >= FireRate then
		lastFireTime = currentTime
		FireSignal:Fire(true) -- Signal that we're firing
	end
end

-- Function to start continuous firing (Auto mode)
local function startAutoFire()
	if fireConnection then return end -- Already firing

	-- Fire immediately on press
	fireSingleShot()

	-- Then continue firing at the specified rate
	fireConnection = RunService.Heartbeat:Connect(function()
		if isFiring then
			fireSingleShot()
		end
	end)
end

-- Function to stop continuous firing
local function stopAutoFire()
	if fireConnection then
		fireConnection:Disconnect()
		fireConnection = nil
	end
	FireSignal:Fire(false) -- Signal that we stopped firing
end

function module.Init()
	-- Configure Firing input
	FireInput:AddBind(Enum.KeyCode.MouseLeftButton) -- Mouse left click
	FireInput:SetHold(true) -- Hold mode is essential for auto fire

	-- Configure Reload Input
	ReloadInput:AddBind(Enum.KeyCode.R)
	ReloadInput:SetHold(false) -- Toggle mode not needed, just tap to reload

	-- Configure Aim Input
	AimInput:AddBind(Enum.KeyCode.MouseRightButton) -- Mouse right click
	AimInput:SetHold(true) -- Hold to aim

	-- Fire Input Logic
	FireInput.Activated:Connect(function(active, wasPressed)
		if active and wasPressed then
			-- Key pressed down
			isFiring = true

			if FireMode == "Auto" then
				startAutoFire()
			elseif FireMode == "Semi" then
				-- In semi mode, just fire once per press
				fireSingleShot()
			end

		elseif not active and not wasPressed then
			-- Key released
			isFiring = false

			if FireMode == "Auto" then
				stopAutoFire()
			end
		end
	end)

	-- Reload Input Logic
	ReloadInput.Activated:Connect(function(active, wasPressed)
		if active and wasPressed then
			ReloadSignal:Fire()
		end
	end)

	-- Aim Input Logic
	AimInput.Activated:Connect(function(active, wasPressed)
		AimSignal:Fire(active) -- Pass the aim state directly
	end)

	return Inputs
end

function module.GetInputs()
	return Inputs
end

-- Set fire mode (Auto or Semi)
function module.SetFireMode(mode: "Auto" | "Semi")
	if mode ~= "Auto" and mode ~= "Semi" then
		warn("[InputController]: Invalid fire mode. Use 'Auto' or 'Semi'")
		return false
	end

	FireMode = mode

	-- If we're currently firing in auto and switch to semi, stop the auto loop
	if FireMode == "Semi" and fireConnection then
		stopAutoFire()
	end

	return true
end

-- Get current fire mode
function module.GetFireMode()
	return FireMode
end

-- Set fire rate (shots per second)
function module.SetFireRate(RPM: number)
	RPM = RPM/60
	RPM = math.max(0.1, RPM) -- Minimum 0.1 shots per second
	FireRate = 1 / RPM -- Convert to time between shots
end

-- Enable/Disable specific input
function module.SetEnabled(Input: "Fire" | "Reload" | "Aim", enabled: boolean)
	if not Inputs[Input] then 
		warn("[InputController]: Invalid Input") 
		return false 
	end

	Inputs[Input]:SetEnabled(enabled)

	-- If disabling fire input while firing, clean up
	if Input == "Fire" and not enabled and isFiring then
		isFiring = false
		stopAutoFire()
	end

	return true
end

-- Cleanup function
function module.Cleanup()
	if fireConnection then
		fireConnection:Disconnect()
		fireConnection = nil
	end

	FireInput:Destroy()
	ReloadInput:Destroy()
	AimInput:Destroy()

	FireSignal:DisconnectAll()
	ReloadSignal:DisconnectAll()
	AimSignal:DisconnectAll()
end

return module