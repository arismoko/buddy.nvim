--- Tests for E2E cancellation flow:
--- request_store binding, tool_service wiring, notifications/cancelled handler
local T = MiniTest.new_set()

T['hooks'] = {
  pre_case = function()
    -- Reset modules for fresh state
    package.loaded['buddy.runtime.state.request_store'] = nil
    package.loaded['buddy.services.tool_service'] = nil
    package.loaded['buddy.tools.executor'] = nil
    -- Force a fresh executor load and reset running_tasks
    require('buddy.tools.executor')._reset()
  end,
}

-- ────────────────────────────────────────────────────────────────
-- RequestStore: tool-task binding
-- ────────────────────────────────────────────────────────────────

T['request_store'] = MiniTest.new_set()

T['request_store']['bind_tool_task stores mapping'] = function()
  local RequestStore = require("buddy.runtime.state.request_store")
  local store = RequestStore.new()

  store:bind_tool_task("sess-1", 42, "task-7")
  MiniTest.expect.equality(store:get_tool_task("sess-1", 42), "task-7")
end

T['request_store']['get_tool_task returns nil for unbound'] = function()
  local RequestStore = require("buddy.runtime.state.request_store")
  local store = RequestStore.new()

  MiniTest.expect.equality(store:get_tool_task("sess-1", 99), nil)
end

T['request_store']['unbind_tool_task removes mapping'] = function()
  local RequestStore = require("buddy.runtime.state.request_store")
  local store = RequestStore.new()

  store:bind_tool_task("sess-1", 42, "task-7")
  store:unbind_tool_task("sess-1", 42)
  MiniTest.expect.equality(store:get_tool_task("sess-1", 42), nil)
end

T['request_store']['cleanup_by_session removes tool-task bindings'] = function()
  local RequestStore = require("buddy.runtime.state.request_store")
  local store = RequestStore.new()

  store:bind_tool_task("sess-A", 1, "task-1")
  store:bind_tool_task("sess-A", 2, "task-2")
  store:bind_tool_task("sess-B", 3, "task-3")

  store:cleanup_by_session("sess-A")

  MiniTest.expect.equality(store:get_tool_task("sess-A", 1), nil)
  MiniTest.expect.equality(store:get_tool_task("sess-A", 2), nil)
  MiniTest.expect.equality(store:get_tool_task("sess-B", 3), "task-3")
end

T['request_store']['composite key isolates sessions'] = function()
  local RequestStore = require("buddy.runtime.state.request_store")
  local store = RequestStore.new()

  store:bind_tool_task("sess-1", 42, "task-A")
  store:bind_tool_task("sess-2", 42, "task-B")

  MiniTest.expect.equality(store:get_tool_task("sess-1", 42), "task-A")
  MiniTest.expect.equality(store:get_tool_task("sess-2", 42), "task-B")
end

T['request_store']['numeric and string request IDs do not collide'] = function()
  local RequestStore = require("buddy.runtime.state.request_store")
  local store = RequestStore.new()

  store:bind_tool_task("sess-1", 1, "task-numeric")
  store:bind_tool_task("sess-1", "1", "task-string")

  MiniTest.expect.equality(store:get_tool_task("sess-1", 1), "task-numeric")
  MiniTest.expect.equality(store:get_tool_task("sess-1", "1"), "task-string")
end

T['request_store']['get_tool_tasks_for_session returns bound task_ids'] = function()
  local RequestStore = require("buddy.runtime.state.request_store")
  local store = RequestStore.new()

  store:bind_tool_task("sess-A", 1, "task-1")
  store:bind_tool_task("sess-A", 2, "task-2")
  store:bind_tool_task("sess-B", 3, "task-3")

  local tasks = store:get_tool_tasks_for_session("sess-A")
  table.sort(tasks)
  MiniTest.expect.equality(tasks, { "task-1", "task-2" })

  -- Other session untouched
  local tasks_b = store:get_tool_tasks_for_session("sess-B")
  MiniTest.expect.equality(tasks_b, { "task-3" })

  -- Non-existent session returns empty
  MiniTest.expect.equality(store:get_tool_tasks_for_session("sess-X"), {})
end

