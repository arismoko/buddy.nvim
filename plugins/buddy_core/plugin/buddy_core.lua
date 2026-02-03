-- buddy_core: Commands and keymaps

if vim.g.loaded_buddy_core then
  return
end
vim.g.loaded_buddy_core = true

-- <Plug> mappings
vim.keymap.set("n", "<Plug>(BuddyManager)", function()
  require("buddy_core.tools.buddy_manager").open_picker()
end, { desc = "Open Buddy Manager" })

vim.keymap.set("n", "<Plug>(DotfyleSearch)", function()
  require("buddy_core.tools.dotfyle").open_picker()
end, { desc = "Search Dotfyle plugins" })

vim.keymap.set("n", "<Plug>(LazyManager)", function()
  require("buddy_core.tools.lazy_manager").open_picker()
end, { desc = "Browse lazy.nvim configs" })

-- User commands
vim.api.nvim_create_user_command("BuddyManager", function()
  require("buddy_core.tools.buddy_manager").open_picker()
end, { desc = "Open Buddy Manager" })

vim.api.nvim_create_user_command("DotfyleSearch", function(opts)
  require("buddy_core.tools.dotfyle").open_picker(opts.args)
end, { nargs = "?", desc = "Search Dotfyle plugins" })

vim.api.nvim_create_user_command("LazyManager", function(opts)
  require("buddy_core.tools.lazy_manager").open_picker(opts.args)
end, { nargs = "?", desc = "Browse lazy.nvim configs" })
