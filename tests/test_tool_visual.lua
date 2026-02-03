local T = MiniTest.new_set()

-- Load visual tool
local visual_tool = require("buddy.tools.builtin.visual")

T['visual'] = MiniTest.new_set()

T['visual']['creates visual selection on single line'] = function()
  -- Create a test buffer
  local buf = vim.api.nvim_create_buf(true, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    "line 1",
    "line 2",
    "line 3",
    "line 4",
    "line 5",
  })
  vim.api.nvim_set_current_buf(buf)

  -- Create visual selection from (1, 0) to (1, 5)
  local result = visual_tool.run({
    start_line = 1,
    start_col = 0,
    end_line = 1,
    end_col = 5,
  })
  MiniTest.expect.equality(result.success, true)
  MiniTest.expect.equality(result.start_line, 1)
  MiniTest.expect.equality(result.start_col, 0)
  MiniTest.expect.equality(result.end_line, 1)
  MiniTest.expect.equality(result.end_col, 5)

  -- Verify cursor is at end position
  local cursor = vim.api.nvim_win_get_cursor(0)
  MiniTest.expect.equality(cursor[1], 1)
  MiniTest.expect.equality(cursor[2], 5)

  -- Verify we are in visual mode
  local mode = vim.api.nvim_get_mode().mode
  MiniTest.expect.equality(mode, "v")

  -- Cleanup
  vim.api.nvim_buf_delete(buf, { force = true })
end

T['visual']['creates visual selection across multiple lines'] = function()
  -- Create a test buffer
  local buf = vim.api.nvim_create_buf(true, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    "line 1",
    "line 2",
    "line 3",
    "line 4",
    "line 5",
  })
  vim.api.nvim_set_current_buf(buf)

  -- Create visual selection from (2, 2) to (4, 3)
  local result = visual_tool.run({
    start_line = 2,
    start_col = 2,
    end_line = 4,
    end_col = 3,
  })
  MiniTest.expect.equality(result.success, true)
  MiniTest.expect.equality(result.start_line, 2)
  MiniTest.expect.equality(result.start_col, 2)
  MiniTest.expect.equality(result.end_line, 4)
  MiniTest.expect.equality(result.end_col, 3)

  -- Verify cursor is at end position
  local cursor = vim.api.nvim_win_get_cursor(0)
  MiniTest.expect.equality(cursor[1], 4)
  MiniTest.expect.equality(cursor[2], 3)

  -- Verify we are in visual mode
  local mode = vim.api.nvim_get_mode().mode
  MiniTest.expect.equality(mode, "v")

  -- Cleanup
  vim.api.nvim_buf_delete(buf, { force = true })
end

T['visual']['creates selection from beginning of buffer'] = function()
  -- Create a test buffer
  local buf = vim.api.nvim_create_buf(true, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    "first line",
    "second line",
    "third line",
  })
  vim.api.nvim_set_current_buf(buf)

  -- Create visual selection from (1, 0) to (2, 6)
  local result = visual_tool.run({
    start_line = 1,
    start_col = 0,
    end_line = 2,
    end_col = 6,
  })
  MiniTest.expect.equality(result.success, true)
  MiniTest.expect.equality(result.start_line, 1)
  MiniTest.expect.equality(result.start_col, 0)

  -- Verify cursor is at end position
  local cursor = vim.api.nvim_win_get_cursor(0)
  MiniTest.expect.equality(cursor[1], 2)
  MiniTest.expect.equality(cursor[2], 6)

  -- Cleanup
  vim.api.nvim_buf_delete(buf, { force = true })
end

T['visual']['creates selection to end of line'] = function()
  -- Create a test buffer
  local buf = vim.api.nvim_create_buf(true, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    "short line",
    "medium length line here",
    "longer line with more text",
  })
  vim.api.nvim_set_current_buf(buf)

  -- Create visual selection from (2, 7) to (2, 21)
  local result = visual_tool.run({
    start_line = 2,
    start_col = 7,
    end_line = 2,
    end_col = 21,
  })
  MiniTest.expect.equality(result.success, true)

  -- Verify cursor is at end position
  local cursor = vim.api.nvim_win_get_cursor(0)
  MiniTest.expect.equality(cursor[1], 2)
  MiniTest.expect.equality(cursor[2], 21)

  -- Cleanup
  vim.api.nvim_buf_delete(buf, { force = true })
