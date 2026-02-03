#!/usr/bin/env -S nvim --headless -u NONE -l
-- Generate vimdoc for buddy tools from their metadata

-- Add plugin to runtimepath
vim.opt.rtp:prepend(".")

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
  local tag = string.format("*buddy.tools.%s*", tool.name)

  -- Section header with right-aligned tag
  local header = string.format("buddy.tools.%s", tool.name)
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

-- Build the full document
local doc_lines = {}

-- Header
table.insert(doc_lines, "*buddy-tools.txt*  Tool reference for buddy")
table.insert(doc_lines, "")

-- Intro
table.insert(doc_lines, "This document describes all available buddy tools.")
table.insert(doc_lines, "Each tool can be called by AI assistants through MCP.")
table.insert(doc_lines, "")
table.insert(doc_lines, "For main documentation, see |buddy|.")
table.insert(doc_lines, "")

-- Table of contents
table.insert(doc_lines, "TOOLS                                              *buddy-tools*")
table.insert(doc_lines, "")
for _, tool in ipairs(tools) do
  local link = string.format("|buddy.tools.%s|", tool.name)
  table.insert(doc_lines, "  " .. link)
end
table.insert(doc_lines, "")
table.insert(doc_lines, string.rep("=", WIDTH))
table.insert(doc_lines, "")

-- Tool sections
for _, tool in ipairs(tools) do
  local section = generate_tool_section(tool)
  for _, line in ipairs(section) do
    table.insert(doc_lines, line)
  end
  table.insert(doc_lines, string.rep("-", WIDTH))
  table.insert(doc_lines, "")
end

-- Footer
table.insert(doc_lines, " vim:tw=78:ts=8:ft=help:norl:")

-- Write to file
local doc_path = "doc/buddy-tools.txt"
vim.fn.writefile(doc_lines, doc_path)

print(string.format("Generated %s with %d tools", doc_path, #tools))
