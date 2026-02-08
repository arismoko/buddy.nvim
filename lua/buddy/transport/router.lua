--- Thin transport router
--- Handles only: auth validation, query parameter parsing, path/method dispatch.
--- Delegates all business logic to app/http_handlers.
--- No MCP protocol knowledge, no service wiring, no hub lifecycle management.

local parser = require("buddy.transport.http.parser")

local M = {}

-- Auth token for Bearer authentication (nil = auth disabled)
local _auth_token = nil

--- Set the auth token for request validation
---@param token string|nil The Bearer token (nil disables auth)
function M.set_auth_token(token)
  _auth_token = token
end

--- Get the current auth token (for testing)
---@return string|nil
function M.get_auth_token()
  return _auth_token
end

--- Route table: method + path → handler function name
---@type table<string, string>
local _routes = {
  ["GET /sse"] = "handle_sse",
  ["GET /health"] = "handle_health",
  ["POST /message"] = "handle_message",
}

--- Handle an incoming HTTP request
--- Performs auth check, parses query params, and dispatches to the appropriate handler.
---@param http_server table HTTPServer instance
---@param client userdata TCP client handle
---@param request table Parsed HTTP request {method, path, headers, version}
---@param body string Request body
function M.handle(http_server, client, request, body)
  local handlers = require("buddy.app.http_handlers")

  -- Parse query parameters from path
  local params, path = parser.parse_query_params(request.path or "")
  request.params = params
  request.path = path

  -- Auth check: skip for /health, enforce for all other endpoints
  if _auth_token and path ~= "/health" then
    local auth_header = request.headers["authorization"] or ""
    local provided_token = auth_header:match("^Bearer%s+(.+)$")
    if provided_token ~= _auth_token then
      http_server:send_response(client, 401, { ["Content-Type"] = "application/json" }, vim.json.encode({
        error = {
          code = -32001,
          message = "Unauthorized: invalid or missing Bearer token",
        },
      }))
      return
    end
  end

  -- Dispatch to handler
  local route_key = request.method .. " " .. path
  local handler_name = _routes[route_key]

  if handler_name then
    handlers[handler_name](http_server, client, request, body)
  else
    handlers.handle_not_found(http_server, client, request)
  end
end

--- Reset internal state (for testing)
function M._reset()
  _auth_token = nil
end

return M
