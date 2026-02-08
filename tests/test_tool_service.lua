-- Tests for services/tool_service.lua
local T = MiniTest.new_set()

T['hooks'] = {
  pre_case = function()
    package.loaded['buddy.services.tool_service'] = nil
    package.loaded['buddy.tools'] = nil
    package.loaded['buddy.tools.executor'] = nil
    package.loaded['buddy.tools.errors'] = nil
  end,
}

local function setup_tool(name, run_fn, extra)
  local tools = require('buddy.tools')
  local def = {
    name = name,
    description = 'Test tool: ' .. name,
    run = run_fn,
  }
  if extra then
    for k, v in pairs(extra) do
      def[k] = v
    end
  end
  tools.register(def)
  return def
end

T['new()'] = MiniTest.new_set()

T['new()']['creates instance without notifier'] = function()
  local ToolService = require('buddy.services.tool_service')
  local svc = ToolService.new()
  MiniTest.expect.no_equality(svc, nil)
end

T['new()']['creates instance with notifier'] = function()
  local ToolService = require('buddy.services.tool_service')
  local svc = ToolService.new({ notifier = { notify = function() end } })
  MiniTest.expect.no_equality(svc, nil)
end

T['singleton'] = MiniTest.new_set()

T['singleton']['set and get instance'] = function()
  local ToolService = require('buddy.services.tool_service')
  MiniTest.expect.equality(ToolService.get_instance(), nil)

  local svc = ToolService.new()
  ToolService.set_instance(svc)
  MiniTest.expect.equality(ToolService.get_instance(), svc)

  ToolService.reset()
  MiniTest.expect.equality(ToolService.get_instance(), nil)
end

T['call()'] = MiniTest.new_set()

T['call()']['returns text content for string results'] = function()
  local ToolService = require('buddy.services.tool_service')
  setup_tool('echo', function(args) return 'hello ' .. (args.msg or '') end)

  local svc = ToolService.new()
  local result = svc:call('s1', { name = 'echo', arguments = { msg = 'world' } }, 1)
  MiniTest.expect.equality(result.content[1].type, 'text')
  MiniTest.expect.equality(result.content[1].text, 'hello world')
end

T['call()']['returns JSON-encoded text for table results'] = function()
  local ToolService = require('buddy.services.tool_service')
  setup_tool('table-tool', function() return { key = 'value' } end)

  local svc = ToolService.new()
  local result = svc:call('s1', { name = 'table-tool' }, 1)
  local decoded = vim.json.decode(result.content[1].text)
  MiniTest.expect.equality(decoded.key, 'value')
end

T['call()']['includes structuredContent when output_schema present'] = function()
  local ToolService = require('buddy.services.tool_service')
  setup_tool('structured', function() return { data = 'test' } end, {
    output_schema = { type = 'object' },
  })

  local svc = ToolService.new()
  local result = svc:call('s1', { name = 'structured' }, 1)
  MiniTest.expect.equality(result.structuredContent.data, 'test')
end

T['call()']['errors on missing name'] = function()
  local ToolService = require('buddy.services.tool_service')
  local svc = ToolService.new()
  MiniTest.expect.error(function()
    svc:call('s1', {}, 1)
  end)
end

T['call()']['errors on unknown tool'] = function()
  local ToolService = require('buddy.services.tool_service')
  local tools = require('buddy.tools')
  tools.clear()

  local svc = ToolService.new()
  MiniTest.expect.error(function()
    svc:call('s1', { name = 'nonexistent' }, 1)
  end)
end

T['call()']['returns isError for tool execution failures'] = function()
  local ToolService = require('buddy.services.tool_service')
  setup_tool('fail-tool', function() error('boom') end)

  local svc = ToolService.new()
  local result = svc:call('s1', { name = 'fail-tool' }, 1)
  MiniTest.expect.equality(result.isError, true)
  -- Should have error content
  MiniTest.expect.equality(result.content[1].type, 'text')
end

T['call()']['sends progress via notifier when token present'] = function()
  local ToolService = require('buddy.services.tool_service')
  local progress_calls = {}
  local mock_notifier = {
    notify = function(_, session_id, method, params)
      table.insert(progress_calls, {
        session_id = session_id,
        method = method,
        params = params,
      })
    end,
  }

  setup_tool('progress-tool', function(_, context)
    if context.on_progress then
      context.on_progress(1, 10, 'step 1')
      context.on_progress(5, 10, 'step 5')
    end
    return 'done'
  end)

  local svc = ToolService.new({ notifier = mock_notifier })
  local result = svc:call('s1', {
    name = 'progress-tool',
    _meta = { progressToken = 'tok-1' },
  }, 1)

  MiniTest.expect.equality(result.content[1].text, 'done')
  MiniTest.expect.equality(#progress_calls, 2)
  MiniTest.expect.equality(progress_calls[1].session_id, 's1')
  MiniTest.expect.equality(progress_calls[1].method, 'notifications/progress')
  MiniTest.expect.equality(progress_calls[1].params.progressToken, 'tok-1')
  MiniTest.expect.equality(progress_calls[1].params.progress, 1)
  MiniTest.expect.equality(progress_calls[2].params.progress, 5)
end

T['call()']['skips progress without notifier'] = function()
  local ToolService = require('buddy.services.tool_service')
  setup_tool('progress-tool-2', function(_, context)
    if context.on_progress then
      context.on_progress(1, 10, 'step')
    end
    return 'ok'
  end)

  -- No notifier — should not crash
  local svc = ToolService.new()
  local result = svc:call('s1', {
    name = 'progress-tool-2',
    _meta = { progressToken = 'tok-2' },
  }, 1)
  MiniTest.expect.equality(result.content[1].text, 'ok')
end

T['call()']['skips progress without token'] = function()
  local ToolService = require('buddy.services.tool_service')
  local called = false
  local mock_notifier = {
    notify = function() called = true end,
  }

  setup_tool('no-token', function() return 'ok' end)

  local svc = ToolService.new({ notifier = mock_notifier })
  svc:call('s1', { name = 'no-token' }, 1)
  MiniTest.expect.equality(called, false)
end

T['cancel()'] = MiniTest.new_set()

T['cancel()']['delegates to executor'] = function()
  local ToolService = require('buddy.services.tool_service')
  local svc = ToolService.new()
  -- cancel on nonexistent task should return false
  local ok = svc:cancel('nonexistent-task')
  MiniTest.expect.equality(ok, false)
end

T['call()']['rejects async tool via cancel fn with isError and cancels task'] = function()
  local ToolService = require('buddy.services.tool_service')
  local executor = require('buddy.tools.executor')
  executor._reset()

  setup_tool('async-cancel', function(_, _context)
    return function() end  -- cancel function = async
  end)

  local svc = ToolService.new()
  local result = svc:call('s1', { name = 'async-cancel' }, 1)

  -- Should return error
  MiniTest.expect.equality(result.isError, true)
  MiniTest.expect.equality(type(result.content[1].text), 'string')

  -- Async task should be cancelled (not leaked)
  MiniTest.expect.equality(#executor.list_running(), 0)
end

T['call()']['rejects async tool via start_async with isError and cancels task'] = function()
  local ToolService = require('buddy.services.tool_service')
  local executor = require('buddy.tools.executor')
  executor._reset()

  setup_tool('async-start', function(_, context)
    context.start_async()
    return nil
  end)

  local svc = ToolService.new()
  local result = svc:call('s1', { name = 'async-start' }, 1)

  -- Should return error
  MiniTest.expect.equality(result.isError, true)

  -- Async task should be cancelled (not leaked)
  MiniTest.expect.equality(#executor.list_running(), 0)
end

return T
