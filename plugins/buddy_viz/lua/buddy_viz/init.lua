-- buddy_viz: Public API

local M = {}

local configuration = require("buddy_viz.configuration")

function M.setup(opts)
  configuration.setup(opts)
end

-- Re-export tools for programmatic access
M.chart = require("buddy_viz.tools.chart")
M.image = require("buddy_viz.tools.image")
M.open = require("buddy_viz.tools.open")
M.pikchr = require("buddy_viz.tools.pikchr")

return M
