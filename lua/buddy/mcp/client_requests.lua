-- Client Requests: Compatibility wrapper delegating to services/client_requester
-- Preserves existing API for callers (roots.lua, sampling.lua, elicitation.lua)

local M = {}

-- Lazily initialized singleton requester backed by SSE transport
local _requester = nil

--- Get or create the singleton ClientRequester wired to SSE transport
---@return table ClientRequester instance
local function get_requester()
  if not _requester then
    local ClientRequester = require("buddy.services.client_requester")
    local SSEHub = require("buddy.transport.sse.hub")
    local hub = SSEHub.get_instance()

    _requester = ClientRequester.new({
      send_fn = function(session_id, msg)
        return hub:send_to_session(session_id, msg)
      end,
    })
  end
  return _requester
end

--- Send a request to client and wait for response
---@param session_id string
---@param method string
---@param params table
---@param timeout_ms? number Default 30000
---@return any result
---@return string|nil error
function M.request(session_id, method, params, timeout_ms)
  return get_requester():request_sync(session_id, method, params, timeout_ms)
end

--- Check if a message is a response to a pending request
---@param msg table JSON-RPC message
---@return boolean
function M.is_response(msg)
  if not _requester then
    return false
  end
  return _requester:is_response(msg)
end

--- Handle a response message
---@param msg table JSON-RPC response
function M.handle_response(msg)
  if _requester then
    _requester:handle_response(msg)
  end
end

--- Cleanup pending requests for a session
---@param session_id string
function M.cleanup_session(session_id)
  if _requester then
    _requester:cleanup_session(session_id)
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

--- Reset internal state (for testing)
function M._reset()
  _requester = nil
end

return M
