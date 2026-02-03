-- Image viewer tool
local helpers = require("buddy_viz.helpers")

local M = {}

function M.display(args)
  local path = vim.fn.expand(args.path)

  if vim.fn.filereadable(path) == 0 then
    return { error = "File not found: " .. path }
  end

  -- Check viz config for viewer preference
  local ok, viz_config = pcall(require, "buddy_viz.configuration")
  local viewer = ok and viz_config.get("viewer") or "builtin"

  if viewer == "builtin" then
    vim.schedule(function()
      helpers.open_viewer(path)
    end)
    return {
      success = true,
      message = "Opening image viewer for: " .. path .. "\n\nControls:\n  -/= : zoom out/in\n  hjkl/arrows : pan\n  r : reset\n  q/Esc : close",
    }
  else
    -- Use external viewer (xdg-open or custom command) - run async to avoid blocking
    local cmd = viewer == "xdg-open" and "xdg-open" or viewer
    vim.fn.jobstart({ cmd, path }, { detach = true })
    return {
      success = true,
      message = "Opening with " .. cmd .. ": " .. path,
    }
  end
end

return M
