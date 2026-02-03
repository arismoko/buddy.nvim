# lua/buddy/tools/builtin/

## Responsibility

The builtin tools module provides 15+ core tools for interacting with Neovim via MCP. These tools expose common Neovim operations (buffer manipulation, editing, navigation, diagnostics, etc.) to AI clients, enabling rich editor control without leaving the AI interface.

Key responsibilities:
- **Buffer operations**: List, read, get info (buffer tool)
- **Text editing**: Insert, replace, delete, text search/replace (edit tool)
- **Navigation**: Jump to files, lines, marks, jumplist (navigation tool)
- **Search**: In-buffer search and replace (search tool)
- **Grep**: Project-wide search using vimgrep (grep tool)
- **Diagnostics**: Expose LSP diagnostics (diagnostics tool)
- **Window management**: Splits, layout, focus (window tool)
- **Tab management**: Create, close, switch tabs (tab tool)
- **Code folding**: Toggle folds, set fold level (fold tool)
- **Visual selections**: Create and manage visual selections (visual tool)
- **Macros**: Record and play macros (macro tool)
- **Registers**: Access yank/paste registers (register tool)
- **Status**: Get cursor position, mode, marks (status tool)
- **Commands**: Execute Ex commands (command tool)
- **Init tool**: Scaffold new user tools (init tool)

## Design

### Tool Organization
- **Each tool = separate file**: `buffer.lua`, `edit.lua`, `navigation.lua`, etc.
- **Action-based pattern**: Most tools use `action` parameter to dispatch to sub-functions
- **Consistent format**: `name`, `title`, `description`, `input_schema`, `run` function
- **MCP annotations**: `readOnlyHint` for read-only tools, `destructiveHint` for editing tools

### Tool Pattern
```lua
return {
  name = "tool_name",
  title = "Tool Title",
  description = "What the tool does",
  annotations = { readOnlyHint = true },  -- or destructiveHint: true
  input_schema = {
    type: "object",
    properties: {
      action: { type: "string", enum: [...], description: "..." },
      param1: { type: "string", description: "..." },
    },
    required: [ "action" ],
  },
  run: function(args)
    if args.action == "action1" then
      -- ...handle action1
    elseif args.action == "action2" then
      -- ...handle action2
    end
  end,
}
```

### Tool List (15 built-ins)

| Tool | Purpose | Read-Only |
|------|---------|-----------|
| `buffer` | List, read, get info on buffers | ✓ |
| `edit` | Insert, replace, delete text | ✗ |
| `navigation` | Jump to files, lines, marks | ✗ (cursor moves) |
| `search` | Find/replace in current buffer | ✗ |
| `grep` | Project-wide search | ✓ |
| `diagnostics` | Get LSP diagnostics | ✓ |
| `window` | Manage splits and layout | ✗ |
| `tab` | Manage tabs | ✗ |
| `fold` | Control code folding | ✗ |
| `visual` | Create visual selections | ✗ |
| `macro` | Record and play macros | ✗ |
| `register` | Access yank/paste registers | ✓ |
| `status` | Get cursor, mode, marks | ✓ |
| `command` | Execute Ex commands | ✗ |
| `init` | Scaffold new user tools | ✗ |

### Buffer Tool (buffer.lua)
**Actions**: `list`, `get_content`, `get_info`

**list**: Return all loaded buffers with metadata
```lua
{
  buffers: [
    { bufnr: 1, name: "/path/to/file", modified: false, filetype: "lua" },
    ...
  ],
  success: true
}
```

**get_content**: Return buffer text with line numbers and diagnostics
```lua
{
  success: true,
  bufnr: 1,
  name: "/path/to/file",
  content: "00001| line1\n00002| line2\n...",
  line_count: 100,
  offset: 0,
  limit: 2000,
  showing: 100,
  has_more: false,
  lsp_clients: [{ name: "lua_ls", id: 1 }],
  diagnostics: [{ line: 10, col: 5, severity: "error", message: "..." }],
  diagnostic_counts: { error: 1, warning: 2, info: 0, hint: 0 }
}
```

**get_info**: Return buffer metadata
```lua
{ success: true, bufnr: 1, name: "...", filetype: "lua", modified: false, line_count: 100 }
```

