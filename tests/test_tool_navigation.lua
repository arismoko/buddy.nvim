local T = MiniTest.new_set()

local navigation_tool = require('buddy.tools.builtin.navigation')

-- Helper to create a test buffer with content
local function create_test_buffer()
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "line1", "line2", "line3", "line4", "line5" })
  vim.api.nvim_set_current_buf(bufnr)
  return bufnr
end

-- Helper to create a temp file
local function create_temp_file(content)
  local tmpfile = vim.fn.tempname()
  local f = io.open(tmpfile, "w")
  if f then
    f:write(content or "temp file content\nline2\nline3")
    f:close()
  end
  return tmpfile
end

T['goto_line'] = MiniTest.new_set()
T['goto_line']['moves cursor to specified line'] = function()
  local bufnr = create_test_buffer()

  -- Start at line 1
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  local start_cursor = vim.api.nvim_win_get_cursor(0)
  MiniTest.expect.equality(start_cursor[1], 1)

  -- Go to line 3
  local result = navigation_tool.run({ action = "goto_line", line = 3 })

  MiniTest.expect.equality(result.success, true)
  MiniTest.expect.equality(result.line, 3)

  -- Verify cursor moved
  local end_cursor = vim.api.nvim_win_get_cursor(0)
  MiniTest.expect.equality(end_cursor[1], 3)

  -- Cleanup
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T['goto_line']['moves cursor with column specified'] = function()
  local bufnr = create_test_buffer()

  -- Go to line 2, column 4
  local result = navigation_tool.run({ action = "goto_line", line = 2, column = 4 })

  MiniTest.expect.equality(result.success, true)
  MiniTest.expect.equality(result.line, 2)
  MiniTest.expect.equality(result.column, 4)

  -- Verify cursor position
  local cursor = vim.api.nvim_win_get_cursor(0)
  MiniTest.expect.equality(cursor[1], 2)
  MiniTest.expect.equality(cursor[2], 4)

  -- Cleanup
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T['goto_line']['returns error when line is not provided'] = function()
  local result = navigation_tool.run({ action = "goto_line" })

  MiniTest.expect.equality(result.success, false)
  MiniTest.expect.equality(type(result.error), "string")
end

T['goto_file'] = MiniTest.new_set()
T['goto_file']['opens specified file'] = function()
  local tmpfile = create_temp_file("test content")

  local result = navigation_tool.run({ action = "goto_file", file = tmpfile })

  MiniTest.expect.equality(result.success, true)
  MiniTest.expect.equality(result.file, tmpfile)

  -- Verify file is open in current buffer
  local current_bufname = vim.api.nvim_buf_get_name(0)
  MiniTest.expect.equality(current_bufname, tmpfile)

  -- Verify content
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  MiniTest.expect.equality(lines[1], "test content")

  -- Cleanup
  vim.api.nvim_buf_delete(0, { force = true })
  os.remove(tmpfile)
end

T['goto_file']['returns error when file is not provided'] = function()
  local result = navigation_tool.run({ action = "goto_file" })

  MiniTest.expect.equality(result.success, false)
  MiniTest.expect.equality(type(result.error), "string")
end

T['set_mark'] = MiniTest.new_set()
T['set_mark']['sets mark at specified position'] = function()
  local bufnr = create_test_buffer()

  -- Set mark 'a' at line 3, column 5
  local result = navigation_tool.run({ action = "set_mark", mark = "a", line = 3, column = 5 })

  MiniTest.expect.equality(result.success, true)
  MiniTest.expect.equality(result.mark, "a")
  MiniTest.expect.equality(result.line, 3)
  MiniTest.expect.equality(result.column, 5)

  -- Verify message
  MiniTest.expect.equality(type(result.message), "string")

  -- Verify mark was set by retrieving it
  local mark_pos = vim.api.nvim_buf_get_mark(0, "a")
  MiniTest.expect.equality(mark_pos[1], 3)
  MiniTest.expect.equality(mark_pos[2], 5)

  -- Cleanup
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T['set_mark']['returns error for invalid mark name'] = function()
  local bufnr = create_test_buffer()

  -- Invalid mark name (not a-z)
  local result = navigation_tool.run({ action = "set_mark", mark = "A", line = 3 })

  MiniTest.expect.equality(result.success, false)
  MiniTest.expect.equality(type(result.error), "string")

  -- Cleanup
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T['set_mark']['returns error when line is not provided'] = function()
  local result = navigation_tool.run({ action = "set_mark", mark = "a" })

  MiniTest.expect.equality(result.success, false)
  MiniTest.expect.equality(type(result.error), "string")