T['request_store']['independent stores are isolated'] = function()
  local RequestStore = require("buddy.runtime.state.request_store")
  local store_a = RequestStore.new()
  local store_b = RequestStore.new()

  store_a:bind_tool_task("sess-1", 42, "task-A")

  -- store_b must not see store_a's binding
  MiniTest.expect.equality(store_b:get_tool_task("sess-1", 42), nil)

  store_b:bind_tool_task("sess-1", 42, "task-B")

  -- Each store has its own value
  MiniTest.expect.equality(store_a:get_tool_task("sess-1", 42), "task-A")
  MiniTest.expect.equality(store_b:get_tool_task("sess-1", 42), "task-B")
end

-- ────────────────────────────────────────────────────────────────
-- ToolService: cancellation binding integration
-- ────────────────────────────────────────────────────────────────

T['tool_service'] = MiniTest.new_set()

T['tool_service']['sync tool does not create binding'] = function()
  local RequestStore = require("buddy.runtime.state.request_store")
  local store = RequestStore.new()

  -- Register a simple sync tool
  local tools = require("buddy.tools")
  tools.register({
    name = "_test_sync_cancel",
    description = "Test sync tool",
    args = {},
    run = function() return { ok = true } end,
  })

  local ToolService = require("buddy.services.tool_service")
  local service = ToolService.new({ request_store = store })

  service:call("sess-1", { name = "_test_sync_cancel" }, 100)

  -- Sync tool should not leave a binding (task_id is nil for sync)
  MiniTest.expect.equality(store:get_tool_task("sess-1", 100), nil)
end

T['tool_service']['async tool gets bound for cancellation'] = function()
  local RequestStore = require("buddy.runtime.state.request_store")
  local store = RequestStore.new()

  -- Register an async tool that returns a cancel function
  local cancel_called = false
  local tools = require("buddy.tools")
  tools.register({
    name = "_test_async_cancel",
    description = "Test async tool",
    args = {},
    run = function(_args, _context)
      -- Return a cancel function → signals async execution
      return function()
        cancel_called = true
      end
    end,
  })

  local ToolService = require("buddy.services.tool_service")
  local service = ToolService.new({ request_store = store })

  -- Call should bind the task for cancellation
  service:call("sess-1", { name = "_test_async_cancel" }, 200)

  -- Async tool should have a binding
  local task_id = store:get_tool_task("sess-1", 200)
  MiniTest.expect.equality(type(task_id), "string")

  -- Cancel should work through the binding
  local cancelled = service:cancel(task_id)
  MiniTest.expect.equality(cancelled, true)
  MiniTest.expect.equality(cancel_called, true)
end

T['tool_service']['cancel delegates to executor'] = function()
  local ToolService = require("buddy.services.tool_service")
  local service = ToolService.new()

  -- Cancel a non-existent task should return false
  local result = service:cancel("nonexistent-task")
  MiniTest.expect.equality(result, false)
end

-- ────────────────────────────────────────────────────────────────
-- Executor: edge cases
-- ────────────────────────────────────────────────────────────────

T['executor'] = MiniTest.new_set()

T['executor']['sync tool returning nil is not classified as async'] = function()
  local executor = require("buddy.tools.executor")
  executor._reset()

  local tools = require("buddy.tools")
  tools.register({
    name = "_test_sync_nil",
    description = "Sync tool returning nil",
    args = {},
    run = function() return nil end,
  })

  local executor = require("buddy.tools.executor")
  -- Even with a callback, nil-returning sync tool should NOT get a task_id
  local result, task_id = executor.execute("_test_sync_nil", {}, {
    callback = function() end,
  })
  MiniTest.expect.equality(result, nil)
  MiniTest.expect.equality(task_id, nil)

  -- No running tasks should be left
  MiniTest.expect.equality(executor.list_running(), {})
end

