local HTTPServer = require("buddy.server.http")
local router = require("buddy.server.router")

local M = {}

function M.start(host, port)
  host = host or "127.0.0.1"
  port = port or 8080

  local server = HTTPServer.new(host, port)

  server:start(router)

  return server
end

return M
