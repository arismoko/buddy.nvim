local M = {}
local tools = {}  -- name -> tool definition

--- Publish tools_changed event via event bus (if runtime available)
local function _notify_tools_changed()
  local ok, buddy = pcall(require, "buddy")
  if ok and buddy._runtime then
    buddy._runtime.event_bus:publish("tools_changed", {})
  end
end

function M.register(tool)
  -- Validate tool has required fields: name, description, run
  if not tool or not tool.name or not tool.description then
    error("Tool must have name and description fields")
  end

  -- Use id if provided, otherwise use name
  local key = tool.id or tool.name
  tools[key] = tool

  _notify_tools_changed()
end

function M.get(name)
  return tools[name]
end

function M.list()
  -- Return array of all tools, sorted by name
  local result = {}
  for _, tool in pairs(tools) do
    table.insert(result, tool)
  end
  table.sort(result, function(a, b) return a.name < b.name end)
  return result
end

function M.clear()
  tools = {}
  _notify_tools_changed()
end

--- Clear only runtimepath tools (tool packs from plugins)
function M.clear_runtimepath_tools()
  local to_remove = {}
  for key, tool in pairs(tools) do
    if tool.runtime == "runtimepath" then
      table.insert(to_remove, key)
    end
  end
  for _, key in ipairs(to_remove) do
    tools[key] = nil
  end

  if #to_remove > 0 then
    _notify_tools_changed()
  end
end

--- Clear tools from a specific source/prefix (for hot reload)
---@param source string The source prefix (e.g., "buddy_viz")
function M.clear_by_source(source)
  local to_remove = {}
  for key, tool in pairs(tools) do
    if tool.source == source then
      table.insert(to_remove, key)
    end
  end
  for _, key in ipairs(to_remove) do
    tools[key] = nil
  end

  if #to_remove > 0 then
    _notify_tools_changed()
  end
end

--- Check if a tool is disabled in config
---@param tool_name string
---@return boolean
local function is_disabled(tool_name)
  local config = require("buddy.config")
  local cfg = config.get()
  local disabled = cfg.tools and cfg.tools.disabled or {}
  for _, name in ipairs(disabled) do
    if name == tool_name then
      return true
    end
  end
  return false
end

function M.load_builtins()
  -- Load built-in tools from buddy.tools.builtin.*
  local builtin_path = "buddy.tools.builtin"
  local builtin_tools = {
    "buffer",
    "init",
    "command",
    "diagnostics",
    "edit",
    "fold",
    "grep",
    "macro",
    "navigation",
    "register",
    "search",
    "status",
    "tab",
    "visual",
    "window",
  }

  for _, name in ipairs(builtin_tools) do
    local ok, tool = pcall(require, builtin_path .. "." .. name)
    if ok and tool then
      -- Skip disabled tools
      local tool_name = tool.name or name
      if not is_disabled(tool_name) then
        M.register(tool)
      end
    end
  end
end

return M
