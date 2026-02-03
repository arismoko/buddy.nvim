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

-- Start the HTTP server with a router
function HTTPServer:start(router)
  self.router = router

  -- Create TCP server
  self.server = uv.new_tcp()
  if not self.server then
    error("Failed to create TCP server")
  end

  -- Bind to address and port
  local host = self.host or "127.0.0.1"
  local bind_ok, err = self.server:bind(host, self.port)
  if not bind_ok then
    self.server:close()
    error(string.format("Failed to bind to %s:%d - %s", host, self.port, err))
  end

  -- Start listening - callback is invoked for each new connection
  local listen_ok, listen_err = self.server:listen(128, function(err2)
    if err2 then
      vim.schedule(function()
        vim.notify(string.format("[buddy] Listen error: %s", err2), vim.log.levels.ERROR)
      end)
      return
    end
    self:_accept()
  end)
  if not listen_ok then
    self.server:close()
    error(string.format("Failed to listen on port %d - %s", self.port, listen_err))
  end

  self.running = true
  print(string.format("HTTP server listening on http://%s:%d", host, self.port))
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

  -- Read data from client
  client:read_start(vim.schedule_wrap(function(err, chunk)
    if err then
      client:close()
      return
    end

    if not chunk then
      -- Connection closed
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

  -- Close all connections
  for _, client in ipairs(self.connections) do
    if not client:is_closing() then
      client:close()
    end
  end
  self.connections = {}

  -- Close SSE connections
  for _session_id, sse_conn in pairs(self.sse_connections) do
    sse_conn:close()
  end
  self.sse_connections = {}

  -- Close server
  if self.server and not self.server:is_closing() then
    self.server:close()
  end

  print("HTTP server stopped")
end

return HTTPServer
