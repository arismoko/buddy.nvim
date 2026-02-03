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

## Quick Start

```lua
require("buddy").setup({
  auto_start = true,
  port = 7234,
})
```

## Features

- 🔌 **MCP Protocol** - Full Model Context Protocol implementation via HTTP/SSE
- 🛠️ **Built-in Tools** - Buffer, edit, navigation, search, diagnostics, and more
- 🎯 **Dual Interface** - Same tool works via MCP and Neovim keymaps/commands
- 🔧 **Extensible** - Create custom tools in Lua with simple API
- 🔄 **Hot Reload** - Edit tool files, keymaps update automatically
- 🔒 **Secure** - Localhost-only by default

## Documentation

- [Installation](installation.md) - Get up and running
- [Configuration](configuration.md) - Customize behavior
- [Tools Reference](tools.md) - Built-in tool documentation
- [Creating Tools](creating-tools.md) - Build your own tools
