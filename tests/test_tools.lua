-- Tests for tool registry
local T = MiniTest.new_set()

-- Fresh registry for each test
T['hooks'] = {
  pre_case = function()
    package.loaded['buddy.tools'] = nil
  end
}

local function get_tools()
  return require('buddy.tools')
end

T['register()'] = MiniTest.new_set()

T['register()']['adds tool to registry'] = function()
  local tools = get_tools()
  tools.register({
    name = 'test-tool',
    description = 'A test tool',
    run = function() return 'ok' end
  })
  
  local tool = tools.get('test-tool')
  MiniTest.expect.equality(tool.name, 'test-tool')
end

T['register()']['errors on missing required fields'] = function()
  local tools = get_tools()
  
  -- Missing name
  MiniTest.expect.error(function()
    tools.register({ description = 'Test', run = function() end })
  end)
  
  -- Missing description
  MiniTest.expect.error(function()
    tools.register({ name = 'test', run = function() end })
  end)
  
  -- Note: run is optional for TS tools (executor handles them)
end

T['get()'] = MiniTest.new_set()

T['get()']['returns nil for unknown tool'] = function()
  local tools = get_tools()
  MiniTest.expect.equality(tools.get('nonexistent'), nil)
end

T['list()'] = MiniTest.new_set()

T['list()']['returns empty array when no tools'] = function()
  local tools = get_tools()
  tools.clear()
  MiniTest.expect.equality(#tools.list(), 0)
end

T['list()']['returns tools sorted by name'] = function()
  local tools = get_tools()
  tools.clear()
  
  tools.register({ name = 'zebra', description = 'd', run = function() end })
  tools.register({ name = 'alpha', description = 'd', run = function() end })
  tools.register({ name = 'beta', description = 'd', run = function() end })
  
  local list = tools.list()
  MiniTest.expect.equality(#list, 3)
  MiniTest.expect.equality(list[1].name, 'alpha')
  MiniTest.expect.equality(list[2].name, 'beta')
  MiniTest.expect.equality(list[3].name, 'zebra')
end

T['clear()'] = MiniTest.new_set()

T['clear()']['removes all tools'] = function()
  local tools = get_tools()
  tools.register({ name = 'test', description = 'd', run = function() end })
  MiniTest.expect.equality(#tools.list() > 0, true)
  
  tools.clear()
  MiniTest.expect.equality(#tools.list(), 0)
end

return T