end

T['visual']['cursor ends at end position'] = function()
  -- Create a test buffer
  local buf = vim.api.nvim_create_buf(true, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    "line 1",
    "line 2",
    "line 3",
  })
  vim.api.nvim_set_current_buf(buf)

  -- Test multiple positions
  local test_cases = {
    { start = {1, 0}, finish = {1, 3} },
    { start = {1, 2}, finish = {2, 4} },
    { start = {2, 0}, finish = {3, 5} },
  }

  for _, tc in ipairs(test_cases) do
    -- Exit visual mode first
    vim.cmd("normal! \27")

    visual_tool.run({
      start_line = tc.start[1],
      start_col = tc.start[2],
      end_line = tc.finish[1],
      end_col = tc.finish[2],
    })

    local cursor = vim.api.nvim_win_get_cursor(0)
    local expected_line = tc.finish[1]
    local expected_col = tc.finish[2]
    MiniTest.expect.equality(cursor[1], expected_line, string.format("Expected line %d, got %d", expected_line, cursor[1]))
    MiniTest.expect.equality(cursor[2], expected_col, string.format("Expected col %d, got %d", expected_col, cursor[2]))
  end

  -- Cleanup
  vim.api.nvim_buf_delete(buf, { force = true })
end

T['visual']['backward selection works'] = function()
  -- Create a test buffer
  local buf = vim.api.nvim_create_buf(true, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    "line 1",
    "line 2",
    "line 3",
  })
  vim.api.nvim_set_current_buf(buf)

  -- Create visual selection from later position to earlier position
  -- Note: visual mode direction doesn't matter for the tool
  local result = visual_tool.run({
    start_line = 2,
    start_col = 3,
    end_line = 1,
    end_col = 2,
  })
  MiniTest.expect.equality(result.success, true)

  -- Cursor should be at end position (1, 2)
  local cursor = vim.api.nvim_win_get_cursor(0)
  MiniTest.expect.equality(cursor[1], 1)
  MiniTest.expect.equality(cursor[2], 2)

  -- Verify we are in visual mode
  local mode = vim.api.nvim_get_mode().mode
  MiniTest.expect.equality(mode, "v")

  -- Cleanup
  vim.api.nvim_buf_delete(buf, { force = true })
end

T['visual']['selection with zero column works'] = function()
  -- Create a test buffer
  local buf = vim.api.nvim_create_buf(true, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    "line 1",
    "line 2",
    "line 3",
  })
  vim.api.nvim_set_current_buf(buf)

  -- Create visual selection starting at column 0
  local result = visual_tool.run({
    start_line = 1,
    start_col = 0,
    end_line = 2,
    end_col = 4,
  })
  MiniTest.expect.equality(result.success, true)
  MiniTest.expect.equality(result.start_col, 0)

  -- Verify cursor position
  local cursor = vim.api.nvim_win_get_cursor(0)
  MiniTest.expect.equality(cursor[1], 2)
  MiniTest.expect.equality(cursor[2], 4)

  -- Cleanup
  vim.api.nvim_buf_delete(buf, { force = true })
end

T['visual']['selection at line boundaries works'] = function()
  -- Create a test buffer
  local buf = vim.api.nvim_create_buf(true, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    "first",
    "second",
    "third",
    "fourth",
  })
  vim.api.nvim_set_current_buf(buf)

  -- Select from start of line 2 to end of line 3
  local result = visual_tool.run({
    start_line = 2,
    start_col = 0,
    end_line = 3,
    end_col = 5,  -- "third" is 5 characters
  })
  MiniTest.expect.equality(result.success, true)

  -- Verify cursor is at end of line 3
  local cursor = vim.api.nvim_win_get_cursor(0)
  MiniTest.expect.equality(cursor[1], 3)
  MiniTest.expect.equality(cursor[2], 5)

  -- Cleanup
  vim.api.nvim_buf_delete(buf, { force = true })
end

return T
