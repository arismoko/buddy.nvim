# buddy.nvim Codemap Documentation Summary

## Completed Documentation

I've filled in the codemap.md files for the 6 priority folders in the buddy.nvim repository:

### 1. Root codemap.md (`/codemap.md`)
**Documented**: Overall architecture of buddy.nvim as an MCP server for Neovim.

**Key sections**:
- **Responsibility**: HTTP/SSE MCP server exposing Neovim functionality as tools
- **Design**: Core architecture, tool pack pattern, dual interface pattern, async execution, hot reload
- **Flow**: Server startup, MCP request/response, tool execution, tool discovery
- **Integration**: Internal dependencies, external dependencies (mini.nvim, Neovim 0.10+), MCP protocol, client integration, Neovim integration

### 2. lua/buddy/codemap.md
**Documented**: Core buddy module providing public API and lifecycle management.

**Key sections**:
- **Responsibility**: Public API (setup, start, stop, restart, status, call, register_tool), server lifecycle orchestration
- **Design**: Single-module pattern, singleton server, configuration layering, global bridge
- **Flow**: Setup flow, start flow (load tools → discover → start server → register session → enable hot reload), tool call flow, runtime registration flow, stop flow
- **Integration**: Dependencies on config, server, tools, discovery, hotreload, sessions; used by plugin/buddy.lua and user configs

### 3. lua/buddy/server/codemap.md
**Documented**: HTTP + SSE server implementation on libuv.

**Key sections**:
- **Responsibility**: Custom HTTP/SSE server using vim.uv, request parsing, routing, SSE connections, broadcasting
- **Design**: HTTPServer class (OOP), SSEConnection class, SSEManager singleton, router pattern, connection tracking, manual HTTP parsing
- **Flow**: Server startup, HTTP request handling, request dispatch, SSE session creation, MCP request/response, notification broadcast, server shutdown, health check
- **Integration**: vim.uv for libuv, router for routing, mcp.handle_request for MCP handling, SSE connections for transport

### 4. lua/buddy/mcp/codemap.md
**Documented**: MCP 2025-06-18 protocol implementation and method handlers.

**Key sections**:
- **Responsibility**: JSON-RPC 2.0 validation/dispatch, MCP methods (initialize, tools, resources, prompts), notifications, content helpers, server-to-client requests
- **Design**: Table-based method dispatch, notification callback registry, session state, server capabilities, tool execution context, resource subscription, content helpers
- **Flow**: Request flow, initialize handshake, tool call, progress notifications, tool change notifications, resource subscription/updates, server-to-client elicitation, completion
- **Integration**: Depends on tools, resources, prompts modules; used by router for handling /message; provides notify_callback to router

### 5. lua/buddy/tools/codemap.md
**Documented**: Tool registry, execution engine, validation, discovery, hot reload.

**Key sections**:
- **Responsibility**: Tool registry, execution (sync/async with cancellation), validation, discovery (runtimepath tools), hot reload, error handling
- **Design**: Registry pattern (in-memory table), async execution pattern with task tracking, execution context (on_progress, elicit, sample), discovery pattern (lua/*/buddy.lua), JSON Schema validation, hot reload with file watching
- **Flow**: Tool registration, built-in loading, runtimepath discovery, sync tool execution, async tool execution, progress updates, elicitation, cancellation, hot reload, validation, error response
- **Integration**: Used by mcp.methods for tools/list and tools/call; uses mcp.methods for change notifications; integrates with hotreload for file watching

### 6. lua/buddy/tools/builtin/codemap.md
**Documented**: 15+ built-in tools for core Neovim operations.

**Key sections**:
- **Responsibility**: Core Neovim tools (buffer, edit, navigation, search, grep, diagnostics, window, tab, fold, visual, macro, register, status, command, init)
- **Design**: Each tool = separate file, action-based pattern, consistent format, MCP annotations (readOnlyHint, destructiveHint)
- **Flow**: Tool registration flow, buffer read flow, edit flow, navigation flow, grep flow, status check flow
- **Integration**: Uses vim.api extensively; registered via tools.load_builtins(); listed in tools/list; executed via tools/call

## Architecture Overview

The buddy.nvim system follows a clear layered architecture:

```
User Config (setup, auto_start)
    ↓
Core Module (init.lua) - Orchestration
    ↓
Server (HTTP/SSE on libuv) ←→ Router ←→ MCP Protocol Layer
    ↓                                ↓
Tool Registry              Method Handlers
    ↓                                ↓
Tool Executor           Built-in Tools (15+)
    ↓
Neovim API
```

**Key Design Patterns**:
1. **Tool Pack Pattern**: Single tool definition works as both MCP tool and Neovim plugin
2. **Action-Based Tools**: Many tools use `action` parameter to dispatch to sub-functions
3. **Async Execution**: Tools can return cancel function, call context(result) when done
4. **Hot Reload**: File watching with module cache clearing for development
5. **Notification Broadcast**: Changes broadcast to all active SSE sessions

## Data Flow Summary

**Request Flow**:
Client (MCP) → HTTP POST /message → Router → MCP handle_request → Method handler → Tool executor → Neovim API → Response via SSE

**Discovery Flow**:
Start → Load builtins → Discover runtimepath (lua/*/buddy.lua) → Register tools → Notify clients

**Hot Reload Flow**:
File change → fs_event → Clear old tools → Reload module → Register new tools → Notify clients → Clients refresh tool list

## Integration Points

**Internal Dependencies**:
- server/ ←→ mcp/ (protocol handling)
- mcp/ → tools/ (tool execution)
- tools/ → mcp/methods (change notifications)
- init.lua coordinates all subsystems

**External Dependencies**:
- mini.nvim (testing framework)
- Neovim 0.10+ (vim.uv, vim.api)
- No external HTTP library (custom on libuv)

**Client Integration**:
- Claude Desktop (http://127.0.0.1:7234/sse)
- OpenCode (same endpoint)
- Any MCP client (HTTP + SSE, JSON-RPC 2.0)

## Documentation Quality

Each codemap.md file includes:
- ✅ **Responsibility**: Clear statement of the module's job
- ✅ **Design**: Key patterns, architectural decisions, module structure
- ✅ **Flow**: Detailed step-by-step data/control flows with code examples
- ✅ **Integration**: How the module connects to other parts (upward/downward dependencies)

The documentation is thorough but concise, suitable for understanding the codebase architecture and navigating development tasks.
