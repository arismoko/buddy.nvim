-- buddy_core: Public API

local M = {}

local configuration = require("buddy_core.configuration")

function M.setup(opts)
  configuration.setup(opts)
end

-- Re-export tools for programmatic access
M.buddy_manager = require("buddy_core.tools.buddy_manager")
M.dotfyle = require("buddy_core.tools.dotfyle")
M.lazy_manager = require("buddy_core.tools.lazy_manager")

return M
