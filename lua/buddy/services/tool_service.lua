--- Tool call orchestration service
--- Owns context construction, progress notification, result shaping, and error handling.
--- Decouples protocol handlers from executor internals.

local log = require("buddy.log")

---@class ToolService
---@field _executor table tools.executor module
---@field _notifier table|nil Notifier instance for progress notifications
---@field _client_requester table|nil ClientRequester for elicitation/sampling
---@field _request_store table|nil RequestStore for request→task binding
local ToolService = {}
ToolService.__index = ToolService

-- Per-server singleton instance (set during server startup wiring)
local _instance = nil

--- Create a new ToolService
---@param opts table { notifier?: Notifier, client_requester?: ClientRequester, request_store?: RequestStore }
---@return ToolService
function ToolService.new(opts)
  opts = opts or {}
  local self = setmetatable({}, ToolService)
  self._executor = require("buddy.tools.executor")
  self._notifier = opts.notifier
  self._client_requester = opts.client_requester
  self._request_store = opts.request_store
  return self
end

--- Set the shared instance (called during server wiring in router.lua)
---@param instance ToolService
function ToolService.set_instance(instance)
  _instance = instance
end

--- Get the shared instance
---@return ToolService|nil
function ToolService.get_instance()
  return _instance
end

--- Reset singleton (for testing)
function ToolService.reset()
  _instance = nil
end

--- Execute a tool call with full MCP context and result shaping
---
--- This is the primary entry point for `tools/call` handlers.
--- Constructs tool context (progress, elicit, sample), executes via executor,
--- and shapes the result into MCP-compatible response format.
---
---@param session_id string MCP session ID
---@param params table MCP tools/call params { name, arguments, _meta }
---@param request_id any JSON-RPC request ID (for cancellation binding)
---@return table MCP response { content, isError?, structuredContent? }
function ToolService:call(session_id, params, request_id)
  local errors = require("buddy.tools.errors")
  local tools = require("buddy.tools")

  if not params or not params.name then
    error("Missing required parameter: name")
  end

  local tool_name = params.name
  local tool = tools.get(tool_name)
  if not tool then
    error("Tool not found: " .. params.name)
  end

  local args = params.arguments or {}
  local progress_token = params._meta and params._meta.progressToken

  -- Build executor options with context (no callback — sync dispatch path).
  -- Async tools are detected by executor via cancel-function return value
  -- or explicit context.start_async() declaration.
  --
  -- Sync tools/call explicitly rejects async tools: the async task is cancelled
  -- immediately and an error response is returned. This prevents leaked async
  -- tasks that have no callback to deliver results to.
  -- All built-in buddy.nvim tools are synchronous.
  local exec_opts = {
    session_id = session_id,
    request_id = request_id,
    request_store = self._request_store,
    progress_token = progress_token,
    on_progress = progress_token and function(progress, total, message)
      self:_send_progress(session_id, progress_token, progress, total, message)
    end or nil,
  }

  -- Execute tool
  local ok, result_or_err, task_id = pcall(self._executor.execute, tool_name, args, exec_opts)

  if not ok then
    return errors.to_mcp_response(result_or_err)
  end

  -- Request→task binding is handled by executor (bound before tool.run(),
  -- unbound on completion/cancel/failure). No binding needed here.

  -- Async tool: result is nil, task_id is set.
  -- Cancel the leaked async task immediately so it doesn't dangle, then return
  -- an explicit error response from sync tools/call so clients do not
  -- misinterpret this as final tool output.
  if task_id then
    self._executor.cancel(task_id)
    -- Unbind request→task mapping (cancel doesn't have access to request_store)
    if self._request_store and request_id then
      self._request_store:unbind_tool_task(session_id, request_id)
    end
    return errors.to_mcp_response(errors.create(
      errors.codes.EXECUTION_ERROR,
      "Tool '" .. tool_name .. "' is async and cannot be invoked via sync tools/call (task " .. task_id .. " cancelled)",
      { tool = tool_name, task_id = task_id }
    ))
  end

  -- Sync tool completed — result_or_err is the actual result.
  return self:_shape_result(result_or_err, tool)
end

--- Send progress notification via notifier
---@param session_id string
---@param progress_token string|number
---@param progress number
---@param total number|nil
---@param message string|nil
function ToolService:_send_progress(session_id, progress_token, progress, total, message)
  if not self._notifier then
    return
  end
  self._notifier:notify(session_id, "notifications/progress", {
    progressToken = progress_token,
    progress = progress,
    total = total,
    message = message,
  })
end

--- Shape a raw tool result into MCP response format
---@param result any Raw result from executor
---@param tool table Tool definition (for output_schema)
---@return table MCP response
function ToolService:_shape_result(result, tool)
  local text_result
  local structured_result
  if type(result) == "table" then
    text_result = vim.json.encode(result)
    -- Include structuredContent if tool has outputSchema
    if tool.output_schema then
      structured_result = result
    end
  else
    text_result = tostring(result)
  end

  local response = {
    content = {
      {
        type = "text",
        text = text_result,
      },
    },
  }
  if structured_result then
    response.structuredContent = structured_result
  end
  return response
end

--- Cancel a running tool task
---@param task_id string
---@return boolean success
function ToolService:cancel(task_id)
  return self._executor.cancel(task_id)
end

return ToolService
