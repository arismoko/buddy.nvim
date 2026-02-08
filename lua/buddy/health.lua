--- Health checks for buddy
--- Run with :checkhealth buddy
local M = {}

M.check = function()
  vim.health.start("buddy")

  -- Check Neovim version
  if vim.fn.has("nvim-0.10") == 1 then
    vim.health.ok("Neovim 0.10+ detected")
  else
    vim.health.warn("Neovim version is old", "Upgrade to 0.10+ for full compatibility")
  end

  -- Check nvim-nio dependency
  local nio_ok = pcall(require, "nio")
  if nio_ok then
    vim.health.ok("nvim-nio found")
  else
    vim.health.error("nvim-nio not found", {
      "Install nvim-nio with your plugin manager:",
      '  lazy.nvim: { "nvim-neotest/nvim-nio" }',
      "  rocks.nvim: :Rocks install nvim-nio",
    })
  end

  -- Check configuration
  local ok, config = pcall(require, "buddy.config")
  if not ok then
    vim.health.error("Failed to load config module", tostring(config))
    return
  end

  local opts = config.get()
  vim.health.ok("Configuration loaded")

  -- Check tools_dir
  local tools_dir = opts.tools_dir
  if tools_dir then
    local expanded = vim.fn.expand(tools_dir)
    if vim.fn.isdirectory(expanded) == 1 then
      vim.health.ok("tools_dir exists: " .. expanded)
    else
      vim.health.info("tools_dir does not exist yet: " .. expanded)
    end
  end

  -- Check tools registry
  local tools_ok, tools = pcall(require, "buddy.tools")
  if not tools_ok then
    vim.health.error("Failed to load tools registry", tostring(tools))
    return
  end

  local tool_list = tools.list()
  local count = vim.tbl_count(tool_list)
  if count > 0 then
    vim.health.ok(count .. " tools registered")
  else
    vim.health.info("No tools registered yet (call setup() first)")
  end

  -- Check server status
  vim.health.start("buddy server")

  local main_ok, main = pcall(require, "buddy")
  if not main_ok then
    vim.health.error("Failed to load main module", tostring(main))
    return
  end

  local status = main.status()
  if status.running then
    vim.health.ok("Server running on port " .. status.port)
  else
    vim.health.info("Server not running (start with :BuddyStart)")
  end

  -- Check host/port config
  vim.health.ok("Configured: " .. opts.host .. ":" .. opts.port)
  if opts.auto_start then
    vim.health.ok("auto_start enabled")
  else
    vim.health.info("auto_start disabled")
  end
end

return M
