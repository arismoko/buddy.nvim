# TODO: Plugin Architecture Refactor

Goal: Tools are standalone Neovim plugins that optionally expose MCP tools via buddy.nvim.

## Architecture (following nvim-best-practices-plugin-template)

```
my-tool/
  plugin/
    my-tool.lua         -- Entry point: commands, keymaps (lazy loading)
  lua/
    my-tool/
      init.lua          -- Public API: M.setup(), M.run(), etc.
      config.lua        -- Configuration with defaults
    buddy.lua           -- MCP interface: thin wrapper calling init.lua
```

**Key principles:**
- `plugin/*.lua` = entry point, defines commands/keymaps, lazy loads require()
- `init.lua` = public API, all functions other code should call
- `config.lua` = configuration with sensible defaults
- `buddy.lua` = MCP tool definition, calls into init.lua's public API
- nvim-buddy discovers buddy.lua and registers MCP metadata

## Changes

### 1. Simplify discovery.lua [DONE]
- [x] Remove `is_tool_enabled()` check - just register everything found
- [x] Remove `integrations.register_setup()` call - discovery is pure MCP data only
- [x] Keep it simple: scan `lua/*/buddy.lua`, register tool metadata

### 2. Simplify config.lua [DONE]
- [x] Remove `tools = {}` from defaults
- [x] Remove `get_tool_opts(name)` function
- [x] Remove `is_tool_enabled(name)` function
- [x] Keep only: `host`, `port`, `auto_start`, `log_level`

### 3. Simplify executor.lua [DONE]
- [x] Remove central config lookup for tool opts
- [x] Tools get config from their own module, not from nvim-buddy

### 4. Remove integrations.lua [DONE]
- [x] Delete integrations.lua - plugins own their commands/keymaps
- [x] Remove all calls to integrations.* from discovery.lua
- [x] Remove all calls to integrations.* from init.lua

### 5. Rewrite builtin/init.lua (scaffolding tool) [DONE]
- [x] Replace string templates with a template folder
- [x] Single template (YAGNI) - covers the common case
- [x] Copy template folder, rename to user's tool name
- [x] Template includes comments guiding idiomatic buddy plugin creation

### 6. Create template folder [DONE]
Location: `lua/buddy/tools/builtin/template/`

Structure:
```
template/
  plugin/
    TOOL_NAME.lua       -- Entry point: commands, keymaps
  lua/
    TOOL_NAME/
      init.lua          -- Public API: M.setup(), M.run()
      config.lua        -- Configuration with defaults
    buddy.lua           -- MCP wrapper: run() calls init.lua
```

Template includes comments explaining:
- Idiomatic Neovim plugin structure (nvim-best-practices)
- buddy.lua as thin MCP wrapper calling public API
- How to add args and validate them
- Multi-tool pattern (tools array)
- Actions pattern (manual routing in run())

### 7. Remove watcher.lua [DONE]
- [x] Delete watcher.lua - YAGNI
- [x] Remove watcher config option from config.lua
- [x] Remove watcher.start() call from init.lua
- [x] If MCP metadata changes, user restarts nvim-buddy

## Remaining Work

### 8. Update buddy-core to new structure
- [ ] Update buddy-core/lua/buddy-core/init.lua to call register() on tools
- [ ] Ensure buddy-core follows the idiomatic plugin pattern

## Out of Scope
- Backward compatibility with old structure
- Multiple templates (YAGNI)
- Central tool configuration
