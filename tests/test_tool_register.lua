local T = MiniTest.new_set()

-- Load register tool
local register_tool = require("buddy.tools.builtin.register")

T['register'] = MiniTest.new_set()

T['register']['set sets register content'] = function()
  local result = register_tool.run({
    action = "set",
    name = "a",
    content = "test content",
  })
  MiniTest.expect.equality(result.success, true)
  MiniTest.expect.equality(result.name, "a")
  MiniTest.expect.equality(result.content, "test content")

  -- Verify register was set
  local reg_content = vim.fn.getreg("a")
  MiniTest.expect.equality(reg_content, "test content")

  -- Cleanup: clear register
  vim.fn.setreg("a", "")
end

T['register']['set returns error without name'] = function()
  local result = register_tool.run({
    action = "set",
    content = "test",
  })
  MiniTest.expect.equality(result.success, false)
  MiniTest.expect.no_equality(result.error, nil)
end

T['register']['set returns error without content'] = function()
  local result = register_tool.run({
    action = "set",
    name = "b",
  })
  MiniTest.expect.equality(result.success, false)
  MiniTest.expect.no_equality(result.error, nil)
end

T['register']['get retrieves register content'] = function()
  -- Set up a register
  vim.fn.setreg("c", "retrieve test")

  local result = register_tool.run({
    action = "get",
    name = "c",
  })
  MiniTest.expect.equality(result.success, true)
  MiniTest.expect.equality(result.name, "c")
  MiniTest.expect.equality(result.content, "retrieve test")
  MiniTest.expect.no_equality(result.type, nil)

  -- Cleanup: clear register
  vim.fn.setreg("c", "")
end

T['register']['get retrieves register type'] = function()
  -- Set up a line-wise register
  vim.fn.setreg("d", "line 1\nline 2\n", "l")

  local result = register_tool.run({
    action = "get",
    name = "d",
  })
  MiniTest.expect.equality(result.success, true)
  MiniTest.expect.equality(result.type, "V")

  -- Cleanup: clear register
  vim.fn.setreg("d", "")
end

T['register']['get returns error without name'] = function()
  local result = register_tool.run({ action = "get" })
  MiniTest.expect.equality(result.success, false)
  MiniTest.expect.no_equality(result.error, nil)
end

T['register']['list lists non-empty registers'] = function()
  -- Set up a few registers
  vim.fn.setreg("e", "content e")
  vim.fn.setreg("f", "content f")
  vim.fn.setreg("g", "content g")

  local result = register_tool.run({ action = "list" })
  MiniTest.expect.equality(result.success, true)
  MiniTest.expect.equality(type(result.registers), "table")
  MiniTest.expect.equality(#result.registers > 0, true)

  -- Check if our registers are in the list
  local found_e = false
  local found_f = false
  local found_g = false

  for _, reg in ipairs(result.registers) do
    if reg.name == "e" then
      found_e = true
      MiniTest.expect.equality(reg.content, "content e")
    elseif reg.name == "f" then
      found_f = true
      MiniTest.expect.equality(reg.content, "content f")
    elseif reg.name == "g" then
      found_g = true
      MiniTest.expect.equality(reg.content, "content g")
    end
  end

  MiniTest.expect.equality(found_e, true)
  MiniTest.expect.equality(found_f, true)
  MiniTest.expect.equality(found_g, true)

  -- Cleanup: clear registers
  vim.fn.setreg("e", "")
  vim.fn.setreg("f", "")
  vim.fn.setreg("g", "")
end

T['register']['list includes register type'] = function()
  -- Set up registers with different types
  vim.fn.setreg("h", "char-wise", "v")
  vim.fn.setreg("i", "line-wise\n", "l")
  vim.fn.setreg("j", "block-wise", "b")

  local result = register_tool.run({ action = "list" })
  MiniTest.expect.equality(result.success, true)

  -- Find our registers and check types
  for _, reg in ipairs(result.registers) do
    if reg.name == "h" then
      MiniTest.expect.equality(reg.type, "v")
    elseif reg.name == "i" then
      MiniTest.expect.equality(reg.type, "V")
    elseif reg.name == "j" then
      -- Blockwise register type includes width and height: "\02210" (type + width + height)
      MiniTest.expect.equality(string.sub(reg.type, 1, 1), "\022")
    end
  end

  -- Cleanup: clear registers
  vim.fn.setreg("h", "")
  vim.fn.setreg("i", "")
  vim.fn.setreg("j", "")
end

T['register']['list does not include empty registers'] = function()
  -- Ensure some registers are empty
  vim.fn.setreg("k", "")

  local result = register_tool.run({ action = "list" })
  MiniTest.expect.equality(result.success, true)

  -- Check that register "k" is not in the list
  local found_k = false
  for _, reg in ipairs(result.registers) do
    if reg.name == "k" then
      found_k = true
    end
  end

  MiniTest.expect.equality(found_k, false)
end

T['register']['special registers can be set and retrieved'] = function()
  -- Test unnamed register
  local result1 = register_tool.run({
    action = "set",
    name = "\"",
    content = "unnamed",
  })
  MiniTest.expect.equality(result1.success, true)

  local result2 = register_tool.run({
    action = "get",
    name = "\"",
  })
  MiniTest.expect.equality(result2.success, true)
  MiniTest.expect.equality(result2.content, "unnamed")

  -- Test clipboard register
  local result3 = register_tool.run({
    action = "set",
    name = "+",
    content = "clipboard",
  })
  MiniTest.expect.equality(result3.success, true)

  local result4 = register_tool.run({
    action = "get",
    name = "+",
  })
  MiniTest.expect.equality(result4.success, true)
  MiniTest.expect.equality(result4.content, "clipboard")

  -- Cleanup
  vim.fn.setreg("\"", "")
  vim.fn.setreg("+", "")
end

T['register']['numbered registers can be set and retrieved'] = function()
  -- Test numbered register 0 (yank register)
  local result1 = register_tool.run({
    action = "set",
    name = "0",
    content = "yank register",
  })
  MiniTest.expect.equality(result1.success, true)

  local result2 = register_tool.run({
    action = "get",
    name = "0",
  })
  MiniTest.expect.equality(result2.success, true)
  MiniTest.expect.equality(result2.content, "yank register")

  -- Cleanup
  vim.fn.setreg("0", "")
end

T['register']['unknown action returns error'] = function()
  local result = register_tool.run({ action = "unknown" })
  MiniTest.expect.equality(result.success, false)
  MiniTest.expect.no_equality(result.error, nil)
end

return T
