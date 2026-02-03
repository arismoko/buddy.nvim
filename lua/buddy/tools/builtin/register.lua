return {
  name = "register",
  title = "Register Access",
  description = "Access Neovim registers",
  annotations = {
    readOnlyHint = false,
  },
  input_schema = {
    type = "object",
    properties = {
      action = {
        type = "string",
        enum = { "get", "set", "list" },
        description = "get: retrieve register content, set: set register content, list: list all non-empty registers",
      },
      name = {
        type = "string",
        description = "Register name (a-z, \", +, *, 0-9)",
      },
      content = {
        type = "string",
        description = "Content to set (required for set action)",
      },
    },
    required = { "action" },
  },

  run = function(args)
    if args.action == "get" then
      local regname = args.name
      if not regname then
        return { success = false, error = "Register name required for get action" }
      end

      local content = vim.fn.getreg(regname)
      local regtype = vim.fn.getregtype(regname)

      return {
        success = true,
        name = regname,
        content = content,
        type = regtype,
      }

    elseif args.action == "set" then
      local regname = args.name
      local content = args.content

      if not regname then
        return { success = false, error = "Register name required for set action" }
      end
      if content == nil then
        return { success = false, error = "Content required for set action" }
      end

      vim.fn.setreg(regname, content)

      return {
        success = true,
        name = regname,
        content = content,
      }

    elseif args.action == "list" then
      local registers = {}

      -- Special registers
      local special_regs = { '"', "+", "*" }
      -- Numbered registers 0-9
      local numbered_regs = {}
      for i = 0, 9 do
        table.insert(numbered_regs, tostring(i))
      end
      -- Named registers a-z
      local named_regs = {}
      for i = string.byte("a"), string.byte("z") do
        table.insert(named_regs, string.char(i))
      end

      -- Combine all registers
      local all_regs = {}
      for _, reg in ipairs(special_regs) do
        table.insert(all_regs, reg)
      end
      for _, reg in ipairs(numbered_regs) do
        table.insert(all_regs, reg)
      end
      for _, reg in ipairs(named_regs) do
        table.insert(all_regs, reg)
      end

      -- List non-empty registers
      for _, reg in ipairs(all_regs) do
        local content = vim.fn.getreg(reg)
        if content and content ~= "" then
          table.insert(registers, {
            name = reg,
            content = content,
            type = vim.fn.getregtype(reg),
          })
        end
      end

      return {
        success = true,
        registers = registers,
      }

    else
      return { success = false, error = "Unknown action: " .. tostring(args.action) }
    end
  end,
}
