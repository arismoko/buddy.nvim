local M = {}
local tools = require("buddy.tools")
local executor = require("buddy.tools.executor")

M._notify_callback = nil

-- Module-level subscription tracking
local subscriptions = {}

function M.set_notify_callback(callback)
  M._notify_callback = callback
end

function M.notify_tools_changed()
  if M._notify_callback then
    M._notify_callback({
      method = "notifications/tools/list_changed",
    })
  end
end

function M.notify_prompts_changed()
  if M._notify_callback then
    M._notify_callback({
      method = "notifications/prompts/list_changed",
    })
  end
end

function M.notify_resources_changed()
  if M._notify_callback then
    M._notify_callback({
      method = "notifications/resources/list_changed",
    })
  end
end

--- Notify subscribers that a resource was updated
---@param uri string The resource URI that changed
function M.notify_resource_updated(uri)
  if M._notify_callback then
    M._notify_callback({
      method = "notifications/resources/updated",
      params = { uri = uri },
    })
  end
end

--- Set up buffer change watching for resource notifications
--- Call this when a buffer is subscribed to
---@param bufnr number Buffer number
---@param uri string Resource URI
function M.watch_buffer(bufnr, uri)
  vim.api.nvim_buf_attach(bufnr, false, {
    on_lines = function()
      M.notify_resource_updated(uri)
      return false  -- keep watching
    end,
  })
end

--- Send cancellation notification to client
---@param request_id string|number The request ID to cancel
---@param reason? string Optional reason
function M.send_cancelled(request_id, reason)
  if M._notify_callback then
    M._notify_callback({
      method = "notifications/cancelled",
      params = {
        requestId = request_id,
        reason = reason,
      },
    })
  end
end

M["ping"] = function(_session_id, _params)
  return vim.empty_dict()
end

M["initialize"] = function(session_id, params)
  -- Store client capabilities for this session
  local session_state = require("buddy.mcp.session_state")
  session_state.initialize(session_id, params)

  return {
    protocolVersion = "2025-06-18",
    capabilities = {
      tools = { listChanged = true },
      logging = vim.empty_dict(),
      resources = { listChanged = true, subscribe = true },
      prompts = { listChanged = true },
      completion = vim.empty_dict(),
    },
    serverInfo = {
      name = "buddy",
      version = "2.0.0",
      title = "Neovim Buddy",
    },
    instructions = "buddy provides tools for interacting with Neovim. Tools prefixed with 'vim_' operate on the connected Neovim instance. Use vim_status to check current state before making changes. Use vim_diagnostics to check for errors after edits.",
  }
end

M["notifications/initialized"] = function(_session_id, _params)
  return nil
end

M["notifications/cancelled"] = function(_session_id, params)
  local log = require("buddy.log")
  if params and params.requestId then
    log.debug("Client cancelled request: %s", tostring(params.requestId))
    -- Future: could cancel in-progress tool execution
  end
  return nil  -- notifications don't return
end

M["notifications/roots/list_changed"] = function(session_id, _params)
  local log = require("buddy.log")
  log.info("Client workspace roots changed")

  -- Optionally refresh our cached roots
  local session_state = require("buddy.mcp.session_state")
  local state = session_state.get(session_id)
  if state then
    -- Clear cached roots so next roots.list() fetches fresh
    state.cached_roots = nil
  end

  return nil  -- notifications don't return
end

--- Handle progress notifications from client (for our server-to-client requests)
M["notifications/progress"] = function(_session_id, params)
  local log = require("buddy.log")
  if params then
    log.debug("Progress: %s/%s - %s",
      tostring(params.progress),
      tostring(params.total or "?"),
      params.message or "")
  end
  return nil  -- notifications don't return
end

-- Module-level state
local log_level = "info"

M["logging/setLevel"] = function(_session_id, params)
  if params and params.level then
    log_level = params.level
    local log = require("buddy.log")
    log.set_level(params.level)
  end
  return vim.empty_dict()
end

-- Export for log.lua to check
M.get_log_level = function()
  return log_level
end

M["tools/list"] = function(_session_id, params)
  local _ = params and params.cursor  -- Accept cursor param (unused - no pagination needed)
  local tool_list = tools.list()

  local mcp_tools = {}
  for _, tool in ipairs(tool_list) do
    local schema
    if tool.input_schema then
      schema = vim.deepcopy(tool.input_schema)
      -- Ensure properties is object not array for JSON encoding
      if schema.properties and next(schema.properties) == nil then
        schema.properties = vim.empty_dict()
      end
    else
      schema = { type = "object", properties = vim.empty_dict() }
    end

    local mcp_tool = {
      name = tool.name,
      description = tool.description or "",
      inputSchema = schema,
    }
    -- Optional fields - only include if present
    if tool.title then mcp_tool.title = tool.title end
    if tool.annotations then mcp_tool.annotations = tool.annotations end
    if tool.output_schema then mcp_tool.outputSchema = tool.output_schema end
    table.insert(mcp_tools, mcp_tool)
  end

  return { tools = mcp_tools }  -- omit nextCursor when no more pages
end

M["tools/call"] = function(session_id, params, _request_id)
  local errors = require("buddy.tools.errors")

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

  -- Execute tool with session context for server-to-client requests
  local ok, result = pcall(executor.execute, tool_name, args, {
    session_id = session_id,
    progress_token = progress_token,
    on_progress = progress_token and function(progress, total, message)
      if M._notify_callback then
        M._notify_callback({
          method = "notifications/progress",
          params = {
            progressToken = progress_token,
            progress = progress,
            total = total,
            message = message,
          },
        })
      end
    end or nil,
  })

  if not ok then
    return errors.to_mcp_response(result)
  end

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
        text = text_result
      }
    }
  }
  if structured_result then
    response.structuredContent = structured_result
  end
  return response
