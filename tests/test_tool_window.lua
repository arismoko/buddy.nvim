-- Tests for window tool
local T = MiniTest.new_set()

-- Setup/teardown for each test
T['hooks'] = {
  pre_case = function()
    -- Start with a single window
    vim.cmd('only')
    -- Create a scratch buffer for testing
    vim.cmd('enew')
  end
}

local function get_tool()
  return require('buddy.tools.builtin.window')
end

local function count_windows()
  return #vim.api.nvim_list_wins()
end

T['list'] = MiniTest.new_set()

T['list']['returns array of windows'] = function()
  local tool = get_tool()
  local result = tool.run({ action = 'list' })

  MiniTest.expect.equality(result.success, true)
  MiniTest.expect.equality(type(result.windows), 'table')
  MiniTest.expect.equality(#result.windows, 1)
end

T['list']['returns windows with correct structure'] = function()
  local tool = get_tool()
  local result = tool.run({ action = 'list' })

  MiniTest.expect.equality(result.success, true)

  -- Check that each window has required fields
  for _, win in ipairs(result.windows) do
    MiniTest.expect.equality(type(win.winnr), 'number')
    MiniTest.expect.equality(type(win.bufnr), 'number')
    MiniTest.expect.equality(type(win.width), 'number')
    MiniTest.expect.equality(type(win.height), 'number')
  end
end

T['split'] = MiniTest.new_set()

T['split']['creates horizontal split'] = function()
  local tool = get_tool()
  local before = count_windows()

  local result = tool.run({ action = 'split' })
  local after = count_windows()

  MiniTest.expect.equality(result.success, true)
  MiniTest.expect.equality(after, before + 1)
  MiniTest.expect.equality(type(result.winnr), 'number')

  -- Clean up
  vim.cmd('only')
end

T['vsplit'] = MiniTest.new_set()

T['vsplit']['creates vertical split'] = function()
  local tool = get_tool()
  local before = count_windows()

  local result = tool.run({ action = 'vsplit' })
  local after = count_windows()

  MiniTest.expect.equality(result.success, true)
  MiniTest.expect.equality(after, before + 1)
  MiniTest.expect.equality(type(result.winnr), 'number')

  -- Clean up
  vim.cmd('only')
end

T['close'] = MiniTest.new_set()

T['close']['closes current window'] = function()
  local tool = get_tool()

  -- Create a split first
  vim.cmd('split')
  local windows_before = count_windows()
  local win_to_close = vim.api.nvim_get_current_win()

  local result = tool.run({ action = 'close', winnr = win_to_close })
  local windows_after = count_windows()

  MiniTest.expect.equality(result.success, true)
  MiniTest.expect.equality(windows_after, windows_before - 1)
end

T['close']['returns error for invalid window'] = function()
  local tool = get_tool()
  local result = tool.run({ action = 'close', winnr = 99999 })

  MiniTest.expect.equality(result.success, false)
  MiniTest.expect.equality(type(result.error), 'string')
end

T['only'] = MiniTest.new_set()

T['only']['closes all but current window'] = function()
  local tool = get_tool()

  -- Create multiple splits
  vim.cmd('split')
  vim.cmd('vsplit')
  local windows_before = count_windows()

  MiniTest.expect.equality(windows_before > 1, true)

  local result = tool.run({ action = 'only' })
  local windows_after = count_windows()

  MiniTest.expect.equality(result.success, true)
  MiniTest.expect.equality(windows_after, 1)
end

T['focus'] = MiniTest.new_set()

T['focus']['focuses window by number'] = function()
  local tool = get_tool()

  -- Create a split to have multiple windows
  vim.cmd('split')
  local target_winnr = vim.api.nvim_get_current_win()

  -- Switch back to first window
  vim.cmd('wincmd w')

  local result = tool.run({ action = 'focus', winnr = target_winnr })
  local current = vim.api.nvim_get_current_win()

  MiniTest.expect.equality(result.success, true)
  MiniTest.expect.equality(current, target_winnr)

  -- Clean up
  vim.cmd('only')
end

T['focus']['navigates by direction'] = function()
  local tool = get_tool()

  -- Create a split
  vim.cmd('split')
  local top_win = vim.api.nvim_get_current_win()
  vim.cmd('wincmd w')

  local result = tool.run({ action = 'focus', direction = 'k' })
  local current = vim.api.nvim_get_current_win()

  MiniTest.expect.equality(result.success, true)
  MiniTest.expect.equality(current, top_win)

  -- Clean up
  vim.cmd('only')
end

T['focus']['returns error for invalid direction'] = function()
  local tool = get_tool()
  local result = tool.run({ action = 'focus', direction = 'x' })

  MiniTest.expect.equality(result.success, false)
  MiniTest.expect.equality(type(result.error), 'string')
end

T['focus']['returns error when missing winnr and direction'] = function()
  local tool = get_tool()
  local result = tool.run({ action = 'focus' })

  MiniTest.expect.equality(result.success, false)
  MiniTest.expect.equality(type(result.error), 'string')
end

T['errors'] = MiniTest.new_set()

T['errors']['returns error for unknown action'] = function()
  local tool = get_tool()
  local result = tool.run({ action = 'unknown_action' })

  MiniTest.expect.equality(result.success, false)
  MiniTest.expect.equality(type(result.error), 'string')
end

return T
