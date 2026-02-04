local HTTPServer = require("buddy.server.http")
local router = require("buddy.server.router")

local M = {}

M._server = nil

--- Start the HTTP server
---@param host string|nil Host to bind to (default: "127.0.0.1")
---@param port number|nil Preferred port (default: 8080)
---@return number actual_port The port the server is actually listening on
function M.start(host, port)
  host = host or "127.0.0.1"
  port = port or 8080

  local server = HTTPServer.new(host, port)

  -- start() returns actual port (may differ if preferred was busy)
  local actual_port = server:start(router)

  M._server = server

  return actual_port
end

--- Get the current server instance
---@return table|nil server
function M.get()
  return M._server
end

return M
