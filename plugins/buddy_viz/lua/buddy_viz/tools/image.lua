-- Image viewer tool
local helpers = require("buddy_viz.helpers")

local M = {}

function M.display(args)
  local path = vim.fn.expand(args.path)

  if vim.fn.filereadable(path) == 0 then
    return { error = "File not found: " .. path }
  end

  vim.schedule(function()
    helpers.open_image(path)
  end)

  return {
    success = true,
    message = "Opening image: " .. path,
  }
end

return M
