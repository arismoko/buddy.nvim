--- Logging utilities for buddy
local M = {}

local LEVELS = {
  DEBUG = 1,
  INFO = 2,
  NOTICE = 3,
  WARNING = 4,
  ERROR = 5,
  CRITICAL = 6,
  ALERT = 7,
  EMERGENCY = 8,
}

local LEVEL_NAMES = { "DEBUG", "INFO", "NOTICE", "WARNING", "ERROR", "CRITICAL", "ALERT", "EMERGENCY" }

-- Callback for sending notifications (set by server)
M._notify_callback = nil

function M.set_notify_callback(callback)
  M._notify_callback = callback
end

--- Set log level
---@param level string
function M.set_level(level)
  local config = require("buddy.config")
  local opts = config.get()
  if level == "debug" then
    opts.debug = true
  else
    opts.debug = false
  end
  -- We don't have a formal "level" in config yet, but we could add it
end

-- Internal helper to maybe broadcast
local function maybe_notify(level, message, data)
  if M._notify_callback then
    M._notify_callback({
      method = "notifications/message",
      params = {
        level = level,
        logger = "buddy",
        data = data or message,
      },
    })
  end
end

---@param level number
---@param msg string
---@param ... any
local function log(level, msg, ...)
  local config = require("buddy.config")
  local opts = config.get()

  -- Debug messages only show when debug mode is enabled
  if level == LEVELS.DEBUG and not opts.debug then
    return
  end

  local formatted = string.format(msg, ...)

  maybe_notify(LEVEL_NAMES[level]:lower(), formatted)

  local prefix = string.format("[buddy:%s]", LEVEL_NAMES[level])

  if level >= LEVELS.WARNING then
    vim.notify(prefix .. " " .. formatted, level >= LEVELS.ERROR and vim.log.levels.ERROR or vim.log.levels.WARN)
  else
    -- Debug/info/notice go to :messages only
    vim.api.nvim_echo({ { prefix .. " " .. formatted, "Comment" } }, true, {})
  end
end

--- Debug message (only shown when debug = true)
---@param msg string
---@param ... any
function M.debug(msg, ...)
  log(LEVELS.DEBUG, msg, ...)
end

--- Info message
---@param msg string
---@param ... any
function M.info(msg, ...)
  log(LEVELS.INFO, msg, ...)
end

--- Notice message
---@param msg string
---@param ... any
function M.notice(msg, ...)
  log(LEVELS.NOTICE, msg, ...)
end

--- Warning message
---@param msg string
---@param ... any
function M.warning(msg, ...)
  log(LEVELS.WARNING, msg, ...)
end

---@deprecated Use warning
function M.warn(msg, ...)
  log(LEVELS.WARNING, msg, ...)
end

--- Error message
---@param msg string
---@param ... any
function M.error(msg, ...)
  log(LEVELS.ERROR, msg, ...)
end

--- Critical message
---@param msg string
---@param ... any
function M.critical(msg, ...)
  log(LEVELS.CRITICAL, msg, ...)
end

--- Alert message
---@param msg string
---@param ... any
function M.alert(msg, ...)
  log(LEVELS.ALERT, msg, ...)
end

--- Emergency message
---@param msg string
---@param ... any
function M.emergency(msg, ...)
  log(LEVELS.EMERGENCY, msg, ...)
end

return M
