# Installation

## Requirements

- **Neovim 0.10+**
- **mini.nvim** (dependency)
- **nvim-nio** (dependency — async operations)

## Plugin Managers

=== "lazy.nvim"

    ```lua
    {
      "arismoko/buddy.nvim",
      dependencies = {
        "echasnovski/mini.nvim",
        "nvim-neotest/nvim-nio",
      },
      lazy = false,
      config = function()
        require("buddy").setup({
          auto_start = true,
          port = 7234,
          -- Recommended: enable buddy_core for BuddyManager and other built-in tools
          extras = { "buddy_core" },
        })
      end,
    }
    ```

=== "packer.nvim"

    ```lua
    use {
      "arismoko/buddy.nvim",
      requires = {
        "echasnovski/mini.nvim",
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

!!! note "Auth with direct SSE"
    With default `auth = true`, direct connections must send `Authorization: Bearer <token>`.
    If your MCP client cannot send auth headers, use `buddy-mcp-proxy` instead.

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

## Companion Tools (Recommended)

buddy.nvim ships with optional companion tools bundled inside the repo. Enable them via the `extras` option:

```lua
require("buddy").setup({
  extras = { "buddy_core" },  -- adds BuddyManager, DotfyleSearch, LazyManager
})
```

### BuddyManager

`:BuddyManager` opens an interactive picker to browse all installed buddy tools and jump directly to their source files. It's the fastest way to explore what's available or debug a custom tool.

```vim
:BuddyManager
```

You can also bind it to a key:

```lua
vim.keymap.set("n", "<leader>bb", "<Plug>(BuddyManager)", { desc = "Buddy Manager" })
```

### Other buddy_core tools

| Command | Description |
|---------|-------------|
| `:DotfyleSearch` | Search for Neovim plugins on dotfyle.com |
| `:LazyManager` | Browse and jump to lazy.nvim plugin config files |

### buddy_viz (optional)

For visualization tools (charts, image viewing, Pikchr diagrams):

```lua
require("buddy").setup({
  extras = { "buddy_core", "buddy_viz" },
})
```

---

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
