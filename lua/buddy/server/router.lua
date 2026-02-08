local log = require("buddy.log")
local client_requests = require("buddy.mcp.client_requests")
local uv = vim.uv

local M = {}

-- Auth token for Bearer authentication (nil = auth disabled)
local _auth_token = nil

-- Whether the notifier has been wired to methods (once per server lifetime)
local _notifier_wired = false

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
  local SSEHub = require("buddy.transport.sse.hub")
  local hub = SSEHub.get_instance(http_server)

  local session_id, _sse_conn = hub:open_session(client, http_server.port)

  -- Wire notifier once (not per session) to route notifications through Notifier service
  if not _notifier_wired then
    local Notifier = require("buddy.services.notifier")

    local notifier = Notifier.new({
      send_fn = function(sid, msg)
        return hub:send_to_session(sid, msg)
      end,
      broadcast_fn = function(msg)
        hub:broadcast(msg)
      end,
    })

    local methods = require("buddy.mcp.methods")
    methods.set_notify_callback(function(notification)
      notifier:broadcast(notification.method, notification.params)
    end)

    -- Wire ToolService singleton with notifier for progress notifications
    local ToolService = require("buddy.services.tool_service")
    ToolService.set_instance(ToolService.new({
      notifier = notifier,
    }))

    _notifier_wired = true
    log.debug("Notifier wired via SSEHub (once)")
  end

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

  local SSEHub = require("buddy.transport.sse.hub")
  local hub = SSEHub.get_instance(http_server)
  local sse_conn = hub:get_session(session_id)

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
      local sent = hub:send_to_session(session_id, response)
      if not sent then
        log.warn(string.format("Failed to send SSE response for session %s, closing dead session", session_id))
        hub:close_session(session_id)
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

--- Reset internal state (for testing)
function M._reset()
  _notifier_wired = false
  local ok, ToolService = pcall(require, "buddy.services.tool_service")
  if ok then
    ToolService.reset()
  end
end

return M
