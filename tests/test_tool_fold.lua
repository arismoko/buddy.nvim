local T = MiniTest.new_set()

-- Load the fold tool
local fold_tool = require("buddy.tools.builtin.fold")

T['fold'] = MiniTest.new_set()

T['fold']['create creates fold between lines'] = function()
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
  vim.opt_local.foldmethod = "manual"

  -- Create fold from line 2 to line 4
  local result = fold_tool.run({
    action = "create",
    start_line = 2,
    end_line = 4,
  })
  MiniTest.expect.equality(result.success, true)
  MiniTest.expect.equality(result.start_line, 2)
  MiniTest.expect.equality(result.end_line, 4)

  -- Verify fold exists (newly created folds start closed)
  local closed_folds = vim.fn.foldclosed(2)
  MiniTest.expect.equality(closed_folds, 2)

  -- Cleanup
  vim.api.nvim_buf_delete(buf, { force = true })
end

T['fold']['create returns error without start_line or end_line'] = function()
  local result1 = fold_tool.run({ action = "create", start_line = 1 })
  MiniTest.expect.equality(result1.success, false)

  local result2 = fold_tool.run({ action = "create", end_line = 5 })
  MiniTest.expect.equality(result2.success, false)
end

T['fold']['open opens fold at line'] = function()
  -- Create a test buffer with fold
  local buf = vim.api.nvim_create_buf(true, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    "line 1",
    "line 2",
    "line 3",
    "line 4",
    "line 5",
  })
  vim.api.nvim_set_current_buf(buf)
  vim.opt_local.foldmethod = "manual"

  -- Create and close a fold
  vim.cmd("2,4fold")
  vim.api.nvim_win_set_cursor(0, { 2, 0 })
  vim.cmd("normal! zC")

  -- Verify fold is closed
  local closed_before = vim.fn.foldclosed(2)
  MiniTest.expect.equality(closed_before, 2)

  -- Open the fold
  local result = fold_tool.run({
    action = "open",
    start_line = 2,
  })
  MiniTest.expect.equality(result.success, true)

  -- Verify fold is open
  local closed_after = vim.fn.foldclosed(2)
  MiniTest.expect.equality(closed_after, -1)

  -- Cleanup
  vim.api.nvim_buf_delete(buf, { force = true })
end

T['fold']['close closes fold at line'] = function()
  -- Create a test buffer with fold
  local buf = vim.api.nvim_create_buf(true, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    "line 1",
    "line 2",
    "line 3",
    "line 4",
    "line 5",
  })
  vim.api.nvim_set_current_buf(buf)
  vim.opt_local.foldmethod = "manual"

  -- Create a fold (starts closed)
  vim.cmd("2,4fold")

  -- Verify fold is closed initially
  local closed_before = vim.fn.foldclosed(2)
  MiniTest.expect.equality(closed_before, 2)

  -- Open the fold first, then close it
  vim.api.nvim_win_set_cursor(0, { 2, 0 })
  vim.cmd("normal! zO")

  -- Verify fold is now open
  local open_after_open = vim.fn.foldclosed(2)
  MiniTest.expect.equality(open_after_open, -1)

  -- Close the fold
  local result = fold_tool.run({
    action = "close",
    start_line = 2,
  })
  MiniTest.expect.equality(result.success, true)

  -- Verify fold is closed
  local closed_after = vim.fn.foldclosed(2)
  MiniTest.expect.equality(closed_after, 2)

  -- Cleanup
  vim.api.nvim_buf_delete(buf, { force = true })
end

T['fold']['toggle toggles fold state'] = function()
  -- Create a test buffer with fold
  local buf = vim.api.nvim_create_buf(true, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    "line 1",
    "line 2",
    "line 3",
    "line 4",
    "line 5",
  })
  vim.api.nvim_set_current_buf(buf)
  vim.opt_local.foldmethod = "manual"

  -- Create a fold (starts closed)
  vim.cmd("2,4fold")

  -- Verify fold is closed initially
  local closed_before = vim.fn.foldclosed(2)
  MiniTest.expect.equality(closed_before, 2)

  -- Toggle to open
  local result1 = fold_tool.run({
    action = "toggle",
    start_line = 2,
  })
  MiniTest.expect.equality(result1.success, true)
  local closed_after_toggle1 = vim.fn.foldclosed(2)
  MiniTest.expect.equality(closed_after_toggle1, -1)

  -- Toggle to close
  local result2 = fold_tool.run({
    action = "toggle",
    start_line = 2,
  })
  MiniTest.expect.equality(result2.success, true)
  local closed_after_toggle2 = vim.fn.foldclosed(2)
  MiniTest.expect.equality(closed_after_toggle2, 2)

  -- Cleanup
  vim.api.nvim_buf_delete(buf, { force = true })