**Features**: 
- Ignores configured filetypes (e.g., terminals)
- Truncates long lines to 2000 chars
- Includes LSP diagnostics and clients
- Uses 5-digit padded line numbers (matches opencode)

### Edit Tool (edit.lua)
**Actions**: `insert`, `replace`, `delete`, `replace_all`, `replace_match`

**insert**: Insert lines at position
```lua
edit({ action: "insert", line: 10, content: "new line\n" })
→ { success: true, inserted: 1 }
```

**replace**: Replace line range
```lua
edit({ action: "replace", line: 10, end_line: 20, content: "replacement" })
→ { success: true, replaced: 11, inserted: 1 }
```

**delete**: Delete line range
```lua
edit({ action: "delete", line: 10, end_line: 20 })
→ { success: true, deleted: 11 }
```

**replace_all**: Replace entire buffer
```lua
edit({ action: "replace_all", content: "all new content\n" })
→ { success: true, replaced_all: true, lines: 1 }
```

**replace_match**: Text search and replace (recommended)
```lua
edit({ action: "replace_match", oldString: "old text", newString: "new text", replaceAll: false })
→ { success: true, action: "replace_match", replaced: 1 }
```

**Features**:
- Works on unsaved buffers (unlike file editing)
- `replace_match` uses plain text search (exact match)
- Validates `oldString` uniqueness if `replaceAll: false`
- Supports both string and array of strings for content

### Navigation Tool (navigation.lua)
**Actions**: `goto_line`, `goto_file`, `set_mark`, `goto_mark`, `jump_back`, `jump_forward`, `jump_list`

**goto_line**: Jump to line/column
```lua
navigation({ action: "goto_line", line: 100, column: 5 })
→ { success: true, line: 100, column: 5 }
```

**goto_file**: Open file in Neovim
```lua
navigation({ action: "goto_file", file: "/path/to/file" })
→ { success: true, file: "/path/to/file" }
```

**set_mark**: Set a mark (a-z)
```lua
navigation({ action: "set_mark", mark: "a", line: 10, column: 5 })
→ { success: true, mark: "a", line: 10, column: 5, message: "Mark a set at line 10, column 5" }
```

**goto_mark**: Jump to mark (a-z or A-Z)
```lua
navigation({ action: "goto_mark", mark: "A" })
→ { success: true, mark: "A", line: 50, column: 0 }
```

**jump_back/forward**: Navigate jumplist
```lua
navigation({ action: "jump_back" })
→ { success: true, direction: "back" }
```

**jump_list**: Get jumplist
```lua
{
  success: true,
  jumps: [{ bufnr: 1, filename: "...", lnum: 10, col: 5 }, ...],
  current: 5,
  total: 20
}
```

**Features**:
- Uses `nvim_buf_set_mark` (like TypeScript)
- Uses `feedkeys` for `<C-o>` and `<C-i>` (jumplist navigation)
- Validates mark names (a-z for set, a-z or A-Z for goto)

### Search Tool (search.lua)
**Actions**: `find`, `replace`

**find**: Find text in current buffer
```lua
search({ action: "find", pattern: "function", case_sensitive: false })
→ { success: true, matches: [{ line: 10, col: 5, text: "..." }, ...] }
```

**replace**: Replace text in buffer
```lua
search({ action: "replace", oldText: "old", newText: "new", replaceAll: true })
→ { success: true, replaced: 5 }
```

### Grep Tool (grep.lua)
**Actions**: `search`

**search**: Project-wide search using vimgrep
```lua
grep({ action: "search", pattern: "TODO", file_pattern: "*.lua" })
→ { success: true, results: [{ file: "...", line: 10, col: 5, text: "..." }, ...] }
```

### Diagnostics Tool (diagnostics.lua)
**Actions**: `get`

**get**: Get LSP diagnostics for buffer or workspace
```lua
diagnostics({ action: "get", bufnr: 1 })
→ { success: true, diagnostics: [...], counts: { error: 1, warning: 2, ... } }
```

### Window Tool (window.lua)
**Actions**: `split`, `vsplit`, `close`, `focus`, `layout`

**split/vsplit**: Create horizontal/vertical split
```lua
window({ action: "split" })
→ { success: true, windows: [...] }
```

