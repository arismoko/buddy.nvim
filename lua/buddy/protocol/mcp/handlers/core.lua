--- MCP core handlers: initialize, ping, logging/setLevel
local registry = require("buddy.protocol.mcp.registry")

local M = {}

-- Module-level state
local log_level = "info"

--- Export for log.lua to check
function M.get_log_level()
  return log_level
end

registry.register("ping", function(_session_id, _params)
  return vim.empty_dict()
end)

registry.register("initialize", function(session_id, params)
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
end)

registry.register("logging/setLevel", function(_session_id, params)
  if params and params.level then
    log_level = params.level
    local log = require("buddy.log")
    log.set_level(params.level)
  end
  return vim.empty_dict()
end)

return M
