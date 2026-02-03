local T = MiniTest.new_set()

local status_tool = require('buddy.tools.builtin.status')

-- Helper to create a test buffer with content
local function create_test_buffer()
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "line1", "line2", "line3" })
  vim.api.nvim_set_current_buf(bufnr)
  return bufnr
end

T['status_tool'] = MiniTest.new_set()

T['status_tool']['returns complete status info without arguments'] = function()
  local bufnr = create_test_buffer()

  -- TS-faithful: NO arguments
  local result = status_tool.run()

  MiniTest.expect.equality(result.success, true)

  -- Verify all expected fields exist and have correct types
  MiniTest.expect.equality(type(result.cursorPosition), "table")
  MiniTest.expect.equality(#result.cursorPosition, 2)
  MiniTest.expect.equality(type(result.cursorPosition[1]), "number") -- line
  MiniTest.expect.equality(type(result.cursorPosition[2]), "number") -- col
  MiniTest.expect.equality(type(result.mode), "string")
  MiniTest.expect.equality(type(result.fileName), "string")
  MiniTest.expect.equality(type(result.windowLayout), "table")
  MiniTest.expect.equality(type(result.currentTab), "number")
  MiniTest.expect.equality(type(result.marks), "table")
  MiniTest.expect.equality(type(result.registers), "table")
  MiniTest.expect.equality(type(result.cwd), "string")
  -- TS returns strings for lspInfo and pluginInfo
  MiniTest.expect.equality(type(result.lspInfo), "string")
  MiniTest.expect.equality(type(result.pluginInfo), "string")

  -- Cleanup
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T['status_tool']['returns correct cursor position'] = function()
  local bufnr = create_test_buffer()
  vim.api.nvim_win_set_cursor(0, { 2, 3 })

  local result = status_tool.run()

  MiniTest.expect.equality(result.cursorPosition[1], 2)
  MiniTest.expect.equality(result.cursorPosition[2], 3)

  -- Cleanup
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T['status_tool']['returns current mode'] = function()
  local bufnr = create_test_buffer()

  local result = status_tool.run()

  MiniTest.expect.equality(type(result.mode), "string")
  MiniTest.expect.equality(#result.mode > 0, true)

  -- Cleanup
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T['status_tool']['returns file name'] = function()
  local bufnr = create_test_buffer()

  local result = status_tool.run()

  -- TS-faithful: fileName is a string (for unnamed buffers, it's like "[No Name]")
  MiniTest.expect.equality(type(result.fileName), "string")

  -- Cleanup
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T['status_tool']['returns working directory'] = function()
  local bufnr = create_test_buffer()

  local result = status_tool.run()
  local expected_cwd = vim.fn.getcwd()

  MiniTest.expect.equality(result.cwd, expected_cwd)

  -- Cleanup
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T['status_tool']['returns window layout info'] = function()
  local bufnr = create_test_buffer()

  local result = status_tool.run()

  -- windowLayout should contain information about splits and windows
  MiniTest.expect.equality(type(result.windowLayout), "table")

  -- currentTab should be a number (tab page number)
  MiniTest.expect.equality(type(result.currentTab), "number")

  -- Cleanup
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T['status_tool']['returns marks and registers'] = function()
  local bufnr = create_test_buffer()

  local result = status_tool.run()

  -- marks and registers should be tables (possibly empty)
  MiniTest.expect.equality(type(result.marks), "table")
  MiniTest.expect.equality(type(result.registers), "table")

  -- Cleanup
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T['status_tool']['returns LSP and plugin info'] = function()
  local bufnr = create_test_buffer()

  local result = status_tool.run()

  -- TS returns strings for lspInfo and pluginInfo
  MiniTest.expect.equality(type(result.lspInfo), "string")
  MiniTest.expect.equality(type(result.pluginInfo), "string")

  -- Cleanup
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T['status_tool']['returns visual selection info'] = function()
  local bufnr = create_test_buffer()

  local result = status_tool.run()

  -- visualInfo should be a table (may be empty if not in visual mode)
  MiniTest.expect.equality(type(result.visualInfo), "table")

  -- Cleanup
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T['status_tool']['ignores extra arguments'] = function()
  local bufnr = create_test_buffer()

  -- TS-faithful: should work even if extra arguments are passed (backward compatibility)
  local result = status_tool.run({ action = "all" })

  MiniTest.expect.equality(result.success, true)
  MiniTest.expect.equality(type(result.cursorPosition), "table")
  MiniTest.expect.equality(type(result.fileName), "string")

  -- Cleanup
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

return T
