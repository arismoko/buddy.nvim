local uv = vim.uv

local SSEConnection = {}
SSEConnection.__index = SSEConnection

function SSEConnection.new(client, session_id)
  local self = setmetatable({}, SSEConnection)
  self.client = client
  self.session_id = session_id
  self.closed = false

  -- Send SSE headers
  self:_send_headers()

  return self
end

function SSEConnection:_send_headers()
  local headers = {
    "Content-Type: text/event-stream",
    "Cache-Control: no-cache",
    "Connection: keep-alive",
    "X-Accel-Buffering: no",
  }

  local response = "HTTP/1.1 200 OK\r\n" .. table.concat(headers, "\r\n") .. "\r\n\r\n"

  self.client:write(response, vim.schedule_wrap(function(err)
    if err then
      error(string.format("SSE header write error: %s", err))
    end
  end))
end

-- Send unnamed event (required for MCP SDK's EventSource.onmessage)
function SSEConnection:send_data(data)
  if self.closed or self.client:is_closing() then
    return false
  end

  local data_json = vim.json.encode(data)
  local event = string.format("data: %s\n\n", data_json)

  self.client:write(event, vim.schedule_wrap(function(err)
    if err then
      error(string.format("SSE data write error: %s", err))
    end
  end))

  return true
end

function SSEConnection:send_raw_event(event_type, data)
  if self.closed or self.client:is_closing() then
    return false
  end

  local event = string.format("event: %s\ndata: %s\n\n", event_type, data)

  self.client:write(event, vim.schedule_wrap(function(err)
    if err then
      error(string.format("SSE event write error: %s", err))
    end
  end))

  return true
end

function SSEConnection:close()
  if self.closed then
    return
  end

  self.closed = true

  if self.client and not self.client:is_closing() then
    self.client:close()
  end
end

local SSEManager = {}
SSEManager.__index = SSEManager

local instance = nil

function SSEManager.get_instance()
  if not instance then
    instance = setmetatable({}, SSEManager)
    instance.sessions = {}
  end
  return instance
end

function SSEManager:create_session(client, port)
  local session_id = tostring(uv.hrtime())
  local sse_conn = SSEConnection.new(client, session_id)
  self.sessions[session_id] = sse_conn

  local host = "127.0.0.1"
  port = port or 7234
  local endpoint_url = string.format("http://%s:%d/message?sessionId=%s", host, port, session_id)

  sse_conn:send_raw_event("endpoint", endpoint_url)

  return session_id, sse_conn
end

function SSEManager:get_session(session_id)
  return self.sessions[session_id]
end

return {
  SSEConnection = SSEConnection,
  SSEManager = SSEManager,
}
