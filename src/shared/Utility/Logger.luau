--!strict
local Config = require(script.Parent.Parent.Config)

export type LogLevel = "DEBUG" | "INFO" | "WARN" | "ERROR"

local LEVELS: { [LogLevel]: number } = {
	DEBUG = 1,
	INFO = 2,
	WARN = 3,
	ERROR = 4,
}

local Logger = {}
local currentLevel: number = LEVELS[Config.LOG_LEVEL or "INFO"] or 2

function Logger.SetLogLevel(level: LogLevel)
	currentLevel = LEVELS[level] or 2
end

local function formatMessage(prefix: string, category: string, formatStr: string, ...: any): string
	local ok, formatted = pcall(string.format, formatStr, ...)
	local content = ok and formatted or tostring(formatStr)
	return string.format("[%s][%s] %s", prefix, category, content)
end

function Logger:Debug(category: string, formatStr: string, ...: any)
	if currentLevel <= LEVELS.DEBUG then
		print(formatMessage("DEBUG", category, formatStr, ...))
	end
end

function Logger:Info(category: string, formatStr: string, ...: any)
	if currentLevel <= LEVELS.INFO then
		print(formatMessage("INFO", category, formatStr, ...))
	end
end

function Logger:Warn(category: string, formatStr: string, ...: any)
	if currentLevel <= LEVELS.WARN then
		warn(formatMessage("WARN", category, formatStr, ...))
	end
end

function Logger:Error(category: string, formatStr: string, ...: any)
	if currentLevel <= LEVELS.ERROR then
		warn(formatMessage("ERROR", category, formatStr, ...))
	end
end

return Logger
