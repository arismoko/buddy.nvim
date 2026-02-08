-- SSE Hub: Thin adapter over existing SSEManager
-- Provides transport-agnostic send interface for services

local log = require("buddy.log")

---@class SSEHub
---@field _manager table SSEManager instance
---@field _http_server table|nil Reference to http_server for connection tracking
local SSEHub = {}
SSEHub.__index = SSEHub

local _instance = nil

--- Get or create the singleton SSEHub
---@param http_server? table HTTP server instance (for connection tracking)
---@return SSEHub
function SSEHub.get_instance(http_server)
  if not _instance then
    local sse = require("buddy.server.sse")
    _instance = setmetatable({}, SSEHub)
    _instance._manager = sse.SSEManager.get_instance()
    _instance._http_server = http_server
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
      log.warn("Dead SSE connection detected, pruning session %s", sid)
      table.insert(dead_sessions, sid)
    end
  end

  -- Prune dead sessions
  if #dead_sessions > 0 then
    for _, sid in ipairs(dead_sessions) do
      self._manager:remove_session(sid)
      if self._http_server and self._http_server.sse_connections then
        self._http_server.sse_connections[sid] = nil
      end
    end
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

return SSEHub
