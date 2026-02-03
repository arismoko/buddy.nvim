-- Tests for MCP protocol layer
local T = MiniTest.new_set()

-- Fresh state for each test
T['hooks'] = {
  pre_case = function()
    -- Clear cached modules
    package.loaded['buddy.mcp'] = nil
    package.loaded['buddy.mcp.methods'] = nil
    package.loaded['buddy.tools'] = nil
    package.loaded['buddy.tools.executor'] = nil
  end
}

local function get_mcp()
  return require('buddy.mcp')
end

local function get_tools()
  return require('buddy.tools')
end

T['handle_request()'] = MiniTest.new_set()

T['handle_request()']['initialize returns server info'] = function()
  local mcp = get_mcp()
  local response = mcp.handle_request('session-1', {
    jsonrpc = '2.0',
    id = 1,
    method = 'initialize',
    params = {}
  })
  
  MiniTest.expect.equality(response.jsonrpc, '2.0')
  MiniTest.expect.equality(response.id, 1)
  MiniTest.expect.equality(response.result.serverInfo.name, 'buddy')
  MiniTest.expect.equality(response.result.protocolVersion, '2025-06-18')
end

T['handle_request()']['tools/list returns registered tools'] = function()
  local tools = get_tools()
  tools.clear()
  tools.register({
    name = 'my-tool',
    description = 'Does something',
    input_schema = { type = 'object' },
    run = function() return 'ok' end
  })
  
  local mcp = get_mcp()
  local response = mcp.handle_request('session-1', {
    jsonrpc = '2.0',
    id = 2,
    method = 'tools/list',
    params = {}
  })
  
  MiniTest.expect.equality(response.id, 2)
  MiniTest.expect.equality(#response.result.tools, 1)
  MiniTest.expect.equality(response.result.tools[1].name, 'my-tool')
  MiniTest.expect.equality(response.result.tools[1].description, 'Does something')
end

T['handle_request()']['tools/call executes tool and returns result'] = function()
  local tools = get_tools()
  tools.clear()
  tools.register({
    name = 'echo',
    description = 'Returns input',
    run = function(args) return 'Hello ' .. (args.name or 'world') end
  })
  
  local mcp = get_mcp()
  local response = mcp.handle_request('session-1', {
    jsonrpc = '2.0',
    id = 3,
    method = 'tools/call',
    params = { name = 'echo', arguments = { name = 'Claude' } }
  })
  
  MiniTest.expect.equality(response.id, 3)
  MiniTest.expect.equality(response.result.content[1].type, 'text')
  MiniTest.expect.equality(response.result.content[1].text, 'Hello Claude')
end

T['handle_request()']['returns error for unknown method'] = function()
  local mcp = get_mcp()
  local response = mcp.handle_request('session-1', {
    jsonrpc = '2.0',
    id = 4,
    method = 'unknown/method',
    params = {}
  })
  
  MiniTest.expect.equality(response.id, 4)
  MiniTest.expect.equality(response.error.code, -32601)
  MiniTest.expect.equality(response.result, nil)
end

T['handle_request()']['notifications/initialized returns nil'] = function()
  local mcp = get_mcp()
  local response = mcp.handle_request('session-1', {
    jsonrpc = '2.0',
    method = 'notifications/initialized',
    params = {}
  })
  
  MiniTest.expect.equality(response, nil)
end

-- JSON serialization tests - ensure MCP SDK compatibility
T['JSON serialization'] = MiniTest.new_set()

T['JSON serialization']['initialize capabilities.tools is object not array'] = function()
  local mcp = get_mcp()
  local response = mcp.handle_request('session-1', {
    jsonrpc = '2.0',
    id = 1,
    method = 'initialize',
    params = {}
  })
  
  -- Serialize to JSON and verify it's correctly formatted
  local json = vim.json.encode(response.result.capabilities.tools)
  MiniTest.expect.equality(json, '{"listChanged":true}')
end

T['JSON serialization']['tools/list inputSchema is object not array'] = function()
  local tools = get_tools()
  tools.clear()
  -- Register tool WITHOUT input_schema to test default
  tools.register({
    name = 'no-schema-tool',
    description = 'Tool without input_schema',
    run = function() return 'ok' end
  })
  
  local mcp = get_mcp()
  local response = mcp.handle_request('session-1', {
    jsonrpc = '2.0',
    id = 2,
    method = 'tools/list',
    params = {}
  })
  
  -- inputSchema must be an object with at least "type" field
  local schema = response.result.tools[1].inputSchema
  MiniTest.expect.equality(type(schema), 'table')
  MiniTest.expect.equality(schema.type, 'object')
  
  -- Verify JSON serialization is object not array
  local json = vim.json.encode(schema)
  MiniTest.expect.equality(json:sub(1, 1), '{')
end

T['JSON serialization']['tools/list with explicit schema preserves it'] = function()
  local tools = get_tools()
  tools.clear()
  tools.register({
    name = 'with-schema',
    description = 'Tool with explicit schema',
    input_schema = {
      type = 'object',
      properties = {
        name = { type = 'string' }
      },
      required = { 'name' }
    },
    run = function() return 'ok' end
  })
  
  local mcp = get_mcp()
  local response = mcp.handle_request('session-1', {
    jsonrpc = '2.0',
    id = 3,
    method = 'tools/list',
    params = {}
  })
  
  local schema = response.result.tools[1].inputSchema
  MiniTest.expect.equality(schema.type, 'object')
  MiniTest.expect.equality(schema.properties.name.type, 'string')
  MiniTest.expect.equality(schema.required[1], 'name')
end

return T
