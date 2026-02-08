-- Transport-agnostic server→client request/response handling
-- Enables sampling, elicitation, and roots requests without SSE coupling

---@class ClientRequester
---@field _send_fn fun(session_id:string, msg:table):boolean
---@field _pending table<string, PendingServiceRequest>
---@field _next_id number
local ClientRequester = {}
ClientRequester.__index = ClientRequester

---@class PendingServiceRequest
---@field session_id string
---@field resolve fun(result: any)
---@field reject fun(error: any)
---@field timer userdata|nil

--- Create a new ClientRequester
---@param opts table { send_fn: fun(session_id:string, msg:table):boolean }
---@return ClientRequester
function ClientRequester.new(opts)
  assert(opts and opts.send_fn, "ClientRequester requires opts.send_fn")
  local self = setmetatable({}, ClientRequester)
  self._send_fn = opts.send_fn
  self._pending = {}
  self._next_id = 1
  return self
end

--- Generate unique request ID
---@return string
function ClientRequester:_generate_id()
  local id = "srv_" .. self._next_id
  self._next_id = self._next_id + 1
  return id
end

--- Send a synchronous request to client (blocks via vim.wait)
---@param session_id string
---@param method string
---@param params table
---@param timeout_ms? number Default 30000
---@return any result
---@return string|nil error
function ClientRequester:request_sync(session_id, method, params, timeout_ms)
  timeout_ms = timeout_ms or 30000

  local id = self:_generate_id()
  local result, err
  local done = false

  -- Create pending request entry
  self._pending[id] = {
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
  self._pending[id].timer = vim.uv.new_timer()
  self._pending[id].timer:start(timeout_ms, 0, vim.schedule_wrap(function()
    if self._pending[id] then
      self._pending[id].reject({ code = -32000, message = "Request timeout" })
      self:_cleanup(id)
    end
  end))

  -- Send request via injected transport
  local request = {
    jsonrpc = "2.0",
    id = id,
    method = method,
    params = params or {},
  }

  local ok = self._send_fn(session_id, request)
  if not ok then
    self:_cleanup(id)
    return nil, "Failed to send request"
  end

  -- Block until response or timeout
  vim.wait(timeout_ms + 100, function() return done end, 10)

  if not done then
    self:_cleanup(id)
    return nil, "Request timeout"
  end

  return result, err
end

--- Check if a message is a response to a pending request
---@param msg table JSON-RPC message
---@return boolean
function ClientRequester:is_response(msg)
  return msg.id ~= nil and self._pending[msg.id] ~= nil
end

--- Handle a response message from client
---@param msg table JSON-RPC response
function ClientRequester:handle_response(msg)
  if msg.error then
    self:_reject(msg.id, msg.error)
  else
    self:_resolve(msg.id, msg.result)
  end
end

--- Resolve a pending request
---@param id string Request ID
---@param result any
function ClientRequester:_resolve(id, result)
  local req = self._pending[id]
  if req then
    req.resolve(result)
    self:_cleanup(id)
  end
end

--- Reject a pending request
---@param id string Request ID
---@param error any
function ClientRequester:_reject(id, error)
  local req = self._pending[id]
  if req then
    req.reject(error)
    self:_cleanup(id)
  end
end

--- Cleanup a pending request
---@param id string
function ClientRequester:_cleanup(id)
  local req = self._pending[id]
  if req then
    if req.timer then
      req.timer:stop()
      req.timer:close()
    end
    self._pending[id] = nil
  end
end

--- Cleanup all pending requests for a session
---@param session_id string
function ClientRequester:cleanup_session(session_id)
  local to_cleanup = {}
  for id, req in pairs(self._pending) do
    if req.session_id == session_id then
      table.insert(to_cleanup, id)
    end
  end
  for _, id in ipairs(to_cleanup) do
    local req = self._pending[id]
    if req then
      req.reject({ code = -32000, message = "Session closed" })
    end
    self:_cleanup(id)
  end
end

return ClientRequester
