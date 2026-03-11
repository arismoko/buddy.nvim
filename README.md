# buddy.nvim

**Lua tools that work as keymaps AND as MCP tools.**

<p align="center">
  <img src="https://img.shields.io/badge/Neovim-0.10+-green.svg?style=flat-square&logo=neovim" alt="Neovim 0.10+" />
  <img src="https://img.shields.io/badge/MCP-2024--11--05-blue.svg?style=flat-square" alt="MCP Protocol" />
  <img src="https://img.shields.io/badge/Lua-purple.svg?style=flat-square&logo=lua" alt="Lua" />
</p>

---

I wanted AI tooling in Neovim without leaving for another editor. So I built this.

buddy.nvim runs an [MCP server](https://modelcontextprotocol.io/) inside Neovim. Claude, OpenCode, or any MCP client can connect and actually control your editor: read buffers, edit files, run commands, navigate. Not just chat.

You write tools in Lua. They work as MCP tools (AI calls them) *and* as regular Neovim plugins (keymaps, commands, autocmds). Same code, both interfaces.

---

## Installation

### lazy.nvim

```lua
{
  "arismoko/buddy.nvim",
  dependencies = {
    "nvim-mini/mini.nvim",
    "nvim-neotest/nvim-nio",
  },
  lazy = false,
  config = function()
    require("buddy").setup({
      auto_start = true,
      port = 7234,
    })
  end,
}
```

### packer.nvim

```lua
use {
  "arismoko/buddy.nvim",
  requires = {
    "nvim-mini/mini.nvim",
    "nvim-neotest/nvim-nio",
  },
  config = function()
    require("buddy").setup({
      auto_start = true,
      port = 7234,
    })
  end,
}
```

### Manual

Clone to your Neovim packages directory:

```bash
git clone https://github.com/arismoko/buddy.nvim ~/.local/share/nvim/site/pack/plugins/start/buddy.nvim
```

---

## Connecting MCP Clients

buddy.nvim uses **HTTP + Server-Sent Events (SSE)** transport, compatible with modern MCP clients.

There are two ways to connect:

### Option A: Via Proxy (Recommended)

The [`buddy-mcp-proxy`](https://www.npmjs.com/package/buddy-mcp-proxy) automatically discovers running Neovim sessions, forwards auth tokens for you, and supports switching between multiple instances. No port configuration needed. Requires [Node.js](https://nodejs.org/) 20+.

```bash
npm install -g buddy-mcp-proxy
```

#### OpenCode

Add to `~/.config/opencode/opencode.jsonc`:

```jsonc
{
  "mcp": {
    "vim": {
      "type": "local",
      "command": ["npx", "buddy-mcp-proxy"]
    }
  }
}
```

#### Claude Desktop

Add to your Claude Desktop config:
- **macOS**: `~/Library/Application Support/Claude/claude_desktop_config.json`
- **Windows**: `%APPDATA%\Claude\claude_desktop_config.json`
- **Linux**: `~/.config/Claude/claude_desktop_config.json`

```json
{
  "mcpServers": {
    "vim": {
      "command": "npx",
      "args": ["buddy-mcp-proxy"]
    }
  }
}
```

### Option B: Direct SSE Connection

Connect directly to a specific Neovim instance by URL. Simpler, but you must know the port and can only connect to one session.

> **Note**: With auth enabled (default), the client must send an `Authorization: Bearer <token>` header. The proxy handles this automatically; for direct connections, either configure your client's auth headers or disable auth in trusted local setups.

> **Tip**: buddy.nvim tools only appear while a buddy-enabled Neovim session is actually running. If your client starts before Neovim, either launch Neovim first or use `buddy-mcp-proxy`, which will auto-connect when a session comes online.

#### OpenCode

```jsonc
{
  "mcp": {
    "vim": {
      "type": "remote",
      "url": "http://127.0.0.1:7234/sse"
    }
  }
}
```

#### Claude Desktop

```json
{
  "mcpServers": {
    "vim": {
      "url": "http://127.0.0.1:7234/sse"
    }
  }
}
```

---

## Security

By default, buddy.nvim binds to `127.0.0.1` (localhost only). This means only local processes can connect.

**To expose on LAN** (e.g., for remote AI clients):

```lua
require("buddy").setup({
  host = "0.0.0.0",  -- Listen on all interfaces
})
```

> **Note**: Bearer token authentication is enabled by default (`auth = true`), but there is no TLS. If you bind to `0.0.0.0`, the token is sent in plaintext. Consider:
> - Using a firewall to restrict access
> - SSH tunneling for remote access
> - Only enabling on trusted networks

---

## Built-in Tools

| Tool          | Description                                    |
| ------------- | ---------------------------------------------- |
| `buffer`      | Read, list, and get info on buffers            |
| `edit`        | Insert, replace, delete text in buffers        |
| `command`     | Execute Ex commands                            |
| `navigation`  | Jump to files, lines, marks                    |
| `search`      | Find and replace in current buffer             |
| `grep`        | Project-wide search using vimgrep              |
| `diagnostics` | Get LSP diagnostics from Neovim                |
| `window`      | Manage splits and window layout                |
| `tab`         | Manage tabs                                    |
| `fold`        | Control code folding                           |
| `visual`      | Create visual selections                       |
| `macro`       | Record and play macros                         |
| `register`    | Access Neovim registers                        |
| `status`      | Get cursor, mode, marks, registers             |
| `init`        | Scaffold new user tools                        |

See [docs/tools.md](docs/tools.md) for full reference with MCP JSON examples.

---

## Creating Tools

Tools live in `lua/{plugin}/buddy.lua` files. buddy.nvim discovers them automatically from the runtimepath.

### Format 1: Tools List

For plugins with one or more independent tools:

```lua
-- lua/my-plugin/buddy.lua
return {
  tools = {
    {
      name = "greet",
      description = "Say hello",
      input_schema = {
        type = "object",
        properties = {
          name = { type = "string", description = "Name to greet" },
        },
        required = { "name" },
      },
      run = function(args)
        return "Hello, " .. args.name
      end,
    },
    {
      name = "farewell",
      description = "Say goodbye",
      input_schema = {
        type = "object",
        properties = {
          name = { type = "string", description = "Name to farewell" },
        },
        required = { "name" },
      },
      run = function(args)
        return "Goodbye, " .. args.name
      end,
    },
  }
}
```

### Format 2: Single Tool

For plugins that expose exactly one tool:

```lua
-- lua/my-plugin/buddy.lua
return {
  name = "my_tool",
  description = "Does a thing",
  input_schema = {
    type = "object",
    properties = {
      message = { type = "string", description = "Message to show" },
    },
    required = {},
  },
  run = function(args)
    vim.notify("Did the thing with: " .. (args.message or "nothing"))
    return { success = true }
  end,
}
```

### Returning Results

Tools return **raw Lua values**. buddy.nvim wraps them into MCP responses automatically:

```lua
-- String → text content block
return "Hello, world!"

-- Table → JSON-encoded text content block
return { success = true, data = "result" }

-- nil → text content block with "nil"
return nil
```

> **Common mistake**: Don't return MCP envelopes like `{ content = { { type = "text", text = "..." } } }` from your tools. Just return the raw value. buddy.nvim wraps it for you.

### Adding Keymaps, Commands, Autocmds

Add a `setup` block and your tool becomes a proper Neovim plugin:

```lua
local function do_thing(args)
  vim.notify("Did the thing with: " .. (args.message or "nothing"))
  return { success = true }
end

return {
  name = "my_tool",
  description = "Does a thing",
  input_schema = {
    type = "object",
    properties = {
      message = { type = "string", description = "Message to show" },
    },
    required = {},
  },
  run = do_thing,

  setup = {
    keymaps = {
      { "n", "<leader>mt", function() do_thing({}) end, { desc = "My Tool" } },
    },
    commands = {
      { "MyTool", function(opts) do_thing({ message = opts.args }) end, nargs = "?" },
    },
    autocmds = {
      { "BufEnter", pattern = "*.md", callback = function() print("Markdown!") end },
    },
  },
}
```

Now your tool:
- Works via MCP when AI calls `my_tool`
- Works via `<leader>mt` keymap
- Works via `:MyTool` command
- Runs on `BufEnter` for markdown files

Edit the file, keymaps and commands update automatically. No restart needed.

See [docs/creating-tools.md](docs/creating-tools.md) for the full guide.

---

## Configuration

```lua
require("buddy").setup({
  host = "127.0.0.1",  -- Bind address (default: "127.0.0.1" for security)
  port = 7234,         -- Server port (default: 7234)
  auto_start = false,  -- Start on VimEnter (default: false)
  auth = true,         -- Bearer token auth on HTTP endpoints (default: true)
  watch = true,        -- Hot reload file watching (default: true)
  log_level = "info",  -- Log level: "debug", "info", "warn", "error"
  tools = {
    disabled = {},     -- Disable specific tools: {"grep", "diagnostics", ...}
  },
  buffer = {
    ignored_filetypes = {},  -- Hide filetypes from buffer listings
  },
})
```

See [docs/configuration.md](docs/configuration.md) for full configuration reference.

---

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

---

## Requirements

- **Neovim 0.10+**
- **mini.nvim** (dependency)
- **nvim-nio** (dependency — async operations)

---

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

---

## License

MIT
