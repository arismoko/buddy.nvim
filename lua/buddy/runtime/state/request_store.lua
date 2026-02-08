--- Inflight request tracking for buddy.nvim runtime
---
--- Tracks in-progress requests (both client→server and server→client) with
--- session association for bulk cleanup on disconnect.

---@class RequestEntry
---@field key string Request identifier
---@field session_id string|nil Associated session
---@field status "pending"|"resolved"|"rejected" Current state
---@field meta table Caller-provided metadata (method, params, timestamps, etc.)
---@field result any|nil Resolution value (set on resolve)
---@field error any|nil Rejection reason (set on reject)
---@field started_at number Timestamp (vim.uv.hrtime)

---@class RequestStore
---@field _requests table<string, RequestEntry>
local RequestStore = {}
RequestStore.__index = RequestStore

--- Create a new RequestStore instance
---@return RequestStore
function RequestStore.new()
  local self = setmetatable({}, RequestStore)
  self._requests = {}
  return self
end

--- Start tracking a new inflight request
---
--- meta should include session_id for cleanup_by_session to work:
---   { session_id = "...", method = "...", ... }
---
---@param key string Unique request identifier
---@param meta table Request metadata (must include session_id for session cleanup)
function RequestStore:start(key, meta)
  self._requests[key] = {
    key = key,
    session_id = meta.session_id,
    status = "pending",
    meta = meta,
    result = nil,
    error = nil,
    started_at = vim.uv.hrtime(),
  }
end

--- Resolve a pending request with a result
---
---@param key string Request identifier
---@param result any Resolution value
---@return boolean success True if request was pending and is now resolved
function RequestStore:resolve(key, result)
  local entry = self._requests[key]
  if not entry or entry.status ~= "pending" then
    return false
  end
  entry.status = "resolved"
  entry.result = result
  return true
end

--- Reject a pending request with an error
---
---@param key string Request identifier
---@param err any Rejection reason
---@return boolean success True if request was pending and is now rejected
function RequestStore:reject(key, err)
  local entry = self._requests[key]
  if not entry or entry.status ~= "pending" then
    return false
  end
  entry.status = "rejected"
  entry.error = err
  return true
end

--- Get a request entry by key
---
---@param key string Request identifier
---@return RequestEntry|nil
function RequestStore:get(key)
  return self._requests[key]
end

--- Clean up all requests associated with a session
---
--- Removes all entries (pending, resolved, or rejected) whose meta.session_id
--- matches the given session_id. Pending requests are rejected before removal.
---
---@param session_id string Session identifier
function RequestStore:cleanup_by_session(session_id)
  local to_remove = {}
  for key, entry in pairs(self._requests) do
    if entry.session_id == session_id then
      -- Reject pending requests before removal
      if entry.status == "pending" then
        entry.status = "rejected"
        entry.error = "session_closed"
      end
      to_remove[#to_remove + 1] = key
    end
  end
  for _, key in ipairs(to_remove) do
    self._requests[key] = nil
  end
end

return RequestStore
