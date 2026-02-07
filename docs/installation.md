# Installation

## Requirements

- **Neovim 0.10+**
- **mini.nvim** (dependency)

## Plugin Managers

=== "lazy.nvim"

    ```lua
    {
      "arismoko/buddy.nvim",
      dependencies = {
        "echasnovski/mini.nvim",
        -- Optional: Companion plugins
        -- { "arismoko/buddy_core.nvim" }, -- Core tools (buddy_manager, dotfyle, lazy)
        -- { "arismoko/buddy_viz.nvim" },  -- Visualization tools (charts, images)
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

=== "packer.nvim"

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

=== "Manual"

    Clone to your Neovim packages directory:

    ```bash
    git clone https://github.com/arismoko/buddy.nvim \
      ~/.local/share/nvim/site/pack/plugins/start/buddy.nvim
    ```

## Connecting MCP Clients

buddy.nvim uses **HTTP + Server-Sent Events (SSE)** transport, compatible with modern MCP clients.

There are two ways to connect:

### Option A: Via Proxy (Recommended)

The [`buddy-mcp-proxy`](https://www.npmjs.com/package/buddy-mcp-proxy) automatically discovers running Neovim sessions and supports switching between multiple instances. No port configuration needed.

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

| Platform | Path |
|----------|------|
| macOS | `~/Library/Application Support/Claude/claude_desktop_config.json` |
| Windows | `%APPDATA%\Claude\claude_desktop_config.json` |
| Linux | `~/.config/Claude/claude_desktop_config.json` |

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

## Verify Installation

Run the health check inside Neovim:

```vim
:checkhealth buddy
```

Check if the server is running:

```lua
:lua print(vim.inspect(require('buddy').status()))
-- { running = true, port = 7234 }
```
