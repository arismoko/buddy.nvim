-- Transport-agnostic server→client request/response handling
-- Enables sampling, elicitation, and roots requests without SSE coupling
-- Uses nvim-nio futures for non-blocking async request/response matching

local nio = require("buddy.dep.nio")

---@class ClientRequester
---@field _send_fn fun(session_id:string, msg:table):boolean
---@field _pending table<string, PendingServiceRequest>
---@field _next_id number
local ClientRequester = {}
ClientRequester.__index = ClientRequester

---@class PendingServiceRequest
---@field session_id string
---@field future table nio.control.future instance
---@field cancelled boolean

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

--- Sentinel returned by timeout branch of nio.first race
local _TIMEOUT = {}

--- Send a request to client and await response (async, must be called in nio coroutine)
---@param session_id string
---@param method string
---@param params table
---@param timeout_ms? number Default 30000
---@return any result
---@return string|table|nil error
function ClientRequester:request(session_id, method, params, timeout_ms)
  -- Guard: must be called inside a nio coroutine
  if not coroutine.running() then
    return nil, "request() must be called inside a nio coroutine; use request_sync() from non-async context"
  end

  timeout_ms = timeout_ms or 30000

  local id = self:_generate_id()
  local future = nio.control.future()

  -- Create pending request entry
  self._pending[id] = {
    session_id = session_id,
    future = future,
    cancelled = false,
  }

  -- Send request via injected transport (pcall to prevent leak on throw)
  local rpc_msg = {
    jsonrpc = "2.0",
    id = id,
    method = method,
    params = params or {},
  }

  local send_ok, send_result = pcall(self._send_fn, session_id, rpc_msg)
  if not send_ok then
    self:_cleanup(id)
    return nil, "Send failed: " .. tostring(send_result)
  end
  if not send_result then
    self:_cleanup(id)
    return nil, "Failed to send request"
  end

  -- Race: wait for response vs timeout (tagged return, no mutable flags)
  local result = nio.first({
    -- Branch 1: wait for the response future
    function()
      return future.wait()
    end,
    -- Branch 2: timeout — return sentinel to distinguish from nil response
    function()
      nio.sleep(timeout_ms)
      return _TIMEOUT
    end,
  })

  self:_cleanup(id)

  if result == _TIMEOUT then
    return nil, "Request timeout"
  end

  -- future.wait() returns packed response: {value=...} or {_is_error=true, error=...}
  if result and result._is_error then
    return nil, result.error
  end

  return result and result.value, nil
end

--- Send a synchronous request to client (blocks, works outside nio context)
--- Internally launches a nio coroutine and waits for completion.
---@param session_id string
---@param method string
---@param params table
---@param timeout_ms? number Default 30000
---@return any result
---@return string|table|nil error
function ClientRequester:request_sync(session_id, method, params, timeout_ms)
  timeout_ms = timeout_ms or 30000

  local result, err
  local done = false

  nio.run(function()
    result, err = self:request(session_id, method, params, timeout_ms)
  end, function(success, ...)
    if not success then
      err = tostring(...)
    end
    done = true
  end)

  -- Block the Neovim event loop until the nio task completes
  vim.wait(timeout_ms + 500, function()
    return done
  end, 10)

  if not done then
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
--- Resolves the future for the matching pending request
---@param msg table JSON-RPC response
function ClientRequester:handle_response(msg)
  local req = self._pending[msg.id]
  if not req then
    return
  end

  if req.future.is_set() then
    return
  end

  if msg.error then
    req.future.set({ _is_error = true, error = msg.error })
  else
    req.future.set({ value = msg.result })
  end
end

--- Cleanup a pending request
---@param id string
function ClientRequester:_cleanup(id)
  local req = self._pending[id]
  if req then
    req.cancelled = true
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
    if req and not req.future.is_set() then
      req.future.set({ _is_error = true, error = { code = -32000, message = "Session closed" } })
    end
    self:_cleanup(id)
  end
end

return ClientRequester