**close**: Close current window
```lua
window({ action: "close" })
→ { success: true }
```

**focus**: Focus window by ID
```lua
window({ action: "focus", window_id: 2 })
→ { success: true }
```

**layout**: Get window layout
```lua
window({ action: "layout" })
→ { success: true, layout: [...] }
```

### Tab Tool (tab.lua)
**Actions**: `list`, `new`, `close`, `goto`

**list**: List tabs
```lua
tab({ action: "list" })
→ { success: true, tabs: [{ id: 1, name: "..." }, ...] }
```

**new**: Create new tab
```lua
tab({ action: "new" })
→ { success: true, tab_id: 2 }
```

**goto**: Switch to tab
```lua
tab({ action: "goto", tab_id: 1 })
→ { success: true }
```

### Fold Tool (fold.lua)
**Actions**: `toggle`, `open`, `close`, `open_all`, `close_all`

**toggle**: Toggle fold at cursor
```lua
fold({ action: "toggle" })
→ { success: true }
```

**open_all/close_all**: Open/close all folds
```lua
fold({ action: "open_all" })
→ { success: true }
```

### Visual Tool (visual.lua)
**Actions**: `select`, `clear`

**select**: Create visual selection
```lua
visual({ action: "select", start_line: 10, end_line: 20 })
→ { success: true }
```

### Macro Tool (macro.lua)
**Actions**: `record`, `play`, `list`

**record**: Record macro
```lua
macro({ action: "record", register: "q" })
→ { success: true }
```

**play**: Play macro
```lua
macro({ action: "play", register: "q", count: 5 })
→ { success: true, times: 5 }
```

### Register Tool (register.lua)
**Actions**: `get`, `set`

**get**: Get register contents
```lua
register({ action: "get", register: "+" })
→ { success: true, content: "...", type: "linewise" }
```

**set**: Set register contents
```lua
register({ action: "set", register: "+", content: "text" })
→ { success: true }
```

### Status Tool (status.lua)
**Actions**: `get`

**get**: Get cursor position, mode, marks
```lua
status({ action: "get" })
→ {
  success: true,
  cursor: { line: 10, column: 5, bufnr: 1 },
  mode: "normal",
  marks: [{ name: "a", line: 10, col: 0 }, ...],
  registers: { ... }
}
```

### Command Tool (command.lua)
**Actions**: `execute`

**execute**: Run Ex command
```lua
command({ action: "execute", cmd: "write" })
→ { success: true, output: "..." }
```

### Init Tool (init.lua)
**Actions**: `scaffold`

**scaffold**: Scaffold new user tool
```lua
init({ action: "scaffold", name: "my_tool", path: "~/.local/share/nvim/buddy-tools/" })
→ { success: true, created: ["/path/to/my_tool.lua", ...] }
```

**Features**:
- Creates buddy.lua template
- Sets up tool structure (name, description, input_schema, run)
- Creates optional setup block for keymaps/commands

## Flow

### Tool Registration Flow
```
buddy.start()
  → tools.load_builtins()
    → require("buddy.tools.builtin.buffer")
    → require("buddy.tools.builtin.edit")
    → ... (all 15+ tools)
    → For each tool: check if disabled in config → registry.register(tool)
```

### Buffer Read Flow
```
AI: tools/call with name="buffer", arguments={ action: "get_content", bufnr: 1 }
  → executor.execute("buffer", args)
    → Validate args
    → tool.run({ action: "get_content", bufnr: 1 })
      → bufnr = 1 or current buffer
      → lines = nvim_buf_get_lines(bufnr, 0, limit, false)
      → Format with line numbers
      → Get diagnostics: nvim_diagnostic_get(bufnr)
      → Get LSP clients: nvim_lsp_get_clients({ bufnr })
      → Return structured result
    → Wrap in MCP format
  → AI receives buffer content with metadata
```

### Edit Flow
```
AI: tools/call with name="edit", arguments={ action: "replace_match", oldString: "...", newString: "..." }
  → executor.execute("edit", args)
    → Validate args
    → tool.run({ action: "replace_match", oldString, newString })
      → Read buffer content
      → Find oldString with plain text search
      → Validate uniqueness if not replaceAll
      → Replace oldString with newString
      → Write back to buffer via nvim_buf_set_lines
      → Return { success: true, replaced: 1 }
    → Wrap in MCP format
  → AI receives edit confirmation
```

