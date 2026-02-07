local sse = require("buddy.server.sse")
local log = require("buddy.log")
local client_requests = require("buddy.mcp.client_requests")
local uv = vim.uv

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

local function parse_query_params(path)
  local query_start = path:find("?")
  if not query_start then
    return {}, path
  end

  local query_string = path:sub(query_start + 1)
  local base_path = path:sub(1, query_start - 1)

  local params = {}
  for pair in query_string:gmatch("[^&]+") do
    local key, value = pair:match("^([^=]+)=([^=]*)")
    if key then
      -- URL decode the value
      value = value:gsub("%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
      end)
      params[key] = value
    end
  end

  return params, base_path
end

function M.handle(http_server, client, request, body)
  local params, path = parse_query_params(request.path or "")
  request.params = params
  request.path = path

  -- Auth check: skip for /health, enforce for all other endpoints
  if _auth_token and path ~= "/health" then
    local auth_header = request.headers["authorization"] or ""
    local provided_token = auth_header:match("^Bearer%s+(.+)$")
    if provided_token ~= _auth_token then
      http_server:send_response(client, 401, {["Content-Type"] = "application/json"}, vim.json.encode({
        error = {
          code = -32001,
          message = "Unauthorized: invalid or missing Bearer token",
        },
      }))
      return
    end
  end

  if request.method == "GET" and path == "/sse" then
    M._handle_sse(http_server, client, request)
  elseif request.method == "POST" and path == "/message" then
    M._handle_message(http_server, client, request, body)
  elseif request.method == "GET" and path == "/health" then
    M._handle_health(http_server, client, request)
  else
    M._handle_404(http_server, client, request)
  end
end

function M._handle_sse(http_server, client, _request)
  local sse_manager = sse.SSEManager.get_instance()

  local session_id, sse_conn = sse_manager:create_session(client, http_server.port)

  http_server.sse_connections[session_id] = sse_conn

  -- Wire up notify callback to broadcast to all sessions
  local methods = require("buddy.mcp.methods")
  methods.set_notify_callback(function(notification)
    local message = {
      jsonrpc = "2.0",
      method = notification.method,
    }
    if notification.params then
      message.params = notification.params
    end

    -- Broadcast to all active SSE connections
    local dead_sessions = {}
    for sid, conn in pairs(http_server.sse_connections) do
      local sent = conn:send_data(message)
      if not sent then
        log.warn(string.format("Dead SSE connection detected, pruning session %s", sid))
        table.insert(dead_sessions, sid)
      end
    end

    -- Prune dead sessions (can't modify table during pairs iteration)
    if #dead_sessions > 0 then
      local sse_mgr = sse.SSEManager.get_instance()
      for _, sid in ipairs(dead_sessions) do
        sse_mgr:remove_session(sid)
        http_server.sse_connections[sid] = nil
      end
    end
  end)
  log.debug("Notify callback wired up for SSE session %s", session_id)

  log.debug(string.format("SSE session created: %s", session_id))
end

function M._handle_message(http_server, client, request, body)
  local session_id = request.params and request.params.sessionId

  if not session_id then
    http_server:send_response(client, 400, {["Content-Type"] = "application/json"}, vim.json.encode({
      error = {
        code = -32600,
        message = "Invalid Request: Missing sessionId parameter",
      },
    }))
    return
  end

  local sse_manager = sse.SSEManager.get_instance()
  local sse_conn = sse_manager:get_session(session_id)

  if not sse_conn then
    http_server:send_response(client, 404, {["Content-Type"] = "application/json"}, vim.json.encode({
      error = {
        code = -32001,
        message = "Session not found",
      },
    }))
    return
  end

  local request_data
  local ok, parsed = pcall(function()
    return vim.json.decode(body or "")
  end)

  if not ok or not parsed then
    http_server:send_response(client, 400, {["Content-Type"] = "application/json"}, vim.json.encode({
      error = {
        code = -32700,
        message = "Parse error: Invalid JSON",
      },
    }))
    return
  end

  request_data = parsed

  if client_requests.is_response(request_data) then
    client_requests.handle_response(request_data)
    http_server:send_response(client, 200, {["Content-Type"] = "application/json"}, "{}")
    return
  end

  local mcp_ok, mcp = pcall(require, "buddy.mcp")
  if not mcp_ok or not mcp.handle_request then
    http_server:send_response(client, 500, {["Content-Type"] = "application/json"}, vim.json.encode({
      error = {
        code = -32603,
        message = "Internal error: MCP handler not available",
      },
    }))
    return
  end

  vim.schedule(function()
    local response
    local response_ok, response_result = pcall(function()
      return mcp.handle_request(session_id, request_data)
    end)

    if response_ok then
      response = response_result
    else
      response = {
        jsonrpc = "2.0",
        id = request_data.id,
        error = {
          code = -32603,
          message = "Internal error: " .. tostring(response_result),
        },
      }
    end

    -- Send response via SSE stream (use unnamed event for MCP SDK compatibility)
    if response then
      local sent = sse_conn:send_data(response)
      if not sent then
        log.warn(string.format("Failed to send SSE response for session %s", session_id))
      end
    else
      log.warn(string.format("No response to send for session %s", session_id))
    end

    log.debug(string.format("MCP request handled for session %s: %s", session_id, request_data.method or "unknown"))
  end)

  http_server:send_response(client, 202, {["Content-Type"] = "application/json"}, "")
end

function M._handle_health(http_server, client, _request)
  local response = vim.json.encode({
    status = "ok",
    timestamp = uv.now(),
  })

  http_server:send_response(
    client,
    200,
    {["Content-Type"] = "application/json"},
    response
  )
end

function M._handle_404(http_server, client, request)
  local response = vim.json.encode({
    error = {
      code = 404,
      message = "Not Found",
      path = request.path,
    },
  })

  http_server:send_response(
    client,
    404,
    {["Content-Type"] = "application/json"},
    response
  )
end

return M
