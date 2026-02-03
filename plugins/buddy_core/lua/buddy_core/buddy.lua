-- buddy_core: MCP Tool Definitions
-- MCP layer - formats responses, calls plugin's plain Lua API

local core = require("buddy_core")

local function ok(text)
  return { content = { { type = "text", text = text or "Success" } } }
end

return {
  tools = {
    {
      name = "buddy_manager",
      description = "View all buddy tools and navigate to their source files",
      input_schema = {
        type = "object",
        properties = {},
      },
      run = function(_args)
        local tools = core.buddy_manager.list_tools()
        local lines = { "buddy tools (" .. #tools .. " registered):", "" }
        for _, tool in ipairs(tools) do
          local runtime = tool.runtime and (" [" .. tool.runtime .. "]") or " [builtin]"
          table.insert(lines, "- " .. tool.name .. runtime .. ": " .. (tool.description or ""))
        end
        return ok(table.concat(lines, "\n"))
      end,
    },
    {
      name = "dotfyle_search",
      description = "Search for Neovim plugins on Dotfyle",
      input_schema = {
        type = "object",
        properties = {
          message = { type = "string", description = "Search query for plugins (optional)" },
        },
      },
      run = function(args)
        local results = core.dotfyle.search(args.message)
        return ok(results)
      end,
    },
    {
      name = "lazy_manager",
      description = "Browse and edit lazy.nvim plugin config files",
      input_schema = {
        type = "object",
        properties = {
          message = { type = "string", description = "Search query to filter config files (optional)" },
        },
      },
      run = function(args)
        local results = core.lazy_manager.list_configs(args.message)
        return ok(results)
      end,
    },
  },
}
