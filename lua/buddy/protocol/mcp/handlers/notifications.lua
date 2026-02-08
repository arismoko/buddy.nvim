--- MCP notification handlers: notifications/cancelled, notifications/initialized,
--- notifications/roots/list_changed, notifications/progress
local registry = require("buddy.protocol.mcp.registry")

registry.register("notifications/initialized", function(_session_id, _params)
  return nil
end)

registry.register("notifications/cancelled", function(session_id, params)
  local log = require("buddy.log")
  if not params or not params.requestId then
    return nil
  end

  log.debug("Client cancelled request: %s (session: %s)", tostring(params.requestId), session_id)

  -- Look up bound task_id and cancel it
  local buddy = require("buddy")
  local request_store = buddy._runtime and buddy._runtime.request_store
  if request_store then
    local task_id = request_store:get_tool_task(session_id, params.requestId)
    if task_id then
      local ToolService = require("buddy.services.tool_service")
      local service = ToolService.get_instance()
      if service then
        local cancelled = service:cancel(task_id)
        log.debug("Cancel task %s for request %s: %s", task_id, tostring(params.requestId), tostring(cancelled))
      end
      request_store:unbind_tool_task(session_id, params.requestId)
    end
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
