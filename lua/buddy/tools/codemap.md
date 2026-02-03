# lua/buddy/tools/

## Responsibility

The tools module provides the tool registry, execution engine, validation, discovery system, and hot reload capabilities for buddy.nvim. It manages the lifecycle of all tools (built-in, runtimepath, and dynamically registered) and provides the execution context for MCP tool calls.

Key responsibilities:
- **Registry**: Store and retrieve tool definitions (name, description, input_schema, run function)
- **Discovery**: Auto-discover tools from runtimepath (`lua/*/buddy.lua`) and built-in sources
- **Execution**: Execute tools with validation, async support, and cancellation
- **Validation**: Validate tool arguments against JSON Schema (properties, required)
- **Hot Reload**: Watch tool files for changes and reload without Neovim restart
- **Change Notifications**: Notify MCP clients when tools change
- **Error Handling**: Convert errors to MCP error responses

## Design

### Module Structure
```
tools/
  init.lua           # Tool registry (register, get, list, clear, load_builtins)
  executor.lua       # Tool execution (sync/async, cancellation, context)
  discovery.lua      # Runtimepath tool discovery (lua/*/buddy.lua)
  validate.lua       # JSON Schema validation for tool arguments
  errors.lua         # MCP error codes and error handling
  lazy.lua           # Lazy-loading support for tool dependencies
  hotreload.lua      # File watching and hot reload system
```

### Tool Definition Format
```lua
return {
  name = "tool_name",
  title = "Tool Title",           -- Optional: human-readable title
  description = "What the tool does",
  annotations = {                  -- Optional: MCP annotations
    readOnlyHint = true,
    destructiveHint = true,
  },
  input_schema = {                 -- JSON Schema for arguments
    type = "object",
    properties = {
      action = { type = "string", enum = { "a", "b" }, description = "..." },
      param = { type = "number", description = "..." },
    },
    required = { "action" },
  },
  output_schema = { ... },         -- Optional: output structure schema
  run = function(args, context)   -- Handler function
    -- Sync: return { success: true, ... }
    -- Async: return cancel_function (call context(result) when done)
    -- Context provides: on_progress, elicit, sample, session_id
  end,
  setup = {                        -- Optional: Neovim plugin interface
    keymaps = { { "n", "<leader>mt", fn, { desc = "..." } } },
    commands = { { "MyTool", fn, nargs = "?" } },
    autocmds = { { "BufEnter", "*", callback = fn } },
  },
}
```

### Registry Pattern (init.lua)
- **In-memory table**: `tools = { [tool_name] = tool_def }`
- **Register**: `tools[key] = tool` (key = tool.id or tool.name)
- **Get/List**: `tools[name]`, `list()` (sorted array)
- **Runtime tagging**: `tool.runtime = "runtimepath"` for plugin tools
- **Source tracking**: `tool._source = "plugin_name"` for hot reload

### Async Execution Pattern (executor.lua)
- **Sync tools**: `run()` returns `{ success: true, ... }` directly
- **Async tools**: `run()` returns cancel function, calls `context(result)` when done
- **Task tracking**: `running_tasks = { [task_id] = { cancel_fn, cancelled, callback } }`
- **Cancellation**: Call cancel function, mark cancelled, ignore late results
- **Context metatable**: `context` is callable → `context(result)` completes async

### Execution Context
```lua
context = {
  session_id = "session_id",        -- For server-to-client requests
  progress_token = "token",          -- For progress updates
  on_progress = function(progress, total, message)
    -- Sends notifications/progress to client
  end,
  elicit = function(message, schema)
    -- Requests user input via requests/elicitation
  end,
  sample = function(params)
    -- Requests model completion via requests/completion
  end,
  -- Context is callable for async completion
  __call = function(_, result)
    -- Calls async_callback(result)
  end,
}
```

### Discovery Pattern (discovery.lua)
- **Runtimepath scan**: `nvim_get_runtime_file("lua/*/buddy.lua", true)`
- **Plugin format**: `lua/{plugin}/buddy.lua` → module name `{plugin}.buddy`
- **Two formats**:
  - Simple: `{ tools = { tool1, tool2, ... } }`
  - Single: Single tool table
- **Module cache clearing**: For hot reload, clear package.loaded before requiring
- **Hot reload tracking**: Track plugin paths for file watching

### Validation (validate.lua)
- **JSON Schema**: Properties (schema definitions), required (field names)
- **Type checking**: string, number, boolean, array, object
- **Enum validation**: Check value in enum array
- **Required fields**: Ensure all required fields present
- **Error messages**: Human-readable validation errors

