--- MCP protocol dispatcher
--- Validates JSON-RPC envelope, looks up handler in registry, calls it
local jsonrpc = require("buddy.protocol.jsonrpc")
local registry = require("buddy.protocol.mcp.registry")
local errors = require("buddy.protocol.mcp.errors")

local M = {}

-- Ensure all handler modules are loaded (registers handlers in registry)
local _loaded = false
local function _ensure_handlers()
  if _loaded then return end
  require("buddy.protocol.mcp.handlers.core")
  require("buddy.protocol.mcp.handlers.tools")
  require("buddy.protocol.mcp.handlers.resources")
  require("buddy.protocol.mcp.handlers.prompts")
  require("buddy.protocol.mcp.handlers.completion")
  require("buddy.protocol.mcp.handlers.notifications")
  _loaded = true
end

--- Handle an incoming MCP request
--- Validates JSON-RPC, resolves handler, and returns the response envelope
---@param session_id string The SSE session ID
---@param request table The parsed JSON-RPC request
---@return table|nil response JSON-RPC response, or nil for notifications
function M.handle_request(session_id, request)
  _ensure_handlers()

  local valid, err = jsonrpc.validate_request(request)
  if not valid then
    if request.id then
      return jsonrpc.error(request.id, errors.INVALID_REQUEST, "Invalid Request", err)
    end
    return nil
  end

  local is_notification = request.id == nil

  local handler = registry.get(request.method)

  if not handler then
    if is_notification then
      return nil
    end
    return jsonrpc.error(request.id, errors.METHOD_NOT_FOUND, "Method not found", "Unknown method: " .. request.method)
  end

  local ok, result = pcall(handler, session_id, request.params or {}, request.id)

  if not ok then
    if is_notification then
      return nil
    end
    return jsonrpc.error(request.id, errors.INTERNAL_ERROR, "Internal error", tostring(result))
  end

  if is_notification then
    return nil
  end

  return jsonrpc.result(request.id, result)
end

return M
