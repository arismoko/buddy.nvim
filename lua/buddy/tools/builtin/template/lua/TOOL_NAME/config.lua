-- TOOL_NAME: Configuration

local M = {}

M.options = {
  default_input = "hello",
  verbose = false,
}

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", M.options, opts or {})
end

return M
