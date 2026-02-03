-- init: Scaffold a new buddy user tool from template folder

local function get_default_tools_dir()
  return vim.fn.stdpath("data") .. "/buddy-tools"
end

local function ensure_runtimepath(path)
  local rtp = vim.o.runtimepath
  if not rtp:find(path, 1, true) then
    vim.o.runtimepath = rtp .. "," .. path
  end
end

--- Transform snake_case to PascalCase
local function to_pascal_case(s)
  return s:gsub("^%l", string.upper):gsub("_%l", function(str)
    return str:sub(2):upper()
  end)
end

return {
  name = "init",
  description = "Scaffold a new buddy Lua tool with the correct structure",
  input_schema = {
    type = "object",
    properties = {
      name = { type = "string", description = "Tool name (snake_case, e.g. 'my_tool')" },
      description = { type = "string", description = "Tool description (optional)" },
      path = { type = "string", description = "Custom path for tool (default: stdpath('data')/buddy-tools/)" },
    },
    required = { "name" },
  },
  run = function(args)
    local name = args.name
    local description = args.description or "A custom buddy tool"
    local base_path = args.path and vim.fn.expand(args.path) or get_default_tools_dir()
    
    -- Ensure path ends with / for consistency in some operations, but we'll use it to build dest
    base_path = base_path:gsub("/$", "")
    local dest = base_path .. "/" .. name

    -- Validate name is snake_case
    if not name:match("^[a-z][a-z0-9_]*$") then
      return {
        isError = true,
        content = { { type = "text", text = "Invalid name: must be snake_case (lowercase letters, numbers, underscores)" } },
      }
    end

    -- Check if already exists
    if vim.fn.isdirectory(dest) == 1 then
      return {
        isError = true,
        content = { { type = "text", text = "Tool already exists at: " .. dest } },
      }
    end

    -- Find template directory relative to this script
    local script_path = debug.getinfo(1).source:sub(2)
    local template_dir = vim.fn.fnamemodify(script_path, ":h") .. "/template"

    if vim.fn.isdirectory(template_dir) == 0 then
      return {
        isError = true,
        content = { { type = "text", text = "Template directory not found at: " .. template_dir } },
      }
    end

    -- Create dest directory
    vim.fn.mkdir(dest, "p")

    -- Add to runtimepath
    ensure_runtimepath(dest)

    -- Copy and process files
    local files = vim.fn.glob(template_dir .. "/**/*", false, true)
    local pascal_name = to_pascal_case(name)

    for _, file_path in ipairs(files) do
      if vim.fn.isdirectory(file_path) == 0 then
        -- Calculate relative path and replace TOOL_NAME in it
        local relative_path = file_path:sub(#template_dir + 2)
        local target_relative_path = relative_path:gsub("TOOL_NAME", name)
        local target_path = dest .. "/" .. target_relative_path
        
        -- Ensure target directory exists
        vim.fn.mkdir(vim.fn.fnamemodify(target_path, ":h"), "p")
        
        -- Read, replace, write
        local f = io.open(file_path, "r")
        if f then
          local content = f:read("*all")
          f:close()
          
          content = content:gsub("TOOL_NAME", name)
          content = content:gsub("TOOL_DESCRIPTION", description)
          content = content:gsub("ToolName", pascal_name)
          
          local wf = io.open(target_path, "w")
          if wf then
            wf:write(content)
            wf:close()
          end
        end
      end
    end

    local msg = string.format(
      [[Created plugin '%s' at: %s

Structure:
  %s/
    plugin/%s.lua     -- Commands & keymaps (entry point)
    lua/
      %s/
        init.lua      -- Public API (M.setup, M.run, etc.)
        config.lua    -- Configuration with defaults
      buddy.lua       -- MCP tool definition for AI agents

Next steps:
1. Add to runtimepath or install via plugin manager
2. Customize the plugin logic in lua/%s/init.lua
3. Update MCP schema in lua/buddy.lua if needed]],
      name, dest, name, name, name, name
    )

    return {
      content = { { type = "text", text = msg } },
    }
  end,
}
