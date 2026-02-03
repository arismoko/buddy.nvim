local T = MiniTest.new_set()

T['prompts.list()'] = function()
  local prompts = require('buddy.prompts')
  local list = prompts.list()
  MiniTest.expect.equality(type(list), 'table')
  MiniTest.expect.equality(#list > 0, true)
  
  -- Check for expected prompt
  local found = false
  for _, p in ipairs(list) do
    if p.name == 'explain_buffer' then
      found = true
      MiniTest.expect.equality(p.title, 'Explain Buffer')
    end
  end
  MiniTest.expect.equality(found, true)
end

T['prompts.get()'] = MiniTest.new_set()

T['prompts.get()']['returns prompt messages'] = function()
  local prompts = require('buddy.prompts')
  local result = prompts.get('explain_buffer', { focus = 'tests' })
  
  MiniTest.expect.equality(type(result), 'table')
  MiniTest.expect.equality(result.description, 'Explain the current buffer\'s code')
  MiniTest.expect.equality(#result.messages, 1)
  MiniTest.expect.equality(result.messages[1].role, 'user')
  MiniTest.expect.equality(result.messages[1].content[1].text, 'Explain this code, focusing on: tests')
end

T['prompts.get()']['uses default arguments'] = function()
  local prompts = require('buddy.prompts')
  local result = prompts.get('explain_buffer', {})
  
  MiniTest.expect.equality(result.messages[1].content[1].text, 'Explain this code, focusing on: overall structure and purpose')
end

T['prompts.get()']['returns nil for unknown prompt'] = function()
  local prompts = require('buddy.prompts')
  local result = prompts.get('non_existent', {})
  MiniTest.expect.equality(result, nil)
end

T['MCP handlers'] = MiniTest.new_set()

T['MCP handlers']['prompts/list'] = function()
  local mcp = require('buddy.mcp')
  local response = mcp.handle_request('session-1', {
    jsonrpc = '2.0',
    id = 1,
    method = 'prompts/list',
    params = {}
  })
  
  MiniTest.expect.equality(response.id, 1)
  MiniTest.expect.equality(type(response.result.prompts), 'table')
  MiniTest.expect.equality(#response.result.prompts > 0, true)
end

T['MCP handlers']['prompts/get'] = function()
  local mcp = require('buddy.mcp')
  local response = mcp.handle_request('session-1', {
    jsonrpc = '2.0',
    id = 2,
    method = 'prompts/get',
    params = { name = 'explain_buffer', arguments = { focus = 'performance' } }
  })
  
  MiniTest.expect.equality(response.id, 2)
  MiniTest.expect.equality(response.result.messages[1].content[1].text, 'Explain this code, focusing on: performance')
end

return T
