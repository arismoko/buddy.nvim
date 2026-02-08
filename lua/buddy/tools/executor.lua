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
    if task and task.cancelled then
      log.debug("Ignoring result from cancelled task %s", task_id)
      running_tasks[task_id] = nil
      return
    end
    log.debug("Async tool %s completed (task %s)", tool_id, task_id)
    running_tasks[task_id] = nil
    callback(nil, result)
  end

  -- Make progress callback available to tool run function
  local context = {
    on_progress = on_progress,
    session_id = opts.session_id,
  }

  -- Add elicitation capability if session_id is available
  if opts.session_id then
    context.elicit = function(message, schema)
      local client_requests = require("buddy.mcp.client_requests")
      return client_requests.elicitation_create(opts.session_id, {
        message = message,
        requestedSchema = schema,
      })
    end
    context.sample = function(params)
      local client_requests = require("buddy.mcp.client_requests")
      return client_requests.sampling_create_message(opts.session_id, params)
    end
  end

  -- Allow tools to use context as a callback for async completion
  setmetatable(context, {
    __call = function(_, result)
      if async_callback then
        async_callback(result)
      end
    end,
  })

  -- Pass context as second arg to run
  local ok, cancel_or_result = pcall(tool.run, args, context)
  if not ok then
    log.error("Tool execution failed: %s", tostring(cancel_or_result))
    errors.throw(errors.codes.EXECUTION_ERROR, "Tool execution failed: " .. tostring(cancel_or_result), { tool = tool_id })
  end

  -- If cancel_or_result is a function, it's a cancel fn (async tool)
  if type(cancel_or_result) == "function" and callback then
    running_tasks[task_id] = {
      cancel_fn = cancel_or_result,
      cancelled = false,
      callback = callback,
      tool_id = tool_id,
    }
    log.debug("Tool %s running async (task %s)", tool_id, task_id)
    return nil, task_id
  end

  -- If result is nil and callback provided, async tool without cancel fn
  if cancel_or_result == nil and callback then
    running_tasks[task_id] = {
      cancel_fn = nil,
      cancelled = false,
      callback = callback,
      tool_id = tool_id,
    }
    log.debug("Tool %s running async without cancel (task %s)", tool_id, task_id)
    return nil, task_id
  end

  -- Sync tool - return result directly
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

  -- Notify callback with cancellation error
  if task.callback then
    task.callback(errors.create(errors.codes.CANCELLED, "Task cancelled"), nil)
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

return M
