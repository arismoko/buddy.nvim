-- buddy_viz: Configuration

local M = {}

M.options = {
  viewer = "builtin",
}

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", M.options, opts or {})
end

function M.get(key)
  return M.options[key]
end

return M
