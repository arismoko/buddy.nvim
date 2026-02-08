# Built-in Tools

buddy.nvim comes with a comprehensive set of built-in tools that AI assistants can use to interact with your editor.

## Overview

| Tool | Description |
|------|-------------|
| [buffer](#buffer) | Read, list, and get info on buffers |
| [edit](#edit) | Insert, replace, delete text in buffers |
| [command](#command) | Execute Ex commands |
| [navigation](#navigation) | Jump to files, lines, marks |
| [search](#search) | Find and replace in current buffer |
| [grep](#grep) | Project-wide search using vimgrep |
| [diagnostics](#diagnostics) | Get LSP diagnostics from Neovim |
| [window](#window) | Manage splits and window layout |
| [tab](#tab) | Manage tabs |
| [fold](#fold) | Control code folding |
| [visual](#visual) | Create visual selections |
| [macro](#macro) | Record and play macros |
| [register](#register) | Access Neovim registers |
| [status](#status) | Get cursor, mode, marks, registers |
| [init](#init) | Scaffold new user tools |

---

## Companion Tools

These tools are provided by separate plugins (`buddy_core`, `buddy_viz`).

| Tool | Description |
|------|-------------|
| [viz](#viz) | Visualization tool for images, charts, and diagrams |
| [buddy_manager](#buddy_manager) | View all buddy tools and navigate to source |
| [dotfyle_search](#dotfyle_search) | Search for Neovim plugins on Dotfyle |
| [lazy_manager](#lazy_manager) | Browse and edit lazy.nvim plugin config files |

---

## buffer

Read and list Neovim buffers.

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `action` | `list` \| `get_content` \| `get_info` | Yes | `list`: all loaded buffers, `get_content`: buffer text, `get_info`: buffer metadata |
| `bufnr` | number | No | Buffer number. Defaults to current buffer if omitted |
| `offset` | number | No | Line number to start reading from (0-based). For `get_content` |
| `limit` | number | No | Number of lines to read (defaults to 2000). For `get_content` |

### MCP Examples

**List all buffers:**

```json
{
  "method": "tools/call",
  "params": {
    "name": "buffer",
    "arguments": { "action": "list" }
  }
}
```

Response (raw tool return — buddy.nvim wraps this in MCP `content`):

```json
{
  "success": true,
  "buffers": [
    { "bufnr": 1, "name": "/home/user/project/init.lua", "modified": false, "filetype": "lua" },
    { "bufnr": 3, "name": "/home/user/project/README.md", "modified": true, "filetype": "markdown" }
  ]
}
```

**Read buffer content with pagination:**

```json
{
  "method": "tools/call",
  "params": {
    "name": "buffer",
    "arguments": { "action": "get_content", "bufnr": 1, "offset": 0, "limit": 100 }
  }
}
```

Response:

```json
{
  "success": true,
  "bufnr": 1,
  "name": "/home/user/project/init.lua",
  "content": "00001| local M = {}\n00002| \n00003| function M.setup()\n...",
  "line_count": 250,
  "offset": 0,
  "limit": 100,
  "showing": 100,
  "has_more": true
}
```

---

## edit

Edit buffer content.

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `action` | `insert` \| `replace` \| `delete` \| `replace_all` \| `replace_match` | Yes | Operation to perform |
| `line` | number | No | Line number (1-indexed) for insert/replace/delete |
| `end_line` | number | No | End line for replace/delete range |
| `content` | string | No | Content to insert/replace |
| `oldString` | string | No | Text to find and replace (for `replace_match`) |
| `newString` | string | No | Replacement text (for `replace_match`) |
| `replaceAll` | boolean | No | Replace all occurrences (for `replace_match`, default: false) |

### Actions

- **insert**: Insert lines at position
- **replace**: Replace line range
- **delete**: Delete line range
- **replace_all**: Replace entire buffer content
- **replace_match**: Find and replace text (recommended for precise edits)

### MCP Examples

**Find-and-replace text (recommended):**

```json
{
  "method": "tools/call",
  "params": {
    "name": "edit",
    "arguments": {
      "action": "replace_match",
      "oldString": "local old_var = 1",
      "newString": "local new_var = 42"
    }
  }
}
```

Response:

```json
{ "success": true, "action": "replace_match", "replaced": 1 }
```

**Insert lines at position:**

```json
{
  "method": "tools/call",
  "params": {
    "name": "edit",
    "arguments": {
      "action": "insert",
      "line": 5,
      "content": "-- New comment\nlocal x = 1"
    }
  }
}
```

Response:

```json
{ "success": true, "inserted": 2 }
```

**Delete a line range:**

```json
{
  "method": "tools/call",
  "params": {
    "name": "edit",
    "arguments": { "action": "delete", "line": 10, "end_line": 15 }
  }
}
```

Response:

```json
{ "success": true, "deleted": 6 }
```

---

## command

Execute Vim commands.

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `cmd` | string | Yes | The Vim command to execute (e.g., `write`, `edit file.txt`, `split`) |

### MCP Examples

**Save the current file:**

```json
{
  "method": "tools/call",
  "params": {
    "name": "command",
    "arguments": { "cmd": "write" }
  }
}
```

Response:

```json
{ "success": true, "cmd": "write", "output": "\"init.lua\" 42L, 1234B written" }
```

**Run a Lua expression:**

```json
{
  "method": "tools/call",
  "params": {
    "name": "command",
    "arguments": { "cmd": "lua vim.fn.getcwd()" }
  }
}
```

Response:

```json
{ "success": true, "cmd": "lua vim.fn.getcwd()", "result": "/home/user/project" }
```

---

## navigation

Navigate Neovim: marks, jumps, and cursor movement.

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `action` | string | Yes | See actions below |
| `line` | number | No | Line number (1-indexed) for `goto_line` or `set_mark` |
| `column` | number | No | Column number (0-indexed) |
| `file` | string | No | File path for `goto_file` |
| `mark` | string | No | Mark character (a-z or A-Z) |

### Actions

| Action | Description |
|--------|-------------|
| `goto_line` | Jump to line |
| `goto_file` | Open file |
| `set_mark` | Set mark (a-z only) |
| `goto_mark` | Jump to mark (a-z or A-Z) |
| `jump_back` | Go back in jumplist |
| `jump_forward` | Go forward in jumplist |
| `jump_list` | List jumps |

### MCP Examples

**Open a file:**

```json
{
  "method": "tools/call",
  "params": {
    "name": "navigation",
    "arguments": { "action": "goto_file", "file": "lua/buddy/init.lua" }
  }
}
```

Response:

```json
{ "success": true, "file": "lua/buddy/init.lua" }
```

**Jump to a line:**

```json
{
  "method": "tools/call",
  "params": {
    "name": "navigation",
    "arguments": { "action": "goto_line", "line": 42, "column": 0 }
  }
}
```

Response:

```json
{ "success": true, "line": 42, "column": 0 }
```

---

## search

Search and replace in current buffer.

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `action` | `find` \| `find_replace` | Yes | Search or search and replace |
| `pattern` | string | Yes | Search pattern |
| `replacement` | string | No | Replacement text (for `find_replace`) |
| `global` | boolean | No | Replace all occurrences |
| `ignore_case` | boolean | No | Case insensitive search |
| `whole_word` | boolean | No | Match whole words only |

### MCP Examples

**Search for a pattern:**

```json
{
  "method": "tools/call",
  "params": {
    "name": "search",
    "arguments": { "action": "find", "pattern": "TODO", "ignore_case": true }
  }
}
```

Response:

```json
{ "success": true, "pattern": "TODO", "total": 3, "incomplete": false }
```

**Find and replace:**

```json
{
  "method": "tools/call",
  "params": {
    "name": "search",
    "arguments": {
      "action": "find_replace",
      "pattern": "old_name",
      "replacement": "new_name",
      "global": true
    }
  }
}
```

Response:

```json
{ "success": true, "pattern": "old_name", "replacement": "new_name", "message": "3 substitutions on 3 lines" }
```

---

## grep

Project-wide search using vimgrep with quickfix list.

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `pattern` | string | Yes | Search pattern to grep for |
| `file_pattern` | string | No | File pattern (default: `**/*`) |
| `path` | string | No | Directory to search in (default: current working directory) |

### MCP Examples

**Search project for a pattern:**

```json
{
  "method": "tools/call",
  "params": {
    "name": "grep",
    "arguments": { "pattern": "require.*buddy", "file_pattern": "**/*.lua" }
  }
}
```

Response:

```json
{
  "success": true,
  "pattern": "require.*buddy",
  "file_pattern": "**/*.lua",
  "matches": [
    { "filename": "lua/buddy/init.lua", "lnum": 3, "text": "local log = require(\"buddy.log\")" },
    { "filename": "lua/buddy/config.lua", "lnum": 1, "text": "--- Configuration for buddy" }
  ],
  "total": 15,
  "showing": 10
}
```

!!! note "Result limit"
    Grep returns up to 10 matches in the response. All matches are available in the quickfix list (`:copen`).

---

## diagnostics

Get LSP diagnostics from Neovim.

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `bufnr` | number | No | Buffer number. Omit for all buffers, 0 for current |
| `severity` | `error` \| `warning` \| `info` \| `hint` \| `all` | No | Filter by severity (default: `all`) |
| `path` | string | No | Filter to files matching this path pattern |
| `scan_dir` | string | No | Directory to scan for files (opens files to trigger LSP) |
| `pattern` | string | No | Glob pattern for scan_dir (default: `**/*.lua`) |

### MCP Examples

**Get all diagnostics for current buffer:**

```json
{
  "method": "tools/call",
  "params": {
    "name": "diagnostics",
    "arguments": { "bufnr": 0, "severity": "error" }
  }
}
```

Response:

```json
{
  "success": true,
  "total": 2,
  "counts": { "error": 2, "warning": 0, "info": 0, "hint": 0 },
  "files": [
    {
      "file": "/home/user/project/init.lua",
      "count": 2,
      "diagnostics": [
        { "line": 10, "col": 5, "severity": "error", "message": "Undefined global `foo`", "source": "Lua Diagnostics.", "code": "undefined-global" },
        { "line": 25, "col": 12, "severity": "error", "message": "Type mismatch", "source": "Lua Diagnostics." }
      ]
    }
  ]
}
```

**Scan a directory for diagnostics:**

```json
{
  "method": "tools/call",
  "params": {
    "name": "diagnostics",
    "arguments": { "scan_dir": "lua/buddy", "pattern": "**/*.lua", "severity": "error" }
  }
}
```

!!! note "scan_dir behavior"
    When `scan_dir` is provided, buddy.nvim opens matching files to trigger LSP analysis, waits up to 10 seconds for diagnostics, then returns results. Temporary buffers are wiped after scanning.

---

## window

Manage Neovim windows.

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `action` | string | Yes | See actions below |
| `winnr` | number | No | Window number |
| `direction` | `h` \| `j` \| `k` \| `l` | No | Direction for focus |

### Actions

| Action | Description |
|--------|-------------|
| `list` | List all windows |
| `focus` | Focus a window |
| `split` | Horizontal split |
| `vsplit` | Vertical split |
| `close` | Close window |
| `only` | Keep only current window |

---

## tab

Manage Neovim tabs.

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `action` | string | Yes | See actions below |
| `tabnr` | number | No | Tab number for `goto` |
| `file` | string | No | File path for `new` tab |

### Actions

| Action | Description |
|--------|-------------|
| `list` | List all tabs |
| `new` | Create new tab |
| `close` | Close current tab |
| `next` | Go to next tab |
| `prev` | Go to previous tab |
| `goto` | Jump to specific tab |
| `first` | Jump to first tab |
| `last` | Jump to last tab |

---

## fold

Manage code folds.

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `action` | string | Yes | See actions below |
| `start_line` | number | No | Starting line for create |
| `end_line` | number | No | Ending line for create |

### Actions

| Action | Description |
|--------|-------------|
| `create` | Create fold from start_line to end_line |
| `open` | Open fold |
| `close` | Close fold |
| `toggle` | Toggle fold |
| `open_all` | Expand all folds |
| `close_all` | Collapse all folds |
| `delete` | Remove fold at line |

---

## visual

Create visual selections.

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `start_line` | number | Yes | Starting line (1-indexed) |
| `start_col` | number | Yes | Starting column (0-indexed) |
| `end_line` | number | Yes | Ending line (1-indexed) |
| `end_col` | number | Yes | Ending column (0-indexed) |

---

## macro

Record and play macros.

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `action` | `record` \| `stop` \| `play` | Yes | Macro action |
| `register` | string | No | Register to use (a-z). Defaults to `q` |
| `count` | number | No | Number of times to play macro. Defaults to 1 |

---

## register

Access Neovim registers.

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `action` | `get` \| `set` \| `list` | Yes | Register action |
| `name` | string | No | Register name (a-z, ", +, *, 0-9) |
| `content` | string | No | Content to set (required for `set`) |

---

## status

Get comprehensive Neovim status including cursor position, mode, marks, and registers.

### Parameters

None required.

---

## init

Scaffold a new buddy Lua tool with the correct structure.

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `name` | string | Yes | Tool name (snake_case, e.g. `my_tool`) |
| `description` | string | No | Tool description |
| `path` | string | No | Custom path for tool (default: `stdpath('data')/buddy-tools/`) |

### MCP Example

**Create a new tool:**

```json
{
  "method": "tools/call",
  "params": {
    "name": "init",
    "arguments": { "name": "my_helper", "description": "A custom helper tool" }
  }
}
```

The tool creates a complete plugin structure at `~/.local/share/nvim/buddy-tools/my_helper/` with:

```
my_helper/
  plugin/my_helper.lua     -- Commands & keymaps (entry point)
  lua/
    my_helper/
      init.lua             -- Public API
      config.lua           -- Configuration with defaults
    buddy.lua              -- MCP tool definition
```

---

## viz

Visualization tool for images, charts, and diagrams.

*Provided by the companion plugin `buddy_viz`.*

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `action` | `chart` \| `image` \| `open` \| `pikchr` | Yes | The visualization action to perform |
| `type` | `bar` \| `line` \| `pie` | No | Chart type (for action=chart) |
| `data` | array | No | Data points for chart (array of objects with label and values) |
| `title` | string | No | Chart title (for action=chart) |
| `series` | array | No | Series names matching values array (for action=chart) |
| `path` | string | No | Absolute path to image file (for action=image) |
| `source` | string | No | Image source: URL, file path, or 'clipboard' (for action=open) |
| `diagram` | string | No | Pikchr diagram code (for action=pikchr) |

---

## buddy_manager

View all buddy tools and navigate to their source files.

*Provided by the companion plugin `buddy_core`.*

### Parameters

None.

---

## dotfyle_search

Search for Neovim plugins on Dotfyle.

*Provided by the companion plugin `buddy_core`.*

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `message` | string | No | Search query for plugins |

---

## lazy_manager

Browse and edit lazy.nvim plugin config files.

*Provided by the companion plugin `buddy_core`.*

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `message` | string | No | Search query to filter config files |
