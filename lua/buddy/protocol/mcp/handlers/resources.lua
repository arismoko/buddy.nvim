--- MCP resources handlers: resources/list, resources/templates/list,
--- resources/read, resources/subscribe, resources/unsubscribe
local registry = require("buddy.protocol.mcp.registry")

-- Module-level subscription tracking
local subscriptions = {}

registry.register("resources/list", function(_session_id, params)
  local _ = params and params.cursor  -- Accept cursor param (unused - no pagination needed)
  local resources = require("buddy.resources")
  return { resources = resources.list() }  -- omit nextCursor when no more pages
end)

registry.register("resources/templates/list", function(_session_id, params)
  local _ = params and params.cursor  -- Accept cursor param (unused - no pagination needed)
  local resources = require("buddy.resources")
  return { resourceTemplates = resources.list_templates() }  -- omit nextCursor when no more pages
end)

registry.register("resources/read", function(_session_id, params)
  if not params or not params.uri then
    error("Missing required parameter: uri")
  end
  local resources = require("buddy.resources")
  local content = resources.read(params.uri)
  if not content then
    error("Resource not found: " .. params.uri)
  end
  return { contents = content }
end)

registry.register("resources/subscribe", function(session_id, params)
  if not params or not params.uri then
    error("Missing required parameter: uri")
  end

  subscriptions[session_id] = subscriptions[session_id] or {}
  subscriptions[session_id][params.uri] = true

  return vim.empty_dict()
end)

registry.register("resources/unsubscribe", function(session_id, params)
  if not params or not params.uri then
    error("Missing required parameter: uri")
  end

  if subscriptions[session_id] then
    subscriptions[session_id][params.uri] = nil
  end

  return vim.empty_dict()
end)
