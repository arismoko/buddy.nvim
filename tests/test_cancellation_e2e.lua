--- Tests for E2E cancellation flow:
--- request_store binding, tool_service wiring, notifications/cancelled handler
local T = MiniTest.new_set()

T['hooks'] = {
  pre_case = function()
    -- Reset modules for fresh state
    package.loaded['buddy.runtime.state.request_store'] = nil
    package.loaded['buddy.services.tool_service'] = nil
    package.loaded['buddy.tools.executor'] = nil
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

-- ────────────────────────────────────────────────────────────────
-- ToolService: cancellation binding integration
-- ────────────────────────────────────────────────────────────────

T['tool_service'] = MiniTest.new_set()

T['tool_service']['call unbinds after sync tool completes'] = function()
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

T['tool_service']['cancel delegates to executor'] = function()
  local ToolService = require("buddy.services.tool_service")
  local service = ToolService.new()

  -- Cancel a non-existent task should return false
  local result = service:cancel("nonexistent-task")
  MiniTest.expect.equality(result, false)
end

return T
