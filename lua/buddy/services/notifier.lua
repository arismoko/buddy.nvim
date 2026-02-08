-- Transport-agnostic protocol notification delivery
-- Sends MCP notifications to connected clients without SSE coupling

---@class Notifier
---@field _send_fn fun(session_id:string, msg:table):boolean
---@field _broadcast_fn? fun(msg:table) Optional broadcast-to-all function
local Notifier = {}
Notifier.__index = Notifier

--- Create a new Notifier
---@param opts table { send_fn: fun(session_id:string, msg:table):boolean, broadcast_fn?: fun(msg:table) }
---@return Notifier
function Notifier.new(opts)
  assert(opts and opts.send_fn, "Notifier requires opts.send_fn")
  local self = setmetatable({}, Notifier)
  self._send_fn = opts.send_fn
  self._broadcast_fn = opts.broadcast_fn
  return self
end

--- Send a notification to a specific session
---@param session_id string
---@param method string
---@param params? table
---@return boolean success
function Notifier:notify(session_id, method, params)
  local message = {
    jsonrpc = "2.0",
    method = method,
  }
  if params then
    message.params = params
  end
  return self._send_fn(session_id, message)
end

--- Broadcast a notification to multiple sessions
--- When session_ids is nil, uses broadcast_fn if available (broadcasts to all connected sessions)
---@param method string
---@param params? table
---@param session_ids? string[] Specific sessions, or nil for all
function Notifier:broadcast(method, params, session_ids)
  local message = {
    jsonrpc = "2.0",
    method = method,
  }
  if params then
    message.params = params
  end

  -- If no specific sessions, use broadcast_fn for "all sessions" delivery
  if not session_ids then
    if self._broadcast_fn then
      self._broadcast_fn(message)
    end
    return
  end

  for _, session_id in ipairs(session_ids) do
    self._send_fn(session_id, message)
  end
end

return Notifier