### Error Handling (errors.lua)
- **MCP error codes**:
  - -32602: Invalid params (validation errors)
  - -32001: Tool not found
  - -32002: Execution error
  - -32800: Tool execution failed
- **Error responses**: `{ error: { code, message, data: { tool } } }`
- **Custom codes**: Tool-specific errors (-32700, -32701 for validation/execution)

### Hot Reload System (hotreload.lua)
- **File watching**: `vim.loop.new_fs_event()` on tool files
- **Debouncing**: Wait for file to stabilize before reloading
- **Plugin reload**: Clear `_source` tools, require fresh module, re-register
- **Change notification**: Notify MCP clients via `mcp.methods.notify_tools_changed()`

### Lazy Loading (lazy.lua)
- **Optional deps**: Defer require until first use
- **Runtime tracking**: Track tools by runtime (runtimepath, builtin)
- **Cache clearing**: Clear lazy cache by runtime prefix

## Flow

### Tool Registration Flow
```
Tool discovery / register_tool()
  → registry.register(tool_def)
    → Validate: tool.name, tool.description
    → key = tool.id or tool.name
    → tools[key] = tool_def
    → tools[key].runtime = "runtimepath"  (for plugin tools)
    → tools[key]._source = "plugin_name"  (for hot reload)
    → mcp.methods.notify_tools_changed()  (broadcast to clients)
```

### Built-in Loading Flow
```
buddy.start()
  → tools.load_builtins()
    → For each builtin name (buffer, edit, navigation, ...):
      → tool = require("buddy.tools.builtin." .. name)
      → Check if disabled in config
      → registry.register(tool)
```

### Runtimepath Discovery Flow
```
buddy.start()
  → discovery.discover()
    → buddy_files = nvim_get_runtime_file("lua/*/buddy.lua", true)
    → For each path (lua/plugin/buddy.lua):
      → prefix = path:match("lua/([^/]+)/buddy%.lua$")
      → discovery._discover_one(prefix, path)
        → Clear module cache: package.loaded[prefix .. ".buddy"] = nil
        → pack = require(prefix .. ".buddy")
        → Register pack (single tool or tools array)
        → hotreload.track_plugin(prefix, path)
```

### Sync Tool Execution Flow
```
MCP: tools/call with name="buffer", arguments={ action: "list" }
  → executor.execute("buffer", { action: "list" }, context)
    → tool = tools.get("buffer")
    → validate arguments against input_schema
    → context = { on_progress, elicit, sample, session_id }
    → result = tool.run(args, context)  (sync returns directly)
    → Return result: { success: true, buffers: [...] }
  → Wrap in MCP format: { content = [{ type: "text", text: "<json>" }] }
```

### Async Tool Execution Flow
```
MCP: tools/call with name="long_operation", arguments={ ... }
  → executor.execute("long_operation", args, context)
    → Validate arguments
    → context = { on_progress, elicit, sample, session_id }
    → result = tool.run(args, context)  (async returns cancel function)
    → running_tasks[task_id] = { cancel_fn, cancelled: false, callback, tool_id }
    → Return nil, task_id  (async, no immediate result)
  → MCP receives 202 Accepted

Tool completes later:
  → context(result)  (calls context callback)
    → async_callback(result)
    → running_tasks[task_id] = nil
    → MCP receives response via SSE: "data: { content: [...] }"
```

### Progress Update Flow (Async Tool)
```
Tool executing async operation:
  → context.on_progress(50, 100, "Processing...")
    → mcp._notify_callback({
        method: "notifications/progress",
        params: { progressToken: "...", progress: 50, total: 100, message: "..." }
      })
    → Broadcast to all SSE sessions
    → Client receives progress update
```

### Elicitation Flow (Tool Needs User Input)
```
Tool needs user input:
  → context.elicit("Enter file path", { type: "string", description: "..." })
    → client_requests.elicitation_create(session_id, { message, requestedSchema })
    → Send server-to-client request
    → Wait for client response
  → Client responds → tool receives input and continues
```

### Tool Cancellation Flow
```
Client sends notifications/cancelled with requestId=123
  → mcp.methods["notifications/cancelled"]()
    → Log cancellation
  → executor.cancel(task_id)
    → running_tasks[task_id].cancelled = true
    → Call cancel function if present
    → running_tasks[task_id] = nil
  → Tool's late result ignored (cancelled flag checked in callback)
```

