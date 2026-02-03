-- buddy tool manager - view and navigate to all registered tools
-- Works with snacks.picker (enhanced) or vim.ui.select (fallback)

local M = {}

-- Fallback using vim.ui.select
local function open_dashboard_fallback()
  local registry = require("buddy.tools")
  local tools = registry.list()

  local items = {}
  local tool_map = {}
  for i, tool in ipairs(tools) do
    local runtime = tool.runtime or "builtin"
    local label = tool.name .. " [" .. runtime .. "]"
    table.insert(items, label)
    tool_map[i] = tool
  end

  vim.ui.select(items, {
    prompt = "buddy Tools:",
  }, function(choice, idx)
    if choice and tool_map[idx] then
      local tool = tool_map[idx]
      if tool.path then
        vim.cmd("edit " .. tool.path)
      else
        vim.notify("Built-in tool: " .. tool.name, vim.log.levels.INFO)
      end
    end
  end)
end

-- Enhanced picker using snacks.picker
local function open_dashboard_snacks(Snacks)
  local registry = require("buddy.tools")
  local tools = registry.list()

  local items = {}
  for i, tool in ipairs(tools) do
    -- Skip builtin tools
    if tool.runtime ~= "builtin" then
      table.insert(items, {
        idx = i,
        text = tool.name,
        tool = tool,
        file = tool.path,
        runtime = tool.runtime or "builtin",
        description = tool.description,
      })
    end
  end

  Snacks.picker.pick({
    source = "buddy_manager",
    title = "buddy Tools",
    items = items,
    format = function(item)
      local runtime_hl = item.runtime == "builtin" and "Comment" or "String"
      return {
        { item.text,                   "Function" },
        { " [" .. item.runtime .. "]", runtime_hl },
      }
    end,
    preview = function(ctx)
      local item = ctx.item
      local lines = {
        "# " .. item.text,
        "",
        item.description,
        "",
        "Runtime: " .. item.runtime,
        "Path: " .. (item.file or "built-in"),
      }
      ctx.preview:set_lines(lines)
    end,
    confirm = function(picker, item)
      picker:close()
      if item and item.file then
        vim.cmd("edit " .. item.file)
      elseif item then
        vim.notify("Built-in tool: " .. item.text, vim.log.levels.INFO)
      end
    end,
    actions = {
      lazy_manager = function(picker)
        picker:close()
        local ok, lm = pcall(require, "buddy_core.tools.lazy_manager")
        if ok and lm.open_picker then
          lm.open_picker()
        end
      end,
    },
    win = {
      preview = {
        wo = { wrap = true },
      },
      input = {
        keys = {
          ["<C-l>"] = { "lazy_manager", desc = "Lazy Manager", mode = { "i", "n" } },
        },
        footer_keys = { "<C-l>" },
      },
    },
  })
end

-- Open dashboard (auto-detect snacks or fallback)
local function open_dashboard()
  local ok, Snacks = pcall(require, "snacks")
  if ok and Snacks.picker then
    open_dashboard_snacks(Snacks)
  else
    open_dashboard_fallback()
  end
end

M.open_picker = open_dashboard

function M.list_tools()
  local registry = require("buddy.tools")
  return registry.list()
end

return M
