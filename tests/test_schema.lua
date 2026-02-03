-- Tests for MCP schema module (JSON-RPC builders)
local T = MiniTest.new_set()
local schema = require('buddy.mcp.schema')

T['result()'] = MiniTest.new_set()

T['result()']['builds valid JSON-RPC response'] = function()
  local res = schema.result(1, { foo = 'bar' })
  
  MiniTest.expect.equality(res.jsonrpc, '2.0')
  MiniTest.expect.equality(res.id, 1)
  MiniTest.expect.equality(res.result.foo, 'bar')
  MiniTest.expect.equality(res.error, nil)
end

T['result()']['handles string id'] = function()
  local res = schema.result('abc-123', 'success')
  
  MiniTest.expect.equality(res.id, 'abc-123')
  MiniTest.expect.equality(res.result, 'success')
end

T['result()']['handles nil result'] = function()
  local res = schema.result(42, nil)
  
  MiniTest.expect.equality(res.id, 42)
  MiniTest.expect.equality(res.result, nil)
end

T['error()'] = MiniTest.new_set()

T['error()']['builds valid JSON-RPC error'] = function()
  local res = schema.error(1, -32600, 'Invalid Request')
  
  MiniTest.expect.equality(res.jsonrpc, '2.0')
  MiniTest.expect.equality(res.id, 1)
  MiniTest.expect.equality(res.error.code, -32600)
  MiniTest.expect.equality(res.error.message, 'Invalid Request')
  MiniTest.expect.equality(res.error.data, nil)
  MiniTest.expect.equality(res.result, nil)
end

T['error()']['includes data when provided'] = function()
  local res = schema.error(2, -32603, 'Internal error', { detail = 'stack trace' })
  
  MiniTest.expect.equality(res.error.data.detail, 'stack trace')
end

T['error()']['handles nil id for parse errors'] = function()
  local res = schema.error(nil, -32700, 'Parse error')
  
  MiniTest.expect.equality(res.id, nil)
  MiniTest.expect.equality(res.error.code, -32700)
end

return T
