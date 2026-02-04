#!/usr/bin/env -S nvim --headless -u NONE -l
-- Generate vimdoc for buddy tools from their metadata

-- Add plugin to runtimepath
vim.opt.rtp:prepend(".")
vim.opt.rtp:append("plugins/buddy_core")
vim.opt.rtp:append("plugins/buddy_viz")

-- Load the registry and builtins
local registry = require("buddy.tools")
registry.load_builtins()

-- Also load user tools from tools/ directory
local discovery = require("buddy.tools.discovery")
discovery.discover()

local tools = registry.list()

local WIDTH = 78

-- Wrap text to fit within width, with indent for continuation lines
local function wrap_text(text, width, indent)
  indent = indent or ""
  local lines = {}
  local current = ""

  for word in text:gmatch("%S+") do
    if current == "" then
      current = word
    elseif #current + 1 + #word <= width then
      current = current .. " " .. word
    else
      table.insert(lines, current)
      current = indent .. word
    end
  end
  if current ~= "" then
    table.insert(lines, current)
  end
  return lines
end

-- Generate docs for a single tool
local function generate_tool_section(tool)
  local lines = {}
  -- Use plugin-specific tag prefix if available, else buddy.tools
  local prefix = "buddy.tools"
  if tool.source == "buddy_core" then
    prefix = "buddy_core.tools"
  elseif tool.source == "buddy_viz" then
    prefix = "buddy_viz.tools"
  end
  
  local tag = string.format("*%s.%s*", prefix, tool.name)

  -- Section header with right-aligned tag
  local header = string.format("%s.%s", prefix, tool.name)
  local padding = WIDTH - #header - #tag
  table.insert(lines, header .. string.rep(" ", math.max(1, padding)) .. tag)
  table.insert(lines, "")

  -- Description (wrapped)
  local desc = tool.description or "No description provided."
  for _, line in ipairs(wrap_text(desc, WIDTH, "")) do
    table.insert(lines, line)
  end
  table.insert(lines, "")

  -- Parameters
  local properties = {}
  local required = {}

  -- Handle both formats: args/required (builtin) and input_schema (user tools)
  if tool.args then
    properties = tool.args
    required = tool.required or {}
  elseif tool.input_schema and tool.input_schema.properties then
    properties = tool.input_schema.properties
    required = tool.input_schema.required or {}
  elseif tool.metadata and tool.metadata.input_schema then
    properties = tool.metadata.input_schema.properties or {}
    required = tool.metadata.input_schema.required or {}
  end

  if next(properties) then
    table.insert(lines, "Parameters: ~")

    -- Sort properties by name
    local sorted_names = vim.tbl_keys(properties)
    table.sort(sorted_names)

    for _, name in ipairs(sorted_names) do
      local prop = properties[name]
      local req = vim.tbl_contains(required, name) and "(required)" or "(optional)"

      -- Type string
      local type_str = prop.type or "any"
      if prop.enum then
        type_str = table.concat(prop.enum, " | ")
      end

      -- Parameter header line
      local header = string.format("  {%s}  %s", name, req)
      table.insert(lines, header)

      -- Type on next line if enum (often long)
      if prop.enum then
        for _, wrapped in ipairs(wrap_text("Type: " .. type_str, WIDTH - 6, "      ")) do
          table.insert(lines, "      " .. wrapped:gsub("^%s+", ""))
        end
      else
        table.insert(lines, "      Type: " .. type_str)
      end

      -- Description on next line(s), indented
      if prop.description then
        for _, wrapped in ipairs(wrap_text(prop.description, WIDTH - 6, "      ")) do
          table.insert(lines, "      " .. wrapped:gsub("^%s+", ""))
        end
      end
      table.insert(lines, "")
    end
  end

  -- Optional docs field for richer documentation
  if tool.docs then
    table.insert(lines, "Notes: ~")
    for line in tool.docs:gmatch("[^\n]+") do
      for _, wrapped in ipairs(wrap_text(line, WIDTH - 2, "  ")) do
        table.insert(lines, "  " .. wrapped:gsub("^%s+", ""))
      end
    end
    table.insert(lines, "")
  end

  return lines
