--- Application lifecycle wiring
--- Manages deterministic setup and teardown of cross-cutting services
--- (Notifier, ToolService, method callbacks) that previously lived in the router.

local log = require("buddy.log")

local M = {}

-- Whether services have been wired (once per server lifetime)
local _wired = false

--- Wire all cross-cutting services for the server lifetime.
--- Must be called once during server startup (not per-session).
---
---@param hub table SSEHub instance for transport delivery
function M.start_wiring(hub)
  if _wired then
    return
  end

  local Notifier = require("buddy.services.notifier")

  local notifier = Notifier.new({
    send_fn = function(sid, msg)
      return hub:send_to_session(sid, msg)
    end,
    broadcast_fn = function(msg)
      hub:broadcast(msg)
    end,
  })

  -- Wire methods facade notification callback
  local methods = require("buddy.mcp.methods")
  methods.set_notify_callback(function(notification)
    notifier:broadcast(notification.method, notification.params)
  end)

  -- Wire ToolService singleton with notifier for progress notifications
  local ToolService = require("buddy.services.tool_service")
  ToolService.set_instance(ToolService.new({
    notifier = notifier,
  }))

  _wired = true
  log.debug("Lifecycle: services wired")
end

--- Reset all wiring (called during server stop for clean restart)
function M.reset_wiring()
  if not _wired then
    return
  end

  -- Reset ToolService singleton
  local ts_ok, ToolService = pcall(require, "buddy.services.tool_service")
  if ts_ok then
    ToolService.reset()
  end

  -- Clear notify callback
  local methods_ok, methods = pcall(require, "buddy.mcp.methods")
  if methods_ok then
    methods.set_notify_callback(nil)
  end

  -- Reset client_requests singleton
  local cr_ok, cr = pcall(require, "buddy.mcp.client_requests")
  if cr_ok and cr._reset then
    cr._reset()
  end

  _wired = false
  log.debug("Lifecycle: services reset")
end

--- Check if services are wired
---@return boolean
function M.is_wired()
  return _wired
end

return M
