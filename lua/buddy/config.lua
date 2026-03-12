--- Configuration options for buddy.
---@tag buddy-config
---@toc_entry Configuration
local M = {}

---@private
local defaults = {
  host = "127.0.0.1",  -- Loopback only by default for security
  port = 7234,
  auto_start = false,
  auth = true,  -- Require Bearer token auth on HTTP endpoints (recommended)
  watch = true,  -- Enable hot reload file watching
  log_level = "info",
  extras = {},  -- Companion plugins to activate, e.g. { "buddy_core", "buddy_viz" }
  tools = {
    disabled = {},  -- List of tool names to exclude (e.g., {"vim_buffer", "vim_diagnostics"})
  },
  buffer = {
    ignored_filetypes = {},  -- Filetypes to hide from buffer list (e.g., {"opencode_terminal"})
  },
}

local current = vim.deepcopy(defaults)

---@private
function M.setup(opts)
  current = vim.tbl_deep_extend("force", defaults, opts or {})
end

---@private
function M.get()
  return current
end

return M