### Navigation Flow
```
AI: tools/call with name="navigation", arguments={ action: "goto_file", file: "/path/to/file" }
  → executor.execute("navigation", args)
    → Validate args
    → tool.run({ action: "goto_file", file: "/path/to/file" })
      → vim.cmd("edit " .. vim.fn.fnameescape(file))
      → Return { success: true, file: "/path/to/file" }
    → Wrap in MCP format
  → AI receives confirmation, Neovim opens file
```

### Grep Flow
```
AI: tools/call with name="grep", arguments={ action: "search", pattern: "TODO" }
  → executor.execute("grep", args)
    → Validate args
    → tool.run({ action: "search", pattern: "TODO" })
      → vim.fn.system("vimgrep /TODO/j **/*")
      → Parse results from quickfix list
      → Return { success: true, results: [...] }
    → Wrap in MCP format
  → AI receives search results
```

### Status Check Flow
```
AI: tools/call with name="status", arguments={ action: "get" }
  → executor.execute("status", args)
    → Validate args
    → tool.run({ action: "get" })
      → cursor = nvim_win_get_cursor(0)
      → mode = nvim_get_mode().mode
      → marks = ... (iterate marks a-z)
      → registers = ... (get registers)
      → Return { success: true, cursor, mode, marks, registers }
    → Wrap in MCP format
  → AI receives editor state
```

## Integration

### Upward Dependencies
- **vim.api**: Neovim API (buffers, windows, tabs, marks, diagnostics, etc.)
- **vim.fn**: Neovim functions (fnameescape, getjumplist, system, etc.)
- **vim.cmd**: Execute Ex commands
- **buddy.config**: Check disabled tools, ignored filetypes

### Downward Dependencies
- **tools.init**: Registered via `tools.load_builtins()`
- **mcp.methods**: Listed in `tools/list`, executed via `tools/call`

### Neovim API Usage
- **Buffers**: `nvim_list_bufs`, `nvim_buf_get_lines`, `nvim_buf_set_lines`, `nvim_buf_line_count`, `nvim_buf_get_name`, `nvim_buf_is_valid`, `nvim_buf_is_loaded`, `nvim_buf_set_mark`
- **Windows**: `nvim_list_wins`, `nvim_win_get_cursor`, `nvim_win_set_cursor`, `nvim_win_call`
- **Tabs**: `nvim_list_tabpages`, `nvim_tabpage_list_wins`
- **Diagnostics**: `nvim_diagnostic_get`, `nvim_diagnostic_severity`
- **LSP**: `nvim_lsp_get_clients`
- **Marks**: `nvim_buf_get_mark`, `nvim_buf_set_mark`
- **Registers**: `nvim_call_function("getreg", ...)`
- **Commands**: `vim.cmd()`

### Tool Interactions
- **Buffer → Edit**: Edit operates on buffers listed by Buffer
- **Status → Buffer**: Status uses current buffer info
- **Diagnostics → Buffer**: Diagnostics retrieved per buffer
- **Navigation → Status**: Navigation changes cursor (updates status)
- **Search → Grep**: Search is buffer-local, Grep is project-wide

### Configuration
- **Disabled tools**: Checked in `load_builtins()`, skip registration if disabled
- **Ignored filetypes**: Buffer tool filters out configured filetypes (e.g., terminals)

### Error Handling
- **pcall**: All Neovim API calls wrapped in pcall for safety
- **Validation errors**: Return `{ success: false, error: "..." }`
- **Neovim errors**: Caught and returned as error messages

### Performance
- **Line limiting**: Buffer tool limits to 2000 lines by default (offset, limit params)
- **Line truncation**: Long lines truncated to 2000 characters
- **Async operations**: All tools are sync (could be async in future)

### Compatibility
- **Opencode tools**: Format matches opencode read/edit tools (line numbers, search/replace)
- **TypeScript tools**: Navigation matches TypeScript tool patterns (marks, jumplist)

### Testing
- **Mock API**: Tests can mock vim.api for unit testing
- **Isolated tools**: Each tool can be tested independently
