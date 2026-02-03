# AGENTS.md - buddy.nvim

Guidelines for AI agents working in this Neovim plugin codebase.

## Project Overview

buddy.nvim is an MCP (Model Context Protocol) server for Neovim, written in Lua. It provides a bridge between AI agents and Neovim via HTTP/SSE endpoints.

## Build & Test Commands

```bash
# Dependencies (required before testing)
make deps          # Clone mini.nvim into deps/
make clean         # Remove deps/

# Testing
make test                              # Run all unit tests
make test-file FILE=tests/test_tools.lua  # Run single test file
make test-integration                  # HTTP/SSE endpoint tests (uses curl)
make test-all                          # Unit + integration tests

# Health check (inside Neovim)
:checkhealth buddy
```

## Code Style Guidelines

### Language & Runtime
- **Language**: Lua (LuaJIT)
- **Runtime**: Neovim's embedded Lua with `vim.uv` (libuv bindings)
- **Testing**: mini.test from mini.nvim
- **LSP Config**: `.luarc.json` configures LuaLS with Neovim globals

### Naming Conventions

| Element | Convention | Example |
|---------|------------|---------|
| Variables/Functions | snake_case | `tool_name`, `handle_request` |
| Private functions | _snake_case | `_accept`, `_dispatch` |
| Modules/Classes | PascalCase | `HTTPServer`, `JsonRpc` |
| Constants | SCREAMING_SNAKE | `MAX_BUFFER_SIZE` |

### Module Structure

```lua
local M = {}

local dep = require("buddy.dep")  -- Core deps at top

local function _private_helper()       -- Private: underscore prefix
end

---@param arg string Description
---@return table|nil result
---@return string|nil error
function M.public_api(arg)             -- Public: on M table
  local lazy = require("buddy.lazy")  -- Lazy load optional deps
  return result, nil
end

return M
```

### Type Annotations (LuaLS/EmmyLua)

```lua
---@class ToolDefinition
---@field name string Tool identifier
---@field description string Human-readable description
---@field args table<string, {type: string, description: string}>
---@field required? string[] Required argument names
---@field run fun(args: table, context: table): table Execution function
```

### Error Handling

1. **pcall** for external/unsafe operations - return `nil, error_message`
2. **error()** for programmer errors (invalid config, setup failures)
3. **vim.notify** for user-facing messages
4. **errors.throw()** for MCP protocol errors with codes

```lua
local ok, result = pcall(risky_operation)
if not ok then
  return nil, "Operation failed: " .. tostring(result)
end
```

### Tool Definition

```lua
return {
  name = "my_tool",
  description = "Brief description",
  args = {
    action = { type = "string", description = "The action to perform" },
    target = { type = "string", description = "Optional target" },
  },
  required = { "action" },
  run = function(args, context)
    -- context.on_progress for streaming updates
    -- context.elicit for user input
    -- context(result) for async completion
    return { success = true, data = "..." }
  end,
}
```

## Directory Structure

```
lua/buddy/
  init.lua          # Entry point, main API
  config.lua        # Configuration management
  bridge.lua        # Lua-to-MCP bridging
  health.lua        # :checkhealth integration
  log.lua           # Logging utilities
  mcp/              # MCP protocol (methods, schema, session)
  server/           # HTTP/SSE server (http.lua, sse.lua, router.lua)
  tools/            # Tool registry, executor, builtins
    builtin/        # Built-in tools (buffer, edit, navigation, etc.)
    executor.lua    # Sync/async tool execution with cancellation

plugins/            # Companion plugins
  buddy_core/       # Core utilities (lazy_manager, dotfyle, buddy_manager)
  buddy_viz/        # Visualization tools (charts, pikchr, images)

tests/              # Test files (test_*.lua)
```

## Testing Guidelines

Test files use `test_*.lua` naming in `tests/` directory.

```lua
local T = MiniTest.new_set()

T['hooks'] = {
  pre_case = function()
    package.loaded['buddy.module'] = nil  -- Fresh state
  end
}

T['feature()'] = MiniTest.new_set()

T['feature()']['does something'] = function()
  local mod = require('buddy.module')
  MiniTest.expect.equality(mod.fn(), expected)
end

T['feature()']['handles errors'] = function()
  MiniTest.expect.error(function()
    error_causing_code()
  end)
end

return T
```

## Common Patterns

### Scheduling (for main loop operations)
```lua
vim.schedule(function()
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
end)
```

### Safe JSON
```lua
local ok, decoded = pcall(vim.json.decode, json_string)
if not ok then return nil, "Invalid JSON" end
```

### Logging
```lua
local log = require("buddy.log")
log.debug("Processing %s", request_id)
log.error("Failed: %s", err)
```

### Async Tools
```lua
run = function(args, context)
  -- Start async work
  local handle = start_async_operation(function(result)
    context(result)  -- Call context to complete
  end)
  -- Return cancel function
  return function()
    handle:cancel()
  end
end
```

## Global Variables

- `vim` - Neovim API (always available)
- `MiniTest` - Testing framework (test context only)
