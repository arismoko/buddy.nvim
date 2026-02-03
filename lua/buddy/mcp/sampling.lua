-- Sampling: Request LLM completion from client

local M = {}

---@class SamplingRequest
---@field messages table[] Array of messages
---@field maxTokens? number
---@field temperature? number
---@field modelPreferences? table

--- Request LLM completion from client
---@param session_id string
---@param params SamplingRequest
---@return table|nil result { content: string, model: string, ... }
---@return string|nil error
function M.create_message(session_id, params)
  local session_state = require("buddy.mcp.session_state")
  local client_requests = require("buddy.mcp.client_requests")
  
  if not session_state.has_capability(session_id, "sampling") then
    return nil, "Client does not support sampling capability"
  end
  
  -- Default timeout of 60s for LLM requests
  local result, err = client_requests.request(session_id, "sampling/createMessage", params, 60000)
  if err then
    return nil, type(err) == "table" and err.message or tostring(err)
  end
  
  return result
end

return M
