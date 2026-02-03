# lua/buddy/server/

## Responsibility

The server module implements a custom HTTP + Server-Sent Events (SSE) server on top of Neovim's `vim.uv` (libuv) bindings. It provides the transport layer for MCP communication, enabling AI clients to connect via HTTP POST for requests and SSE for responses/notifications.

Key responsibilities:
- Create and manage TCP server using libuv (no external HTTP library)
- Handle HTTP request parsing (method, path, headers, body)
- Route requests to MCP handlers (`/sse`, `/message`, `/health`)
- Maintain SSE connections for each client session
- Broadcast notifications to all active SSE sessions
- Gracefully handle connection lifecycle (accept, read, respond, close)

## Design

### Module Structure
```
server/
  init.lua         # Entry point: create server and start with router
  http.lua         # HTTPServer class: TCP server, HTTP parsing, connection management
  sse.lua          # SSEConnection + SSEManager: SSE protocol implementation
  router.lua       # Request routing and endpoint handlers
```

### HTTPServer Class (http.lua)
- **OOP pattern**: `HTTPServer.new()` → setmetatable with `__index`
- **State**: host, port, server (TCP), connections [], sse_connections {}, router, running
- **Methods**: `start(router)`, `_accept()`, `_handle_connection(client)`, `_dispatch()`, `send_response()`, `stop()`

