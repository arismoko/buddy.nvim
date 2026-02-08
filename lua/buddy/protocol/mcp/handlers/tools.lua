--- MCP tools handlers: tools/list, tools/call
local registry = require("buddy.protocol.mcp.registry")
local tools = require("buddy.tools")
local executor = require("buddy.tools.executor")

registry.register("tools/list", function(_session_id, params)
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
end)

registry.register("tools/call", function(session_id, params, _request_id)
  local errors = require("buddy.tools.errors")
  local methods = require("buddy.mcp.methods")

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
      if methods._notify_callback then
        methods._notify_callback({
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
        text = text_result,
      },
    },
  }
  if structured_result then
    response.structuredContent = structured_result
  end
  return response
end)
