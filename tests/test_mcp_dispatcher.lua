-- Tests for protocol/mcp/dispatcher.lua
local T = MiniTest.new_set()

-- Fresh state for each test
T['hooks'] = {
  pre_case = function()
    -- Clear cached modules for clean state
    package.loaded['buddy.mcp'] = nil
    package.loaded['buddy.protocol.mcp.dispatcher'] = nil
    package.loaded['buddy.protocol.mcp.registry'] = nil
    package.loaded['buddy.protocol.jsonrpc'] = nil
    package.loaded['buddy.protocol.mcp.handlers.core'] = nil
    package.loaded['buddy.protocol.mcp.handlers.tools'] = nil
    package.loaded['buddy.protocol.mcp.handlers.resources'] = nil
    package.loaded['buddy.protocol.mcp.handlers.prompts'] = nil
    package.loaded['buddy.protocol.mcp.handlers.completion'] = nil
    package.loaded['buddy.protocol.mcp.handlers.notifications'] = nil
    package.loaded['buddy.tools'] = nil
    package.loaded['buddy.tools.executor'] = nil
  end,
}

local function get_dispatcher()
  return require('buddy.protocol.mcp.dispatcher')
end

-- === JSON-RPC validation ===

T['handle_request()'] = MiniTest.new_set()

T['handle_request()']['rejects non-table request'] = function()
  local dispatcher = get_dispatcher()
  -- Non-table with an id can't produce a response (no id to reference)
  local response = dispatcher.handle_request('s1', 'not a table')
  MiniTest.expect.equality(response, nil)
end

T['handle_request()']['rejects missing jsonrpc version'] = function()
  local dispatcher = get_dispatcher()
  local response = dispatcher.handle_request('s1', { id = 1, method = 'ping' })
  MiniTest.expect.equality(response.error.code, -32600)
  MiniTest.expect.equality(response.id, 1)
end

T['handle_request()']['rejects missing method field'] = function()
  local dispatcher = get_dispatcher()
  local response = dispatcher.handle_request('s1', { jsonrpc = '2.0', id = 1 })
  MiniTest.expect.equality(response.error.code, -32600)
end

T['handle_request()']['returns -32601 for unknown method'] = function()
  local dispatcher = get_dispatcher()
  local response = dispatcher.handle_request('s1', {
    jsonrpc = '2.0',
    id = 1,
    method = 'nonexistent/method',
  })
  MiniTest.expect.equality(response.error.code, -32601)
  MiniTest.expect.equality(response.id, 1)
end

T['handle_request()']['returns nil for unknown notification'] = function()
  local dispatcher = get_dispatcher()
  local response = dispatcher.handle_request('s1', {
    jsonrpc = '2.0',
    method = 'nonexistent/notification',
  })
  MiniTest.expect.equality(response, nil)
end

-- === Handler dispatch ===

T['handle_request()']['dispatches ping and returns empty result'] = function()
  local dispatcher = get_dispatcher()
  local response = dispatcher.handle_request('s1', {
    jsonrpc = '2.0',
    id = 1,
    method = 'ping',
  })
  MiniTest.expect.equality(response.jsonrpc, '2.0')
  MiniTest.expect.equality(response.id, 1)
  -- ping returns vim.empty_dict() which is a table
  MiniTest.expect.equality(type(response.result), 'table')
end

T['handle_request()']['dispatches initialize with correct protocol version'] = function()
  local dispatcher = get_dispatcher()
  local response = dispatcher.handle_request('s1', {
    jsonrpc = '2.0',
    id = 1,
    method = 'initialize',
    params = {},
  })
  MiniTest.expect.equality(response.result.protocolVersion, '2025-06-18')
  MiniTest.expect.equality(response.result.serverInfo.name, 'buddy')
end

T['handle_request()']['notifications/initialized returns nil'] = function()
  local dispatcher = get_dispatcher()
  local response = dispatcher.handle_request('s1', {
    jsonrpc = '2.0',
    method = 'notifications/initialized',
    params = {},
  })
  MiniTest.expect.equality(response, nil)
end

T['handle_request()']['wraps handler errors in -32603'] = function()
  local dispatcher = get_dispatcher()
  -- tools/call with no params will error("Missing required parameter: name")
  local response = dispatcher.handle_request('s1', {
    jsonrpc = '2.0',
    id = 5,
    method = 'tools/call',
    params = {},
  })
  MiniTest.expect.equality(response.error.code, -32603)
  MiniTest.expect.equality(response.id, 5)
end

T['handle_request()']['notification handler error returns nil'] = function()
  -- Register a handler that errors for testing
  local registry = require('buddy.protocol.mcp.registry')
  registry.register('notifications/test_error', function()
    error('boom')
  end)

  local dispatcher = get_dispatcher()
  local response = dispatcher.handle_request('s1', {
    jsonrpc = '2.0',
    method = 'notifications/test_error',
  })
  MiniTest.expect.equality(response, nil)
end

T['handle_request()']['mcp.handle_request delegates to dispatcher'] = function()
  local mcp = require('buddy.mcp')
  local response = mcp.handle_request('s1', {
    jsonrpc = '2.0',
    id = 1,
    method = 'ping',
  })
  MiniTest.expect.equality(response.jsonrpc, '2.0')
  MiniTest.expect.equality(response.id, 1)
end

return T