### Hot Reload Flow
```
User edits lua/viz/buddy.lua
  → fs_event callback fires (debounced)
  → hotreload.on_change(path)
    → Parse path to get prefix="viz"
    → tools.clear_by_source("viz")  (remove old tools)
    → lazy.clear_by_runtime("runtimepath")  (clear lazy cache)
    → discovery._discover_one("viz", path)  (reload fresh)
      → Clear module cache
      → require("viz.buddy")  (fresh load)
      → Register new tools
    → mcp.methods.notify_tools_changed()  (broadcast to clients)
```

### Validation Flow
```
Tool execution with arguments
  → validate.validate(args, { properties, required })
    → Check all required fields present
    → For each property:
      → Check type (string, number, boolean, array, object)
      → Check enum if defined
      → Check nested objects recursively
    → Return valid=true or valid=false, error_message
  → If invalid: errors.throw(-32602, error_message, { tool })
```

### Error Response Flow
```
Tool execution fails
  → pcall(tool.run) catches error
  → errors.throw(code, message, { tool })
    → Create error: { code, message, data: { tool } }
  → executor catches error
  → errors.to_mcp_response(error)
    → Return MCP error response: { error: { code, message, data } }
```

## Integration

### Upward Dependencies
- **buddy.mcp.methods**: Tool change notifications (notify_tools_changed)
- **buddy.mcp.client_requests**: Server-to-client requests (elicit, sample)
- **buddy.config**: Disabled tools list
- **buddy.log**: Debug logging for execution
- **vim.api**: Neovim API for tool operations (buffers, windows, etc.)
- **vim.json**: JSON encoding for responses

### Downward Dependencies
- **tools.register()**: Called by init.lua (load_builtins), discovery (_discover_one), buddy (register_tool)
- **tools.get/list()**: Called by mcp.methods (tools/list), executor
- **executor.execute()**: Called by mcp.methods (tools/call), buddy.init (call)
- **discovery.discover()**: Called by buddy.init (start)
- **hotreload.start_watching()**: Called by buddy.init (start)

### MCP Integration
- **tools/list**: Uses `tools.list()` to get all tools
- **tools/call**: Uses `executor.execute()` with context
- **Tool changes**: `notify_tools_changed()` broadcast to MCP clients
- **Progress updates**: Context `on_progress` sends `notifications/progress`

### Registry Integration
- **Built-in tools**: Registered in `load_builtins()` from `buddy.tools.builtin.*`
- **Runtimepath tools**: Registered in `discovery._discover_one()` from `lua/*/buddy.lua`
- **Dynamic tools**: Registered via `buddy.register_tool()` (runtime="plugin")
- **Hot reload**: `clear_by_source()` removes old tools before reload

### Validation Integration
- **Tool registration**: No validation (deferred to execution)
- **Tool execution**: Arguments validated against `input_schema` before calling `run()`
- **Error propagation**: Validation errors converted to MCP error responses

### Hot Reload Integration
- **File watching**: `vim.loop` events on tool files
- **Module cache**: `package.loaded` cleared before requiring updated modules
- **Lazy cache**: Lazy-loaded module cache cleared by runtime prefix
- **Change broadcast**: MCP clients notified to refresh tool lists

### Error Handling Integration
- **Execution errors**: Caught via `pcall`, converted to MCP errors
- **Validation errors**: Throw via `errors.throw()`, caught in executor
- **Cancellation errors**: Create error via `errors.create()`, passed to callback

### Tool Dependencies
- **Lazy loading**: Optional deps loaded on first use via `lazy.require()`
- **Module tracking**: Lazy cache tracks tools by runtime prefix
- **Cache clearing**: Clear by runtime prefix on hot reload

### Session Context
- **session_id**: Passed in execution context for server-to-client requests
- **progress_token**: Optional token for progress notifications
- **elicit/sample**: Use session_id to make server-to-client requests

### Neovim Integration
- **Tool definitions**: Can include `setup` block with keymaps, commands, autocmds
- **Hot reload**: Editing tool files reloads without Neovim restart
- **File watching**: Uses `vim.loop` for cross-platform file events

### Configuration
- **Disabled tools**: Checked in `load_builtins()` before registration
- **Buffer ignoring**: Config used in buffer tool (not tools module)

### Testing
- **executor.execute()**: Can be tested with mock tools
- **validate.validate()**: Pure function, easy to unit test
- **discovery._discover_one()**: Can be tested with fake runtimepath
