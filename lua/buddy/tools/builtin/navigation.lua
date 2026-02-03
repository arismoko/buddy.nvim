return {
  name = "navigation",
  title = "Navigation",
  description = "Navigate Neovim: marks, jumps, and cursor movement",
  annotations = {
    readOnlyHint = false,
  },
  input_schema = {
    type = "object",
    properties = {
      action = {
        type = "string",
        enum = { "goto_line", "goto_file", "set_mark", "goto_mark", "jump_back", "jump_forward", "jump_list" },
        description = "goto_line: jump to line, goto_file: open file, set_mark: set mark, goto_mark: jump to mark, jump_back: go back in jumplist, jump_forward: go forward, jump_list: list jumps",
      },
      line = {
        type = "number",
        description = "Line number for goto_line or set_mark (1-indexed)",
      },
      column = {
        type = "number",
        description = "Column number for goto_line or set_mark (0-indexed)",
      },
      file = {
        type = "string",
        description = "File path for goto_file",
      },
      mark = {
        type = "string",
        description = "Mark character (a-z or A-Z) for set_mark or goto_mark",
      },
    },
    required = { "action" },
  },

  run = function(args)
    if args.action == "goto_line" then
      if not args.line then
        return { success = false, error = "Line number required for goto_line" }
      end
      local col = args.column or 0
      vim.api.nvim_win_set_cursor(0, { args.line, col })
      return { success = true, line = args.line, column = col }

    elseif args.action == "goto_file" then
      if not args.file then
        return { success = false, error = "File path required for goto_file" }
      end
      local ok, err = pcall(function() vim.cmd("edit " .. vim.fn.fnameescape(args.file)) end)
      if not ok then
        return { success = false, error = tostring(err) }
      end
      return { success = true, file = args.file }

    elseif args.action == "set_mark" then
      -- Same validation as TS
      if not args.mark or not args.mark:match("^[a-z]$") then
        return { success = false, error = "Invalid mark name (must be a-z)" }
      end
      if not args.line then
        return { success = false, error = "Line number required for set_mark" }
      end
      local col = args.column or 0

      -- Use nvim_buf_set_mark like TS does via setpos
      local ok, err = pcall(vim.api.nvim_buf_set_mark, 0, args.mark, args.line, col, {})
      if not ok then
        return { success = false, error = "Failed to set mark: " .. tostring(err) }
      end
      return {
        success = true,
        mark = args.mark,
        line = args.line,
        column = col,
        message = string.format("Mark %s set at line %d, column %d", args.mark, args.line, col),
      }

    elseif args.action == "goto_mark" then
      if not args.mark or not args.mark:match("^[a-zA-Z]$") then
        return { success = false, error = "Invalid mark name (must be a-z or A-Z)" }
      end
      local ok, err = pcall(function() vim.cmd("normal! `" .. args.mark) end)
      if not ok then
        return { success = false, error = tostring(err) }
      end
      local cursor = vim.api.nvim_win_get_cursor(0)
      return { success = true, mark = args.mark, line = cursor[1], column = cursor[2] }

    elseif args.action == "jump_back" then
      -- Use feedkeys with special key notation (same as TS: Ctrl-O)
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-o>", true, false, true), "n", false)
      return { success = true, direction = "back" }

    elseif args.action == "jump_forward" then
      -- Use feedkeys with special key notation (same as TS: Ctrl-I)
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-i>", true, false, true), "n", false)
      return { success = true, direction = "forward" }

    elseif args.action == "jump_list" then
      -- Get jump list (same as TS)
      local jumplist = vim.fn.getjumplist()
      local jumps = jumplist[1] or {}
      local current_idx = jumplist[2] or 0

      local result = {}
      for _i, jump in ipairs(jumps) do
        local filename = vim.fn.bufname(jump.bufnr)
        table.insert(result, {
          bufnr = jump.bufnr,
          filename = filename,
          lnum = jump.lnum,
          col = jump.col,
        })
      end

      return {
        success = true,
        jumps = result,
        current = current_idx,
        total = #result,
      }

    else
      return { success = false, error = "Unknown action: " .. tostring(args.action) }
    end
  end,
}
