--- Lazy loading utilities for tools
local M = {}

local log = require("buddy.log")

-- Cache of loaded tools: path -> { tool, initialized }
local loaded_cache = {}

--- Create a lazy proxy for a tool
--- The proxy holds metadata but defers loading run/init/setup until first use
---@param tool_def table Tool definition (name, description, args, required)
---@param path string Path to tool file
---@param runtime string "runtimepath"
---@param module string|nil Module name for runtimepath tools
---@return table proxy
function M.create_proxy(tool_def, path, runtime, module)
  local proxy = {
    name = tool_def.name,
    description = tool_def.description,
    args = tool_def.args or {},
    required = tool_def.required or {},
    runtime = runtime,
    path = path,
    _module = module,
    _lazy = true,
  }

  --- Load the actual tool (called on first run)
  ---@return table tool
  function proxy:_load()
    -- Check cache first
    if loaded_cache[path] then
      log.debug("Using cached tool: %s", self.name)
      return loaded_cache[path].tool
    end

    log.debug("Lazy loading tool: %s from %s", self.name, path)

    local ok, tool
    if module then
      -- Clear from package cache to allow fresh load
      package.loaded[module] = nil
      ok, tool = pcall(require, module)
    else
      error("Tool must have a module for runtimepath loading: " .. self.name)
    end

    if not ok then
      error("Failed to load tool " .. self.name .. ": " .. tostring(tool))
    end

    -- Cache the loaded tool
    loaded_cache[path] = { tool = tool, initialized = false }

    return tool
  end

  --- Ensure tool is initialized (called before run)
  function proxy:_ensure_init()
    local cache_entry = loaded_cache[self.path]
    if cache_entry and cache_entry.initialized then
      return cache_entry.tool
    end

    local tool = self:_load()
    cache_entry = loaded_cache[self.path]

    -- Run init() if not yet done
    if not cache_entry.initialized and tool.init then
      log.debug("Calling init() for lazy tool: %s", self.name)
      local init_ok, err = pcall(tool.init)
      if not init_ok then
        log.warn("Tool %s init() failed: %s", self.name, tostring(err))
      end
    end

    cache_entry.initialized = true
    return tool
  end

  --- Lazy run - loads tool on first call
  ---@param args table
  ---@param callback? function
  ---@return any
  function proxy.run(args, callback)
    local tool = proxy:_ensure_init()
    if not tool.run then
      error("Tool has no run function: " .. proxy.name)
    end
    return tool.run(args, callback)
  end

  --- Dispose - called on hot-reload or shutdown
  function proxy.dispose()
    local cache_entry = loaded_cache[path]
    if cache_entry and cache_entry.tool and cache_entry.tool.dispose then
      log.debug("Calling dispose() for lazy tool: %s", proxy.name)
      pcall(cache_entry.tool.dispose)
    end
    loaded_cache[path] = nil
  end

  return proxy
end

--- Clear a specific tool from cache (for hot-reload)
---@param path string
function M.clear_cache(path)
  local cache_entry = loaded_cache[path]
  if cache_entry then
    -- Call dispose if available
    if cache_entry.tool and cache_entry.tool.dispose then
      log.debug("Disposing cached tool at: %s", path)
      pcall(cache_entry.tool.dispose)
    end
    loaded_cache[path] = nil
  end
end

--- Clear all cached tools
function M.clear_all()
  for path, _ in pairs(loaded_cache) do
    M.clear_cache(path)
  end
end

--- Clear cached tools by runtime type
---@param runtime string "lua" or "runtimepath"
function M.clear_by_runtime(runtime)
  local registry = require("buddy.tools")
  for _, tool in ipairs(registry.list()) do
    if tool.runtime == runtime and tool.path then
      M.clear_cache(tool.path)
    end
  end
end

--- Check if a tool is loaded
---@param path string
---@return boolean
function M.is_loaded(path)
  return loaded_cache[path] ~= nil
end

return M
