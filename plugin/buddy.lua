if vim.g.loaded_buddy then
  return
end
vim.g.loaded_buddy = true

-- Commands
vim.api.nvim_create_user_command("BuddyStart", function()
  require("buddy").start()
end, { desc = "Start buddy MCP server" })

vim.api.nvim_create_user_command("BuddyStop", function()
  require("buddy").stop()
end, { desc = "Stop buddy MCP server" })

vim.api.nvim_create_user_command("BuddyRestart", function()
  require("buddy").restart()
end, { desc = "Restart buddy MCP server" })

vim.api.nvim_create_user_command("BuddyStatus", function()
  local status = require("buddy").status()
  if status.running then
    print("[buddy] Running on port " .. status.port)
  else
    print("[buddy] Stopped")
  end
end, { desc = "Show buddy status" })

vim.api.nvim_create_user_command("BuddyInstallExamples", function()
  require("buddy").reinstall_examples()
end, { desc = "Reinstall buddy example tools" })

vim.api.nvim_create_user_command("BuddyReloadTools", function()
  require("buddy.tools.discovery").reload_all()
  print("[buddy] All tools reloaded")
end, { desc = "Reload all buddy tools (user + runtimepath)" })

-- Auto-start if configured
vim.api.nvim_create_autocmd("VimEnter", {
  callback = function()
    local config = require("buddy.config")
    if config.get().auto_start then
      vim.schedule(function()
        require("buddy").start()
      end)
    end
  end,
  desc = "Auto-start buddy if configured",
})

-- Clean up on quit
vim.api.nvim_create_autocmd("VimLeavePre", {
  callback = function()
    local buddy = require("buddy")
    if buddy._server then
      buddy.stop()
    end
  end,
  desc = "Stop buddy and unregister session on quit",
})
