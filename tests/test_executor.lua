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

T['execute()']['runs sync tool and returns result'] = function()
  local tools = get_tools()
  local executor = get_executor()

  tools.register({
    name = 'sync-tool',
    description = 'Sync tool',
    run = function(args)
      return { value = args.x or 42 }
    end,
  })

  local result, task_id = executor.execute('sync-tool', { x = 99 })
  MiniTest.expect.equality(result.value, 99)
  MiniTest.expect.equality(task_id, nil)
end

T['execute()']['throws on unknown tool'] = function()
  local executor = get_executor()
  local tools = get_tools()
  tools.clear()

  MiniTest.expect.error(function()
    executor.execute('nonexistent', {})
  end)
end

T['execute()']['passes on_progress to context'] = function()
  local tools = get_tools()
  local executor = get_executor()
  local progress_calls = {}

  tools.register({
    name = 'progress-exec-tool',
    description = 'Tool with progress',
    run = function(_, context)
      if context.on_progress then
        context.on_progress(1, 10, 'working')
      end
      return 'done'
    end,
  })

  local result = executor.execute('progress-exec-tool', {}, {
    on_progress = function(p, t, m)
      table.insert(progress_calls, { p = p, t = t, m = m })
    end,
  })

  MiniTest.expect.equality(result, 'done')
  MiniTest.expect.equality(#progress_calls, 1)
  MiniTest.expect.equality(progress_calls[1].p, 1)
  MiniTest.expect.equality(progress_calls[1].m, 'working')
end

T['cancel()'] = MiniTest.new_set()

T['cancel()']['returns false for nonexistent task'] = function()
  local executor = get_executor()
  MiniTest.expect.equality(executor.cancel('999'), false)
end

T['list_running()'] = MiniTest.new_set()

T['list_running()']['returns empty list initially'] = function()
  local executor = get_executor()
  MiniTest.expect.equality(#executor.list_running(), 0)
end

return T
