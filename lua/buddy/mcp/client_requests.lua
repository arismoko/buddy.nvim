-- Client Requests: Server-to-client request/response handling
-- Enables sampling, elicitation, and roots requests

local M = {}

-- Pending requests keyed by request ID
local pending = {}
local next_id = 1

---@class PendingRequest
---@field resolve fun(result: any)
---@field reject fun(error: any)
---@field timer userdata|nil
---@field session_id string

--- Generate unique request ID
---@return string
local function generate_id()
  local id = "srv_" .. next_id
  next_id = next_id + 1
  return id
end

--- Send a request to client and return a promise-like table
---@param session_id string
---@param method string
---@param params table
---@param timeout_ms? number Default 30000
---@return any result
---@return string|nil error
function M.request(session_id, method, params, timeout_ms)
  timeout_ms = timeout_ms or 30000
  
  -- Get SSE connection for this session
  local sse = require("buddy.server.sse")
  local manager = sse.SSEManager.get_instance()
  local conn = manager:get_session(session_id)
  
  if not conn then
    return nil, "Session not found: " .. session_id
  end
  
  local id = generate_id()
  local result, err
  local done = false
  
  -- Create pending request entry
  pending[id] = {
    session_id = session_id,
    resolve = function(res)
      result = res
      done = true
    end,
    reject = function(e)
      err = e
      done = true
    end,
    timer = nil,
  }
  
  -- Set timeout
  pending[id].timer = vim.uv.new_timer()
  pending[id].timer:start(timeout_ms, 0, vim.schedule_wrap(function()
    if pending[id] then
      pending[id].reject({ code = -32000, message = "Request timeout" })
      M.cleanup(id)
    end
  end))
  
  -- Send request via SSE
  local request = {
    jsonrpc = "2.0",
    id = id,
    method = method,
    params = params or {},
  }
  
  local ok = conn:send_data(request)
  if not ok then
    M.cleanup(id)
    return nil, "Failed to send request"
  end
  
  -- Block until response or timeout
  vim.wait(timeout_ms + 100, function() return done end, 10)
  
  if not done then
    M.cleanup(id)
    return nil, "Request timeout"
  end
  
  return result, err
end

--- Resolve a pending request (called when client response arrives)
---@param id string Request ID
---@param result any
function M.resolve(id, result)
  local req = pending[id]
  if req then
    req.resolve(result)
    M.cleanup(id)
  end
end

--- Reject a pending request (called when client error arrives)
---@param id string Request ID  
---@param error any
function M.reject(id, error)
  local req = pending[id]
  if req then
    req.reject(error)
    M.cleanup(id)
  end
end

--- Check if a message is a response to a pending request
---@param msg table JSON-RPC message
---@return boolean
function M.is_response(msg)
  local log = require("buddy.log")
  local is_resp = msg.id and pending[msg.id] ~= nil
  if msg.id and not msg.method then
    log.debug("Checking response: id=%s, pending=%s, is_response=%s", 
      tostring(msg.id), pending[msg.id] and "yes" or "no", tostring(is_resp))
  end
  return is_resp
end

--- Handle a response message
---@param msg table JSON-RPC response
function M.handle_response(msg)
  if msg.error then
    M.reject(msg.id, msg.error)
  else
    M.resolve(msg.id, msg.result)
  end
end

--- Cleanup a pending request
---@param id string
function M.cleanup(id)
  local req = pending[id]
  if req then
    if req.timer then
      req.timer:stop()
      req.timer:close()
    end
    pending[id] = nil
  end
end

--- Send ping to client (server-initiated)
---@param session_id string
---@return table|nil result Empty object on success
---@return string|nil error
function M.ping(session_id)
  return M.request(session_id, "ping", {}, 5000)
end

--- Request workspace roots from client
---@param session_id string
---@return table|nil result { roots = { { uri, name? }... } }
---@return string|nil error
function M.roots_list(session_id)
  return M.request(session_id, "roots/list", {}, 10000)
end

--- Request LLM sampling from client
---@param session_id string
---@param params table { messages, modelPreferences?, systemPrompt?, ... }
---@return table|nil result { model, stopReason, role, content }
---@return string|nil error
function M.sampling_create_message(session_id, params)
  return M.request(session_id, "sampling/createMessage", params, 60000)
end

--- Request user elicitation from client
---@param session_id string
---@param params table { message, requestedSchema }
---@return table|nil result { action, content? }
---@return string|nil error
function M.elicitation_create(session_id, params)
  return M.request(session_id, "elicitation/create", params, 120000)
end

return M
