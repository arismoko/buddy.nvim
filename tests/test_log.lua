local T = MiniTest.new_set()

T['hooks'] = {
  pre_case = function()
    package.loaded['buddy.log'] = nil
  end
}

T['log'] = MiniTest.new_set()

T['log']['does not crash on percent signs in message'] = function()
  -- Regression: P1 logger crashed on stray % in format string
  local log = require('buddy.log')

  -- These should not throw
  local ok1 = pcall(log.info, '100% complete')
  MiniTest.expect.equality(ok1, true)

  local ok2 = pcall(log.error, 'failed at 50%')
  MiniTest.expect.equality(ok2, true)
end

T['log']['does not crash on mismatched format args'] = function()
  -- Regression: P1 string.format with wrong arg count
  local log = require('buddy.log')

  -- Too few args for format specifiers
  local ok1 = pcall(log.info, '%s and %s', 'one')
  MiniTest.expect.equality(ok1, true)

  -- Format specifier with no args
  local ok2 = pcall(log.warning, '%d items processed')
  MiniTest.expect.equality(ok2, true)
end

return T
