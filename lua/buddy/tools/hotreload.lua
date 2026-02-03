--- Hot reload system for buddy.nvim plugin tools
--- Handles watching, caching, and reloading of plugin Lua modules
local M = {}

local log = require("buddy.log")

---@class TrackedPlugin
---@field prefix string Plugin prefix (e.g., "buddy_viz")
---@field buddy_path string Path to buddy.lua file
---@field lua_dir string Path to lua directory
---@field watcher userdata|nil vim.uv fs_event handle
---@field last_reload number Timestamp of last reload

---@type table<string, TrackedPlugin>
local tracked_plugins = {}

---@type boolean
local watching = false

---@type number Debounce delay in milliseconds
local DEBOUNCE_MS = 100

---@type table<string, number> Last reload time per prefix for debouncing
local last_reload_times = {}

--- Clear all modules from package.loaded that match a prefix
--- Clears package.loaded[prefix] and package.loaded[prefix.*]
---@param prefix string Plugin prefix (e.g., "buddy_viz")
---@return number count Number of modules cleared
function M.clear_plugin_cache(prefix)
  local count = 0
  local to_clear = {}

  for module_name, _ in pairs(package.loaded) do
    -- Match exact prefix or prefix followed by dot
    if module_name == prefix or module_name:match("^" .. vim.pesc(prefix) .. "%.") then
      table.insert(to_clear, module_name)
    end
  end

  for _, module_name in ipairs(to_clear) do
    package.loaded[module_name] = nil
    count = count + 1
  end

  if count > 0 then
    log.debug("Cleared %d modules for prefix '%s'", count, prefix)
  end

  return count
end

--- Extract lua directory from buddy.lua path
---@param buddy_path string Path to buddy.lua
---@return string|nil lua_dir
local function extract_lua_dir(buddy_path)
  -- buddy_path: /path/to/lua/prefix/buddy.lua
  -- lua_dir: /path/to/lua/prefix
  local lua_dir = buddy_path:match("(.+)/buddy%.lua$")
  return lua_dir
end

--- Track a plugin for hot reloading
---@param prefix string Plugin prefix
---@param buddy_path string Path to buddy.lua file
function M.track_plugin(prefix, buddy_path)
  local lua_dir = extract_lua_dir(buddy_path)
  if not lua_dir then
    log.warn("Could not extract lua_dir from %s", buddy_path)
    return
  end

  tracked_plugins[prefix] = {
    prefix = prefix,
    buddy_path = buddy_path,
    lua_dir = lua_dir,
    watcher = nil,
    last_reload = 0,
  }

  log.debug("Tracking plugin: %s at %s", prefix, lua_dir)

  -- Start watcher if watching is enabled
  if watching then
    M._start_watcher(prefix)
  end
end

--- Stop tracking a plugin
---@param prefix string Plugin prefix
function M.untrack_plugin(prefix)
  local plugin = tracked_plugins[prefix]
  if not plugin then
    return
  end

  -- Stop watcher if exists
  if plugin.watcher then
    plugin.watcher:stop()
    plugin.watcher = nil
  end

  tracked_plugins[prefix] = nil
  log.debug("Untracked plugin: %s", prefix)
end

--- Reload a specific plugin
---@param prefix string Plugin prefix
---@return boolean success
---@return string|nil error
function M.reload_plugin(prefix)
  local plugin = tracked_plugins[prefix]
  if not plugin then
    return false, "Plugin not tracked: " .. prefix
  end

  -- Debounce check
  local now = vim.uv.now()
  local last = last_reload_times[prefix] or 0
  if now - last < DEBOUNCE_MS then
    log.debug("Debouncing reload for %s", prefix)
    return true, nil
  end
  last_reload_times[prefix] = now

  log.debug("Reloading plugin: %s", prefix)

  -- 1. Clear module cache
  M.clear_plugin_cache(prefix)

  -- 2. Clear registry tools from this source
  local registry = require("buddy.tools")
  registry.clear_by_source(prefix)

  -- 3. Clear lazy cache for this prefix
  local lazy = require("buddy.tools.lazy")
  lazy.clear_by_prefix(prefix)

  -- 4. Require the module and register tools
  local module_name = prefix .. ".buddy"
  local ok, pack = pcall(require, module_name)
  if not ok then
    log.warn("Failed to reload %s: %s", module_name, tostring(pack))
    return false, tostring(pack)
  end

  -- Register using discovery helper
  local discovery = require("buddy.tools.discovery")
  discovery._register_pack(pack, plugin.buddy_path, prefix)

  plugin.last_reload = vim.uv.now()

  vim.schedule(function()
    vim.notify("[buddy] Reloaded: " .. prefix, vim.log.levels.INFO)
  end)

  return true, nil
end

