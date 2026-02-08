--- *buddy.txt*  MCP server for Neovim
---
--- buddy is an MCP (Model Context Protocol) server for Neovim.
--- It enables AI assistants to interact with your editor through tools.
---
--- For tool reference, see |buddy-tools|.
---
--- Quick start: >lua
---   require("buddy").setup({
---     auto_start = true,
---     port = 7234,
---   })
--- <
---
--- Table of contents:
---@toc
---@tag buddy
---@toc_entry Introduction

local M = {}

M._server = nil
M._actual_port = nil
M._runtime = nil

--- Get or lazily create the runtime primitives (event bus, stores)
---
--- Returns a table with event_bus, session_store, and request_store instances.
--- Created once and reused for the lifetime of the server.
---
---@return table runtime { event_bus: BuddyEventBus, session_store: SessionStore, request_store: RequestStore }
function M.runtime()
  if not M._runtime then
    local EventBus = require("buddy.runtime.event_bus")
    local SessionStore = require("buddy.runtime.state.session_store")
    local RequestStore = require("buddy.runtime.state.request_store")
    M._runtime = {
      event_bus = EventBus.new(),
      session_store = SessionStore.new(),
      request_store = RequestStore.new(),
    }
  end
  return M._runtime
end

--- Setup buddy with the given options
---
---@param opts table|nil Configuration options
---@field host string Server host (default: "127.0.0.1")
---@field port number Server port (default: 7234)
---@field auto_start boolean Start server automatically (default: false)
---@field auth boolean Enable Bearer token auth on HTTP endpoints (default: true)
---@field watch boolean Enable hot reload file watching (default: true)
---@field debug boolean Enable debug logging (default: false)
---@field tools table Tool configuration
---@field tools.disabled string[] List of tool names to exclude (e.g., {"buffer", "diagnostics"})
---
---@usage `require("buddy").setup({ auto_start = true })`
---@usage `require("buddy").setup({ watch = false })` -- disable hot reload
---@usage `require("buddy").setup({ tools = { disabled = { "buffer", "diagnostics" } } })`
function M.setup(opts)
  local config = require("buddy.config")
  config.setup(opts)
end

--- Start the MCP server
---@return boolean success
function M.start()
  if M._server then
    vim.notify("[buddy] Already running", vim.log.levels.WARN)
    return
  end

  -- Load built-in tools
  local registry = require("buddy.tools")
  registry.load_builtins()

  -- Add each tool subdirectory to runtimepath (not just the parent)
  -- and source their plugin files (since we're past startup)
  local default_tools_dir = vim.fn.stdpath("data") .. "/buddy-tools"
  if vim.fn.isdirectory(default_tools_dir) == 1 then
    local rtp = vim.o.runtimepath
    for name, type in vim.fs.dir(default_tools_dir) do
      if type == "directory" then
        local tool_path = default_tools_dir .. "/" .. name
        local is_new = not rtp:find(tool_path, 1, true)
        if is_new then
          vim.o.runtimepath = vim.o.runtimepath .. "," .. tool_path
        end
        -- Source plugin files (Neovim doesn't auto-load after startup)
        if is_new then
          local plugin_dir = tool_path .. "/plugin"
          if vim.fn.isdirectory(plugin_dir) == 1 then
            for pname, ptype in vim.fs.dir(plugin_dir) do
              if ptype == "file" and pname:match("%.lua$") then
                local ok, err = pcall(vim.cmd.source, plugin_dir .. "/" .. pname)
                if not ok then
                  vim.notify("[buddy] Failed to source " .. pname .. ": " .. tostring(err), vim.log.levels.WARN)
                end
              end
            end
          end
        end
      end
    end
  end

  -- Discover runtimepath tools
  local discovery = require("buddy.tools.discovery")
  discovery.discover()

  -- Start server
  local server = require("buddy.server")
  local config = require("buddy.config")
  local cfg = config.get()

  -- Generate auth token if auth is enabled
  local auth_token = nil
  if cfg.auth then
    local uv = vim.uv
    -- Generate a cryptographically-sufficient random token from hrtime + pid + random
    local raw = string.format("%s:%s:%s:%s", uv.hrtime(), vim.fn.getpid(), math.random(1e9), uv.hrtime())
    auth_token = vim.fn.sha256(raw)
  end

  -- Set auth token on router before starting server so it's ready for first connection
  local router = require("buddy.server.router")
  router.set_auth_token(auth_token)

  local actual_port = server.start(cfg.host, cfg.port)
  M._server = server.get()
  M._actual_port = actual_port

  -- Register this session for multi-session support (use actual bound port)
  local sessions = require("buddy.sessions")
  sessions.cleanup_stale()  -- Clean up dead sessions first
  sessions.register({
    port = actual_port,
    host = cfg.host,
    auth_token = auth_token,
  })

  -- Start hot reload watching if enabled
  if cfg.watch then
    local hotreload = require("buddy.tools.hotreload")
    hotreload.start_watching()
  end
end

--- Stop the MCP server
---@return boolean success
function M.stop()
  -- Stop hot reload watching
  local hotreload = require("buddy.tools.hotreload")
  hotreload.stop_watching()

  -- Unregister session
  local sessions = require("buddy.sessions")
  sessions.unregister()

  if M._server then
    M._server:stop()
    M._server = nil
    M._actual_port = nil
  end

  -- Reset runtime singletons so next start() gets fresh state
  M._runtime = nil

  require("buddy.tools").clear()
end

function M.restart()
  M.stop()
  M.start()
end

--- Get server status
---@return table status { running: boolean, port: number|nil }
function M.status()
  if M._server then
    return { running = true, port = M._actual_port }
  end
  return { running = false }
end

--- Call a tool programmatically by name
---@param tool_name string The tool name to call
---@param args? table Arguments to pass to the tool
---@return table|nil result The tool result
function M.call(tool_name, args)
  local executor = require("buddy.tools.executor")
  local ok, result = pcall(executor.execute, tool_name, args or {})
  if not ok then
    vim.notify("[" .. tool_name .. "] Error: " .. tostring(result), vim.log.levels.ERROR)
    return nil
  end
  return result
end

--- Register a tool programmatically
---@param tool table Tool definition with name, description, args, required, and run function
---@param opts? table Optional configuration to pass to the tool
function M.register_tool(tool, opts)
  if not tool or not tool.name then
    error("Tool must have a name")
  end
  
  local registry = require("buddy.tools")
  
  local tool_def = {
    id = tool.name,
    name = tool.name,
    description = tool.description,
    args = tool.args or {},
    required = tool.required or {},
    runtime = "plugin",  -- Mark as plugin-registered (not from tools_dir)
    run = tool.run,
    setup = tool.setup,
    init = tool.init,
    dispose = tool.dispose,
    opts = opts,
  }
  
  registry.register(tool_def)
end

return M
