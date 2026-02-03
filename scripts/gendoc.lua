#!/usr/bin/env -S nvim --headless -u NONE -l
-- Generate vimdoc using mini.doc
-- Run: nvim --headless -u NONE -l scripts/gendoc.lua

-- Add project and deps to runtimepath
vim.opt.rtp:prepend(".")
vim.opt.rtp:append("deps/mini.doc")

-- Load mini.doc
local ok, minidoc = pcall(require, "mini.doc")
if not ok then
  print("Error: mini.doc not found. Run:")
  print("  git clone --depth 1 https://github.com/echasnovski/mini.doc deps/mini.doc")
  os.exit(1)
end

minidoc.setup({})

-- Generate from main module files
minidoc.generate(
  {
    "lua/buddy/init.lua",
    "lua/buddy/config.lua",
    "lua/buddy/tools/executor.lua",
    "lua/buddy/testing.lua",
  },
  "doc/buddy.txt"
)

-- Post-process: replace M with buddy
local doc_path = "doc/buddy.txt"
local content = vim.fn.readfile(doc_path)
for i, line in ipairs(content) do
  -- Replace `M.foo` -> `buddy.foo`
  -- Replace *M.foo* -> *buddy.foo*
  -- Replace standalone `M` -> module name based on section
  line = line:gsub("`M%.", "`buddy.")
  line = line:gsub("%*M%.", "*buddy.")
  -- Remove standalone `M` lines (module declaration artifacts)
  if line:match("^%s*`M`%s*$") then
    content[i] = ""
  else
    content[i] = line
  end
end
vim.fn.writefile(content, doc_path)

print("Generated doc/buddy.txt")
