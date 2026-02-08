-- SSE Hub: Authoritative lifecycle manager for SSE sessions
-- Owns session→connection mapping, client→session reverse lookup,
-- and emits events via the event bus on connect/disconnect.

local log = require("buddy.log")

---@class SSEHub
---@field _manager table SSEManager instance
---@field _http_server table|nil Reference to http_server
---@field _client_to_session table<userdata, string> TCP client → session_id reverse map
local SSEHub = {}
SSEHub.__index = SSEHub

local _instance = nil

--- Get or create the singleton SSEHub
---@param http_server? table HTTP server instance
---@return SSEHub
function SSEHub.get_instance(http_server)
  if not _instance then
    local sse = require("buddy.server.sse")
    _instance = setmetatable({}, SSEHub)
    _instance._manager = sse.SSEManager.get_instance()
    _instance._http_server = http_server
    _instance._client_to_session = {}
  end
  if http_server then
    _instance._http_server = http_server
  end
  return _instance
end

--- Reset singleton (for testing)
function SSEHub.reset()
  _instance = nil
end

--- Open a new SSE session for a client connection
--- This is the canonical entry point for session creation.
---@param client userdata TCP client handle
---@param port number Server port
---@return string session_id
---@return table sse_conn The SSE connection object
function SSEHub:open_session(client, port)
  local session_id, sse_conn = self._manager:create_session(client, port)

  -- Track in http_server's sse_connections for backward compatibility
  if self._http_server then
    self._http_server.sse_connections[session_id] = sse_conn
  end

  -- Reverse map: client handle → session_id (for disconnect detection)
  self._client_to_session[client] = session_id

  log.debug("Hub: session opened: %s", session_id)
  return session_id, sse_conn
end

--- Close a session by session_id
--- Cleans up all mappings, closes the SSE connection, and emits session_disconnected.
---@param session_id string
function SSEHub:close_session(session_id)
  local conn = self._manager:get_session(session_id)

  -- Remove reverse mapping
  if conn and conn.client then
    self._client_to_session[conn.client] = nil
  end

  -- Remove from http_server tracking
  if self._http_server and self._http_server.sse_connections then
    self._http_server.sse_connections[session_id] = nil
  end

  -- This closes the connection and emits session_disconnected via _emit()
  self._manager:remove_session(session_id)

  -- Clean up downstream stores
  self:_cleanup_session_stores(session_id)

  log.debug("Hub: session closed: %s", session_id)
end

--- Close a session by TCP client handle (used on TCP disconnect)
---@param client userdata TCP client handle
function SSEHub:close_by_client(client)
  local session_id = self._client_to_session[client]
  if session_id then
    self:close_session(session_id)
  end
end

--- Clean up downstream session state stores
---@param session_id string
function SSEHub:_cleanup_session_stores(session_id)
  -- Session state (legacy)
  local ss_ok, session_state = pcall(require, "buddy.mcp.session_state")
  if ss_ok then
    session_state.cleanup(session_id)
  end

  -- Client requests (pending server→client requests)
  local cr_ok, client_requests = pcall(require, "buddy.app.client_requests")
  if cr_ok and client_requests.cleanup_session then
    client_requests.cleanup_session(session_id)
  end

  -- Runtime stores (if runtime exists)
  local ok, buddy = pcall(require, "buddy")
  if ok and buddy._runtime then
    -- Cancel any running tool tasks for this session before removing bindings
    local task_ids = buddy._runtime.request_store:get_tool_tasks_for_session(session_id)
    if #task_ids > 0 then
      local ts_ok, ToolService = pcall(require, "buddy.services.tool_service")
      if ts_ok then
        local service = ToolService.get_instance()
        if service then
          for _, task_id in ipairs(task_ids) do
            service:cancel(task_id)
            log.debug("Hub: cancelled task %s for disconnected session %s", task_id, session_id)
          end
        end
      end
    end

    buddy._runtime.session_store:cleanup(session_id)
    buddy._runtime.request_store:cleanup_by_session(session_id)
  end
end

--- Send a message to a specific session
---@param session_id string
---@param msg table JSON-RPC message
---@return boolean success
function SSEHub:send_to_session(session_id, msg)
  local conn = self._manager:get_session(session_id)
  if not conn then
    return false
  end
  return conn:send_data(msg)
end

--- Broadcast a message to multiple sessions or all active sessions
---@param msg table JSON-RPC message
---@param session_ids? string[] Specific sessions, or nil for all
function SSEHub:broadcast(msg, session_ids)
  local targets = session_ids

  -- If no specific sessions, broadcast to all known connections
  if not targets then
    targets = {}
    if self._http_server and self._http_server.sse_connections then
      for sid, _ in pairs(self._http_server.sse_connections) do
        table.insert(targets, sid)
      end
    end
  end

  local dead_sessions = {}
  for _, sid in ipairs(targets) do
    local ok = self:send_to_session(sid, msg)
    if not ok then
      log.warn("Dead SSE connection detected, closing session %s", sid)
      table.insert(dead_sessions, sid)
    end
  end

  -- Close dead sessions through the canonical path
  for _, sid in ipairs(dead_sessions) do
    self:close_session(sid)
  end
end

--- Get all active session IDs
---@return string[]
function SSEHub:get_session_ids()
  local ids = {}
  if self._http_server and self._http_server.sse_connections then
    for sid, _ in pairs(self._http_server.sse_connections) do
      table.insert(ids, sid)
    end
  end
  return ids
end

--- Get an SSE connection by session ID
---@param session_id string
---@return table|nil sse_conn The SSE connection, or nil if not found
function SSEHub:get_session(session_id)
  return self._manager:get_session(session_id)
end

--- Close all sessions (used during server shutdown)
function SSEHub:close_all()
  local session_ids = self:get_session_ids()
  for _, sid in ipairs(session_ids) do
    self:close_session(sid)
  end
end

return SSEHub
