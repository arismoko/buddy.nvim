-- Elicitation: Request user input from client

local M = {}

---@class ElicitationRequest
---@field message string Prompt message to show user
---@field requestedSchema? table JSON Schema for expected input

--- Request user input from client
---@param session_id string
---@param params ElicitationRequest
---@return table|nil result User's input
---@return string|nil error
function M.create(session_id, params)
  local session_state = require("buddy.mcp.session_state")
  local client_requests = require("buddy.app.client_requests")
  
  if not session_state.has_capability(session_id, "elicitation") then
    return nil, "Client does not support elicitation capability"
  end
  
  local result, err = client_requests.request(session_id, "elicitation/create", params)
  if err then
    return nil, type(err) == "table" and err.message or tostring(err)
  end
  
  return result
end

return M
