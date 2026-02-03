local T = MiniTest.new_set()

local edit_tool = require('buddy.tools.builtin.edit')

-- Helper to create a test buffer with content
local function create_test_buffer(content)
  local bufnr = vim.api.nvim_create_buf(false, true)
  local lines = content or { "line1", "line2", "line3", "line4", "line5" }
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.api.nvim_set_current_buf(bufnr)
  return bufnr
end

T['insert'] = MiniTest.new_set()
T['insert']['inserts lines at specified position'] = function()
  local bufnr = create_test_buffer({ "line1", "line2", "line3" })

  -- Insert at position 2 (between line1 and line2)
  local result = edit_tool.run({
    action = "insert",
    line = 2,
    content = "new line"
  })

  MiniTest.expect.equality(result.success, true)
  MiniTest.expect.equality(result.inserted, 1)

  -- Verify content
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  MiniTest.expect.equality(lines[1], "line1")
  MiniTest.expect.equality(lines[2], "new line")
  MiniTest.expect.equality(lines[3], "line2")
  MiniTest.expect.equality(lines[4], "line3")
  MiniTest.expect.equality(#lines, 4)

  -- Cleanup
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T['insert']['inserts multiple lines at position'] = function()
  local bufnr = create_test_buffer({ "line1", "line2" })

  -- Insert multiple lines
  local result = edit_tool.run({
    action = "insert",
    line = 2,
    content = "new line 1\nnew line 2\nnew line 3"
  })

  MiniTest.expect.equality(result.success, true)
  MiniTest.expect.equality(result.inserted, 3)

  -- Verify content
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  MiniTest.expect.equality(lines[1], "line1")
  MiniTest.expect.equality(lines[2], "new line 1")
  MiniTest.expect.equality(lines[3], "new line 2")
  MiniTest.expect.equality(lines[4], "new line 3")
  MiniTest.expect.equality(lines[5], "line2")

  -- Cleanup
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T['replace'] = MiniTest.new_set()
T['replace']['replaces specified line range'] = function()
  local bufnr = create_test_buffer({ "line1", "line2", "line3", "line4", "line5" })

  -- Replace lines 2-3
  local result = edit_tool.run({
    action = "replace",
    line = 2,
    end_line = 3,
    content = "replaced line"
  })

  MiniTest.expect.equality(result.success, true)
  MiniTest.expect.equality(result.replaced, 2)
  MiniTest.expect.equality(result.inserted, 1)

  -- Verify content
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  MiniTest.expect.equality(lines[1], "line1")
  MiniTest.expect.equality(lines[2], "replaced line")
  MiniTest.expect.equality(lines[3], "line4")
  MiniTest.expect.equality(lines[4], "line5")
  MiniTest.expect.equality(#lines, 4)

  -- Cleanup
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T['replace']['replaces with multiple lines'] = function()
  local bufnr = create_test_buffer({ "line1", "line2", "line3" })

  -- Replace line 2 with multiple lines
  local result = edit_tool.run({
    action = "replace",
    line = 2,
    end_line = 2,
    content = "new line 1\nnew line 2"
  })

  MiniTest.expect.equality(result.success, true)
  MiniTest.expect.equality(result.replaced, 1)
  MiniTest.expect.equality(result.inserted, 2)

  -- Verify content
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  MiniTest.expect.equality(lines[1], "line1")
  MiniTest.expect.equality(lines[2], "new line 1")
  MiniTest.expect.equality(lines[3], "new line 2")
  MiniTest.expect.equality(lines[4], "line3")

  -- Cleanup
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T['delete'] = MiniTest.new_set()
T['delete']['deletes specified line range'] = function()
  local bufnr = create_test_buffer({ "line1", "line2", "line3", "line4", "line5" })

  -- Delete lines 2-4
  local result = edit_tool.run({
    action = "delete",
    line = 2,
    end_line = 4
  })

  MiniTest.expect.equality(result.success, true)
  MiniTest.expect.equality(result.deleted, 3)

  -- Verify content
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  MiniTest.expect.equality(lines[1], "line1")
  MiniTest.expect.equality(lines[2], "line5")
  MiniTest.expect.equality(#lines, 2)

  -- Cleanup
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T['delete']['deletes single line'] = function()
  local bufnr = create_test_buffer({ "line1", "line2", "line3" })

  -- Delete line 2
  local result = edit_tool.run({
    action = "delete",
    line = 2,
    end_line = 2
  })

  MiniTest.expect.equality(result.success, true)
  MiniTest.expect.equality(result.deleted, 1)

  -- Verify content
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  MiniTest.expect.equality(lines[1], "line1")
  MiniTest.expect.equality(lines[2], "line3")
  MiniTest.expect.equality(#lines, 2)

  -- Cleanup
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T['replace_all'] = MiniTest.new_set()
T['replace_all']['replaces entire buffer content'] = function()
  local bufnr = create_test_buffer({ "old1", "old2", "old3" })

  local result = edit_tool.run({
    action = "replace_all",
    content = "new1\nnew2\nnew3\nnew4"
  })

  MiniTest.expect.equality(result.success, true)
  MiniTest.expect.equality(result.replaced_all, true)
  MiniTest.expect.equality(result.lines, 4)

  -- Verify content
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  MiniTest.expect.equality(lines[1], "new1")
  MiniTest.expect.equality(lines[2], "new2")
  MiniTest.expect.equality(lines[3], "new3")
  MiniTest.expect.equality(lines[4], "new4")
  MiniTest.expect.equality(#lines, 4)

  -- Cleanup
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T['replace_all']['replaces entire buffer with empty content'] = function()
  local bufnr = create_test_buffer({ "line1", "line2", "line3" })

  local result = edit_tool.run({
    action = "replace_all",
    content = ""
  })

  MiniTest.expect.equality(result.success, true)
  MiniTest.expect.equality(result.replaced_all, true)

  -- Verify buffer has one empty line (nvim always has at least 1 line)
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  MiniTest.expect.equality(#lines, 1)
  MiniTest.expect.equality(lines[1], "")

  -- Cleanup
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

return T
