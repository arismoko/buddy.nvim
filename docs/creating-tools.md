# Creating Tools

Tools are defined in a `buddy.lua` file at `lua/{plugin}/buddy.lua`. buddy.nvim discovers these automatically.

## Basic Tool Structure

```lua
return {
  name = "tool_name",           -- Tool name (required)
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

## Tool Formats

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
        return "Hello, " .. args.name
      end,
    },
  }
}
```

### Format 2: Action-Based Tool

For tools with multiple related actions, define a single `input_schema` with an `action` enum and route manually in your `run` function:

```lua
-- lua/buddy_viz/buddy.lua
return {
  name = "viz",
  description = "Visualization tool for images, charts, and diagrams",
  input_schema = {
    type = "object",
    properties = {
      action = {
        type = "string",
        enum = { "chart", "image", "open", "pikchr" },
        description = "The visualization action to perform",
      },
      -- Chart action args
      type = { type = "string", enum = { "bar", "line", "pie" }, description = "Chart type (for action=chart)" },
      title = { type = "string", description = "Chart title (for action=chart)" },
      -- Image action args
      path = { type = "string", description = "Path to image file (for action=image)" },
      -- Other action-specific args...
    },
    required = { "action" },
  },
  run = function(args)
    local action = args.action

    if action == "chart" then
      -- handle chart
      return { rendered = true, chart_type = args.type }
    elseif action == "image" then
      -- handle image
      return { rendered = true, path = args.path }
    else
      error("Unknown action: " .. action)
    end
  end,
}
```

This pattern keeps all action logic in one file with explicit routing via if/elseif

## Parameter Types

| Type | Description | Example |
|------|-------------|---------|
| `string` | Text value | `{ type = "string" }` |
| `number` | Numeric value | `{ type = "number" }` |
| `boolean` | True/false | `{ type = "boolean" }` |
| `array` | List of values | `{ type = "array", items = { type = "string" } }` |
| `object` | Key-value pairs | `{ type = "object" }` |

### Enums

Constrain string values to a set:

```lua
action = { 
  type = "string", 
  enum = { "create", "read", "update", "delete" },
  description = "create: make new, read: fetch, update: modify, delete: remove"
}
```

## Adding Keymaps, Commands, Autocmds

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

- ✅ Works via MCP when AI calls `my_tool`
- ✅ Works via `<leader>mt` keymap
- ✅ Works via `:MyTool` command
- ✅ Runs on `BufEnter` for markdown files

!!! tip "Hot Reload"
    Edit the file, keymaps and commands update automatically. No restart needed.

## Async Tools

For long-running operations, either return a cancel function or explicitly
declare async mode with `context.start_async()`:

### Option 1: Return a Cancel Function

Return a function from `run()` to signal async mode. The function is used for
cancellation. Call `context(result)` when the work completes.

```lua
run = function(args, context)
  -- Start async work
  local handle = start_async_operation(function(result)
    context(result)  -- Call context to complete
  end)
  -- Return cancel function (signals async mode)
  return function()
    handle:cancel()
  end
end
```

### Option 2: Declare Async with `context.start_async()`

For non-cancellable async work (or when you want to provide a cancel function
separately), call `context.start_async()` before returning:

```lua
run = function(args, context)
  context.start_async()  -- optional: context.start_async(cancel_fn)
  start_async_operation(function(result)
    context(result)
  end)
  return nil  -- MUST return nil when start_async() was called
end
```

!!! warning "Return Contract"
    When `context.start_async()` is called, `run()` **must** return `nil`.
    Returning a non-nil value after calling `start_async()` is a programming
    error and will raise an exception.

    When using Option 1 (return cancel function), do **not** also call
    `context.start_async()` — the return value already signals async mode.
    If both are used, the returned cancel function takes precedence.

!!! note "Sync tools/call"
    The MCP `tools/call` endpoint is synchronous. Async tools invoked via
    `tools/call` are immediately cancelled and an error response is returned.
    Async tools are intended for use via the callback-based `execute()` or
    `execute_async()` APIs.

## Returning Results

Tools return **raw Lua values** from `run()`. buddy.nvim automatically wraps
them into MCP-compatible responses — you do **not** return MCP envelope objects
(like `{ content = { ... } }`) directly.

### String Results

Returned as-is in a text content block:

```lua
return "Hello, world!"
-- → MCP response: { content = [{ type = "text", text = "Hello, world!" }] }
```

### Table Results

JSON-encoded into a text content block:

```lua
return { success = true, data = "result" }
-- → MCP response: { content = [{ type = "text", text = "{\"success\":true,\"data\":\"result\"}" }] }
```

### Nil Results

Returned as the string `"nil"`:

```lua
return nil
-- → MCP response: { content = [{ type = "text", text = "nil" }] }
```

### Structured Output (with output_schema)

If your tool defines `output_schema`, the table result is also included as
`structuredContent` in the MCP response:

```lua
return {
  name = "my_tool",
  output_schema = { type = "object", properties = { count = { type = "number" } } },
  run = function(args)
    return { count = 42 }
    -- → MCP response: { content = [...], structuredContent = { count = 42 } }
  end,
}
```

### Errors

To signal a tool error, use `error()` or the structured error API:

```lua
local errors = require("buddy.tools.errors")

-- Option 1: Simple error (becomes isError MCP response)
error("Something went wrong")

-- Option 2: Structured error with code
errors.throw(errors.codes.EXECUTION_ERROR, "Something went wrong", { detail = "..." })
```

## Testing Tools

Use the testing utilities:

```lua
local testing = require("buddy.testing")

-- Create test context
local ctx = testing.create_context(my_tool, {})

-- Run and assert
local success, result = testing.run(ctx, { action = "test" })
assert(success)

-- Validate schema
testing.assert_valid(my_tool, { action = "test" })
testing.assert_invalid(my_tool, {})  -- missing required field
```

See `:help buddy-testing` for full testing API.
