local T = MiniTest.new_set()

local macro_tool = require('buddy.tools.builtin.macro')

T['macro'] = MiniTest.new_set()

T['macro']['record starts recording and returns success'] = function()
  -- Note: In headless mode, we can only verify the function doesn't error
  -- and returns the expected structure
  local result = macro_tool.run({
    action = "record",
    register = "a",
  })

  MiniTest.expect.equality(result.success, true)
  MiniTest.expect.equality(result.register, "a")

  -- Clean up - stop any recording that might have started
  pcall(function()
    macro_tool.run({ action = "stop" })
  end)
end

T['macro']['record with default register q'] = function()
  local result = macro_tool.run({
    action = "record",
  })

  MiniTest.expect.equality(result.success, true)
  MiniTest.expect.equality(result.register, "q")

  -- Clean up
  pcall(function()
    macro_tool.run({ action = "stop" })
  end)
end

T['macro']['stop stops recording and returns success'] = function()
  -- In headless mode, we test that the stop action is valid
  -- We attempt to record first, then stop (even if recording didn't fully start)
  pcall(function()
    macro_tool.run({ action = "record", register = "a" })
  end)

  local result = macro_tool.run({
    action = "stop",
  })

  MiniTest.expect.equality(result.success, true)
end

T['macro']['play executes macro and returns success'] = function()
  -- Note: In headless mode, we can only verify the function doesn't error
  -- and returns the expected structure
  local result = macro_tool.run({
    action = "play",
    register = "a",
    count = 1,
  })

  MiniTest.expect.equality(result.success, true)
  MiniTest.expect.equality(result.register, "a")
  MiniTest.expect.equality(result.count, 1)
end

T['macro']['play with default count 1'] = function()
  local result = macro_tool.run({
    action = "play",
    register = "b",
  })

  MiniTest.expect.equality(result.success, true)
  MiniTest.expect.equality(result.register, "b")
  MiniTest.expect.equality(result.count, 1)
end

T['macro']['play with custom count'] = function()
  local result = macro_tool.run({
    action = "play",
    register = "c",
    count = 5,
  })

  MiniTest.expect.equality(result.success, true)
  MiniTest.expect.equality(result.register, "c")
  MiniTest.expect.equality(result.count, 5)
end

T['macro']['unknown action returns error'] = function()
  local result = macro_tool.run({
    action = "unknown_action",
  })

  MiniTest.expect.equality(result.success, false)
  MiniTest.expect.equality(type(result.error), "string")
  MiniTest.expect.equality(result.error:find("Unknown action"), 1)
end

T['macro']['all basic actions execute without errors'] = function()
  -- Test that all actions can be called without raising Lua errors
  -- This is important for headless environments where full functionality
  -- may be limited

  local actions = { "record", "stop", "play" }

  for _, action in ipairs(actions) do
    local ok, result = pcall(macro_tool.run, { action = action })
    MiniTest.expect.equality(ok, true, "Action '" .. action .. "' should not raise an error")
  end
end

return T
