-- TOOL_NAME: Neovim Plugin Entry Point
-- ============================================================================
-- Loaded automatically by Neovim. Defines commands and keymaps.
-- Plugin logic lazy-loads via require() inside callbacks.
-- ============================================================================

if vim.g.loaded_TOOL_NAME then
  return
end
vim.g.loaded_TOOL_NAME = true

-- User command
vim.api.nvim_create_user_command("ToolName", function(opts)
  require("TOOL_NAME").run(opts.args ~= "" and opts.args or nil)
end, {
  nargs = "?",
  desc = "TOOL_DESCRIPTION",
})

-- Optional: <Plug> mapping for user customization
-- vim.keymap.set("n", "<Plug>(ToolName)", function()
--   require("TOOL_NAME").run()
-- end, { desc = "Run TOOL_NAME" })
