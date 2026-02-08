local M = {}
local dispatcher = require("buddy.protocol.mcp.dispatcher")

function M.handle_request(session_id, request)
  return dispatcher.handle_request(session_id, request)
end

return M