T['executor']['cancel-then-complete race does not invoke callback twice'] = function()
  local executor = require("buddy.tools.executor")
  executor._reset()

  local tools = require("buddy.tools")
  local complete_fn
  tools.register({
    name = "_test_race",
    description = "Async tool for race test",
    args = {},
    run = function(_args, context)
      -- Capture the context callback for manual completion
      complete_fn = function(result) context(result) end
      return function() end -- cancel fn
    end,
  })

  local executor = require("buddy.tools.executor")
  local callback_count = 0
  local _, task_id = executor.execute("_test_race", {}, {
    callback = function()
      callback_count = callback_count + 1
    end,
  })

  -- Cancel the task (this calls callback once with cancellation error)
  executor.cancel(task_id)
  MiniTest.expect.equality(callback_count, 1) -- cancel invoked callback

  -- Now simulate late completion (race condition)
  complete_fn({ late = true })

  -- Callback should NOT have been called again (task was already removed)
  MiniTest.expect.equality(callback_count, 1)
  MiniTest.expect.equality(executor.list_running(), {})
end

T['executor']['async tool without callback cleans up on completion'] = function()
  local executor = require("buddy.tools.executor")
  executor._reset()

  local tools = require("buddy.tools")
  local complete_fn
  tools.register({
    name = "_test_no_callback",
    description = "Async tool without callback",
    args = {},
    run = function(_args, context)
      complete_fn = function(result) context(result) end
      return function() end -- cancel fn
    end,
  })

  local executor = require("buddy.tools.executor")
  -- No callback provided — simulates ToolService:call() sync path
  local result, task_id = executor.execute("_test_no_callback", {})

  MiniTest.expect.equality(result, nil)
  MiniTest.expect.equality(type(task_id), "string")

  -- Task should be in running_tasks
  local running = executor.list_running()
  MiniTest.expect.equality(#running, 1)

  -- Tool completes via context()
  complete_fn({ done = true })

  -- running_tasks should be cleaned up
  MiniTest.expect.equality(executor.list_running(), {})
end

T['executor']['immediate-completion async tool delivers result'] = function()
  local executor = require("buddy.tools.executor")
  executor._reset()

  local tools = require("buddy.tools")
  tools.register({
    name = "_test_immediate_async",
    description = "Async tool that completes inside run()",
    args = {},
    run = function(_args, context)
      -- Complete synchronously BEFORE returning cancel function
      context({ immediate = true })
      return function() end -- cancel fn (returned after completion)
    end,
  })

  local executor = require("buddy.tools.executor")
  local callback_result = nil
  local _, task_id = executor.execute("_test_immediate_async", {}, {
    callback = function(_err, result)
      callback_result = result
    end,
  })

  -- Should still be classified as async (returned cancel fn)
  MiniTest.expect.equality(type(task_id), "string")

  -- Callback should have been invoked with the result (not dropped)
  MiniTest.expect.equality(callback_result, { immediate = true })

  -- Task should be cleaned up (completed inside run)
  MiniTest.expect.equality(executor.list_running(), {})
end

T['executor']['immediate-completion async without callback cleans up'] = function()
  local executor = require("buddy.tools.executor")
  executor._reset()

  local tools = require("buddy.tools")
  tools.register({
    name = "_test_immediate_no_cb",
    description = "Async tool that completes inside run() without callback",
    args = {},
    run = function(_args, context)
      -- Complete synchronously BEFORE returning cancel function
      context({ immediate = true })
      return function() end
    end,
  })

  local executor = require("buddy.tools.executor")
  local _, task_id = executor.execute("_test_immediate_no_cb", {})

  MiniTest.expect.equality(type(task_id), "string")
  -- Task should be cleaned up even without callback
  MiniTest.expect.equality(executor.list_running(), {})
end

T['executor']['cancel callback failure does not leak task'] = function()
  local executor = require("buddy.tools.executor")
  executor._reset()

  local tools = require("buddy.tools")
  tools.register({
    name = "_test_cancel_cb_fail",
    description = "Async tool with failing cancel callback",
    args = {},
    run = function(_args, _context)
      return function() end -- cancel fn
    end,
  })

  local executor = require("buddy.tools.executor")
  local _, task_id = executor.execute("_test_cancel_cb_fail", {}, {
    callback = function()
      error("callback exploded!")
    end,
  })

  -- Cancel should succeed even if callback throws
  local cancelled = executor.cancel(task_id)
  MiniTest.expect.equality(cancelled, true)

  -- Task should be cleaned up despite callback failure
  MiniTest.expect.equality(executor.list_running(), {})
end

-- ────────────────────────────────────────────────────────────────
-- ToolService: binding cleanup on async completion
-- ────────────────────────────────────────────────────────────────

T['tool_service']['async binding cleaned up on completion'] = function()
  local RequestStore = require("buddy.runtime.state.request_store")
  local store = RequestStore.new()

  local tools = require("buddy.tools")
  local complete_fn
  tools.register({
    name = "_test_async_unbind",
    description = "Async tool for binding cleanup test",
    args = {},
    run = function(_args, context)
      complete_fn = function(result) context(result) end
      return function() end
    end,
  })

  local ToolService = require("buddy.services.tool_service")
  local service = ToolService.new({ request_store = store })

  service:call("sess-1", { name = "_test_async_unbind" }, 500)

  -- Binding should exist while tool is running
  local task_id = store:get_tool_task("sess-1", 500)
  MiniTest.expect.equality(type(task_id), "string")

  -- Complete the async tool
  complete_fn({ done = true })

  -- Binding should be cleaned up after completion
  MiniTest.expect.equality(store:get_tool_task("sess-1", 500), nil)
end

T['tool_service']['immediate-completion async tool leaves no binding'] = function()
  local RequestStore = require("buddy.runtime.state.request_store")
  local store = RequestStore.new()

  local tools = require("buddy.tools")
  tools.register({
    name = "_test_immediate_unbind",
    description = "Async tool that completes inside run()",
    args = {},
    run = function(_args, context)
      -- Complete synchronously inside run() before returning cancel fn
      context({ immediate = true })
      return function() end
    end,
  })

  local ToolService = require("buddy.services.tool_service")
  local service = ToolService.new({ request_store = store })

  service:call("sess-1", { name = "_test_immediate_unbind" }, 600)

  -- Binding should NOT exist (tool completed inside run, unbind happened)
  MiniTest.expect.equality(store:get_tool_task("sess-1", 600), nil)
end

T['tool_service']['sync tool does not leave binding'] = function()
  local RequestStore = require("buddy.runtime.state.request_store")
  local store = RequestStore.new()

  local tools = require("buddy.tools")
  tools.register({
    name = "_test_sync_no_bind",
    description = "Sync tool for binding test",
    args = {},
    run = function() return { ok = true } end,
  })

  local ToolService = require("buddy.services.tool_service")
  local service = ToolService.new({ request_store = store })

  service:call("sess-1", { name = "_test_sync_no_bind" }, 700)

  -- Sync tool should not leave a binding
  MiniTest.expect.equality(store:get_tool_task("sess-1", 700), nil)
end

-- ────────────────────────────────────────────────────────────────
-- ToolService: async response semantics
-- ────────────────────────────────────────────────────────────────

T['tool_service']['sync tool returning nil returns shaped result'] = function()
  local tools = require("buddy.tools")
  tools.register({
    name = "_test_sync_nil_shaped",
    description = "Sync tool returning nil",
    args = {},
    run = function() return nil end,
  })

  local ToolService = require("buddy.services.tool_service")
  local service = ToolService.new()
  local response = service:call("sess-1", { name = "_test_sync_nil_shaped" }, 300)

  -- Should be a valid non-error response with "nil" text
  MiniTest.expect.equality(response.isError, nil)
  MiniTest.expect.equality(response.content[1].type, "text")
  MiniTest.expect.equality(response.content[1].text, "nil")
end

T['tool_service']['async tool returns error response in sync path'] = function()
  local tools = require("buddy.tools")
  tools.register({
    name = "_test_async_response",
    description = "Async tool for response test",
    args = {},
    run = function(_args, _context)
      return function() end -- cancel fn
    end,
  })

  local ToolService = require("buddy.services.tool_service")
  local service = ToolService.new()
  local response = service:call("sess-1", { name = "_test_async_response" }, 400)

  -- Should be an explicit error response to avoid false-success semantics
  MiniTest.expect.equality(response.isError, true)
  MiniTest.expect.equality(response.data.tool, "_test_async_response")
  MiniTest.expect.equality(type(response.data.task_id), "string")
  MiniTest.expect.equality(response.content[1].type, "text")
  MiniTest.expect.equality(type(response.content[1].text), "string")
  MiniTest.expect.equality(response.content[1].text:find("_test_async_response", 1, true) ~= nil, true)
  MiniTest.expect.equality(response.content[1].text:find("sync tools/call does not support async results", 1, true) ~= nil, true)
end

return T