--- Reload all tracked plugins
---@return number count Number of plugins reloaded
function M.reload_all()
  local count = 0
  for prefix, _ in pairs(tracked_plugins) do
    local ok, _ = M.reload_plugin(prefix)
    if ok then
      count = count + 1
    end
  end
  return count
end

--- Start watcher for a specific plugin
---@param prefix string Plugin prefix
function M._start_watcher(prefix)
  local plugin = tracked_plugins[prefix]
  if not plugin then
    return
  end

  -- Stop existing watcher
  if plugin.watcher then
    plugin.watcher:stop()
    plugin.watcher = nil
  end

  -- Create directory watcher
  local watcher = vim.uv.new_fs_event()
  if not watcher then
    log.warn("Failed to create fs_event for %s", prefix)
    return
  end

  local ok = watcher:start(plugin.lua_dir, { recursive = true }, function(err, filename, events)
    if err then
      log.warn("Watcher error for %s: %s", prefix, err)
      return
    end

    -- Filter: only reload on .lua file changes, or if filename is nil (recursive event)
    if filename == nil or filename:match("%.lua$") then
      vim.schedule(function()
        M.reload_plugin(prefix)
      end)
    end
  end)

  if not ok then
    log.warn("Failed to start watcher for %s at %s", prefix, plugin.lua_dir)
    watcher:stop()
    return
  end

  plugin.watcher = watcher
  log.debug("Started watcher for %s at %s", prefix, plugin.lua_dir)
end

--- Stop watcher for a specific plugin
---@param prefix string Plugin prefix
function M._stop_watcher(prefix)
  local plugin = tracked_plugins[prefix]
  if not plugin or not plugin.watcher then
    return
  end

  plugin.watcher:stop()
  plugin.watcher = nil
  log.debug("Stopped watcher for %s", prefix)
end

--- Start watching all tracked plugins
function M.start_watching()
  if watching then
    return
  end

  watching = true

  for prefix, _ in pairs(tracked_plugins) do
    M._start_watcher(prefix)
  end

  -- Set up autocmd for runtimepath changes
  vim.api.nvim_create_autocmd("OptionSet", {
    pattern = "runtimepath",
    group = vim.api.nvim_create_augroup("BuddyHotReload", { clear = true }),
    callback = function()
      vim.schedule(function()
        M._rescan_runtimepath()
      end)
    end,
    desc = "buddy.nvim: Rescan runtimepath on change",
  })

  -- Also hook into lazy.nvim's LazyLoad event
  vim.api.nvim_create_autocmd("User", {
    pattern = "LazyLoad",
    group = vim.api.nvim_create_augroup("BuddyHotReloadLazy", { clear = true }),
    callback = function()
      vim.schedule(function()
        M._rescan_runtimepath()
      end)
    end,
    desc = "buddy.nvim: Rescan after lazy.nvim loads plugin",
  })

  log.debug("Started watching for hot reload")
end

--- Stop watching all plugins
function M.stop_watching()
  if not watching then
    return
  end

  watching = false

  for prefix, _ in pairs(tracked_plugins) do
    M._stop_watcher(prefix)
  end

  -- Remove autocmds
  pcall(vim.api.nvim_del_augroup_by_name, "BuddyHotReload")
  pcall(vim.api.nvim_del_augroup_by_name, "BuddyHotReloadLazy")

  log.debug("Stopped watching for hot reload")
end

--- Check if watching is enabled
---@return boolean
function M.is_watching()
  return watching
end

--- Rescan runtimepath for new/removed buddy.lua files
function M._rescan_runtimepath()
  local discovery = require("buddy.tools.discovery")
  local registry = require("buddy.tools")

  -- Get current buddy files
  local buddy_files = vim.api.nvim_get_runtime_file("lua/*/buddy.lua", true)
  local current_prefixes = {}

  for _, path in ipairs(buddy_files) do
    local prefix = path:match("lua/([^/]+)/buddy%.lua$")
    if prefix then
      current_prefixes[prefix] = path
    end
  end

  -- Find new plugins (in runtimepath but not tracked)
  for prefix, path in pairs(current_prefixes) do
    if not tracked_plugins[prefix] then
      log.debug("New plugin discovered: %s", prefix)
      discovery._discover_one(prefix, path)
    end
  end

  -- Find removed plugins (tracked but not in runtimepath)
  for prefix, _ in pairs(tracked_plugins) do
    if not current_prefixes[prefix] then
      log.debug("Plugin removed from runtimepath: %s", prefix)
      M.untrack_plugin(prefix)
      registry.clear_by_source(prefix)
    end
  end
end

--- Get list of tracked plugins
---@return TrackedPlugin[]
function M.list_tracked()
  local result = {}
  for _, plugin in pairs(tracked_plugins) do
    table.insert(result, plugin)
  end
  table.sort(result, function(a, b)
    return a.prefix < b.prefix
  end)
  return result
end

return M
