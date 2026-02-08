-- Tests for protocol/mcp/handlers/tools.lua
local T = MiniTest.new_set()

T['hooks'] = {
  pre_case = function()
    package.loaded['buddy.mcp'] = nil
    package.loaded['buddy.mcp.methods'] = nil
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

local function mcp_request(session_id, id, method, params)
  local dispatcher = require('buddy.protocol.mcp.dispatcher')
  return dispatcher.handle_request(session_id, {
    jsonrpc = '2.0',
    id = id,
    method = method,
    params = params or {},
  })
end

T['tools/list'] = MiniTest.new_set()

T['tools/list']['returns registered tools'] = function()
  local tools = require('buddy.tools')
  tools.clear()
  tools.register({
    name = 'test-tool',
    description = 'A test tool',
    input_schema = { type = 'object' },
    run = function() return 'ok' end,
  })

  local response = mcp_request('s1', 1, 'tools/list')
  MiniTest.expect.equality(response.id, 1)
  MiniTest.expect.equality(#response.result.tools, 1)
  MiniTest.expect.equality(response.result.tools[1].name, 'test-tool')
  MiniTest.expect.equality(response.result.tools[1].description, 'A test tool')
end

T['tools/list']['returns empty list when no tools registered'] = function()
  local tools = require('buddy.tools')
  tools.clear()

  local response = mcp_request('s1', 1, 'tools/list')
  MiniTest.expect.equality(#response.result.tools, 0)
end

T['tools/list']['provides default inputSchema when tool has none'] = function()
  local tools = require('buddy.tools')
  tools.clear()
  tools.register({
    name = 'no-schema',
    description = 'No schema',
    run = function() return 'ok' end,
  })

  local response = mcp_request('s1', 1, 'tools/list')
  local schema = response.result.tools[1].inputSchema
  MiniTest.expect.equality(schema.type, 'object')
  -- properties should serialize as object not array
  local json = vim.json.encode(schema)
  MiniTest.expect.equality(json:sub(1, 1), '{')
end

T['tools/list']['preserves explicit inputSchema'] = function()
  local tools = require('buddy.tools')
  tools.clear()
  tools.register({
    name = 'with-schema',
    description = 'Has schema',
    input_schema = {
      type = 'object',
      properties = { name = { type = 'string' } },
      required = { 'name' },
    },
    run = function() return 'ok' end,
  })

  local response = mcp_request('s1', 1, 'tools/list')
  local schema = response.result.tools[1].inputSchema
  MiniTest.expect.equality(schema.properties.name.type, 'string')
  MiniTest.expect.equality(schema.required[1], 'name')
end

T['tools/list']['includes optional fields when present'] = function()
  local tools = require('buddy.tools')
  tools.clear()
  tools.register({
    name = 'full-tool',
    description = 'Full tool',
    title = 'Full Tool Title',
    annotations = { readOnly = true },
    output_schema = { type = 'object' },
    run = function() return {} end,
  })

  local response = mcp_request('s1', 1, 'tools/list')
  local tool = response.result.tools[1]
  MiniTest.expect.equality(tool.title, 'Full Tool Title')
  MiniTest.expect.equality(tool.annotations.readOnly, true)
  MiniTest.expect.equality(tool.outputSchema.type, 'object')
end

T['tools/call'] = MiniTest.new_set()

T['tools/call']['executes tool and returns text content'] = function()
  local tools = require('buddy.tools')
  tools.clear()
  tools.register({
    name = 'echo',
    description = 'Returns input',
    run = function(args) return 'Hello ' .. (args.name or 'world') end,
  })

  local response = mcp_request('s1', 2, 'tools/call', { name = 'echo', arguments = { name = 'Claude' } })
  MiniTest.expect.equality(response.id, 2)
  MiniTest.expect.equality(response.result.content[1].type, 'text')
  MiniTest.expect.equality(response.result.content[1].text, 'Hello Claude')
end

T['tools/call']['errors on missing tool name'] = function()
  local response = mcp_request('s1', 3, 'tools/call', {})
  MiniTest.expect.equality(response.error.code, -32603)
end

T['tools/call']['errors on unknown tool'] = function()
  local tools = require('buddy.tools')
  tools.clear()
  local response = mcp_request('s1', 4, 'tools/call', { name = 'nonexistent' })
  MiniTest.expect.equality(response.error.code, -32603)
end

T['tools/call']['returns JSON-encoded table results'] = function()
  local tools = require('buddy.tools')
  tools.clear()
  tools.register({
    name = 'json-tool',
    description = 'Returns table',
    run = function() return { key = 'value' } end,
  })

  local response = mcp_request('s1', 5, 'tools/call', { name = 'json-tool' })
  local text = response.result.content[1].text
  local decoded = vim.json.decode(text)
  MiniTest.expect.equality(decoded.key, 'value')
end

T['tools/call']['includes structuredContent for tools with output_schema'] = function()
  local tools = require('buddy.tools')
  tools.clear()
  tools.register({
    name = 'structured',
    description = 'Structured output',
    output_schema = { type = 'object' },
    run = function() return { data = 'test' } end,
  })

  local response = mcp_request('s1', 6, 'tools/call', { name = 'structured' })
  MiniTest.expect.equality(response.result.structuredContent.data, 'test')
end

T['tools/call']['rejects async tool with isError response'] = function()
  local tools = require('buddy.tools')
  local executor = require('buddy.tools.executor')
  executor._reset()
  tools.clear()
  tools.register({
    name = 'async-tool',
    description = 'Async tool',
    run = function(_, _context)
      return function() end  -- cancel fn = async
    end,
  })

  local response = mcp_request('s1', 7, 'tools/call', { name = 'async-tool' })
  MiniTest.expect.equality(response.result.isError, true)
  -- Task should not be leaked
  MiniTest.expect.equality(#executor.list_running(), 0)
end

return T
