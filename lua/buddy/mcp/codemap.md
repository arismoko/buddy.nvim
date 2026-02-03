# lua/buddy/mcp/

## Responsibility

The MCP module implements the Model Context Protocol (version 2025-06-18) specification, handling JSON-RPC 2.0 requests, managing server capabilities, and providing method handlers for tools, resources, and prompts. It serves as the protocol bridge between the HTTP/SSE transport and the tool/resource/prompt subsystems.

Key responsibilities:
- Validate and dispatch JSON-RPC 2.0 requests to method handlers
- Implement all MCP 2025-06-18 methods: initialize, tools/list, tools/call, resources/*, prompts/*, completion/complete
- Manage server capabilities and client session state
- Handle notifications (tools/prompts/resources changed, cancelled, progress)
- Provide content helpers (image, audio, resource, resource_link)
- Support server-to-client requests (elicitation, sampling) for interactive tools

## Design

### Module Structure
```
mcp/
  init.lua              # Request validation and dispatch
  methods.lua           # Method handlers (M["method_name"] functions)
  schema.lua            # JSON-RPC response builders (result, error)
  session_state.lua     # Per-session client capability storage
  client_requests.lua   # Server-to-client request handling (elicitation, sampling)
  roots.lua             # Workspace root management
  sampling.lua          # Sampling protocol helpers
  elicitation.lua       # Elicitation protocol helpers
```

### JSON-RPC 2.0 Validation (init.lua)
- **Request format**: `{ jsonrpc: "2.0", method: "...", params?: {...}, id?: ... }`
- **Error codes**:
  - -32700: Parse error
  - -32600: Invalid request
  - -32601: Method not found
  - -32602: Invalid params
  - -32603: Internal error

### Method Dispatch Pattern
- **Table dispatch**: `methods[request.method]` looks up handler
- **Notifications**: Requests without `id` → no response returned
- **Error handling**: `pcall(method_handler)` → convert errors to JSON-RPC errors

### Method Handler Registration
- **Table-based**: `M["initialize"]`, `M["tools/list"]`, etc.
- **Signature**: `function(session_id, params, request_id?) -> result|nil`
- **Context**: `session_id` passed to all methods for per-session state

### Notification System
- **Callback registry**: `M._notify_callback` wired up on first SSE connection
- **Broadcast**: Router iterates all SSE sessions → `send_data(notification)`
- **Notifications**:
  - `notifications/tools/list_changed`: Tools added/removed
  - `notifications/prompts/list_changed`: Prompts added/removed
  - `notifications/resources/list_changed`: Resources added/removed
  - `notifications/resources/updated`: Specific resource content changed
  - `notifications/cancelled`: Client cancelled a request
  - `notifications/progress`: Progress updates from tools

### Session State Management
- **session_state module**: Stores client capabilities per session
- **initialize()**: Called on handshake, stores `params.capabilities`
- **roots/list_changed**: Invalidates cached roots when client workspace changes

### Server Capabilities (initialize response)
```lua
{
  protocolVersion = "2025-06-18",
  capabilities = {
    tools = { listChanged = true },
    logging = {},
    resources = { listChanged = true, subscribe = true },
    prompts = { listChanged = true },
    completion = {},
  },
  serverInfo = { name = "buddy", version = "2.0.0", title = "Neovim Buddy" },
  instructions = "..."
}
```

### Tool Execution (methods["tools/call"])
- **Validation**: Tool exists, input validated against schema
- **Context**: Pass `on_progress`, `elicit`, `sample` to tool via executor
- **Progress**: `on_progress(progress, total, message)` → `notifications/progress`
- **Elicitation**: `context.elicit(message, schema)` → prompts client for input
- **Sampling**: `context.sample(params)` → requests completion from client's model
- **Response format**: `{ content = [{ type = "text", text = "..." }] }`

### Resource Subscription
- **subscriptions table**: `subscriptions[session_id][uri] = true`
- **subscribe/unsubscribe**: Track per-session resource subscriptions
- **watch_buffer()**: Attach `on_lines` handler to buffer for change notifications

### Content Helpers (methods.lua)
- **image_content()**: `{ type = "image", data = base64, mimeType = "image/png" }`
- **audio_content()**: `{ type = "audio", data = base64, mimeType = "audio/wav" }`
- **embedded_resource()**: `{ type = "resource", resource = { uri, text, mimeType } }`
- **embedded_blob()**: `{ type = "resource", resource = { uri, blob, mimeType } }`
- **resource_link()**: `{ type = "resource_link", uri, name, description?, mimeType? }`

### Server-to-Client Requests (client_requests.lua)
- **elicitation_create()**: Prompt user for structured input via `requests/elicitation` method
- **sampling_create_message()**: Request model completion via `requests/completion` method
- **handle_response()**: Process client responses to server-to-client requests

### Completion (methods["completion/complete"])
- **ref-based**: `ref.type` determines completion source
- **ref/prompt**: Prompt argument completions (e.g., refactor goal options)
- **ref/resource**: Buffer URI completions (list loaded buffers)
- **Return**: `{ completion = { values = [...], total, hasMore } }`

## Flow

### Request Flow
```
HTTP POST /message?sessionId=XYZ
  → router._handle_message()
    → vim.schedule(→ mcp.handle_request(session_id, request))
      → validate_request() (jsonrpc, method, id)
      → method = methods[request.method]
      → pcall(method, session_id, params, id)
        → Tool/resource/prompt execution
        → Return result or error
      → schema.result(id, result) or schema.error(id, code, message)
  → router sends via SSE: "data: {...}\n\n"
```

### Initialize Handshake Flow
```
Client: { jsonrpc: "2.0", method: "initialize", params: { capabilities: {...}, ... }, id: 1 }
  → methods["initialize"](session_id, params, 1)
    → session_state.initialize(session_id, params)  (store client caps)
    → Return server capabilities, instructions
Server: { jsonrpc: "2.0", id: 1, result: { protocolVersion: "2025-06-18", capabilities: {...} } }
Client: { jsonrpc: "2.0", method: "notifications/initialized" }  (notification, no id)
  → methods["notifications/initialized"](session_id, params)
    → Return nil (notifications have no response)
```

### Tool Call Flow
```
Client: { jsonrpc: "2.0", method: "tools/call", params: { name: "buffer", arguments: { action: "list" } }, id: 2 }
  → methods["tools/call"](session_id, params, 2)
    → tool = tools.get("buffer")
    → args = params.arguments
    → progress_token = params._meta.progressToken
    → context = { on_progress, elicit, sample, session_id }
    → executor.execute("buffer", args, context)
      → Validate args against schema
      → Call tool.run(args, context)
      → Return result: { success: true, buffers: [...] }
    → Wrap result: { content = [{ type: "text", text: "<json>" }] }
Server: { jsonrpc: "2.0", id: 2, result: { content: [{ type: "text", text: "..." }] } }
```

### Progress Notification Flow (Async Tool)
```
Tool executing async operation:
  → context.on_progress(5, 10, "Processing...")
    → notify_callback({
        method: "notifications/progress",
        params: { progressToken, progress: 5, total: 10, message: "Processing..." }
      })
    → Broadcast to all SSE sessions
    → Client receives: "data: {"method":"notifications/progress",...}\n\n"
```

### Tool Change Notification Flow
```
tools.register(new_tool) or hotreload detects file change
  → tools.register() calls methods.notify_tools_changed()
    → notify_callback({ method: "notifications/tools/list_changed" })
    → Broadcast to all SSE sessions
    → Client receives → refreshes tool list via tools/list
```

### Resource Subscription Flow
```
Client: { jsonrpc: "2.0", method: "resources/subscribe", params: { uri: "vim://buffer/1" }, id: 3 }
  → methods["resources/subscribe"](session_id, params, 3)
    → subscriptions[session_id]["vim://buffer/1"] = true
    → methods.watch_buffer(1, "vim://buffer/1")
      → vim.api.nvim_buf_attach(1, false, {
          on_lines = function()
            → methods.notify_resource_updated("vim://buffer/1")
          end
        })
Server: { jsonrpc: "2.0", id: 3, result: {} }
```

### Resource Update Notification Flow
```
User edits buffer 1
  → buf_attach on_lines callback fires
    → methods.notify_resource_updated("vim://buffer/1")
      → notify_callback({
          method: "notifications/resources/updated",
          params: { uri: "vim://buffer/1" }
        })
      → Broadcast to subscribed sessions
    → Client receives → re-reads resource via resources/read
```

### Server-to-Client Elicitation Flow
```
Tool needs user input:
  → context.elicit("Enter file path", { type: "string", description: "..." })
    → client_requests.elicitation_create(session_id, {
        message: "Enter file path",
        requestedSchema: { type: "string", ... }
      })
    → Send via client_requests module (stores pending request)
Client receives: { jsonrpc: "2.0", method: "requests/elicitation", params: { ... }, id: 99 }
  → Client responds: { jsonrpc: "2.0", id: 99, result: "path/to/file.txt" }
  → router._handle_message() detects response → client_requests.handle_response()
    → Resolve pending elicitation promise
    → Tool receives user input and continues execution
```

### Completion Flow
```
Client: { jsonrpc: "2.0", method: "completion/complete", params: { ref: { type: "ref/prompt", name: "refactor_selection" }, argument: { name: "goal" } }, id: 4 }
  → methods["completion/complete"](session_id, params, 4)
    → ref.type == "ref/prompt" && ref.name == "refactor_selection" && argument.name == "goal"
    → Return: { completion: { values: [
        { value: "simplify", description: "Simplify complex code" },
        { value: "extract", description: "Extract to function/variable" },
        ...
      ], total: 4, hasMore: false }}
Server: { jsonrpc: "2.0", id: 4, result: { completion: {...} } }
```

## Integration

### Upward Dependencies
- **buddy.tools**: Tool registry and executor (used by tools/list, tools/call)
- **buddy.resources**: Resource registry (used by resources/list, resources/read)
- **buddy.prompts**: Prompt templates (used by prompts/list, prompts/get)
- **buddy.tools.errors**: Error handling for tool execution
- **buddy.log**: Debug logging for request/response
- **vim.api**: Neovim API for buffer watching, diagnostics
- **vim.json**: JSON encoding/decoding

### Downward Dependencies
- **mcp.handle_request()**: Called by router._handle_message()
- **methods.notify_*()**: Called by tools.register(), tools.clear(), hotreload
- **methods.set_notify_callback()**: Called by router on first SSE connection
- **session_state**: Used by methods.initialize()

### Transport Integration
- **Router**: Calls `mcp.handle_request()` for POST /message
- **Router**: Registers `notify_callback` via `methods.set_notify_callback()`
- **SSE**: Responses sent via `sse_conn:send_data()`

### Tool System Integration
- **tools/list**: Calls `tools.list()`, converts to MCP format (inputSchema, annotations, title)
- **tools/call**: Calls `executor.execute()` with context (progress, elicit, sample)
- **Tool execution errors**: Converted via `errors.to_mcp_response()`
- **Tool changes**: `tools.register()` → `methods.notify_tools_changed()`

### Resource System Integration
- **resources/list**: Calls `resources.list()`
- **resources/read**: Calls `resources.read(uri)`
- **resources/subscribe**: Track in `subscriptions` table, call `watch_buffer()`
- **Resource updates**: `notify_resource_updated()` broadcast to subscribed sessions

### Prompt System Integration
- **prompts/list**: Calls `prompts.list()`
- **prompts/get**: Calls `prompts.get(name, arguments)`
- **Prompt changes**: `prompts.register()` → `methods.notify_prompts_changed()`

### Server-to-Client Requests
- **client_requests module**: Manages pending server-to-client requests
- **elicitation**: Interactive tools solicit user input via `requests/elicitation`
- **sampling**: Tools request model completions via `requests/completion`
- **Response handling**: Router detects responses via `client_requests.is_response()`

### Client Session Management
- **session_id**: Passed to all method handlers
- **session_state**: Stores client capabilities, cached roots
- **Multi-session**: Each client has independent session state

### Error Handling
- **Invalid JSON-RPC**: Return error code -32700 (parse), -32600 (invalid request)
- **Method not found**: Return error code -32601
- **Invalid params**: Tool executor throws → error code -32602
- **Execution errors**: `pcall` handler → error code -32603
- **Tool errors**: Converted via `errors.to_mcp_response()`

### Protocol Compliance
- **JSON-RPC 2.0**: Full compliance (requests, responses, notifications, error codes)
- **MCP 2025-06-18**: All core methods implemented
- **SSE unnamed events**: For MCP SDK EventSource.onmessage compatibility
- **Progress tokens**: Optional `_meta.progressToken` in tool call params

### Capabilities
- **Tools**: List/change notifications, structured outputs via outputSchema
- **Resources**: List/change notifications, subscribe, read
- **Prompts**: List/change notifications, get with arguments
- **Logging**: Dynamic log level via `logging/setLevel`
- **Completion**: Prompt argument completion, resource URI completion

### Content Types
- **Text**: Standard tool responses
- **Image**: Base64-encoded images (charts, visualizations)
- **Audio**: Base64-encoded audio (future)
- **Resource**: Embedded resources or resource links
- **Structured**: Tool output with outputSchema (structuredContent field)

### Testing
- **test_schema.lua**: JSON-RPC response building tests
- **Mock methods**: Used in server integration tests