end

T['fold']['open_all opens all folds'] = function()
  -- Create a test buffer with multiple folds
  local buf = vim.api.nvim_create_buf(true, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    "line 1",
    "line 2",
    "line 3",
    "line 4",
    "line 5",
    "line 6",
    "line 7",
    "line 8",
  })
  vim.api.nvim_set_current_buf(buf)
  vim.opt_local.foldmethod = "manual"

  -- Create and close multiple folds
  vim.cmd("2,4fold")
  vim.cmd("5,7fold")
  vim.api.nvim_win_set_cursor(0, { 2, 0 })
  vim.cmd("normal! zC")
  vim.api.nvim_win_set_cursor(0, { 5, 0 })
  vim.cmd("normal! zC")

  -- Verify folds are closed
  local closed_1 = vim.fn.foldclosed(2)
  local closed_2 = vim.fn.foldclosed(5)
  MiniTest.expect.equality(closed_1, 2)
  MiniTest.expect.equality(closed_2, 5)

  -- Open all folds
  local result = fold_tool.run({ action = "open_all" })
  MiniTest.expect.equality(result.success, true)

  -- Verify folds are open
  local open_1 = vim.fn.foldclosed(2)
  local open_2 = vim.fn.foldclosed(5)
  MiniTest.expect.equality(open_1, -1)
  MiniTest.expect.equality(open_2, -1)

  -- Cleanup
  vim.api.nvim_buf_delete(buf, { force = true })
end

T['fold']['close_all closes all folds'] = function()
  -- Create a test buffer with multiple folds
  local buf = vim.api.nvim_create_buf(true, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    "line 1",
    "line 2",
    "line 3",
    "line 4",
    "line 5",
    "line 6",
    "line 7",
    "line 8",
  })
  vim.api.nvim_set_current_buf(buf)
  vim.opt_local.foldmethod = "manual"

  -- Create multiple folds (start closed)
  vim.cmd("2,4fold")
  vim.cmd("5,7fold")

  -- Verify folds are closed initially
  local closed_1_init = vim.fn.foldclosed(2)
  local closed_2_init = vim.fn.foldclosed(5)
  MiniTest.expect.equality(closed_1_init, 2)
  MiniTest.expect.equality(closed_2_init, 5)

  -- Open the folds first
  vim.api.nvim_win_set_cursor(0, { 2, 0 })
  vim.cmd("normal! zO")
  vim.api.nvim_win_set_cursor(0, { 5, 0 })
  vim.cmd("normal! zO")

  -- Verify folds are open
  local open_1 = vim.fn.foldclosed(2)
  local open_2 = vim.fn.foldclosed(5)
  MiniTest.expect.equality(open_1, -1)
  MiniTest.expect.equality(open_2, -1)

  -- Close all folds
  local result = fold_tool.run({ action = "close_all" })
  MiniTest.expect.equality(result.success, true)

  -- Verify folds are closed
  local closed_1 = vim.fn.foldclosed(2)
  local closed_2 = vim.fn.foldclosed(5)
  MiniTest.expect.equality(closed_1, 2)
  MiniTest.expect.equality(closed_2, 5)

  -- Cleanup
  vim.api.nvim_buf_delete(buf, { force = true })
end

T['fold']['delete removes fold'] = function()
  -- Create a test buffer with fold
  local buf = vim.api.nvim_create_buf(true, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    "line 1",
    "line 2",
    "line 3",
    "line 4",
    "line 5",
  })
  vim.api.nvim_set_current_buf(buf)
  vim.opt_local.foldmethod = "manual"

  -- Create a fold
  vim.cmd("2,4fold")

  -- Verify fold exists
  local closed_before = vim.fn.foldclosedend(2)
  MiniTest.expect.no_equality(closed_before, -1)

  -- Delete the fold
  local result = fold_tool.run({
    action = "delete",
    start_line = 2,
  })
  MiniTest.expect.equality(result.success, true)

  -- Verify fold is deleted
  local closed_after = vim.fn.foldclosedend(2)
  MiniTest.expect.equality(closed_after, -1)

  -- Cleanup
  vim.api.nvim_buf_delete(buf, { force = true })
end

T['fold']['unknown action returns error'] = function()
  local result = fold_tool.run({ action = "unknown" })
  MiniTest.expect.equality(result.success, false)
  MiniTest.expect.no_equality(result.error, nil)
end

return T