end

-- Generate doc file content
local function generate_doc_file(title, filename, tool_list, intro_text)
  local doc_lines = {}

  -- Header
  table.insert(doc_lines, string.format("*%s*  %s", filename, title))
  table.insert(doc_lines, "")
  
  -- Intro
  if intro_text then
    for _, line in ipairs(intro_text) do
      table.insert(doc_lines, line)
    end
    table.insert(doc_lines, "")
  end

  -- Table of contents
  table.insert(doc_lines, string.format("TOOLS%s*%s*", string.rep(" ", WIDTH - 5 - #filename:gsub("%.txt", "")), filename:gsub("%.txt", "")))
  table.insert(doc_lines, "")
  for _, tool in ipairs(tool_list) do
    local prefix = "buddy.tools"
    if tool.source == "buddy_core" then prefix = "buddy_core.tools" end
    if tool.source == "buddy_viz" then prefix = "buddy_viz.tools" end
    
    local link = string.format("|%s.%s|", prefix, tool.name)
    table.insert(doc_lines, "  " .. link)
  end
  table.insert(doc_lines, "")
  table.insert(doc_lines, string.rep("=", WIDTH))
  table.insert(doc_lines, "")

  -- Tool sections
  for _, tool in ipairs(tool_list) do
    local section = generate_tool_section(tool)
    for _, line in ipairs(section) do
      table.insert(doc_lines, line)
    end
    table.insert(doc_lines, string.rep("-", WIDTH))
    table.insert(doc_lines, "")
  end

  -- Footer
  table.insert(doc_lines, " vim:tw=78:ts=8:ft=help:norl:")
  
  return doc_lines
end

-- Split tools by source
local core_tools = {}
local buddy_core_tools = {}
local buddy_viz_tools = {}

for _, tool in ipairs(tools) do
  if tool.source == "buddy_core" then
    table.insert(buddy_core_tools, tool)
  elseif tool.source == "buddy_viz" then
    table.insert(buddy_viz_tools, tool)
  else
    table.insert(core_tools, tool)
  end
end

-- Generate buddy-tools.txt (Core)
local core_doc = generate_doc_file(
  "Tool reference for buddy",
  "buddy-tools.txt",
  core_tools,
  {
    "This document describes the built-in buddy tools.",
    "Each tool can be called by AI assistants through MCP.",
    "",
    "For main documentation, see |buddy|."
  }
)
vim.fn.writefile(core_doc, "doc/buddy-tools.txt")
print(string.format("Generated doc/buddy-tools.txt with %d tools", #core_tools))

-- Generate buddy_core.txt
if #buddy_core_tools > 0 then
  local doc = generate_doc_file(
    "Core companion tools for buddy.nvim",
    "buddy_core.txt",
    buddy_core_tools,
    {
      "This document describes tools provided by the buddy_core plugin.",
      "These tools require the buddy_core plugin to be installed."
    }
  )
  vim.fn.writefile(doc, "plugins/buddy_core/doc/buddy_core.txt")
  print(string.format("Generated plugins/buddy_core/doc/buddy_core.txt with %d tools", #buddy_core_tools))
end

-- Generate buddy_viz.txt
if #buddy_viz_tools > 0 then
  local doc = generate_doc_file(
    "Visualization tools for buddy.nvim",
    "buddy_viz.txt",
    buddy_viz_tools,
    {
      "This document describes tools provided by the buddy_viz plugin.",
      "These tools require the buddy_viz plugin to be installed."
    }
  )
  vim.fn.writefile(doc, "plugins/buddy_viz/doc/buddy_viz.txt")
  print(string.format("Generated plugins/buddy_viz/doc/buddy_viz.txt with %d tools", #buddy_viz_tools))
end

