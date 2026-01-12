--// Coded By Skyler | Roblox (Takeables) | Discord (skyler_wrld) \\--

local Logger = {}

local LOG_CONFIGS = {
	Error = { icon = "🛑", prefix = "[ERROR]", fn = error },
	Warn = { icon = "⚠️", prefix = "[WARNING]", fn = warn },
	Print = { icon = "📃", prefix = "[LOG]", fn = print }
}
local LOGGING = true
local function formatMessage(config, message, scriptName)
	
	return string.format(
		"%s %s %s | Logged From Script: %s",
		config.icon,
		config.prefix,
		message,
		scriptName or "Unknown"
	)
end

function Logger.Error(message, scriptName)
	if not LOGGING then return end
	local config = LOG_CONFIGS.Error
	config.fn(formatMessage(config, message, scriptName))
end

function Logger.Warn(message, scriptName)
	if not LOGGING then return end
	local config = LOG_CONFIGS.Warn
	config.fn(formatMessage(config, message, scriptName))
end

function Logger.Print(message, scriptName)
	if not LOGGING then return end
	local config = LOG_CONFIGS.Print
	config.fn(formatMessage(config, message, scriptName))
end

return Logger