--- MCP method handler registry
--- Central registration table for protocol method handlers
local M = {}

---@type table<string, function>
local _handlers = {}

--- Register a method handler
---@param method string The MCP method name (e.g., "tools/list")
---@param handler function Handler function(session_id, params, request_id?) -> result|nil
function M.register(method, handler)
  _handlers[method] = handler
end

--- Get a handler for a method
---@param method string The MCP method name
---@return function|nil handler
function M.get(method)
  return _handlers[method]
end

--- Get all registered handlers
---@return table<string, function>
function M.all()
  return _handlers
end

return M
