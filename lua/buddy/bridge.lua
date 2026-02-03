-- lua/buddy/bridge.lua
-- Global state bridge for plugins

_G.buddy = _G.buddy or {}

-- Shared state for UI components (e.g., picker items)
_G.buddy.state = {}

local M = {}

--- Clear the bridge state
function M.clear()
  _G.buddy.state = {}
end

return M
