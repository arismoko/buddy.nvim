--- Tool call orchestration service
--- Owns context construction, progress notification, result shaping, and error handling.
--- Decouples protocol handlers from executor internals.

local log = require("buddy.log")

---@class ToolService
---@field _executor table tools.executor module
---@field _notifier table|nil Notifier instance for progress notifications
---@field _client_requester table|nil ClientRequester for elicitation/sampling
local ToolService = {}
ToolService.__index = ToolService

-- Per-server singleton instance (set during server startup wiring)
local _instance = nil

--- Create a new ToolService
---@param opts table { notifier?: Notifier, client_requester?: ClientRequester }
---@return ToolService
function ToolService.new(opts)
  opts = opts or {}
  local self = setmetatable({}, ToolService)
  self._executor = require("buddy.tools.executor")
  self._notifier = opts.notifier
  self._client_requester = opts.client_requester
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
---@param _request_id any JSON-RPC request ID (for future cancellation binding)
---@return table MCP response { content, isError?, structuredContent? }
function ToolService:call(session_id, params, _request_id)
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

  -- Build executor options with context
  local exec_opts = {
    session_id = session_id,
    progress_token = progress_token,
    on_progress = progress_token and function(progress, total, message)
      self:_send_progress(session_id, progress_token, progress, total, message)
    end or nil,
  }

  -- Execute tool
  local ok, result = pcall(self._executor.execute, tool_name, args, exec_opts)

  if not ok then
    return errors.to_mcp_response(result)
  end

  return self:_shape_result(result, tool)
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
