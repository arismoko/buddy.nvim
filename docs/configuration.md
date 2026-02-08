# Configuration

## Setup Options

```lua
require("buddy").setup({
  host = "127.0.0.1",   -- Bind address (default: "127.0.0.1" for security)
  port = 7234,          -- Server port (default: 7234)
  auto_start = false,   -- Start on VimEnter (default: false)
  auth = true,          -- Bearer token auth on HTTP endpoints (default: true)
  watch = true,         -- Hot reload file watching (default: true)
  log_level = "info",   -- Log level: "debug", "info", "warn", "error" (default: "info")
  tools = {
    disabled = {},      -- List of tool names to disable (e.g., {"grep", "diagnostics"})
  },
  buffer = {
    ignored_filetypes = {},  -- Filetypes to hide from buffer list (e.g., {"neo-tree"})
  },
})
```

### Options Reference

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `host` | string | `"127.0.0.1"` | Server bind address |
| `port` | number | `7234` | Server port |
| `auto_start` | boolean | `false` | Auto-start server on VimEnter |
| `auth` | boolean | `true` | Enable Bearer token auth on HTTP endpoints |
| `watch` | boolean | `true` | Enable hot reload file watching |
| `log_level` | string | `"info"` | Log level: `"debug"`, `"info"`, `"warn"`, `"error"` |
| `tools.disabled` | string[] | `{}` | List of built-in tool names to disable |
| `buffer.ignored_filetypes` | string[] | `{}` | Filetypes to exclude from buffer listings |

## Disabling Built-in Tools

You can disable specific built-in tools by adding their names to `tools.disabled`:

```lua
require("buddy").setup({
  tools = {
    disabled = { "grep", "diagnostics", "macro" },
  },
})
```

Available built-in tools that can be disabled:
- `buffer` - Read, list, and get info on buffers
- `command` - Execute Ex commands
- `diagnostics` - Get LSP diagnostics
- `edit` - Insert, replace, delete text
- `fold` - Control code folding
- `grep` - Project-wide search
- `init` - Scaffold new tools
- `macro` - Record and play macros
- `navigation` - Jump to files, lines, marks
- `register` - Access Neovim registers
- `search` - Find and replace in buffer
- `status` - Get cursor, mode, marks, registers
- `tab` - Manage tabs
- `visual` - Create visual selections
- `window` - Manage splits and layout

Note: Tools from companion plugins (like `buddy_manager`, `viz`, `dotfyle_search`) are managed by installing/uninstalling their respective plugins and are not controlled by `tools.disabled`.

## Security

By default, buddy.nvim binds to `127.0.0.1` (localhost only). This means only local processes can connect.

When `auth` is enabled (default), the server requires an `Authorization: Bearer <token>` header on HTTP/SSE requests. The proxy (`buddy-mcp-proxy`) reads the token from the session registry and injects it automatically. For direct URL connections, your MCP client must support custom auth headers (or you must disable auth in trusted local setups).

!!! warning "Exposing on LAN"
    To expose on LAN (e.g., for remote AI clients):

    ```lua
    require("buddy").setup({
      host = "0.0.0.0",  -- Listen on all interfaces
    })
    ```

    **Warning**: Even with `auth = true`, there is no TLS. If you bind to `0.0.0.0`, consider:

    - Using a firewall to restrict access
    - SSH tunneling for remote access
    - Only enabling on trusted networks

## API

```lua
local buddy = require("buddy")

-- Start the MCP server
buddy.start()

-- Stop the server
buddy.stop()

-- Restart (stop + start)
buddy.restart()

-- Check status
local status = buddy.status()
-- { running = true, port = 7234 }

-- Call a tool programmatically
local result = buddy.call("buffer", { action = "list" })

-- Register a tool programmatically
buddy.register_tool({
  name = "my_tool",
  description = "Does something",
  args = {
    param = { type = "string", description = "A parameter" },
  },
  required = { "param" },
  run = function(args) return { success = true, param = args.param } end,
})
```

## Troubleshooting

### Port already in use

```
Failed to bind to 127.0.0.1:7234 - address already in use
```

Another instance is running, or another app is using port 7234. Either stop the other process or change the port:

```lua
require("buddy").setup({ port = 7235 })
```

### Tool not loading

Check `:messages` for errors. Common issues:

- Syntax errors in your tool file
- Missing `name`, `description`, or `run` fields
- Invalid `input_schema`

### SSE connection failing

Ensure:

1. buddy.nvim is running: `:lua print(require('buddy').status().running)`
2. The URL matches your config (default: `http://127.0.0.1:7234/sse`)
3. No firewall blocking the connection
