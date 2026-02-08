local uv = vim.uv

local HTTPServer = {}
HTTPServer.__index = HTTPServer

-- Create a new HTTP server
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

-- Try to bind AND listen on a specific port
-- Returns true on success, or false + error message on failure
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

  -- Success - store the server
  self.server = server
  return true
end

-- Check if error is a port-in-use error
local function is_addr_in_use(err)
  return err and (err:match("EADDRINUSE") or err:match("address already in use"))
end

-- Start the HTTP server with a router
-- Returns the actual port bound (may differ from self.port if fallback was used)
function HTTPServer:start(router)
  self.router = router

  local host = self.host or "127.0.0.1"
  local preferred_port = self.port
  local max_retries = 10

  -- Create the listen callback
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
  local ok, err = self:_try_port(host, preferred_port, listen_callback)

  if ok then
    self.port = preferred_port
    self.running = true
    vim.schedule(function()
      vim.notify(string.format("[buddy] HTTP server listening on http://%s:%d", host, preferred_port), vim.log.levels.INFO)
    end)
    return preferred_port
  end

  -- Preferred port failed - try fallbacks if it's an address-in-use error
  if not is_addr_in_use(err) then
    error(string.format("Failed to start server on %s:%d - %s", host, preferred_port, err or "unknown error"))
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

    ok, err = self:_try_port(host, try_port, listen_callback)
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

  error(string.format("Failed to find available port after %d attempts (last error: %s)", max_retries, err or "unknown"))
end

-- Accept a new connection (called by listen callback for each connection)
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

  -- Track connection
  table.insert(self.connections, client)

  -- Handle connection
  self:_handle_connection(client)
end

-- Handle an incoming connection
function HTTPServer:_handle_connection(client)
  local buffer = ""
  local headers_complete = false
  local content_length = 0
  local request = {
    method = nil,
    path = nil,
    headers = {},
    version = "1.1",
  }

  local function remove_connection()
    for i, c in ipairs(self.connections) do
      if c == client then
        table.remove(self.connections, i)
        break
      end
    end
  end

  -- Read data from client
  client:read_start(vim.schedule_wrap(function(err, chunk)
    if err then
      remove_connection()
      if not client:is_closing() then
        client:close()
      end
      return
    end

    if not chunk then
      -- Connection closed - remove from tracking
      remove_connection()
      -- Notify hub of client disconnect (cleans up SSE session if this was one)
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

    buffer = buffer .. chunk

    -- Check if headers are complete
    if not headers_complete then
      local header_end = buffer:find("\r\n\r\n")
      if header_end then
        -- Parse headers
        local header_data = buffer:sub(1, header_end - 1)
        local body_start = header_end + 4

        -- Parse request line
        local request_line_end = header_data:find("\r\n")
        local request_line = header_data:sub(1, request_line_end - 1)
        local parts = {}
        for part in request_line:gmatch("%S+") do
          table.insert(parts, part)
        end

        if #parts >= 2 then
          request.method = parts[1]
          request.path = parts[2]
          if parts[3] then
            request.version = parts[3]:sub(string.find(parts[3], "%d+%.%d+") or 1)
          end
        end

        -- Parse headers
        local remaining_headers = header_data:sub(request_line_end + 2)
        for line in remaining_headers:gmatch("[^\r\n]+") do
          local key, value = line:match("^([^:]+):%s*(.*)")
          if key and value then
            request.headers[key:lower()] = value
            if key:lower() == "content-length" then
              content_length = tonumber(value) or 0
            end
          end
        end

        headers_complete = true
        buffer = buffer:sub(body_start)

        -- Check if we have the full body
        if #buffer >= content_length then
          local body = buffer:sub(1, content_length)
          self:_dispatch(client, request, body)
        end
      end
    else
      -- Headers already parsed, check for body
      if #buffer >= content_length then
        local body = buffer:sub(1, content_length)
        self:_dispatch(client, request, body)
      end
    end
  end))
end

-- Dispatch request to router
function HTTPServer:_dispatch(client, request, body)
  if not self.router then
    self:send_response(client, 500, {}, "Internal server error: No router")
    client:close()
    return
  end

  -- Call router
  self.router.handle(self, client, request, body)
end

-- Send HTTP response and close connection
function HTTPServer:send_response(client, status, headers, body)
  local status_text = ({
    [200] = "OK",
    [202] = "Accepted",
    [400] = "Bad Request",
    [401] = "Unauthorized",
    [404] = "Not Found",
    [500] = "Internal Server Error",
  })[status] or "OK"

  -- Build headers
  local response_headers = {}
  for key, value in pairs(headers) do
    table.insert(response_headers, string.format("%s: %s", key, value))
  end

  -- Add default headers if not present
  local has_content_type = headers["Content-Type"] ~= nil
  local has_content_length = headers["Content-Length"] ~= nil

  if not has_content_type then
    table.insert(response_headers, "Content-Type: text/plain")
  end
  if not has_content_length then
    table.insert(response_headers, string.format("Content-Length: %d", #(body or "")))
  end
  table.insert(response_headers, "Connection: close")

  -- Build response
  local response = string.format(
    "HTTP/1.1 %d %s\r\n%s\r\n\r\n%s",
    status,
    status_text,
    table.concat(response_headers, "\r\n"),
    body or ""
  )

  -- Write and close in callback
  client:write(response, function(_err)
    if not client:is_closing() then
      client:shutdown()
      client:close()
    end
  end)
end

-- Stop the server
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

  -- Clear any remaining SSE connection refs (hub:close_all should handle these)
  self.sse_connections = {}

  -- Close server socket
  if self.server and not self.server:is_closing() then
    self.server:close()
  end

  vim.notify("[buddy] HTTP server stopped", vim.log.levels.INFO)
end

return HTTPServer
