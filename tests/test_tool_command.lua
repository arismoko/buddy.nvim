-- Tests for command tool
local T = MiniTest.new_set()

-- Setup for each test
T['hooks'] = {
  pre_case = function()
    -- Ensure a clean buffer
    vim.cmd('enew')
  end
}

local function get_tool()
  return require('buddy.tools.builtin.command')
end

T['execute'] = MiniTest.new_set()

T['execute']['runs successful command'] = function()
  local tool = get_tool()

  -- Test setting an option
  local result = tool.run({ cmd = 'set number' })

  MiniTest.expect.equality(result.success, true)
  MiniTest.expect.equality(result.cmd, 'set number')

  -- Verify the command actually executed
  MiniTest.expect.equality(vim.wo.number, true)

  -- Clean up
  vim.cmd('set nonumber')
end

T['execute']['runs command with parameters'] = function()
  local tool = get_tool()

  -- Test setting a value
  local result = tool.run({ cmd = 'set tabstop=4' })

  MiniTest.expect.equality(result.success, true)
  MiniTest.expect.equality(result.cmd, 'set tabstop=4')

  -- Verify the command executed
  MiniTest.expect.equality(vim.bo.tabstop, 4)
end

T['execute']['handles multiple word commands'] = function()
  local tool = get_tool()

  -- Test a command with spaces
  local result = tool.run({ cmd = 'set shiftwidth=2 expandtab' })

  MiniTest.expect.equality(result.success, true)
  MiniTest.expect.equality(result.cmd, 'set shiftwidth=2 expandtab')

  -- Verify both settings were applied
  MiniTest.expect.equality(vim.bo.shiftwidth, 2)
  MiniTest.expect.equality(vim.bo.expandtab, true)
end

T['execute']['handles write command'] = function()
  local tool = get_tool()

  -- Add some content to buffer
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'test content' })

  -- Use a temp file
  local temp_file = '/tmp/nvim-buddy-test.txt'
  local result = tool.run({ cmd = 'write ' .. temp_file })

  MiniTest.expect.equality(result.success, true)
  MiniTest.expect.equality(result.cmd, 'write ' .. temp_file)

  -- Verify file was created
  local f = io.open(temp_file, 'r')
  local content = f:read('*all')
  f:close()

  MiniTest.expect.equality(content, 'test content\n')

  -- Clean up
  os.remove(temp_file)
end

T['errors'] = MiniTest.new_set()

T['errors']['returns error for invalid command'] = function()
  local tool = get_tool()

  -- Try an invalid command
  local result = tool.run({ cmd = 'InvalidCommandThatDoesNotExist' })

  MiniTest.expect.equality(result.success, false)
  MiniTest.expect.equality(type(result.error), 'string')
end

T['errors']['returns error for empty command'] = function()
  local tool = get_tool()

  local result = tool.run({ cmd = '' })

  MiniTest.expect.equality(result.success, false)
  MiniTest.expect.equality(type(result.error), 'string')
end

T['errors']['returns error when cmd is nil'] = function()
  local tool = get_tool()

  local result = tool.run({})

  MiniTest.expect.equality(result.success, false)
  MiniTest.expect.equality(type(result.error), 'string')
end

T['errors']['handles command with syntax errors'] = function()
  local tool = get_tool()

  -- Try a command that will definitely throw an error
  local result = tool.run({ cmd = 'luaerror' })

  MiniTest.expect.equality(result.success, false)
  MiniTest.expect.equality(type(result.error), 'string')
end

T['edit_commands'] = MiniTest.new_set()

T['edit_commands']['opens a file'] = function()
  local tool = get_tool()

  -- Create a temp file to edit
  local temp_file = '/tmp/nvim-buddy-edit-test.txt'
  local f = io.open(temp_file, 'w')
  f:write('original content')
  f:close()

  local result = tool.run({ cmd = 'edit ' .. temp_file })

  MiniTest.expect.equality(result.success, true)
  MiniTest.expect.equality(result.cmd, 'edit ' .. temp_file)

  -- Verify buffer was loaded
  local content = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  MiniTest.expect.equality(content[1], 'original content')

  -- Clean up
  os.remove(temp_file)
  vim.cmd('enew')
end

return T
