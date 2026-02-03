-- Session State: Track client capabilities per session

local M = {}

-- Session state keyed by session_id
local sessions = {}

---@class SessionState
---@field capabilities table Client capabilities from initialize
---@field client_info table Client info from initialize
---@field cached_roots table|nil Cached workspace roots for the session

--- Store session state from initialize request
---@param session_id string
---@param params table Initialize params from client
function M.initialize(session_id, params)
  sessions[session_id] = {
    capabilities = params.capabilities or {},
    client_info = params.clientInfo or {},
  }
end

--- Get session state
---@param session_id string
---@return SessionState|nil
function M.get(session_id)
  return sessions[session_id]
end

--- Check if client supports a capability
---@param session_id string
---@param capability string e.g., "sampling", "roots", "elicitation"
---@return boolean
function M.has_capability(session_id, capability)
  local state = sessions[session_id]
  if not state then return false end
  return state.capabilities[capability] ~= nil
end

--- Get specific capability config
---@param session_id string
---@param capability string
---@return table|nil
function M.get_capability(session_id, capability)
  local state = sessions[session_id]
  if not state then return nil end
  return state.capabilities[capability]
end

--- Clean up session
---@param session_id string
function M.cleanup(session_id)
  sessions[session_id] = nil
end

--- Cache roots for a session
---@param session_id string
---@param roots table
function M.cache_roots(session_id, roots)
  local state = sessions[session_id]
  if state then
    state.cached_roots = roots
  end
end

--- Get cached roots
---@param session_id string
---@return table|nil
function M.get_cached_roots(session_id)
  local state = sessions[session_id]
  return state and state.cached_roots
end

return M
