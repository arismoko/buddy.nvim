--- Per-session state store for buddy.nvim runtime
---
--- Manages session lifecycle data: client capabilities, client info,
--- resource subscriptions, and cached roots. This will eventually replace
--- the module-level singleton in mcp/session_state.lua.

---@class SessionEntry
---@field session_id string
---@field capabilities table Client capabilities from initialize
---@field client_info table Client info from initialize
---@field subscriptions table<string, boolean> URI -> true set
---@field cached_roots table|nil Cached workspace roots
---@field created_at number Timestamp (vim.uv.hrtime)

---@class SessionStore
---@field _sessions table<string, SessionEntry>
local SessionStore = {}
SessionStore.__index = SessionStore

--- Create a new SessionStore instance
---@return SessionStore
function SessionStore.new()
  local self = setmetatable({}, SessionStore)
  self._sessions = {}
  return self
end

--- Initialize a new session with params from the MCP initialize request
---
---@param session_id string Unique session identifier
---@param init_params table Initialize params from client (capabilities, clientInfo, etc.)
function SessionStore:init_session(session_id, init_params)
  self._sessions[session_id] = {
    session_id = session_id,
    capabilities = init_params.capabilities or {},
    client_info = init_params.clientInfo or {},
    subscriptions = {},
    cached_roots = nil,
    created_at = vim.uv.hrtime(),
  }
end

--- Get session state
---
---@param session_id string
---@return SessionEntry|nil
function SessionStore:get(session_id)
  return self._sessions[session_id]
end

--- Update session with a shallow patch
---
--- Merges top-level keys from patch into the session entry.
--- Does nothing if session does not exist.
---
---@param session_id string
---@param patch table Key-value pairs to merge into session
function SessionStore:update(session_id, patch)
  local session = self._sessions[session_id]
  if not session then
    return
  end
  for k, v in pairs(patch) do
    session[k] = v
  end
end

--- Clean up a session, removing all associated state
---
---@param session_id string
function SessionStore:cleanup(session_id)
  self._sessions[session_id] = nil
end

--- Add a resource subscription for a session
---
---@param session_id string
---@param uri string Resource URI to subscribe to
function SessionStore:add_subscription(session_id, uri)
  local session = self._sessions[session_id]
  if not session then
    return
  end
  session.subscriptions[uri] = true
end

--- Remove a resource subscription for a session
---
---@param session_id string
---@param uri string Resource URI to unsubscribe from
function SessionStore:remove_subscription(session_id, uri)
  local session = self._sessions[session_id]
  if not session then
    return
  end
  session.subscriptions[uri] = nil
end

--- Find all session IDs subscribed to a given URI
---
---@param uri string Resource URI
---@return string[] session_ids List of session IDs with active subscriptions
function SessionStore:subscribers_for_uri(uri)
  local result = {}
  for session_id, session in pairs(self._sessions) do
    if session.subscriptions[uri] then
      result[#result + 1] = session_id
    end
  end
  return result
end

return SessionStore
