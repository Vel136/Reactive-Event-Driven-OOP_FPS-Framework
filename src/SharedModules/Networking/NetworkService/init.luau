--[=[
	@class NetworkService
	Singleton wrapper around NetRay for weapon framework networking.
	Provides abstraction and type-safe event handling.
]=]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local module = {}

local Blink = require(script.Blink.Client)

local Events = require(script.Events)
local Logger = require(ReplicatedStorage.SharedModules.Utilities.LogService) -- Adjust path as needed

local Identity = "[NetworkService]"

-- Singleton pattern with read-only access
return module