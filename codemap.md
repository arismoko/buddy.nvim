# 2026-01-26-nvim-buddy-v3/

## Responsibility

buddy.nvim is an MCP (Model Context Protocol) server for Neovim that enables AI assistants to interact with the editor through tools. It provides a bridge between AI clients (like Claude Desktop, OpenCode) and Neovim, exposing editor functionality as MCP tools via HTTP/SSE endpoints.

Key responsibilities:
- Run an HTTP + SSE server compatible with MCP clients
- Discover and manage tools from both built-in sources and runtimepath plugins
- Execute Neovim operations (buffer manipulation, navigation, editing, etc.) on behalf of AI clients
- Support dual-mode tools: callable via MCP and as standard Neovim plugins (keymaps, commands, autocmds)
- Provide hot-reload of tool definitions for development workflow
- Maintain session state and broadcast notifications for tool/resource changes

## Design

### Core Architecture
- **Server-first design**: HTTP/SSE server using `vim.uv` (libuv) for async I/O
- **Plugin-style tool discovery**: Tools defined in `lua/*/buddy.lua` format, auto-discovered from runtimepath
- **Unified tool format**: Single tool definition works for both MCP and Neovim plugin interfaces
- **MCP 2025-06-18 protocol**: Implements latest MCP specification with tools, resources, and prompts

### Key Patterns
1. **Tool Pack Pattern**: Two formats for defining tools:
   - Simple list: `{ tools = { tool1, tool2, ... } }`
   - Action-based: `{ name = "viz", actions = { image = require("viz.tools.image") } }`

2. **Dual Interface Pattern**: Tools include optional `setup` block with:
   - `keymaps`: Neovim keymap definitions
   - `commands`: Ex commands
   - `autocmds`: Autocmd definitions

3. **Async Execution Pattern**: Tools can return a cancel function for async operations, with context callback for completion

4. **Hot Reload Pattern**: File watching with module cache clearing for development iteration

### Module Organization
```
lua/buddy/
  init.lua           # Public API (setup, start, stop, status, call, register_tool)
  config.lua         # Configuration management with defaults
  bridge.lua         # Global state bridge for UI components
  log.lua            # Logging utilities
  health.lua         # :checkhealth integration
  sessions.lua       # Multi-session registry for server instances
  prompts.lua        # Prompt template management
  resources.lua      # MCP resource definitions
  testing.lua        # Testing utilities
  
  server/            # HTTP/SSE server implementation
  mcp/               # MCP protocol handler and method implementations
  tools/             # Tool registry, execution, discovery, validation
    builtin/         # 15+ built-in tools for core Neovim operations
```

## Flow

### Server Startup Flow
1. User calls `require("buddy").setup({ ... })` - merges config with defaults
2. User calls `require("buddy").start()`:
   - Loads built-in tools from `buddy.tools.builtin.*`
   - Adds `~/.local/share/nvim/site/buddy-tools/*` to runtimepath
   - Discovers runtimepath tools via `lua/*/buddy.lua` pattern
   - Starts HTTP server on configured host/port (fallback to ephemeral if port in use)
   - Registers session in multi-session registry
   - Starts file watcher for hot reload if enabled

### MCP Request Flow
1. Client connects to `/sse` endpoint → creates SSE session with unique ID
2. Client POSTs to `/message?sessionId=XYZ` with JSON-RPC 2.0 request
3. Router validates JSON, extracts sessionId, finds SSE connection
4. If response (client-to-server), handled by `client_requests` module
5. If request, dispatched to `mcp.handle_request()`:
   - Validates JSON-RPC 2.0 format
   - Routes to appropriate method handler in `mcp.methods`
   - Methods may call `tools.execute()` with session context
   - Response sent back via SSE stream (unnamed event for SDK compatibility)
6. Notifications (tools/prompts/resources changed) broadcast to all active SSE sessions

### Tool Execution Flow
1. MCP client calls `tools/call` with tool name and arguments
2. Router → `mcp.methods["tools/call"]` → `tools.execute(tool_name, args, context)`
3. Executor validates tool exists, validates input against schema
4. Creates async context with:
   - `on_progress`: Progress callback to client
   - `elicit`: Solicit user input via MCP
   - `sample`: Request completion from client's model
5. Calls `tool.run(args, context)`:
   - Sync: Returns result directly
   - Async: Returns cancel function, calls `context(result)` when done
6. Result wrapped in MCP content format (`{ content = [{ type = "text", text = "..." }] }`)

### Tool Discovery Flow
1. `tools.discover()` scans `lua/*/buddy.lua` via `nvim_get_runtime_file()`
2. For each plugin (e.g., `lua/viz/buddy.lua`):
   - Clears module cache for hot reload
   - Requires plugin's buddy module
   - Validates tool pack format
   - Registers tools with `runtime="runtimepath"` and `_source="viz"`
   - Tracks file for hot reload monitoring
3. Tools available immediately to MCP clients and Neovim keymaps/commands

## Integration

### Internal Dependencies
- **server/** depends on: `mcp.methods`, `mcp.client_requests` (for handling client responses)
- **mcp/** depends on: `tools`, `resources`, `prompts` (for tool/resource/prompt lists)
- **tools/** depends on: `mcp.methods` (for change notifications), `config` (for disabled tools)
- All modules depend on: `log` (logging), `config` (configuration)

### External Dependencies
- **mini.nvim**: Testing framework (`mini.test`)
- **Neovim 0.10+**: `vim.uv` (libuv), `vim.json`, `vim.api` (Neovim API)
- **No HTTP library**: Custom HTTP implementation on top of libuv TCP

### Protocol Integration
- **MCP 2025-06-18**: Full implementation of:
  - `initialize` / `notifications/initialized` handshake
  - `tools/list`, `tools/call`
  - `resources/list`, `resources/read`, `resources/subscribe` + change notifications
  - `prompts/list`, `prompts/get` + change notifications
  - `completion/complete` for argument suggestions
  - `notifications/cancelled`, `notifications/progress`, `logging/setLevel`

### Client Integration
- **Claude Desktop**: Connects to `http://127.0.0.1:7234/sse`
- **OpenCode**: Same endpoint, via `"type": "remote"` in config
- **Any MCP client**: HTTP + SSE transport, JSON-RPC 2.0 over POST + server-sent events

### Neovim Integration
- **`:checkhealth buddy`**: Health checks for server status, tool loading
- **Keymaps/Commands**: Tools can register Neovim interfaces via `setup` block
- **LSP Diagnostics**: Built-in `diagnostics` tool exposes LSP data to AI
- **Buffer watching**: `mcp.methods.watch_buffer()` for resource change notifications

### Plugin System Integration
- **runtimepath-based discovery**: Any Neovim plugin can add tools by including `lua/{plugin}/buddy.lua`
- **buddy-tools directory**: `~/.local/share/nvim/site/buddy-tools/{tool}/` for user tools
- **Hot reload**: Editing tool files auto-reloads without Neovim restart
- **Companion plugins**: `plugins/buddy_core/`, `plugins/buddy_viz/` provide additional tool packs
