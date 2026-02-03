-- Roots: Request workspace roots from client

local M = {}

--- Request workspace roots from client
---@param session_id string
---@return table|nil roots Array of root URIs
---@return string|nil error
function M.list(session_id)
  local session_state = require("buddy.mcp.session_state")
  local client_requests = require("buddy.mcp.client_requests")
  
  if not session_state.has_capability(session_id, "roots") then
    return nil, "Client does not support roots capability"
  end
  
  local result, err = client_requests.request(session_id, "roots/list", {})
  if err then
    return nil, type(err) == "table" and err.message or tostring(err)
  end
  
  return result and result.roots or {}
end

return M
