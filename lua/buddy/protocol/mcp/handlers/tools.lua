--- MCP tools handlers: tools/list, tools/call
local registry = require("buddy.protocol.mcp.registry")
local tools = require("buddy.tools")
local log = require("buddy.log")

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

registry.register("tools/call", function(session_id, params, request_id)
  local ToolService = require("buddy.services.tool_service")
  local service = ToolService.get_instance()

  -- Fallback: create an unwired instance if no singleton set (e.g., direct tests).
  -- WARNING: This fallback has no notifier, request_store, or client_requester,
  -- so progress notifications, cancellation binding, and elicitation will not work.
  if not service then
    log.debug("tools/call: no ToolService singleton set, using unwired fallback (test-only path)")
    service = ToolService.new()
  end

  return service:call(session_id, params, request_id)
end)