end

T['goto_mark'] = MiniTest.new_set()
T['goto_mark']['jumps to specified mark'] = function()
  local bufnr = create_test_buffer()

  -- First set mark 'b' at line 5
  vim.api.nvim_buf_set_mark(0, "b", 5, 0, {})

  -- Start at line 1
  vim.api.nvim_win_set_cursor(0, { 1, 0 })

  -- Go to mark 'b'
  local result = navigation_tool.run({ action = "goto_mark", mark = "b" })

  MiniTest.expect.equality(result.success, true)
  MiniTest.expect.equality(result.mark, "b")

  -- Verify cursor moved to line 5
  local cursor = vim.api.nvim_win_get_cursor(0)
  MiniTest.expect.equality(cursor[1], 5)

  -- Cleanup
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T['goto_mark']['returns error when mark is not provided'] = function()
  local result = navigation_tool.run({ action = "goto_mark" })

  MiniTest.expect.equality(result.success, false)
  MiniTest.expect.equality(type(result.error), "string")
end

T['jump_back'] = MiniTest.new_set()
T['jump_back']['navigates back in jump list'] = function()
  local bufnr = create_test_buffer()

  -- Create some jumps
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  vim.api.nvim_win_set_cursor(0, { 3, 0 })
  vim.api.nvim_win_set_cursor(0, { 5, 0 })

  local result = navigation_tool.run({ action = "jump_back" })

  MiniTest.expect.equality(result.success, true)
  MiniTest.expect.equality(result.direction, "back")

  -- Cleanup
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T['jump_forward'] = MiniTest.new_set()
T['jump_forward']['navigates forward in jump list'] = function()
  local bufnr = create_test_buffer()

  -- Create some jumps and go back first
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  vim.api.nvim_win_set_cursor(0, { 3, 0 })
  vim.api.nvim_win_set_cursor(0, { 5, 0 })
  navigation_tool.run({ action = "jump_back" })

  -- Now go forward
  local result = navigation_tool.run({ action = "jump_forward" })

  MiniTest.expect.equality(result.success, true)
  MiniTest.expect.equality(result.direction, "forward")

  -- Cleanup
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T['jump_list'] = MiniTest.new_set()
T['jump_list']['returns jump list with correct field names'] = function()
  local bufnr = create_test_buffer()

  -- Create some jumps
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  vim.api.nvim_win_set_cursor(0, { 3, 0 })
  vim.api.nvim_win_set_cursor(0, { 5, 0 })

  local result = navigation_tool.run({ action = "jump_list" })

  MiniTest.expect.equality(result.success, true)
  -- Main fix: use 'jumps' not 'jump_list'
  MiniTest.expect.equality(type(result.jumps), "table")
  MiniTest.expect.equality(#result.jumps >= 1, true)

  -- Verify current and total fields
  MiniTest.expect.equality(type(result.current), "number")
  MiniTest.expect.equality(type(result.total), "number")

  -- Verify jump entry structure
  if #result.jumps > 0 then
    local jump = result.jumps[1]
    MiniTest.expect.equality(type(jump.bufnr), "number")
    MiniTest.expect.equality(type(jump.filename), "string")
    MiniTest.expect.equality(type(jump.lnum), "number")
    MiniTest.expect.equality(type(jump.col), "number")
  end

  -- Cleanup
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T['unknown_action'] = MiniTest.new_set()
T['unknown_action']['returns error for invalid action'] = function()
  local result = navigation_tool.run({ action = "invalid_action" })

  MiniTest.expect.equality(result.success, false)
  MiniTest.expect.equality(type(result.error), "string")
end

return T
