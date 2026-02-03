# lua/buddy/

## Responsibility

The core buddy module provides the public API and lifecycle management for the buddy.nvim MCP server. It serves as the main entry point for users and coordinates between the HTTP server, MCP protocol handler, tool system, and configuration.

Key responsibilities:
- Provide user-facing API: `setup()`, `start()`, `stop()`, `restart()`, `status()`, `call()`, `register_tool()`
- Orchestrate server startup: load tools, start HTTP server, register sessions, enable hot reload
- Manage server lifecycle: port handling (fallback to ephemeral), connection tracking, graceful shutdown
- Expose programmatic tool execution: `call(tool_name, args)` for direct invocation
- Support runtime tool registration: `register_tool()` for dynamic tool addition
- Coordinate with multi-session system for running multiple buddy instances

## Design

### Module Structure
- **Single-module pattern**: `M` table with all public functions, private helpers as local functions
- **Singleton server**: `M._server` holds the HTTPServer instance
- **Configuration layering**: `config.lua` provides defaults → user config → merged state
- **Global bridge**: `_G.buddy.state` for UI component state sharing (e.g., picker items)

### Key Patterns
1. **Orchestration Pattern**: `start()` coordinates multiple subsystems:
   ```lua
   - Load builtins → Discover runtimepath → Start server → Register session → Enable hot reload
   ```

2. **Port Fallback Pattern**: If configured port is in use, automatically fall back to ephemeral port (port=0)

3. **Tool Discovery Pattern**: Extends runtimepath with each tool subdirectory (not just parent) to allow plugin-style tools

4. **Session Registry Pattern**: Multi-session support allows running buddy.nvim in multiple Neovim instances

### Configuration Architecture
```lua
defaults = {
  host = "127.0.0.1",
  port = 7234,
  auto_start = false,
  log_level = "info",
  watch = true,                    -- Hot reload file watching
  tools = { disabled = [] },      -- Disable specific tools
  buffer = { ignored_filetypes = [] }
}
```

### API Functions
- `setup(opts)`: Merge configuration with defaults (no-op if server already running)
- `start()`: Full server startup sequence (returns early if already running)
- `stop()`: Graceful shutdown: stop hot reload, unregister session, stop server, clear tools
- `restart()`: Stop + start (for config changes or hot reload triggers)
- `status()`: Return `{ running, host, port }` for health checks
- `call(tool_name, args)`: Execute tool programmatically (bypass MCP)
- `register_tool(tool, opts)`: Register tool at runtime (for dynamic plugins)

## Flow

### Setup Flow
```
require("buddy").setup({ port = 7234, auto_start = false })
  → config.setup(opts)
  → Deep merge defaults + opts
  → Store in module state (no server started yet)
```

### Start Flow
```
require("buddy").start()
  → Check if M._server exists (early return if yes)
  → tools.load_builtins()  (15+ tools from buddy.tools.builtin.*)
  → Extend runtimepath with buddy-tools/{tool}/* subdirectories
  → discovery.discover()    (find all lua/*/buddy.lua files)
  → server.start(host, port)
    → Create HTTPServer, bind to port
    → If port in use and fixed port, retry with port=0 (ephemeral)
    → Start listening, resolve actual port
  → M._server = server_instance
  → sessions.register({ host, port })  (multi-session registry)
  → hotreload.start_watching()  (if cfg.watch == true)
```

### Tool Call Flow
```
require("buddy").call("buffer", { action = "list" })
  → executor.execute("buffer", { action: "list" })
  → tools.get("buffer") → validate args → tool.run()
  → Return result or nil (with vim.notify on error)
```

### Runtime Tool Registration
```
require("buddy").register_tool({
  name = "my_tool",
  description = "Does something",
  input_schema = { ... },
  run = function(args, context) ... end
}, opts)
  → Build tool_def with id, runtime="plugin", opts
  → registry.register(tool_def)
  → Notify tools changed (MCP clients reload)
```

### Stop Flow
```
require("buddy").stop()
  → hotreload.stop_watching()
  → sessions.unregister()
  → server:stop()  (close all connections, shutdown TCP)
  → M._server = nil
  → tools.clear()  (remove all tools from registry)
```

## Integration

### Upward Dependencies (Modules this module uses)
- **buddy.config**: Configuration defaults and merged state
- **buddy.server**: HTTP/SSE server instance and lifecycle
- **buddy.tools**: Tool registry (load_builtins, clear, register_tool)
- **buddy.tools.discovery**: Runtimepath tool discovery
- **buddy.tools.hotreload**: File watching for development
- **buddy.tools.executor**: For direct tool execution via `call()`
- **buddy.sessions**: Multi-session registry

### Downward Dependencies (Modules that use this module)
- **plugin/buddy.lua**: Autoloads on VimEnter if `auto_start=true`
- **User config scripts**: Call `require("buddy").setup()` in init.lua
- **Health checks**: Call `buddy.status()` for diagnostics
- **Dynamic plugins**: Call `buddy.register_tool()` for runtime registration

### Server Integration
- HTTPServer created via `server.start(host, port)` and stored in `M._server`
- Server methods: `stop()`, `host`, `port` for lifecycle management
- Server callbacks: SSE manager wired up in first SSE connection

### Tool System Integration
- Built-in tools loaded via `tools.load_builtins()` from `buddy.tools.builtin.*`
- Runtimepath tools discovered via `discovery.discover()`
- Tool registry used for direct `call()` execution
- Hot reload watches tool files for changes

### Session Management
- Server instance registered in multi-session system
- Allows multiple Neovim instances to run buddy.nvim
- Sessions tracked by host/port tuple

### Configuration Flow
```
User config → setup() → config.setup() → defaults + opts → config.get()
                                                     ↓
                           start() → cfg = config.get() → use cfg.host, cfg.port, etc.
```

### Error Handling
- Server start failures: `pcall(server.start)`, fall back to ephemeral port
- Tool call failures: `pcall(executor.execute)`, `vim.notify` error messages
- Port conflicts: Automatic fallback, user notified via `vim.notify`
- Invalid tool registration: `error("Tool must have a name")`

### Logging
- Uses `vim.notify` for user-facing messages (server status, errors)
- Delegates debug logging to `buddy.log` module
- Health checks via `:checkhealth buddy`

### Testing
- `testing.lua`: Test utilities and fixtures
- Uses mini.test framework
- Mock server, tool registry for isolated tests
