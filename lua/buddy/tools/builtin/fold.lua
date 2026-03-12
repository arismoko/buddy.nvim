return {
  name = "fold",
  title = "Fold Manager",
  description = "Manage code folds",
  annotations = {
    readOnlyHint = false,
  },
  input_schema = {
    type = "object",
    properties = {
      action = {
        type = "string",
        enum = { "create", "open", "close", "toggle", "open_all", "close_all", "delete" },
        description = "create: create fold from start_line to end_line, open: open fold, close: close fold, toggle: toggle fold, open_all/close_all: expand/collapse all folds, delete: remove fold at line",
      },
      start_line = {
        type = "number",
        description = "Starting line for create action.",
      },
      end_line = {
        type = "number",
        description = "Ending line for create action.",
      },
    },
    required = { "action" },
  },

  run = function(args)
    if args.action == "create" then
      if not args.start_line or not args.end_line then
        return { success = false, error = "start_line and end_line required for create action" }
      end

      -- Ensure foldmethod is manual; fold creation requires it
      local prev_foldmethod = vim.wo.foldmethod
      if prev_foldmethod ~= "manual" then
        vim.wo.foldmethod = "manual"
      end

      -- Set cursor to start line
      vim.api.nvim_win_set_cursor(0, { args.start_line, 0 })
      local ok, err = pcall(vim.cmd, args.start_line .. "," .. args.end_line .. "fold")
      if not ok then
        -- Restore foldmethod on failure
        vim.wo.foldmethod = prev_foldmethod
        return { success = false, error = "Failed to create fold: " .. tostring(err) }
      end

      return { success = true, start_line = args.start_line, end_line = args.end_line }

    elseif args.action == "open" then
      if args.start_line then
        vim.api.nvim_win_set_cursor(0, { args.start_line, 0 })
      end
      vim.cmd("normal! zO")
      return { success = true }

    elseif args.action == "close" then
      if args.start_line then
        vim.api.nvim_win_set_cursor(0, { args.start_line, 0 })
      end
      vim.cmd("normal! zC")
      return { success = true }

    elseif args.action == "toggle" then
      if args.start_line then
        vim.api.nvim_win_set_cursor(0, { args.start_line, 0 })
      end
      vim.cmd("normal! za")
      return { success = true }

    elseif args.action == "open_all" then
      vim.cmd("normal! zR")
      return { success = true }

    elseif args.action == "close_all" then
      vim.cmd("normal! zM")
      return { success = true }

    elseif args.action == "delete" then
      if args.start_line then
        vim.api.nvim_win_set_cursor(0, { args.start_line, 0 })
      end
      vim.cmd("normal! zd")
      return { success = true }

    else
      return { success = false, error = "Unknown action: " .. tostring(args.action) }
    end
  end,
}
