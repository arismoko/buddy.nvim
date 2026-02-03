# Installation

## Requirements

- **Neovim 0.10+**
- **mini.nvim** (dependency)

## Plugin Managers

=== "lazy.nvim"

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

| Platform | Path |
|----------|------|
| macOS | `~/Library/Application Support/Claude/claude_desktop_config.json` |
| Windows | `%APPDATA%\Claude\claude_desktop_config.json` |
| Linux | `~/.config/Claude/claude_desktop_config.json` |

```json
{
  "mcpServers": {
    "buddy": {
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
