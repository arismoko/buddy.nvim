-- TOOL_NAME: Public API
-- ============================================================================
-- This is the main plugin module and PUBLIC API.
--
-- Usage with lazy.nvim:
--   { "your-name/TOOL_NAME", opts = { default_input = "world" } }
-- ============================================================================

local config = require("TOOL_NAME.config")

local M = {}

--- Setup the plugin with user options
--- Called automatically by lazy.nvim when using opts = {}
---@param opts? table User configuration options
function M.setup(opts)
  config.setup(opts)
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

--- Main entry point for the tool
---@param input? string Input to process
---@return string result The processed result
function M.run(input)
  input = input or config.options.default_input

  -- ========================================
  -- YOUR LOGIC HERE
  -- ========================================
  local result = string.format("Processed: %s", input)

  print(result)
  return result
end

return M
