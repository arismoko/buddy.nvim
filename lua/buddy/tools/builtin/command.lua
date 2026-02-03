return {
  name = "command",
  title = "Vim Command",
  description = "Execute Vim commands",
  annotations = {
    destructiveHint = true,
  },
  input_schema = {
    type = "object",
    properties = {
      cmd = {
        type = "string",
        description = "The Vim command to execute (e.g., 'write', 'edit file.txt', 'split')",
      },
    },
    required = { "cmd" },
  },

  run = function(args)
    local cmd = args.cmd

    if not cmd or cmd == "" then
      return { success = false, error = "Command cannot be empty" }
    end

    -- Check if it's a lua command - capture return value
    if cmd:match("^lua%s+") then
      local lua_code = cmd:gsub("^lua%s+", "")
      -- Wrap in return if it's an expression
      local chunk, err = loadstring("return " .. lua_code)
      if not chunk then
        -- Try without return (statement)
        chunk, err = loadstring(lua_code)
      end
      if not chunk then
        return { success = false, error = "Lua syntax error: " .. tostring(err) }
      end
      local ok, result = pcall(chunk)
      if ok then
        return { success = true, cmd = cmd, result = result }
      else
        return { success = false, error = tostring(result) }
      end
    end

    -- Regular vim command - use nvim_exec2 to capture output
    local ok, result = pcall(vim.api.nvim_exec2, cmd, { output = true })

    if ok then
      return { success = true, cmd = cmd, output = result.output ~= "" and result.output or nil }
    else
      return { success = false, error = tostring(result) }
    end
  end,
}
