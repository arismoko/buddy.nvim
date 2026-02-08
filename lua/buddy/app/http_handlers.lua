--- HTTP request handlers for MCP transport
--- Contains the business logic for SSE, message, health, and 404 endpoints.
--- Separated from transport routing to keep the router thin.

local log = require("buddy.log")

local uv = vim.uv

local M = {}

--- Handle GET /sse — create a new SSE session
---@param http_server table HTTPServer instance
---@param client userdata TCP client handle
---@param _request table Parsed HTTP request
function M.handle_sse(http_server, client, _request)
  local SSEHub = require("buddy.transport.sse.hub")
  local hub = SSEHub.get_instance(http_server)

  local session_id, _sse_conn = hub:open_session(client, http_server.port)

  log.debug(string.format("SSE session created: %s", session_id))
end

--- Handle POST /message — process an MCP message
---@param http_server table HTTPServer instance
---@param client userdata TCP client handle
---@param request table Parsed HTTP request (with params populated)
---@param body string Request body
function M.handle_message(http_server, client, request, body)
  local client_requests = require("buddy.mcp.client_requests")
  local session_id = request.params and request.params.sessionId

  if not session_id then
    http_server:send_response(client, 400, { ["Content-Type"] = "application/json" }, vim.json.encode({
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
    http_server:send_response(client, 404, { ["Content-Type"] = "application/json" }, vim.json.encode({
      error = {
        code = -32001,
        message = "Session not found",
      },
    }))
    return
  end

  -- Parse JSON body
  local ok, parsed = pcall(vim.json.decode, body or "")

  if not ok or not parsed then
    http_server:send_response(client, 400, { ["Content-Type"] = "application/json" }, vim.json.encode({
      error = {
        code = -32700,
        message = "Parse error: Invalid JSON",
      },
    }))
    return
  end

  local request_data = parsed

  -- Handle client responses to server-initiated requests
  if client_requests.is_response(request_data) then
    client_requests.handle_response(request_data)
    http_server:send_response(client, 200, { ["Content-Type"] = "application/json" }, "{}")
    return
  end

  -- Dispatch to MCP protocol layer
  local mcp_ok, mcp = pcall(require, "buddy.mcp")
  if not mcp_ok or not mcp.handle_request then
    http_server:send_response(client, 500, { ["Content-Type"] = "application/json" }, vim.json.encode({
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

    -- Send response via SSE stream
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

  http_server:send_response(client, 202, { ["Content-Type"] = "application/json" }, "")
end

--- Handle GET /health — return server health status
---@param http_server table HTTPServer instance
---@param client userdata TCP client handle
---@param _request table Parsed HTTP request
function M.handle_health(http_server, client, _request)
  local response = vim.json.encode({
    status = "ok",
    timestamp = uv.now(),
  })

  http_server:send_response(
    client,
    200,
    { ["Content-Type"] = "application/json" },
    response
  )
end

--- Handle unknown routes — return 404
---@param http_server table HTTPServer instance
---@param client userdata TCP client handle
---@param request table Parsed HTTP request
function M.handle_not_found(http_server, client, request)
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
    { ["Content-Type"] = "application/json" },
    response
  )
end

return M
