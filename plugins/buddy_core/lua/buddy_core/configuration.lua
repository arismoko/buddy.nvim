-- buddy_core: Configuration

local M = {}

M.options = {
  keymaps = {
    buddy_manager = nil,
    dotfyle_search = nil,
    lazy_manager = nil,
  },
}

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", M.options, opts or {})

  -- Apply keymaps
  local keymaps = M.options.keymaps or {}
  if keymaps.buddy_manager then
    vim.keymap.set("n", keymaps.buddy_manager, "<Plug>(BuddyManager)", { remap = true })
  end
  if keymaps.dotfyle_search then
    vim.keymap.set("n", keymaps.dotfyle_search, "<Plug>(DotfyleSearch)", { remap = true })
  end
  if keymaps.lazy_manager then
    vim.keymap.set("n", keymaps.lazy_manager, "<Plug>(LazyManager)", { remap = true })
  end
end

return M
