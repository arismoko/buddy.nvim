local M = {}

local registry = require("buddy.tools")
local log = require("buddy.log")

---@param tool table
---@param path string
---@return boolean, string?
local function validate_tool(tool, path)
  if type(tool) ~= "table" then
    return false, "Tool must return a table: " .. path
  end
  if not tool.name or not tool.description then
    return false, "Tool missing name or description: " .. path
  end
  return true, nil
end

--- Discover tools from runtimepath (plugin-style tool packs)
--- Scans: lua/*/buddy.lua - registers tools with registry
function M.discover()
  log.debug("Discovering runtimepath tools")
  local count = 0
  
  -- Pattern: buddy.lua files
  local buddy_files = vim.api.nvim_get_runtime_file("lua/*/buddy.lua", true)
  
  for _, path in ipairs(buddy_files) do
    -- Pattern: lua/{plugin}/buddy.lua
    local prefix = path:match("lua/([^/]+)/buddy%.lua$")
    if prefix then
      local module = prefix .. ".buddy"
      
      -- Clear from package cache for hot reloading
      package.loaded[module] = nil
      
      local ok, pack = pcall(require, module)
      if ok and type(pack) == "table" then
        local tools_to_register = {}
        if pack.tools then
          -- Format 1: buddy.lua returns { tools = { tool1, tool2, ... } }
          tools_to_register = pack.tools
        else
          -- Format 2: buddy.lua returns a single tool table
          table.insert(tools_to_register, pack)
        end
        
        for _, tool in ipairs(tools_to_register) do
          local valid, err = validate_tool(tool, path)
          if valid then
            tool.runtime = "runtimepath"
            registry.register(tool)
            count = count + 1
          else
            log.warn(err)
          end
        end
      elseif not ok then
        log.warn("Failed to load buddy pack %s: %s", module, tostring(pack))
      end
    end
  end
  
  log.debug("Registered %d runtimepath tools", count)
end

--- Reload all runtimepath tools
function M.reload_all()
  log.debug("Reloading all tools")
  registry.clear_runtimepath_tools()
  M.discover()
end

--- Register a pack (internal helper for hotreload)
---@param pack table The buddy pack (single tool or { tools = {...} })
---@param path string Path to buddy.lua file
---@param prefix string Plugin prefix (e.g., "buddy_viz")
function M._register_pack(pack, path, prefix)
  if type(pack) ~= "table" then
    log.warn("Invalid pack from %s", path)
    return 0
  end

  local tools_to_register = {}
  if pack.tools then
    tools_to_register = pack.tools
  else
    table.insert(tools_to_register, pack)
  end

  local count = 0
  for _, tool in ipairs(tools_to_register) do
    local valid, err = validate_tool(tool, path)
    if valid then
      tool.runtime = "runtimepath"
      tool.source = prefix
      registry.register(tool)
      count = count + 1
    else
      log.warn(err)
    end
  end

  log.debug("Registered %d tools from %s", count, prefix)
  return count
end

--- Discover and register a single plugin (internal helper for hotreload)
---@param prefix string Plugin prefix
---@param path string Path to buddy.lua file
function M._discover_one(prefix, path)
  local module = prefix .. ".buddy"

  -- Clear from package cache
  package.loaded[module] = nil

  local ok, pack = pcall(require, module)
  if ok and type(pack) == "table" then
    M._register_pack(pack, path, prefix)
  elseif not ok then
    log.warn("Failed to load buddy pack %s: %s", module, tostring(pack))
  end
end

return M
