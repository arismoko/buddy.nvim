local T = MiniTest.new_set()

T['hooks'] = {
  pre_case = function()
    package.loaded['buddy.tools'] = nil
    package.loaded['buddy.tools.executor'] = nil
  end
}

local function get_executor()
  return require('buddy.tools.executor')
end

local function get_tools()
  return require('buddy.tools')
end

T['execute()'] = MiniTest.new_set()

T['execute()']['validates input_schema required fields'] = function()
  -- Regression: P1 executor used tool.args but builtins use tool.input_schema
  local tools = get_tools()
  local executor = get_executor()

  tools.register({
    name = 'test-schema-tool',
    description = 'Test tool with input_schema',
    input_schema = {
      type = "object",
      properties = {
        action = { type = "string", description = "Action" },
      },
      required = { "action" },
    },
    run = function(args)
      return { success = true, action = args.action }
    end,
  })

  -- Missing required field should throw
  MiniTest.expect.error(function()
    executor.execute('test-schema-tool', {})
  end)

  -- With required field should succeed
  local result = executor.execute('test-schema-tool', { action = "test" })
  MiniTest.expect.equality(result.success, true)
end

T['execute()']['validates legacy args schema'] = function()
  local tools = get_tools()
  local executor = get_executor()

  tools.register({
    name = 'test-legacy-tool',
    description = 'Test tool with legacy args',
    args = {
      name = { type = "string", description = "Name" },
    },
    required = { "name" },
    run = function(args)
      return { success = true, name = args.name }
    end,
  })

  -- Missing required field should throw
  MiniTest.expect.error(function()
    executor.execute('test-legacy-tool', {})
  end)

  -- With required field should succeed
  local result = executor.execute('test-legacy-tool', { name = "test" })
  MiniTest.expect.equality(result.success, true)
end

return T
