local T = MiniTest.new_set()

local search_tool = require('buddy.tools.builtin.search')

-- Helper function to create a test buffer with content
local function create_test_buffer(content)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, content)
  return bufnr
end

T['find'] = MiniTest.new_set()

T['find']['finds pattern in buffer and returns total count'] = function()
  local content = {
    "hello world",
    "hello there",
    "goodbye world",
    "hello again",
  }

  local bufnr = create_test_buffer(content)
  vim.api.nvim_set_current_buf(bufnr)

  local result = search_tool.run({
    action = "find",
    pattern = "hello",
  })

  MiniTest.expect.equality(result.success, true)
  MiniTest.expect.equality(result.pattern, "hello")
  MiniTest.expect.equality(result.total, 3)

  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T['find']['returns message when no matches found'] = function()
  local content = {
    "hello world",
    "hello there",
  }

  local bufnr = create_test_buffer(content)
  vim.api.nvim_set_current_buf(bufnr)

  local result = search_tool.run({
    action = "find",
    pattern = "goodbye",
  })

  MiniTest.expect.equality(result.success, true)
  MiniTest.expect.equality(result.pattern, "goodbye")
  MiniTest.expect.equality(result.total, 0)
  MiniTest.expect.equality(result.message, "No matches found")

  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T['find']['find with ignore_case flag'] = function()
  local content = {
    "Hello world",
    "hello there",
    "HELLO again",
    "goodbye world",
  }

  local bufnr = create_test_buffer(content)
  vim.api.nvim_set_current_buf(bufnr)

  local result = search_tool.run({
    action = "find",
    pattern = "hello",
    ignore_case = true,
  })

  MiniTest.expect.equality(result.success, true)
  MiniTest.expect.equality(result.total, 3)

  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T['find']['find with whole_word flag'] = function()
  -- Note: In Vim, \<hello\> matches "hello" in "hello-there" because - is not a word char
  -- Use "helloworld" (no separator) to test whole_word properly
  local content = {
    "hello world",
    "helloworld",
    "goodbye",
  }

  local bufnr = create_test_buffer(content)
  vim.api.nvim_set_current_buf(bufnr)

  local result = search_tool.run({
    action = "find",
    pattern = "hello",
    whole_word = true,
  })

  MiniTest.expect.equality(result.success, true)
  -- Only "hello world" matches - "helloworld" does not because hello is not a separate word
  MiniTest.expect.equality(result.total, 1)

  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T['find']['returns error when pattern is empty'] = function()
  local content = { "hello world" }
  local bufnr = create_test_buffer(content)
  vim.api.nvim_set_current_buf(bufnr)

  local result = search_tool.run({
    action = "find",
    pattern = "",
  })

  MiniTest.expect.equality(result.success, false)
  MiniTest.expect.equality(type(result.error), "string")

  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T['find_replace'] = MiniTest.new_set()

