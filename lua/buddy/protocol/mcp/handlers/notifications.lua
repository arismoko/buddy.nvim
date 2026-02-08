--- MCP notification handlers: notifications/cancelled, notifications/initialized,
--- notifications/roots/list_changed, notifications/progress
local registry = require("buddy.protocol.mcp.registry")

registry.register("notifications/initialized", function(_session_id, _params)
  return nil
end)

registry.register("notifications/cancelled", function(_session_id, params)
  local log = require("buddy.log")
  if params and params.requestId then
    log.debug("Client cancelled request: %s", tostring(params.requestId))
    -- Future: could cancel in-progress tool execution
  end
  return nil  -- notifications don't return
end)

registry.register("notifications/roots/list_changed", function(session_id, _params)
  local log = require("buddy.log")
  log.info("Client workspace roots changed")

  -- Optionally refresh our cached roots
  local session_state = require("buddy.mcp.session_state")
  local state = session_state.get(session_id)
  if state then
    -- Clear cached roots so next roots.list() fetches fresh
    state.cached_roots = nil
  end

  return nil  -- notifications don't return
end)

--- Handle progress notifications from client (for our server-to-client requests)
registry.register("notifications/progress", function(_session_id, params)
  local log = require("buddy.log")
  if params then
    log.debug("Progress: %s/%s - %s",
      tostring(params.progress),
      tostring(params.total or "?"),
      params.message or "")
  end
  return nil  -- notifications don't return
end)
