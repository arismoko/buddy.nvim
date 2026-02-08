--- Tool execution with async support and cancellation.
---@tag buddy-executor
---@toc_entry Tool Execution
local M = {}

local validate = require("buddy.tools.validate")
local errors = require("buddy.tools.errors")
local log = require("buddy.log")

-- Track running async tasks: task_id -> { cancel_fn, cancelled, callback }
local running_tasks = {}
local next_task_id = 1

--- Execute a Lua tool (sync or async)
---@param tool_id string
---@param args table
---@param opts table|function|nil Options table or callback function
---@return table|nil result for sync, nil for async
---@return string|nil task_id for async tools (to cancel)
function M.execute(tool_id, args, opts)
  local callback
  local on_progress
  if type(opts) == "function" then
    callback = opts
    opts = {}
  elseif type(opts) == "table" then
    callback = opts.callback
    on_progress = opts.on_progress
  else
    opts = {}
  end

  local registry = require("buddy.tools")
  log.debug("Executing tool: %s", tool_id)
  local tool = registry.get(tool_id)
  if not tool then
    errors.throw(errors.codes.NOT_FOUND, "Unknown tool: " .. tool_id)
  end

  if not tool.run then
    errors.throw(errors.codes.EXECUTION_ERROR, "Tool has no run function: " .. tool_id)
  end

  -- Validate input against schema (supports both formats)
  local schema = nil
  if tool.input_schema then
    -- New format: tool.input_schema has { type, properties, required }
    schema = {
      properties = tool.input_schema.properties,
      required = tool.input_schema.required,
    }
  elseif tool.args then
    -- Legacy format: tool.args and tool.required
    schema = {
      properties = tool.args,
      required = tool.required,
    }
  end
  local valid, err = validate.validate(args, schema)
  if not valid then
    log.debug("Validation failed for %s: %s", tool_id, err)
    errors.throw(errors.codes.INVALID_INPUT, err, { tool = tool_id })
  end

  -- Tool execution
  log.debug("Running %s", tool_id)

  -- Generate task_id for async tracking
  local task_id = tostring(next_task_id)
  next_task_id = next_task_id + 1

  -- Create async callback wrapper that handles cancellation
  local async_callback = callback and function(result)
    local task = running_tasks[task_id]
    if not task then
      -- Task already removed (cancelled or completed) — drop the result
      log.debug("Ignoring result for absent task %s (likely cancelled)", task_id)
      return
    end
    if task.cancelled then
      log.debug("Ignoring result from cancelled task %s", task_id)
      running_tasks[task_id] = nil
      return
    end
    log.debug("Async tool %s completed (task %s)", tool_id, task_id)
    running_tasks[task_id] = nil
    -- pcall to prevent callback failures from skipping cleanup in context.__call
    local cb_ok, cb_err = pcall(callback, nil, result)
    if not cb_ok then
      log.warn("Async callback failed for task %s: %s", task_id, tostring(cb_err))
    end
  end

  local async_declared = false
  -- When start_async() is active, defer context(result) calls until after
  -- run() returns so the mixed-mode guard can reject invalid contracts
  -- BEFORE any success is delivered.
  local deferred_result = nil  -- { result = <value> } when pending
  local deferred_delivered = false

  -- Make progress callback available to tool run function
  local context = {
    on_progress = on_progress,
    session_id = opts.session_id,
    -- Explicitly mark a tool as async even if run() returns nil.
    -- Optional cancel_fn allows non-cancellable async tools to still declare async.
    start_async = function(cancel_fn)
      if cancel_fn ~= nil and type(cancel_fn) ~= "function" then
        error("context.start_async(cancel_fn) expects function or nil")
      end
      async_declared = true
      if type(cancel_fn) == "function" then
        local task = running_tasks[task_id]
        if task then
          task.cancel_fn = cancel_fn
        end
      end
    end,
  }

  -- Add elicitation capability if session_id is available
  if opts.session_id then
    context.elicit = function(message, schema)
      local client_requests = require("buddy.app.client_requests")
      return client_requests.elicitation_create(opts.session_id, {
        message = message,
        requestedSchema = schema,
      })
    end
    context.sample = function(params)
      local client_requests = require("buddy.app.client_requests")
      return client_requests.sampling_create_message(opts.session_id, params)
    end
  end

  -- Deliver a completion result: invoke async_callback or clean up running_tasks.
  -- Also unbinds request→task mapping to prevent binding leaks.
  local function _deliver_result(result)
    if async_callback then
      async_callback(result)
    else
      -- No external callback — still clean up running_tasks
      local task = running_tasks[task_id]
      if task and not task.cancelled then
        log.debug("Async tool %s completed without callback (task %s)", tool_id, task_id)
        running_tasks[task_id] = nil
      end
    end
    -- Unbind request→task mapping on completion (prevents binding leak)
    if opts.request_store and opts.session_id and opts.request_id then
      opts.request_store:unbind_tool_task(opts.session_id, opts.request_id)
    end
  end

  -- Allow tools to use context as a callback for async completion.
  -- Even without an external callback, clean up the running_tasks entry
  -- and unbind from request_store if available.
  --
  -- When start_async() has been called, defer delivery until after run()
  -- returns so the mixed-mode contract guard can reject before success
  -- is delivered.
  setmetatable(context, {
    __call = function(_, result)
      if async_declared and not deferred_delivered then
        -- Buffer the result; it will be flushed after run() returns
        -- and contract validation passes.
        deferred_result = { result = result }
        return
      end
      _deliver_result(result)
    end,
  })

  -- Register a placeholder in running_tasks BEFORE calling tool.run().
  -- This prevents a race where an async tool calls context(result) synchronously
  -- inside run() before returning its cancel function — the callback/context __call
  -- would see running_tasks[task_id] == nil and drop the result.
  running_tasks[task_id] = {
    cancel_fn = nil, -- Updated after tool.run() returns
    cancelled = false,
    callback = callback,
    tool_id = tool_id,
  }

  -- Bind request→task mapping BEFORE tool.run() so that immediate-completion
  -- async tools can unbind during run() without a race against post-exec binding.
  if opts.request_store and opts.session_id and opts.request_id then
    opts.request_store:bind_tool_task(opts.session_id, opts.request_id, task_id)
  end

  -- Pass context as second arg to run
  local ok, cancel_or_result = pcall(tool.run, args, context)
  if not ok then
    -- Clean up placeholder and binding on failure
    running_tasks[task_id] = nil
    if opts.request_store and opts.session_id and opts.request_id then
      opts.request_store:unbind_tool_task(opts.session_id, opts.request_id)
    end
    log.error("Tool execution failed: %s", tostring(cancel_or_result))
    errors.throw(errors.codes.EXECUTION_ERROR, "Tool execution failed: " .. tostring(cancel_or_result), { tool = tool_id })
  end

  -- If cancel_or_result is a function, it's a cancel fn (async tool).
  -- Update the placeholder with the actual cancel function.
  if type(cancel_or_result) == "function" then
    local task = running_tasks[task_id]
    if task then
      -- Task still exists (wasn't completed synchronously inside run())
      task.cancel_fn = cancel_or_result
      log.debug("Tool %s running async (task %s)", tool_id, task_id)
    else
      -- Task was already completed synchronously inside run() via context().
      -- The placeholder was cleaned up by async_callback or context __call.
      log.debug("Tool %s completed synchronously inside run() (task %s)", tool_id, task_id)
    end

    -- Transition deferred state so context() calls deliver immediately from
    -- this point on (prevents permanent deferral when start_async() was also
    -- called).  Flush any result that was buffered during run().
    if async_declared then
      deferred_delivered = true
      if deferred_result then
        _deliver_result(deferred_result.result)
        deferred_result = nil
      end
    end

    return nil, task_id
  end

  -- Async tool explicitly declared via context.start_async().
  if async_declared then
    -- Mixed-mode guard: if start_async() was called but run() returned a
    -- non-nil, non-function value, that's a programming error — the tool is
    -- confused about its sync/async contract. Clean up and throw WITHOUT
    -- delivering any deferred result.
    if cancel_or_result ~= nil then
      -- Discard any deferred result — contract is invalid.
      deferred_result = nil
      running_tasks[task_id] = nil
      if opts.request_store and opts.session_id and opts.request_id then
        opts.request_store:unbind_tool_task(opts.session_id, opts.request_id)
      end
      errors.throw(
        errors.codes.EXECUTION_ERROR,
        "Tool '" .. tool_id .. "' called context.start_async() but also returned a value; "
          .. "async tools must return nil (got " .. type(cancel_or_result) .. ")",
        { tool = tool_id }
      )
    end

    -- Contract is valid. Flush any deferred completion from context() calls
    -- that happened inside run().
    deferred_delivered = true
    if deferred_result then
      _deliver_result(deferred_result.result)
    end

    local task = running_tasks[task_id]
    if task then
      log.debug("Tool %s declared async (task %s)", tool_id, task_id)
    else
      -- Task already completed synchronously inside run() via context().
      log.debug("Tool %s declared async and completed inside run() (task %s)", tool_id, task_id)
    end
    return nil, task_id
  end

  -- Sync tool - clean up the placeholder and binding, return result directly.
  -- (nil is a valid sync result)
  running_tasks[task_id] = nil
  if opts.request_store and opts.session_id and opts.request_id then
    opts.request_store:unbind_tool_task(opts.session_id, opts.request_id)
  end
  log.debug("Tool %s completed", tool_id)
  return cancel_or_result, nil
end

--- Execute a tool asynchronously using nio futures
--- Returns a nio future that resolves to {result=...} or {error=...}
--- This is the canonical async execution path. execute() is the sync adapter.
---@param tool_id string
---@param args table
---@param opts table|nil Options { session_id?, progress_token?, on_progress? }
---@return table nio_future A future with :wait() that returns the result
---@return string|nil task_id For cancellation
function M.execute_async(tool_id, args, opts)
  local nio = require("buddy.dep.nio")
  local future = nio.control.future()
  opts = opts or {}

  -- Use the callback-based execute() internally
  local exec_opts = {
    session_id = opts.session_id,
    on_progress = opts.on_progress,
    callback = function(err, result)
      if future.is_set() then return end
      if err then
        future.set({ error = err })
      else
        future.set({ result = result })
      end
    end,
  }

  local exec_ok, sync_result_or_err, task_id = pcall(M.execute, tool_id, args, exec_opts)

  if not exec_ok then
    -- Synchronous throw: resolve future with error instead of propagating.
    -- Preserve structured error tables (from errors.throw) rather than stringifying.
    if not future.is_set() then
      future.set({ error = sync_result_or_err })
    end
    return future, nil
  end

  -- If tool completed synchronously (task_id is nil), resolve the future.
  -- Check task_id rather than result value because sync tools may legitimately return nil.
  if task_id == nil and not future.is_set() then
    future.set({ result = sync_result_or_err })
  end

  return future, task_id
end

--- Cancel a running async task
---@param task_id string
---@return boolean success
function M.cancel(task_id)
  local task = running_tasks[task_id]
  if not task then
    log.debug("Cannot cancel task %s - not found", task_id)
    return false
  end

  if task.cancelled then
    log.debug("Task %s already cancelled", task_id)
    return true
  end

  log.debug("Cancelling task %s (%s)", task_id, task.tool_id)
  task.cancelled = true

  -- Call cancel function if provided
  if task.cancel_fn then
    local ok, cancel_err = pcall(task.cancel_fn)
    if not ok then
      log.warn("Cancel function failed for task %s: %s", task_id, tostring(cancel_err))
    end
  end

  -- Notify callback with cancellation error (pcall to prevent leaked entries)
  if task.callback then
    local cb_ok, cb_err = pcall(task.callback, errors.create(errors.codes.CANCELLED, "Task cancelled"), nil)
    if not cb_ok then
      log.warn("Cancel callback failed for task %s: %s", task_id, tostring(cb_err))
    end
  end

  running_tasks[task_id] = nil
  return true
end

--- List running tasks (for debugging)
---@return table
function M.list_running()
  local result = {}
  for id, task in pairs(running_tasks) do
    table.insert(result, { id = id, tool_id = task.tool_id, cancelled = task.cancelled })
  end
  return result
end

--- Reset internal state (for testing only)
function M._reset()
  running_tasks = {}
  next_task_id = 1
end

return M
