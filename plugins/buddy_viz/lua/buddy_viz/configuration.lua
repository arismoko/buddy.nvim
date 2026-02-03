-- buddy_viz: Configuration

local M = {}

M.options = {
  -- Viewer options: "builtin" (Kitty graphics), "external" (xdg-open), "command" (custom), "none"
  viewer = "external",
  -- Custom command for viewer = "command" mode (use %s for filepath)
  viewer_command = nil,
}

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", M.options, opts or {})
end

function M.get(key)
  return M.options[key]
end

return M
