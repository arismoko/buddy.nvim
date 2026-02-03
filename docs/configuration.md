# Configuration

## Setup Options

```lua
local buddy = require("buddy")

buddy.setup({
  host = "127.0.0.1",   -- Bind address (default: "127.0.0.1" for security)
  port = 7234,          -- Server port (default: 7234)
  auto_start = false,   -- Start on VimEnter (default: false)
  debug = false,        -- Enable debug logging (default: false)
  tools_dir = nil,      -- Custom tools directory (default: nil)
  tools = {},           -- Per-tool configuration (default: {})
})
```

### Options Reference

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `host` | string | `"127.0.0.1"` | Server bind address |
| `port` | number | `7234` | Server port |
| `auto_start` | boolean | `false` | Auto-start server on VimEnter |
| `debug` | boolean | `false` | Enable debug logging |
| `tools_dir` | string | `nil` | Custom tools directory |
| `tools` | table | `{}` | Per-tool configuration |

## Security

By default, buddy.nvim binds to `127.0.0.1` (localhost only). This means only local processes can connect.

!!! warning "Exposing on LAN"
    To expose on LAN (e.g., for remote AI clients):

    ```lua
    require("buddy").setup({
      host = "0.0.0.0",  -- Listen on all interfaces
    })
    ```

    **Warning**: There is no authentication or TLS. If you bind to `0.0.0.0`, anyone on your network can control your editor. Consider:

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

-- Register a tool programmatically
buddy.register_tool({
  name = "my_tool",
  description = "Does something",
  args = {},
  required = {},
  run = function(args) return { success = true } end,
})

-- Call a tool programmatically
local result = buddy.call("my_tool", { some_arg = "value" })
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
- Invalid `args` schema

### SSE connection failing

Ensure:

1. buddy.nvim is running: `:lua print(require('buddy').status().running)`
2. The URL matches your config (default: `http://127.0.0.1:7234/sse`)
3. No firewall blocking the connection
