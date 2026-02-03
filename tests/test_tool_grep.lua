local T = MiniTest.new_set()

local grep_tool = require('buddy.tools.builtin.grep')

-- Helper function to create temp test files (supports subdirectories)
local function create_temp_files(files)
  local temp_dir = vim.fn.tempname()
  vim.fn.mkdir(temp_dir, "p")

  local created_files = {}
  for filename, content in pairs(files) do
    local filepath = temp_dir .. "/" .. filename
    -- Create subdirectories if needed
    local dir = vim.fn.fnamemodify(filepath, ":h")
    if dir ~= temp_dir then
      vim.fn.mkdir(dir, "p")
    end
    local file = io.open(filepath, "w")
    if file then
      file:write(content)
      file:close()
      table.insert(created_files, filepath)
    end
  end

  return temp_dir, created_files
end

-- Helper function to clean up temp files
local function cleanup_temp_files(files, dir)
  for _, filepath in ipairs(files) do
    vim.loop.fs_unlink(filepath)
  end
  vim.loop.fs_rmdir(dir)
end

-- Save original working directory
local original_cwd = vim.fn.getcwd()

-- Clean up quickfix list before each test
local function clean_qflist()
  vim.fn.setqflist({}, "r")
end

T['grep'] = MiniTest.new_set()

