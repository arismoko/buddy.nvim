# buddy-mcp-proxy

MCP proxy server for buddy.nvim sessions. This proxy allows OpenCode (or any MCP client) to connect to multiple buddy.nvim instances and switch between them dynamically.

## How it works

1. **Sessions Registry**: Reads buddy.nvim session info from `~/.local/state/buddy/sessions.json` (or `$XDG_STATE_HOME/buddy/sessions.json`)
2. **Meta-tools**: Exposes tools to list, select, and manage sessions
3. **Tool Proxying**: Once a session is selected, proxies all its tools to the MCP client

## Meta-tools

- `buddy_sessions_list` - List all available buddy.nvim sessions
- `buddy_session_select` - Select a session by ID to connect to
- `buddy_session_info` - Get info about the currently selected session
- `buddy_refresh` - Refresh sessions list and reconnect if needed

## Installation

```bash
cd mcp/buddy-mcp-proxy
bun install
bun run build
```

## Usage

### With OpenCode

Update `~/.config/opencode/opencode.jsonc`:

```jsonc
{
  "mcp": {
    "vim": {
      "type": "local",
      "command": [
        "node",
        "/home/ari/Work/tries/2026-01-26-nvim-buddy-v3/mcp/buddy-mcp-proxy/dist/index.js"
      ]
    }
  }
}
```

Or using bunx (if published):

```json
{
  "mcp": {
    "servers": {
      "buddy": {
        "command": "bunx",
        "args": ["buddy-mcp-proxy"]
      }
    }
  }
}
```

### Development

```bash
# Run directly with bun (no build needed)
bun run dev

# Build for production
bun run build

# Type check
bun run typecheck
```

## Sessions Registry Format

The proxy understands buddy.nvim's format (recommended) and a legacy array format.

Recommended (buddy.nvim):

```json
{
  "version": 1,
  "sessions": {
    "<session_id>": {
      "host": "127.0.0.1",
      "port": 52341,
      "cwd": "/home/user/project-a",
      "label": "project-a",
      "pid": 12345,
      "started_at": 1730000000,
      "last_seen": 1730000030
    }
  }
}
```

## Logs

All logs are written to stderr only (as required by MCP stdio transport).
