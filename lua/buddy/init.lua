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

--- Setup buddy with the given options
---
---@param opts table|nil Configuration options
---@field host string Server host (default: "127.0.0.1")
---@field port number Server port (default: 7234)
---@field auto_start boolean Start server automatically (default: false)
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
  local default_tools_dir = vim.fn.stdpath("data") .. "/buddy-tools"
  if vim.fn.isdirectory(default_tools_dir) == 1 then
    local rtp = vim.o.runtimepath
    for name, type in vim.fs.dir(default_tools_dir) do
      if type == "directory" then
        local tool_path = default_tools_dir .. "/" .. name
        if not rtp:find(tool_path, 1, true) then
          vim.o.runtimepath = vim.o.runtimepath .. "," .. tool_path
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

  M._server = server.start(cfg.host, cfg.port)

  -- Register this session for multi-session support
  local sessions = require("buddy.sessions")
  sessions.register({
    port = cfg.port,
    host = cfg.host,
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
  end

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
    local config = require("buddy.config")
    return { running = true, port = config.get().port }
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
