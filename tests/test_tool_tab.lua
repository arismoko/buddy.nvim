local T = MiniTest.new_set()

-- Load the tab tool
local tab_tool = require("buddy.tools.builtin.tab")

T['tab'] = MiniTest.new_set()

T['tab']['list returns array of tabs'] = function()
  local result = tab_tool.run({ action = "list" })
  MiniTest.expect.equality(result.success, true)
  MiniTest.expect.equality(type(result.tabs), "table")
  MiniTest.expect.equality(#result.tabs > 0, true)
  MiniTest.expect.equality(type(result.tabs[1].tabnr), "number")
  MiniTest.expect.equality(type(result.tabs[1].buffers), "table")
end

T['tab']['new creates new tab'] = function()
  local before_tabs = vim.api.nvim_list_tabpages()

  local result = tab_tool.run({ action = "new" })
  MiniTest.expect.equality(result.success, true)

  local after_tabs = vim.api.nvim_list_tabpages()
  MiniTest.expect.equality(#after_tabs, #before_tabs + 1)

  -- Cleanup: close the new tab
  vim.cmd("tabclose")
end

T['tab']['new with file creates new tab with file'] = function()
  local before_tabs = vim.api.nvim_list_tabpages()

  local result = tab_tool.run({ action = "new", file = "/tmp/test_file.txt" })
  MiniTest.expect.equality(result.success, true)

  local after_tabs = vim.api.nvim_list_tabpages()
  MiniTest.expect.equality(#after_tabs, #before_tabs + 1)

  -- Check if the file is opened in current buffer
  local buf_name = vim.api.nvim_buf_get_name(0)
  MiniTest.expect.equality(buf_name, "/tmp/test_file.txt")

  -- Cleanup: close the new tab
  vim.cmd("tabclose")
end

T['tab']['close closes current tab'] = function()
  -- Create a new tab first
  vim.cmd("tabnew")

  local before_tabs = vim.api.nvim_list_tabpages()

  local result = tab_tool.run({ action = "close" })
  MiniTest.expect.equality(result.success, true)

  local after_tabs = vim.api.nvim_list_tabpages()
  MiniTest.expect.equality(#after_tabs, #before_tabs - 1)
end

T['tab']['next navigates to next tab'] = function()
  -- Create 3 tabs
  vim.cmd("tabnew")
  vim.cmd("tabnew")
  vim.cmd("tabfirst")

  local current_tab = vim.api.nvim_get_current_tabpage()

  tab_tool.run({ action = "next" })
  local next_tab = vim.api.nvim_get_current_tabpage()

  MiniTest.expect.no_equality(current_tab, next_tab)

  -- Cleanup: close extra tabs
  vim.cmd("tabclose")
  vim.cmd("tabclose")
end

T['tab']['prev navigates to previous tab'] = function()
  -- Create 3 tabs and go to last
  vim.cmd("tabnew")
  vim.cmd("tabnew")

  local current_tab = vim.api.nvim_get_current_tabpage()

  tab_tool.run({ action = "prev" })
  local prev_tab = vim.api.nvim_get_current_tabpage()

  MiniTest.expect.no_equality(current_tab, prev_tab)

  -- Cleanup: close extra tabs
  vim.cmd("tabclose")
  vim.cmd("tabclose")
end

T['tab']['goto goes to specific tab'] = function()
  -- Create 3 tabs
  vim.cmd("tabnew")
  vim.cmd("tabnew")
  vim.cmd("tabfirst")

  local result = tab_tool.run({ action = "goto", tabnr = 2 })
  MiniTest.expect.equality(result.success, true)
  MiniTest.expect.equality(result.tabnr, 2)

  local current_tab = vim.api.nvim_get_current_tabpage()
  local all_tabs = vim.api.nvim_list_tabpages()
  MiniTest.expect.equality(current_tab, all_tabs[2])

  -- Cleanup: close extra tabs
  vim.cmd("tabclose")
  vim.cmd("tabclose")
end

T['tab']['goto returns error without tabnr'] = function()
  local result = tab_tool.run({ action = "goto" })
  MiniTest.expect.equality(result.success, false)
  MiniTest.expect.no_equality(result.error, nil)
end

T['tab']['first goes to first tab'] = function()
  -- Create 3 tabs and go to last
  vim.cmd("tabnew")
  vim.cmd("tabnew")

  tab_tool.run({ action = "first" })

  local all_tabs = vim.api.nvim_list_tabpages()
  local current_tab = vim.api.nvim_get_current_tabpage()
  MiniTest.expect.equality(current_tab, all_tabs[1])

  -- Cleanup: close extra tabs
  vim.cmd("tabclose")
  vim.cmd("tabclose")
end

T['tab']['last goes to last tab'] = function()
  -- Create 3 tabs and go to first
  vim.cmd("tabnew")
  vim.cmd("tabnew")
  vim.cmd("tabfirst")

  tab_tool.run({ action = "last" })

  local all_tabs = vim.api.nvim_list_tabpages()
  local current_tab = vim.api.nvim_get_current_tabpage()
  MiniTest.expect.equality(current_tab, all_tabs[#all_tabs])

  -- Cleanup: close extra tabs
  vim.cmd("tabclose")
  vim.cmd("tabclose")
end

T['tab']['unknown action returns error'] = function()
  local result = tab_tool.run({ action = "unknown" })
  MiniTest.expect.equality(result.success, false)
  MiniTest.expect.no_equality(result.error, nil)
end

T['tab']['new with malicious file arg does not execute commands'] = function()
  -- Regression: P0 command injection fix
  -- Old code used vim.cmd("tabnew " .. args.file) which allowed injection
  vim.g._buddy_injection_test = nil
  local before_tabs = vim.api.nvim_list_tabpages()

  -- This payload would execute arbitrary code with the old string concatenation approach
  local result = tab_tool.run({ action = "new", file = "test|lua vim.g._buddy_injection_test=1" })
  MiniTest.expect.equality(result.success, true)

  -- The injection should NOT have executed
  MiniTest.expect.equality(vim.g._buddy_injection_test, nil)

  -- Cleanup
  vim.cmd("tabclose")
  vim.g._buddy_injection_test = nil
end

return T
