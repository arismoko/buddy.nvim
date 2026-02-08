local T = MiniTest.new_set()

T['hooks'] = {
  pre_case = function()
    package.loaded['buddy.tools'] = nil
    package.loaded['buddy.tools.executor'] = nil
    -- Force a fresh executor load and reset running_tasks
    require('buddy.tools.executor')._reset()
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

-- Async via cancel function return
T['execute()']['async via cancel fn returns nil and task_id'] = function()
  local tools = get_tools()
  local executor = get_executor()

  tools.register({
    name = 'async-cancel-tool',
    description = 'Async tool with cancel fn',
    run = function(_, _context)
      return function() end  -- cancel function
    end,
  })

  local result, task_id = executor.execute('async-cancel-tool', {}, {
    callback = function() end,
  })
  MiniTest.expect.equality(result, nil)
  MiniTest.expect.no_equality(task_id, nil)

  -- Task should be tracked
  local running = executor.list_running()
  MiniTest.expect.equality(#running, 1)
  MiniTest.expect.equality(running[1].tool_id, 'async-cancel-tool')

  -- Clean up
  executor.cancel(task_id)
end

-- Async via context.start_async()
T['execute()']['async via start_async returns nil and task_id'] = function()
  local tools = get_tools()
  local executor = get_executor()

  tools.register({
    name = 'async-start-tool',
    description = 'Async tool with start_async',
    run = function(_, context)
      context.start_async()
      return nil
    end,
  })

  local result, task_id = executor.execute('async-start-tool', {}, {
    callback = function() end,
  })
  MiniTest.expect.equality(result, nil)
  MiniTest.expect.no_equality(task_id, nil)

  -- Clean up
  executor.cancel(task_id)
end

-- Mixed-mode: start_async + non-nil return is an error
T['execute()']['start_async with non-nil return throws'] = function()
  local tools = get_tools()
  local executor = get_executor()

  tools.register({
    name = 'mixed-mode-tool',
    description = 'Mixed-mode tool (broken)',
    run = function(_, context)
      context.start_async()
      return { result = "should not be here" }  -- non-nil, non-function
    end,
  })

  MiniTest.expect.error(function()
    executor.execute('mixed-mode-tool', {})
  end)

  -- Ensure no leaked tasks
  MiniTest.expect.equality(#executor.list_running(), 0)
end

-- start_async + function return uses cancel-fn branch precedence
T['execute()']['start_async with function return uses cancel-fn precedence'] = function()
  local tools = get_tools()
  local executor = get_executor()

  -- Note: a function return is caught FIRST by the cancel-fn branch (line 184),
  -- so start_async + function return works — the cancel-fn takes precedence.
  -- This is the documented behavior: return function = async (cancel fn branch).
  -- start_async is only checked when return is NOT a function.

  tools.register({
    name = 'start-async-fn-tool',
    description = 'start_async + cancel fn',
    run = function(_, context)
      context.start_async()
      return function() end
    end,
  })

  -- This should NOT throw — cancel fn branch takes precedence
  local result, task_id = executor.execute('start-async-fn-tool', {}, {
    callback = function() end,
  })
  MiniTest.expect.equality(result, nil)
  MiniTest.expect.no_equality(task_id, nil)

  -- Clean up
  executor.cancel(task_id)
end

-- start_async with cancel_fn argument
T['execute()']['start_async with cancel_fn arg registers it'] = function()
  local tools = get_tools()
  local executor = get_executor()
  local cancel_called = false

  tools.register({
    name = 'async-cancel-arg-tool',
    description = 'Async with cancel fn arg',
    run = function(_, context)
      context.start_async(function()
        cancel_called = true
      end)
      return nil
    end,
  })

  local _, task_id = executor.execute('async-cancel-arg-tool', {}, {
    callback = function() end,
  })
  MiniTest.expect.no_equality(task_id, nil)

  -- Cancel should invoke the cancel fn
  executor.cancel(task_id)
  MiniTest.expect.equality(cancel_called, true)
end

-- start_async rejects non-function, non-nil argument
T['execute()']['start_async rejects non-function argument'] = function()
  local tools = get_tools()
  local executor = get_executor()

  tools.register({
    name = 'start-async-bad-arg',
    description = 'start_async with bad arg',
    run = function(_, context)
      context.start_async("not a function")
      return nil
    end,
  })

  MiniTest.expect.error(function()
    executor.execute('start-async-bad-arg', {})
  end)
end

return T
