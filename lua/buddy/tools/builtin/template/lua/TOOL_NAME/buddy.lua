-- TOOL_NAME: MCP Tool Definition for buddy
-- ============================================================================
-- This file is discovered by buddy and exposes your plugin to AI agents.
--
-- PATTERN: buddy.lua is a thin MCP wrapper - it calls the plugin's PUBLIC API.
--
-- Your plugin works standalone as a Neovim plugin (with lazy.nvim opts = {}),
-- and buddy.lua adds MCP support for AI assistants.
-- ============================================================================

local plugin = require("TOOL_NAME")

return {
  name = "TOOL_NAME",
  -- title = "Human-Readable Tool Name",  -- Optional: display name for UI
  description = "TOOL_DESCRIPTION",
  -- annotations = {                       -- Optional: behavior hints for clients
  --   readOnlyHint = true,                -- Tool only reads, doesn't modify
  --   destructiveHint = false,            -- Tool may perform destructive actions
  --   idempotentHint = false,             -- Multiple calls have same effect as one
  -- },
  input_schema = {
    type = "object",
    properties = {
      input = { type = "string", description = "Input to process" },
    },
    required = { "input" },
  },
  run = function(args)
    local result = plugin.run(args.input)
    if type(result) == "table" and result.error then
      error(result.error)
    end
    if type(result) == "table" and result.message then
      return result.message
    end
    return result
  end,
}
