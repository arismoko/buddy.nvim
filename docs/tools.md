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

---

## command

Execute Vim commands.

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `cmd` | string | Yes | The Vim command to execute (e.g., `write`, `edit file.txt`, `split`) |

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
| `mark` | string | No | Mark character (a-z) |

### Actions

| Action | Description |
|--------|-------------|
| `goto_line` | Jump to line |
| `goto_file` | Open file |
| `set_mark` | Set mark |
| `goto_mark` | Jump to mark |
| `jump_back` | Go back in jumplist |
| `jump_forward` | Go forward in jumplist |
| `jump_list` | List jumps |

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

---

## grep

Project-wide search using vimgrep with quickfix list.

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `pattern` | string | Yes | Search pattern to grep for |
| `file_pattern` | string | No | File pattern (default: `**/*`) |
| `path` | string | No | Directory to search in (default: current working directory) |

---

## diagnostics

Get LSP diagnostics from Neovim.

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `bufnr` | number | No | Buffer number. Omit for all buffers, 0 for current |
| `severity` | `error` \| `warn` \| `info` \| `hint` \| `all` | No | Filter by severity (default: `all`) |
| `path` | string | No | Filter to files matching this path pattern |
| `scan_dir` | string | No | Directory to scan for files |
| `pattern` | string | No | Glob pattern for scan_dir (default: `**/*.lua`) |

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

---

## viz

Visualization tool for images, charts, and diagrams.

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

### Parameters

None.

---

## dotfyle_search

Search for Neovim plugins on Dotfyle.

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `message` | string | No | Search query for plugins |

---

## lazy_manager

Browse and edit lazy.nvim plugin config files.

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `message` | string | No | Search query to filter config files |
