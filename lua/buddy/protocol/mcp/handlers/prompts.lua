--- MCP prompts handlers: prompts/list, prompts/get
local registry = require("buddy.protocol.mcp.registry")

registry.register("prompts/list", function(_session_id, params)
  local _ = params and params.cursor  -- Accept cursor param (unused - no pagination needed)
  local prompts = require("buddy.prompts")
  return { prompts = prompts.list() }  -- omit nextCursor when no more pages
end)

registry.register("prompts/get", function(_session_id, params)
  if not params or not params.name then
    error("Missing required parameter: name")
  end
  local prompts = require("buddy.prompts")
  local result = prompts.get(params.name, params.arguments or {})
  if not result then
    error("Prompt not found: " .. params.name)
  end
  return result
end)