### SSEConnection Class (sse.lua)
- **Per-session SSE channel**: Wraps TCP client with SSE protocol
- **SSE headers**: `Content-Type: text/event-stream`, `Cache-Control: no-cache`, `X-Accel-Buffering: no`
- **Methods**: `send_data(data)`, `send_raw_event(event_type, data)`, `close()`
- **Unnamed events**: `data: {...}` (required for MCP SDK's EventSource.onmessage)

### SSEManager Singleton (sse.lua)
- **Session registry**: `sessions[session_id] = SSEConnection`
- **Lifecycle**: `create_session()` → assign session_id, send endpoint URL via `event: endpoint`
- **Pattern**: Singleton accessed via `SSEManager.get_instance()`

### Router Pattern (router.lua)
- **Route table**: Maps (method, path) → handler function
- **Query params**: Parsed from URL, attached to `request.params`
- **Endpoints**:
  - `GET /sse`: Create SSE session
  - `POST /message`: Handle MCP JSON-RPC request
  - `GET /health`: Health check (for monitoring)
  - `*`: 404 handler

### Connection Tracking
- `connections[]`: All TCP clients (for cleanup on server stop)
- `sse_connections[session_id]`: Active SSE connections (for broadcasting)

### HTTP Parsing
- **Manual parsing**: Split headers at `\r\n\r\n`, parse request line, parse header lines
- **Content-Length**: Used to determine when body is complete
- **Chunked reading**: `read_start()` callback buffers until full request received

### Response Format
```
HTTP/1.1 {status} {status_text}
{headers}

{body}
```

### SSE Format
```
HTTP/1.1 200 OK
Content-Type: text/event-stream
...

event: endpoint
data: http://127.0.0.1:7234/message?sessionId=123...

data: {"jsonrpc":"2.0","id":1,"result":{...}}

event: notification
data: {"method":"notifications/tools/list_changed"}
```

## Flow

### Server Startup Flow
```
require("buddy").start()
  → server.start(host, port)
    → HTTPServer.new(host, port)
    → uv.new_tcp() → tcp:bind(host, port)
    → tcp:listen(128, accept_callback)
      → On connection: self:_accept()
        → uv.new_tcp() → tcp:accept(client)
        → connections.push(client)
        → self:_handle_connection(client)
```

### HTTP Request Handling Flow
```
client:read_start(callback)
  → On data chunk:
    → buffer ← buffer + chunk
    → Check for header end (\r\n\r\n)
    → Parse request line: "GET /sse HTTP/1.1"
    → Parse headers into request.headers table
    → Extract Content-Length for body
    → If full body received: self:_dispatch(client, request, body)
```

### Request Dispatch Flow
```
_dispatch(client, request, body)
  → router.handle(self, client, request, body)
    → parse_query_params(request.path) → request.params, request.path (base)
    → Route to handler:
      - GET /sse → _handle_sse()
      - POST /message → _handle_message()
      - GET /health → _handle_health()
      - * → _handle_404()
```

### SSE Session Creation Flow
```
GET /sse
  → sse_manager.create_session(client, host, port)
    → session_id = uv.hrtime()  (unique ID)
    → sse_conn = SSEConnection.new(client, session_id)
      → Send SSE headers: "HTTP/1.1 200 OK\nContent-Type: text/event-stream\n..."
    → sessions[session_id] = sse_conn
    → server.sse_connections[session_id] = sse_conn
    → sse_conn:send_raw_event("endpoint", endpoint_url)
      → client:write("event: endpoint\ndata: http://.../message?sessionId=...\n\n")
    → On first SSE, wire up notify_callback for broadcasting
```

### MCP Request/Response Flow
```
POST /message?sessionId=XYZ
  → Validate sessionId → get sse_conn from manager
  → Parse JSON body
  → If response (client-to-server): client_requests.handle_response() → return 200 OK
  → If request: vim.schedule(→ mcp.handle_request(session_id, request_data))
    → route to method handler
    → execute tool, get result
    → sse_conn:send_data(response)
      → client:write("data: {json}\n\n")
  → Return 202 Accepted (actual response via SSE)
```

### Notification Broadcast Flow
```
tools changed / resources changed
  → mcp.methods.notify_tools_changed()
    → notify_callback({ method: "notifications/tools/list_changed" })
    → Broadcast to all active SSE connections:
      for sid, conn in pairs(sse_connections):
        conn:send_data(message)
```

### Server Shutdown Flow
```
server:stop()
  → running = false
  → Close all connections:
    for client in connections:
      if not client:is_closing(): client:close()
    connections = []
  → Close SSE connections:
    for session_id, sse_conn in sse_connections:
      sse_conn:close()
    sse_connections = {}
  → Close TCP server:
    if server:is_closing(): server:close()
```

### Health Check Flow
```
GET /health
  → Return JSON: { status: "ok", timestamp: uv.now() }
  → Use 200 status, Content-Type: application/json
```

## Integration

### Upward Dependencies
- **vim.uv**: Libuv bindings for TCP, timers, async I/O
- **vim.schedule**: Schedule callbacks on Neovim main loop
- **vim.json**: JSON encoding/decoding for request/response bodies
- **vim.notify**: User-facing error messages (listen errors, bind failures)

### Downward Dependencies
- **router.lua** called by: HTTPServer:`_dispatch()`
- **sse.lua** used by: router:`_handle_sse()`
- **HTTPServer** created by: `buddy.server.start()` in `lua/buddy/init.lua`

### MCP Integration
- **Router → MCP Handler**: `_handle_message()` → `mcp.handle_request(session_id, request_data)`
- **MCP → Server**: Responses sent via `sse_conn:send_data()`
- **MCP → Broadcast**: `notify_callback` registered on first SSE connection
- **Client Requests**: `_handle_message()` detects responses via `client_requests.is_response()`

### Tool Integration
- **Tool change notifications**: Broadcast to all SSE sessions when tools registered/cleared
- **Resource updates**: When buffer subscribed, `mcp.methods.watch_buffer()` triggers notifications

### Session Management
- **SSE Session IDs**: Used as `sessionId` parameter in `/message` endpoint
- **Session lookup**: `sse_manager:get_session(session_id)` retrieves SSEConnection
- **Multi-buddy**: Each buddy instance has its own server with separate sessions

### Error Handling
- **Bind failures**: `error("Failed to bind to %s:%d - %s", host, port, err)`
- **Listen errors**: `vim.notify("[buddy] Listen error: %s", vim.log.levels.ERROR)`
- **Invalid JSON**: Return 400 with MCP error code -32700
- **Missing sessionId**: Return 400 with MCP error code -32600
- **Session not found**: Return 404 with MCP error code -32001
- **MCP handler error**: Return 500 with MCP error code -32603
- **SSE write errors**: `error("SSE data write error: %s", err)`

### Connection Lifecycle
- **Accept**: `tcp:listen()` → callback for each connection
- **Read**: `read_start()` → callback for each chunk
- **Write**: `client:write(data, callback)` → async write with completion callback
- **Close**: `client:close()` (after write in `send_response()`, or explicit in `stop()`)

### Security
- **Host binding**: Default `127.0.0.1` (localhost only), can configure `0.0.0.0` for LAN
- **No authentication**: Assumes trusted network (firewall recommended for `0.0.0.0`)
- **No TLS**: Plain HTTP (future enhancement)

### Performance
- **Non-blocking I/O**: All operations via libuv async callbacks
- **Connection pooling**: Multiple concurrent connections supported
- **Buffering**: Manual chunk buffering for request parsing
- **Efficient broadcast**: Iterate over SSE connections for notifications

### Compatibility
- **MCP SDK**: Uses unnamed SSE events (`data: {...}`) for EventSource.onmessage compatibility
- **HTTP/1.1**: Simple protocol, no chunked transfer encoding
- **TCP**: Low-level, works on all platforms via libuv

### Debugging
- **Health endpoint**: `GET /health` for monitoring/liveness checks
- **Logging**: Via `buddy.log` module (debug level for request/response)
- **Connection tracking**: `connections` and `sse_connections` for inspection