T['grep']['basic grep with default file_pattern finds pattern'] = function()
  clean_qflist()

  local files = {
    ["test1.txt"] = "hello world\nthis is a test\n",
    ["test2.txt"] = "hello there\nanother test\n",
    ["test3.txt"] = "goodbye world\n",
  }

  local temp_dir, created_files = create_temp_files(files)

  -- Change to temp directory for vimgrep to work
  vim.fn.chdir(temp_dir)

  local result = grep_tool.run({
    pattern = "hello",
    -- file_pattern defaults to "**/*"
  })

  MiniTest.expect.equality(result.success, true)
  MiniTest.expect.equality(result.pattern, "hello")
  MiniTest.expect.equality(result.file_pattern, "**/*")
  MiniTest.expect.equality(result.total, 2)
  MiniTest.expect.equality(result.showing, 2)
  MiniTest.expect.equality(#result.matches, 2)

  -- Verify matches are from our test files, not from project files
  for _, match in ipairs(result.matches) do
    MiniTest.expect.equality(match.filename:match("test%d.txt"), match.filename:match("test%d.txt"))
  end

  -- Check that matches contain filename, lnum, and text
  MiniTest.expect.equality(type(result.matches[1].filename), "string")
  MiniTest.expect.equality(type(result.matches[1].lnum), "number")
  MiniTest.expect.equality(type(result.matches[1].text), "string")

  vim.fn.chdir(original_cwd)
  cleanup_temp_files(created_files, temp_dir)
end

T['grep']['grep with specific file_pattern searches matching files'] = function()
  clean_qflist()

  local files = {
    ["subdir/nested.txt"] = "nested content\n",
    ["root.txt"] = "root content\n",
    ["other.txt"] = "other content\n",
  }

  local temp_dir, created_files = create_temp_files(files)

  vim.fn.chdir(temp_dir)

  -- Test searching in specific subdirectory using file_pattern
  local result = grep_tool.run({
    pattern = "nested",
    file_pattern = "subdir/nested.txt",
  })

  MiniTest.expect.equality(result.success, true)
  MiniTest.expect.equality(result.file_pattern, "subdir/nested.txt")
  MiniTest.expect.equality(result.total, 1)
  MiniTest.expect.equality(result.matches[1].filename:match("nested.txt"), "nested.txt")

  vim.fn.chdir(original_cwd)
  cleanup_temp_files(created_files, temp_dir)
end

T['grep']['grep with glob pattern searches matching files'] = function()
  clean_qflist()

  local files = {
    ["file1.lua"] = "local function test()\n",
    ["file2.lua"] = "local function setup()\n",
    ["file3.txt"] = "not lua content\n",
  }

  local temp_dir, created_files = create_temp_files(files)

  vim.fn.chdir(temp_dir)

  -- Test searching only in .lua files
  local result = grep_tool.run({
    pattern = "function",
    file_pattern = "*.lua",
  })

  MiniTest.expect.equality(result.success, true)
  MiniTest.expect.equality(result.file_pattern, "*.lua")
  MiniTest.expect.equality(result.total, 2)

  vim.fn.chdir(original_cwd)
  cleanup_temp_files(created_files, temp_dir)
end

T['grep']['grep returns filename, lnum, text for each match'] = function()
  clean_qflist()

  local files = {
    ["test.txt"] = "line 1: hello\nline 2: hello again\nline 3: goodbye\n",
  }

  local temp_dir, created_files = create_temp_files(files)

  vim.fn.chdir(temp_dir)

  local result = grep_tool.run({
    pattern = "hello",
    file_pattern = "test.txt",
  })

  MiniTest.expect.equality(result.success, true)
  MiniTest.expect.equality(result.total, 2)

  -- Check first match
  MiniTest.expect.equality(result.matches[1].lnum, 1)
  MiniTest.expect.equality(type(result.matches[1].filename), "string")
  MiniTest.expect.equality(result.matches[1].text:find("hello") ~= nil, true)

  -- Check second match
  MiniTest.expect.equality(result.matches[2].lnum, 2)
  MiniTest.expect.equality(type(result.matches[2].filename), "string")
  MiniTest.expect.equality(result.matches[2].text:find("hello") ~= nil, true)

  vim.fn.chdir(original_cwd)
  cleanup_temp_files(created_files, temp_dir)
end

T['grep']['grep returns empty matches when pattern not found'] = function()
  clean_qflist()

  local files = {
    ["test.txt"] = "hello world\ngoodbye world\n",
  }

  local temp_dir, created_files = create_temp_files(files)

  vim.fn.chdir(temp_dir)

  local result = grep_tool.run({
    pattern = "nonexistent",
    file_pattern = "test.txt",
  })

  MiniTest.expect.equality(result.success, true)
  MiniTest.expect.equality(result.total, 0)
  MiniTest.expect.equality(#result.matches, 0)
  MiniTest.expect.equality(type(result.message), "string")
  MiniTest.expect.equality(result.message:find("No matches") ~= nil, true)

  vim.fn.chdir(original_cwd)
  cleanup_temp_files(created_files, temp_dir)
end

T['grep']['grep returns error for empty pattern'] = function()
  clean_qflist()

  local result = grep_tool.run({
    pattern = "",
  })

  MiniTest.expect.equality(result.success, false)
  MiniTest.expect.equality(type(result.error), "string")
  MiniTest.expect.equality(result.error:find("empty") ~= nil, true)
end

T['grep']['grep limits matches to 10 but returns total count'] = function()
  clean_qflist()

  local content_lines = {}
  for i = 1, 15 do
    table.insert(content_lines, "line " .. i .. ": hello world\n")
  end

  local files = {
    ["test.txt"] = table.concat(content_lines),
  }

  local temp_dir, created_files = create_temp_files(files)

  vim.fn.chdir(temp_dir)

  local result = grep_tool.run({
    pattern = "hello",
    file_pattern = "test.txt",
  })

  MiniTest.expect.equality(result.success, true)
  MiniTest.expect.equality(result.total, 15)
  MiniTest.expect.equality(result.showing, 10)
  MiniTest.expect.equality(#result.matches, 10)  -- Only first 10 returned

  vim.fn.chdir(original_cwd)
  cleanup_temp_files(created_files, temp_dir)
end

T['grep']['grep shows correct showing field when matches <= 10'] = function()
  clean_qflist()

  local content_lines = {}
  for i = 1, 5 do
    table.insert(content_lines, "line " .. i .. ": hello world\n")
  end

  local files = {
    ["test.txt"] = table.concat(content_lines),
  }

  local temp_dir, created_files = create_temp_files(files)

  vim.fn.chdir(temp_dir)

  local result = grep_tool.run({
    pattern = "hello",
    file_pattern = "test.txt",
  })

  MiniTest.expect.equality(result.success, true)
  MiniTest.expect.equality(result.total, 5)
  MiniTest.expect.equality(result.showing, 5)
  MiniTest.expect.equality(#result.matches, 5)

  vim.fn.chdir(original_cwd)
  cleanup_temp_files(created_files, temp_dir)
end

T['grep']['grep preserves custom file_pattern in result'] = function()
  clean_qflist()

  local files = {
    ["test.txt"] = "hello world\n",
  }

  local temp_dir, created_files = create_temp_files(files)

  vim.fn.chdir(temp_dir)

  local result = grep_tool.run({
    pattern = "hello",
    file_pattern = "*.txt",
  })

  MiniTest.expect.equality(result.success, true)
  MiniTest.expect.equality(result.file_pattern, "*.txt")

  vim.fn.chdir(original_cwd)
  cleanup_temp_files(created_files, temp_dir)
end

return T
