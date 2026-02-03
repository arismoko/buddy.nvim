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
  dependencies = { "echasnovski/mini.nvim" },
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
  requires = { "echasnovski/mini.nvim" },
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

## Connecting to MCP Clients

nvim-buddy uses **HTTP + Server-Sent Events (SSE)** transport, compatible with modern MCP clients.

### OpenCode

Add to `~/.config/opencode/opencode.jsonc`:

```jsonc
{
  "mcp": {
    "buddy": {
      "type": "remote",
      "url": "http://127.0.0.1:7234/sse"
    }
  }
}
```

### Claude Desktop

Add to your Claude Desktop config:
- **macOS**: `~/Library/Application Support/Claude/claude_desktop_config.json`
- **Windows**: `%APPDATA%\Claude\claude_desktop_config.json`
- **Linux**: `~/.config/Claude/claude_desktop_config.json`

```json
{
  "mcpServers": {
    "buddy": {
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
require("nvim-buddy").setup({
  host = "0.0.0.0",  -- Listen on all interfaces
})
```

⚠️ **Warning**: There is no authentication or TLS. If you bind to `0.0.0.0`, anyone on your network can control your editor. Consider:
- Using a firewall to restrict access
- SSH tunneling for remote access
- Only enabling on trusted networks

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

---

## Creating Tools

Tools are defined in a `buddy.lua` file at `lua/{plugin}/buddy.lua`. nvim-buddy discovers these automatically.

### Format 1: Simple Tools List

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
        return { content = { { type = "text", text = "Hello, " .. args.name } } }
      end,
    },
  }
}
```

### Format 2: Action-Based Tool (Recommended for Multi-Action Tools)

For tools with multiple related actions, use the action-based pattern:

```lua
-- lua/viz/buddy.lua
return {
  name = "viz",
  description = "Visualization tool for images, charts, and diagrams",
  actions = {
    image = require("viz.tools.image"),
    chart = require("viz.tools.chart"),
  },
}

-- lua/viz/tools/image.lua
return {
  description = "Display a local image",
  input_schema = {
    type = "object",
    properties = {
      path = { type = "string", description = "Path to image file" },
    },
    required = { "path" },
  },
  run = function(args)
    -- implementation
  end,
}
```

The framework auto-generates:
- Unified input_schema from all actions
- Action enum with descriptions (e.g., `"image: Display a local image, chart: Generate charts"`)
- Routing to the correct action handler
- Per-action validation with helpful error messages

### Tool Format

Individual tools (or actions) use this format:

```lua
return {
  name = "tool_name",           -- Tool name (optional for actions)
  description = "What it does", -- Required
  input_schema = {              -- JSON Schema for parameters
    type = "object",
    properties = {
      param1 = { type = "string", description = "A parameter" },
      action = { type = "string", enum = { "a", "b" }, description = "a: do A, b: do B" },
    },
    required = { "action" },
  },
  run = function(args)          -- Handler function
    return { success = true, result = "..." }
  end,
}
```

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

---

## Configuration

```lua
local buddy = require("buddy")

buddy.setup({
  host = "127.0.0.1",  -- Bind address (default: "127.0.0.1" for security)
  port = 7234,         -- Server port (default: 7234)
  auto_start = false,  -- Start on VimEnter (default: false)
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

-- Register a tool programmatically
buddy.register_tool({
  name = "my_tool",
  description = "Does something",
  input_schema = {
    type = "object",
    properties = {},
    required = {},
  },
  run = function(args) return { success = true } end,
})
```

---

## Requirements

- **Neovim 0.10+**
- **mini.nvim** (dependency)

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
- Invalid `args` schema

### SSE connection failing

Ensure:
1. nvim-buddy is running (`:lua print(require('nvim-buddy').status().running)`)
2. The URL matches your config (default: `http://127.0.0.1:7234/sse`)
3. No firewall blocking the connection

---

## License

MIT
