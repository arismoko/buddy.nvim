-- Tests for SSE Hub lifecycle management
local T = MiniTest.new_set()

T['hooks'] = {
  pre_case = function()
    package.loaded['buddy.transport.sse.hub'] = nil
    package.loaded['buddy.server.sse'] = nil
    package.loaded['buddy.mcp.session_state'] = nil
    package.loaded['buddy.mcp.client_requests'] = nil
    package.loaded['buddy'] = nil
  end,
}

-- Mock SSEManager for unit testing without real TCP connections
local function mock_sse_manager()
  local sessions = {}
  local manager = {}

  function manager:create_session(client, port)
    local session_id = 'test-session-' .. tostring(port) .. '-' .. tostring(#vim.tbl_keys(sessions) + 1)
    local conn = {
      client = client,
      session_id = session_id,
      closed = false,
      sent = {},
      send_data = function(self_conn, data)
        if self_conn.closed then return false end
        table.insert(self_conn.sent, data)
        return true
      end,
      close = function(self_conn)
        self_conn.closed = true
      end,
    }
    sessions[session_id] = conn
    return session_id, conn
  end

  function manager:get_session(session_id)
    return sessions[session_id]
  end

  function manager:remove_session(session_id)
    local conn = sessions[session_id]
    if conn then
      conn:close()
      sessions[session_id] = nil
    end
  end

  return manager, sessions
end

-- Mock HTTP server
local function mock_http_server()
  return {
    sse_connections = {},
    port = 7234,
  }
end

-- Mock TCP client
local function mock_client(id)
  return {
    _id = id or 'client-1',
    _closing = false,
    is_closing = function(self) return self._closing end,
    close = function(self) self._closing = true end,
  }
end

T['SSEHub'] = MiniTest.new_set()

T['SSEHub']['open_session creates session and tracks it'] = function()
  local manager = mock_sse_manager()
  -- Inject mock manager
  package.loaded['buddy.server.sse'] = { SSEManager = { get_instance = function() return manager end } }

  local SSEHub = require('buddy.transport.sse.hub')
  SSEHub.reset()

  local http_server = mock_http_server()
  local hub = SSEHub.get_instance(http_server)
  local client = mock_client()

  local session_id, conn = hub:open_session(client, 7234)
  MiniTest.expect.no_equality(session_id, nil)
  MiniTest.expect.no_equality(conn, nil)

  -- Should be tracked in http_server
  MiniTest.expect.no_equality(http_server.sse_connections[session_id], nil)
end

T['SSEHub']['close_session removes all mappings'] = function()
  local manager = mock_sse_manager()
  package.loaded['buddy.server.sse'] = { SSEManager = { get_instance = function() return manager end } }

  local SSEHub = require('buddy.transport.sse.hub')
  SSEHub.reset()

  local http_server = mock_http_server()
  local hub = SSEHub.get_instance(http_server)
  local client = mock_client()

  local session_id, _ = hub:open_session(client, 7234)

  -- Verify tracked
  MiniTest.expect.no_equality(http_server.sse_connections[session_id], nil)

  -- Close
  hub:close_session(session_id)

  -- Verify cleaned
  MiniTest.expect.equality(http_server.sse_connections[session_id], nil)
  MiniTest.expect.equality(manager:get_session(session_id), nil)
end

T['SSEHub']['close_by_client finds and closes session'] = function()
  local manager = mock_sse_manager()
  package.loaded['buddy.server.sse'] = { SSEManager = { get_instance = function() return manager end } }

  local SSEHub = require('buddy.transport.sse.hub')
  SSEHub.reset()

  local http_server = mock_http_server()
  local hub = SSEHub.get_instance(http_server)
  local client = mock_client()

  local session_id, _ = hub:open_session(client, 7234)

  -- Close by client handle
  hub:close_by_client(client)

  -- Session should be gone
  MiniTest.expect.equality(http_server.sse_connections[session_id], nil)
  MiniTest.expect.equality(manager:get_session(session_id), nil)
end

T['SSEHub']['close_by_client is safe for unknown clients'] = function()
  local manager = mock_sse_manager()
  package.loaded['buddy.server.sse'] = { SSEManager = { get_instance = function() return manager end } }

  local SSEHub = require('buddy.transport.sse.hub')
  SSEHub.reset()

  local hub = SSEHub.get_instance(mock_http_server())
  local unknown_client = mock_client('unknown')

  -- Should not error
  hub:close_by_client(unknown_client)
end

T['SSEHub']['close_all closes all sessions'] = function()
  local manager = mock_sse_manager()
  package.loaded['buddy.server.sse'] = { SSEManager = { get_instance = function() return manager end } }

  local SSEHub = require('buddy.transport.sse.hub')
  SSEHub.reset()

  local http_server = mock_http_server()
  local hub = SSEHub.get_instance(http_server)

  hub:open_session(mock_client('c1'), 7234)
  hub:open_session(mock_client('c2'), 7234)

  MiniTest.expect.equality(vim.tbl_count(http_server.sse_connections), 2)

  hub:close_all()

  MiniTest.expect.equality(vim.tbl_count(http_server.sse_connections), 0)
end

T['SSEHub']['send_to_session delivers message'] = function()
  local manager = mock_sse_manager()
  package.loaded['buddy.server.sse'] = { SSEManager = { get_instance = function() return manager end } }

  local SSEHub = require('buddy.transport.sse.hub')
  SSEHub.reset()

  local hub = SSEHub.get_instance(mock_http_server())
  local session_id, conn = hub:open_session(mock_client(), 7234)

  local msg = { jsonrpc = '2.0', method = 'test' }
  local ok = hub:send_to_session(session_id, msg)
  MiniTest.expect.equality(ok, true)
  MiniTest.expect.equality(#conn.sent, 1)
  MiniTest.expect.equality(conn.sent[1].method, 'test')
end

T['SSEHub']['send_to_session returns false for unknown session'] = function()
  local manager = mock_sse_manager()
  package.loaded['buddy.server.sse'] = { SSEManager = { get_instance = function() return manager end } }

  local SSEHub = require('buddy.transport.sse.hub')
  SSEHub.reset()

  local hub = SSEHub.get_instance(mock_http_server())
  local ok = hub:send_to_session('nonexistent', { method = 'test' })
  MiniTest.expect.equality(ok, false)
end

T['SSEHub']['broadcast sends to all sessions'] = function()
  local manager = mock_sse_manager()
  package.loaded['buddy.server.sse'] = { SSEManager = { get_instance = function() return manager end } }

  local SSEHub = require('buddy.transport.sse.hub')
  SSEHub.reset()

  local http_server = mock_http_server()
  local hub = SSEHub.get_instance(http_server)

  local _, conn1 = hub:open_session(mock_client('c1'), 7234)
  local _, conn2 = hub:open_session(mock_client('c2'), 7234)

  hub:broadcast({ jsonrpc = '2.0', method = 'notify' })

  MiniTest.expect.equality(#conn1.sent, 1)
  MiniTest.expect.equality(#conn2.sent, 1)
end

T['SSEHub']['get_session_ids returns all active IDs'] = function()
  local manager = mock_sse_manager()
  package.loaded['buddy.server.sse'] = { SSEManager = { get_instance = function() return manager end } }

  local SSEHub = require('buddy.transport.sse.hub')
  SSEHub.reset()

  local http_server = mock_http_server()
  local hub = SSEHub.get_instance(http_server)

  hub:open_session(mock_client('c1'), 7234)
  hub:open_session(mock_client('c2'), 7234)

  local ids = hub:get_session_ids()
  MiniTest.expect.equality(#ids, 2)
end

T['SSEHub']['cleans up session_state on close'] = function()
  local manager = mock_sse_manager()
  package.loaded['buddy.server.sse'] = { SSEManager = { get_instance = function() return manager end } }

  local session_state = require('buddy.mcp.session_state')
  session_state.initialize('test-sid', { capabilities = {}, clientInfo = {} })
  MiniTest.expect.no_equality(session_state.get('test-sid'), nil)

  -- Manually insert session into manager so Hub can find it
  local client = mock_client()
  manager:create_session(client, 7234)

  -- Now create Hub and test
  local SSEHub = require('buddy.transport.sse.hub')
  SSEHub.reset()
  local http_server = mock_http_server()
  local hub = SSEHub.get_instance(http_server)

  local session_id, _ = hub:open_session(mock_client('c2'), 7234)

  -- Manually initialize session_state for this session
  session_state.initialize(session_id, { capabilities = {}, clientInfo = {} })
  MiniTest.expect.no_equality(session_state.get(session_id), nil)

  hub:close_session(session_id)
  MiniTest.expect.equality(session_state.get(session_id), nil)
end

return T