T['find_replace']['replaces pattern in buffer'] = function()
  local content = {
    "hello world",
    "hello there",
    "goodbye world",
  }

  local bufnr = create_test_buffer(content)
  vim.api.nvim_set_current_buf(bufnr)

  local result = search_tool.run({
    action = "find_replace",
    pattern = "hello",
    replacement = "hi",
  })

  MiniTest.expect.equality(result.success, true)
  MiniTest.expect.equality(result.pattern, "hello")
  MiniTest.expect.equality(result.replacement, "hi")

  -- Verify the replacement (note: without global flag, only first occurrence per line)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  MiniTest.expect.equality(lines[1], "hi world")
  MiniTest.expect.equality(lines[2], "hi there")

  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T['find_replace']['with global flag replaces all occurrences on each line'] = function()
  local content = {
    "hello hello world",
    "hello there hello",
  }

  local bufnr = create_test_buffer(content)
  vim.api.nvim_set_current_buf(bufnr)

  local result = search_tool.run({
    action = "find_replace",
    pattern = "hello",
    replacement = "hi",
    global = true,
  })

  MiniTest.expect.equality(result.success, true)

  -- Verify the replacement
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  MiniTest.expect.equality(lines[1], "hi hi world")
  MiniTest.expect.equality(lines[2], "hi there hi")

  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T['find_replace']['without global flag replaces only first occurrence per line'] = function()
  local content = {
    "hello hello world",
    "hello there hello",
  }

  local bufnr = create_test_buffer(content)
  vim.api.nvim_set_current_buf(bufnr)

  local result = search_tool.run({
    action = "find_replace",
    pattern = "hello",
    replacement = "hi",
  })

  MiniTest.expect.equality(result.success, true)

  -- Verify the replacement
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  MiniTest.expect.equality(lines[1], "hi hello world")
  MiniTest.expect.equality(lines[2], "hi there hello")

  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T['find_replace']['with ignore_case flag'] = function()
  local content = {
    "Hello world",
    "hello there",
    "HELLO again",
  }

  local bufnr = create_test_buffer(content)
  vim.api.nvim_set_current_buf(bufnr)

  local result = search_tool.run({
    action = "find_replace",
    pattern = "hello",
    replacement = "hi",
    ignore_case = true,
  })

  MiniTest.expect.equality(result.success, true)

  -- Verify the replacement (case is preserved when pattern matches)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  -- Note: :s/.../.../i will replace regardless of case, but keeps the replacement text as-is

  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T['find_replace']['with global and ignore_case flags'] = function()
  local content = {
    "Hello Hello world",
    "hello there HELLO",
  }

  local bufnr = create_test_buffer(content)
  vim.api.nvim_set_current_buf(bufnr)

  local result = search_tool.run({
    action = "find_replace",
    pattern = "hello",
    replacement = "hi",
    global = true,
    ignore_case = true,
  })

  MiniTest.expect.equality(result.success, true)

  -- Verify the replacement
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  MiniTest.expect.equality(lines[1], "hi hi world")
  MiniTest.expect.equality(lines[2], "hi there hi")

  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T['find_replace']['requires replacement argument'] = function()
  local content = { "hello world" }
  local bufnr = create_test_buffer(content)
  vim.api.nvim_set_current_buf(bufnr)

  local result = search_tool.run({
    action = "find_replace",
    pattern = "hello",
  })

  MiniTest.expect.equality(result.success, false)
  MiniTest.expect.equality(type(result.error), "string")

  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T['find_replace']['returns success message when pattern not found'] = function()
  local content = { "hello world" }
  local bufnr = create_test_buffer(content)
  vim.api.nvim_set_current_buf(bufnr)

  local result = search_tool.run({
    action = "find_replace",
    pattern = "goodbye",
    replacement = "farewell",
  })

  MiniTest.expect.equality(result.success, true)
  MiniTest.expect.equality(result.message, "No matches found")

  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T['find_replace']['handles special characters in pattern and replacement'] = function()
  local content = {
    "hello/world",
    "hello/world there",
  }

  local bufnr = create_test_buffer(content)
  vim.api.nvim_set_current_buf(bufnr)

  local result = search_tool.run({
    action = "find_replace",
    pattern = "hello/world",
    replacement = "hi/world",
  })

  MiniTest.expect.equality(result.success, true)

  -- Verify the replacement (special chars should be escaped)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  MiniTest.expect.equality(lines[1], "hi/world")
  MiniTest.expect.equality(lines[2], "hi/world there")

  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T['error handling'] = MiniTest.new_set()

T['error handling']['returns error for unknown action'] = function()
  local content = { "hello world" }
  local bufnr = create_test_buffer(content)
  vim.api.nvim_set_current_buf(bufnr)

  local result = search_tool.run({
    action = "unknown",
    pattern = "hello",
  })

  MiniTest.expect.equality(result.success, false)
  MiniTest.expect.equality(type(result.error), "string")

  vim.api.nvim_buf_delete(bufnr, { force = true })
end

return T