end

M["resources/list"] = function(_session_id, params)
  local _ = params and params.cursor  -- Accept cursor param (unused - no pagination needed)
  local resources = require("buddy.resources")
  return { resources = resources.list() }  -- omit nextCursor when no more pages
end

M["resources/templates/list"] = function(_session_id, params)
  local _ = params and params.cursor  -- Accept cursor param (unused - no pagination needed)
  local resources = require("buddy.resources")
  return { resourceTemplates = resources.list_templates() }  -- omit nextCursor when no more pages
end

M["resources/read"] = function(_session_id, params)
  if not params or not params.uri then
    error("Missing required parameter: uri")
  end
  local resources = require("buddy.resources")
  local content = resources.read(params.uri)
  if not content then
    error("Resource not found: " .. params.uri)
  end
  return { contents = content }
end

M["resources/subscribe"] = function(session_id, params)
  if not params or not params.uri then
    error("Missing required parameter: uri")
  end

  subscriptions[session_id] = subscriptions[session_id] or {}
  subscriptions[session_id][params.uri] = true

  return vim.empty_dict()
end

M["resources/unsubscribe"] = function(session_id, params)
  if not params or not params.uri then
    error("Missing required parameter: uri")
  end

  if subscriptions[session_id] then
    subscriptions[session_id][params.uri] = nil
  end

  return vim.empty_dict()
end

M["prompts/list"] = function(_session_id, params)
  local _ = params and params.cursor  -- Accept cursor param (unused - no pagination needed)
  local prompts = require("buddy.prompts")
  return { prompts = prompts.list() }  -- omit nextCursor when no more pages
end

M["prompts/get"] = function(_session_id, params)
  if not params or not params.name then
    error("Missing required parameter: name")
  end
  local prompts = require("buddy.prompts")
  local result = prompts.get(params.name, params.arguments or {})
  if not result then
    error("Prompt not found: " .. params.name)
  end
  return result
end

M["completion/complete"] = function(_session_id, params)
  if not params or not params.ref then
    error("Missing required parameter: ref")
  end

  local ref = params.ref
  local argument = params.argument or {}
  local values = {}

  -- Handle prompt argument completion
  if ref.type == "ref/prompt" then
    local prompt_name = ref.name
    local arg_name = argument.name

    -- Provide suggestions based on prompt and argument
    if prompt_name == "refactor_selection" and arg_name == "goal" then
      values = {
        { value = "simplify", description = "Simplify complex code" },
        { value = "extract", description = "Extract to function/variable" },
        { value = "rename", description = "Improve naming" },
        { value = "dry", description = "Remove duplication" },
      }
    elseif prompt_name == "write_tests" and arg_name == "framework" then
      values = {
        { value = "mini.test", description = "mini.nvim test framework" },
        { value = "plenary", description = "Plenary test framework" },
        { value = "busted", description = "Busted test framework" },
      }
    elseif prompt_name == "explain_buffer" and arg_name == "focus" then
      values = {
        { value = "overall structure", description = "High-level overview" },
        { value = "error handling", description = "How errors are handled" },
        { value = "performance", description = "Performance considerations" },
        { value = "dependencies", description = "External dependencies" },
      }
    end
    -- Handle resource URI completion
  elseif ref.type == "ref/resource" then
    -- Suggest buffer URIs
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(bufnr) then
        local name = vim.api.nvim_buf_get_name(bufnr)
        if name and name ~= "" then
          table.insert(values, {
            value = "vim://buffer/" .. bufnr,
            description = vim.fn.fnamemodify(name, ":t"),
          })
        end
      end
    end
  end

  return {
    completion = {
      values = values,
      total = #values,
      hasMore = false,
    },
  }
end

-- Export helper for creating image content
M.image_content = function(base64_data, mime_type)
  return {
    type = "image",
    data = base64_data,
    mimeType = mime_type or "image/png",
  }
end

--- Create an AudioContent block
---@param base64_data string Base64-encoded audio data
---@param mime_type string MIME type (e.g., "audio/wav", "audio/mp3", "audio/ogg")
---@return table
function M.audio_content(base64_data, mime_type)
  return {
    type = "audio",
    data = base64_data,
    mimeType = mime_type,
  }
end

M.resource_content = function(uri, mime_type, text)
  return {
    type = "resource",
    resource = {
      uri = uri,
      mimeType = mime_type or "text/plain",
      text = text,
    },
  }
end

--- Create an EmbeddedResource content block
--- Use when returning actual resource content in a tool response
---@param uri string Resource URI
---@param text string Text content
---@param mime_type? string MIME type (default: text/plain)
---@return table
function M.embedded_resource(uri, text, mime_type)
  return {
    type = "resource",
    resource = {
      uri = uri,
      mimeType = mime_type or "text/plain",
      text = text,
    },
  }
end

--- Create an EmbeddedResource with binary blob
---@param uri string Resource URI
---@param blob string Base64-encoded binary data
---@param mime_type string MIME type
---@return table
function M.embedded_blob(uri, blob, mime_type)
  return {
    type = "resource",
    resource = {
      uri = uri,
      mimeType = mime_type,
      blob = blob,
    },
  }
end

--- Create a ResourceLink content block (reference without content)
---@param uri string Resource URI
---@param name string Human-readable name (required)
---@param description? string Description
---@param mime_type? string MIME type
---@return table
function M.resource_link(uri, name, description, mime_type)
  if not name or name == "" then
    error("ResourceLink requires a name")
  end
  local link = {
    type = "resource_link",
    uri = uri,
    name = name,
  }
  if description then link.description = description end
  if mime_type then link.mimeType = mime_type end
  return link
end

return M
