--- HTTP/1.1 server built on libuv
--- Handles TCP connections, delegates parsing to transport/http/parser,
--- and dispatches requests to a router module.

local parser = require("buddy.transport.http.parser")

local uv = vim.uv

---@class HTTPServer
---@field host string
---@field port number
---@field server userdata|nil TCP server handle
---@field connections userdata[] Active TCP client handles
---@field sse_connections table<string, table> Session ID → SSE connection
---@field router table|nil Router module with handle(http_server, client, request, body)
---@field running boolean
local HTTPServer = {}
HTTPServer.__index = HTTPServer

--- Create a new HTTP server
---@param host string|nil Host to bind (default "127.0.0.1")
---@param port number|nil Preferred port
---@return HTTPServer
function HTTPServer.new(host, port)
  local self = setmetatable({}, HTTPServer)
  self.host = host or "127.0.0.1"
  self.port = port
  self.server = nil
  self.connections = {}
  self.sse_connections = {}
  self.router = nil
  self.running = false
  return self
end

--- Try to bind AND listen on a specific port
---@param host string
---@param port number
---@param listen_callback function
---@return boolean ok
---@return string|nil err
function HTTPServer:_try_port(host, port, listen_callback)
  local server = uv.new_tcp()
  if not server then
    return false, "Failed to create TCP server"
  end

  local bind_ok, bind_err = server:bind(host, port)
  if not bind_ok then
    server:close()
    return false, bind_err
  end

  local listen_ok, listen_err = server:listen(128, listen_callback)
  if not listen_ok then
    server:close()
    return false, listen_err
  end

  self.server = server
  return true
end

--- Check if error is a port-in-use error
---@param err string|nil
---@return boolean
local function _is_addr_in_use(err)
  return err and (err:match("EADDRINUSE") or err:match("address already in use")) ~= nil
end

--- Start the HTTP server with a router
--- Returns the actual port bound (may differ from self.port if fallback was used)
---@param router table Router module
---@return number actual_port
function HTTPServer:start(router)
  self.router = router

  local host = self.host or "127.0.0.1"
  local preferred_port = self.port
  local max_retries = 10

  local listen_callback = function(err)
    if err then
      vim.schedule(function()
        vim.notify(string.format("[buddy] Listen error: %s", err), vim.log.levels.ERROR)
      end)
      return
    end
    self:_accept()
  end

  -- Try preferred port first
  local ok, bind_err = self:_try_port(host, preferred_port, listen_callback)

  if ok then
    self.port = preferred_port
    self.running = true
    vim.schedule(function()
      vim.notify(string.format("[buddy] HTTP server listening on http://%s:%d", host, preferred_port), vim.log.levels.INFO)
    end)
    return preferred_port
  end

  -- Preferred port failed - try fallbacks if it's an address-in-use error
  if not _is_addr_in_use(bind_err) then
    error(string.format("Failed to start server on %s:%d - %s", host, preferred_port, bind_err or "unknown error"))
  end

  vim.schedule(function()
    vim.notify(
      string.format("[buddy] Port %d in use, finding available port...", preferred_port),
      vim.log.levels.INFO
    )
  end)

  -- Try alternative ports
  for i = 1, max_retries do
    local try_port = preferred_port + i
    if try_port > 7999 then
      try_port = 7235 + math.random(0, 764)
    end

    ok, bind_err = self:_try_port(host, try_port, listen_callback)
    if ok then
      self.port = try_port
      self.running = true
      vim.schedule(function()
        vim.notify(
          string.format("[buddy] Server started on http://%s:%d (port %d was busy)", host, try_port, preferred_port),
          vim.log.levels.INFO
        )
      end)
      return try_port
    end
  end

  error(string.format("Failed to find available port after %d attempts (last error: %s)", max_retries, bind_err or "unknown"))
end

--- Accept a new connection
function HTTPServer:_accept()
  if not self.running then
    return
  end

  local client = uv.new_tcp()
  if not client then
    return
  end

  local ok, _err = self.server:accept(client)
  if not ok then
    client:close()
    return
  end

  table.insert(self.connections, client)
  self:_handle_connection(client)
end

--- Handle an incoming TCP connection using the incremental parser
---@param client userdata TCP client handle
function HTTPServer:_handle_connection(client)
  local state = parser.new()

  local function remove_connection()
    for i, c in ipairs(self.connections) do
      if c == client then
        table.remove(self.connections, i)
        break
      end
    end
  end

  client:read_start(vim.schedule_wrap(function(err, chunk)
    if err then
      remove_connection()
      if not client:is_closing() then
        client:close()
      end
      return
    end

    if not chunk then
      -- Connection closed
      remove_connection()
      -- Notify hub of client disconnect
      local hub_ok, SSEHub = pcall(require, "buddy.transport.sse.hub")
      if hub_ok then
        local hub = SSEHub.get_instance()
        hub:close_by_client(client)
      end
      if not client:is_closing() then
        client:close()
      end
      return
    end

    -- Feed chunk to parser
    local request, body = parser.feed(state, chunk)

    if state.error then
      -- Parse error — close connection
      remove_connection()
      if not client:is_closing() then
        client:close()
      end
      return
    end

    if request then
      -- Complete request — dispatch to router
      self:_dispatch(client, request, body)
    end
    -- else: parser needs more data, keep reading
  end))
end

--- Dispatch request to router
---@param client userdata
---@param request table
---@param body string
function HTTPServer:_dispatch(client, request, body)
  if not self.router then
    self:send_response(client, 500, {}, "Internal server error: No router")
    client:close()
    return
  end

  self.router.handle(self, client, request, body)
end

--- Send HTTP response
---@param client userdata TCP client handle
---@param status number HTTP status code
---@param headers table<string, string> Response headers
---@param body string|nil Response body
function HTTPServer:send_response(client, status, headers, body)
  local status_text = ({
    [200] = "OK",
    [202] = "Accepted",
    [400] = "Bad Request",
    [401] = "Unauthorized",
    [404] = "Not Found",
    [500] = "Internal Server Error",
  })[status] or "OK"

  local response_headers = {}
  for key, value in pairs(headers) do
    response_headers[#response_headers + 1] = string.format("%s: %s", key, value)
  end

  if not headers["Content-Type"] then
    response_headers[#response_headers + 1] = "Content-Type: text/plain"
  end
  if not headers["Content-Length"] then
    response_headers[#response_headers + 1] = string.format("Content-Length: %d", #(body or ""))
  end
  response_headers[#response_headers + 1] = "Connection: close"

  local response = string.format(
    "HTTP/1.1 %d %s\r\n%s\r\n\r\n%s",
    status,
    status_text,
    table.concat(response_headers, "\r\n"),
    body or ""
  )

  client:write(response, function(_err)
    if not client:is_closing() then
      client:shutdown()
      client:close()
    end
  end)
end

--- Stop the server
function HTTPServer:stop()
  self.running = false

  -- Close all SSE sessions through Hub for deterministic cleanup
  local hub_ok, SSEHub = pcall(require, "buddy.transport.sse.hub")
  if hub_ok then
    local hub = SSEHub.get_instance()
    hub:close_all()
  end

  -- Close all TCP connections
  for _, client in ipairs(self.connections) do
    if not client:is_closing() then
      client:close()
    end
  end
  self.connections = {}
  self.sse_connections = {}

  -- Close server socket
  if self.server and not self.server:is_closing() then
    self.server:close()
  end

  vim.notify("[buddy] HTTP server stopped", vim.log.levels.INFO)
end

return HTTPServer
