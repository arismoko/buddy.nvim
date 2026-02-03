-- Tests for buffer tool
local T = MiniTest.new_set()

local function setup_buffer()
  -- Create a scratch buffer with content for testing
  local buf = vim.api.nvim_create_buf(true, true)
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    'line 1',
    'line 2',
    'line 3'
  })
  vim.bo[buf].filetype = 'lua'
  return buf
end

local function get_tool()
  return require('buddy.tools.builtin.buffer')
end

T['list'] = MiniTest.new_set()

T['list']['returns array of buffers with correct structure'] = function()
  local tool = get_tool()
  local result = tool.run({ action = 'list' })

  MiniTest.expect.equality(result.success, true)
  MiniTest.expect.equality(type(result.buffers), 'table')

  -- Check that each buffer has required fields
  for _, buf in ipairs(result.buffers) do
    MiniTest.expect.equality(type(buf.bufnr), 'number')
    MiniTest.expect.equality(type(buf.name), 'string')
    MiniTest.expect.equality(type(buf.modified), 'boolean')
    MiniTest.expect.equality(type(buf.filetype), 'string')
  end
end

T['list']['includes current buffer'] = function()
  setup_buffer()  -- Ensure current buffer has a filetype so it's included
  local tool = get_tool()
  local result = tool.run({ action = 'list' })
  local current_bufnr = vim.api.nvim_get_current_buf()

  local found = false
  for _, buf in ipairs(result.buffers) do
    if buf.bufnr == current_bufnr then
      found = true
      break
    end
  end

  MiniTest.expect.equality(found, true)
end

T['get_content'] = MiniTest.new_set()

T['get_content']['returns buffer content as string'] = function()
  setup_buffer()
  local tool = get_tool()
  local result = tool.run({ action = 'get_content', bufnr = 0 })

  MiniTest.expect.equality(result.success, true)
  -- Format: 5-digit padded line numbers matching opencode read tool
  MiniTest.expect.equality(result.content, '00001| line 1\n00002| line 2\n00003| line 3')
  MiniTest.expect.equality(result.line_count, 3)
  MiniTest.expect.equality(result.showing, 3)
  MiniTest.expect.equality(result.has_more, false)
end

T['get_content']['uses current buffer when bufnr is 0'] = function()
  local tool = get_tool()
  local result = tool.run({ action = 'get_content', bufnr = 0 })
  local expected_bufnr = vim.api.nvim_get_current_buf()

  MiniTest.expect.equality(result.success, true)
  MiniTest.expect.equality(result.bufnr, expected_bufnr)
end

T['get_content']['returns error for invalid bufnr'] = function()
  local tool = get_tool()
  local result = tool.run({ action = 'get_content', bufnr = 99999 })

  MiniTest.expect.equality(result.success, false)
  MiniTest.expect.equality(type(result.error), 'string')
end

T['get_info'] = MiniTest.new_set()

T['get_info']['returns buffer metadata'] = function()
  local tool = get_tool()
  local result = tool.run({ action = 'get_info', bufnr = 0 })

  MiniTest.expect.equality(result.success, true)
  MiniTest.expect.equality(type(result.bufnr), 'number')
  MiniTest.expect.equality(type(result.name), 'string')
  MiniTest.expect.equality(type(result.filetype), 'string')
  MiniTest.expect.equality(type(result.modified), 'boolean')
  MiniTest.expect.equality(type(result.line_count), 'number')
end

T['get_info']['returns correct filetype'] = function()
  setup_buffer()
  local tool = get_tool()
  local result = tool.run({ action = 'get_info', bufnr = 0 })

  MiniTest.expect.equality(result.success, true)
  MiniTest.expect.equality(result.filetype, 'lua')
end

T['get_info']['returns correct line count'] = function()
  setup_buffer()
  local tool = get_tool()
  local result = tool.run({ action = 'get_info', bufnr = 0 })

  MiniTest.expect.equality(result.success, true)
  MiniTest.expect.equality(result.line_count, 3)
end

T['get_info']['returns error for invalid bufnr'] = function()
  local tool = get_tool()
  local result = tool.run({ action = 'get_info', bufnr = 99999 })

  MiniTest.expect.equality(result.success, false)
  MiniTest.expect.equality(type(result.error), 'string')
end

T['errors'] = MiniTest.new_set()

T['errors']['returns error for unknown action'] = function()
  local tool = get_tool()
  local result = tool.run({ action = 'unknown_action' })

  MiniTest.expect.equality(result.success, false)
  MiniTest.expect.equality(type(result.error), 'string')
  assert(result.error:find('Unknown action'), 'Expected error to contain "Unknown action"')
end

return T
