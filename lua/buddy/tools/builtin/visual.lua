return {
  name = "visual",
  title = "Visual Selection",
  description = "Create visual selections",
  annotations = {
    readOnlyHint = true,
  },
  input_schema = {
    type = "object",
    properties = {
      start_line = {
        type = "number",
        description = "Starting line (1-indexed)",
      },
      start_col = {
        type = "number",
        description = "Starting column (0-indexed)",
      },
      end_line = {
        type = "number",
        description = "Ending line (1-indexed)",
      },
      end_col = {
        type = "number",
        description = "Ending column (0-indexed)",
      },
    },
    required = { "start_line", "start_col", "end_line", "end_col" },
  },

  run = function(args)
    -- Move to start position
    vim.api.nvim_win_set_cursor(0, { args.start_line, args.start_col })
    -- Enter visual mode
    vim.cmd("normal! v")
    -- Move to end position
    vim.api.nvim_win_set_cursor(0, { args.end_line, args.end_col })

    return {
      success = true,
      start_line = args.start_line,
      start_col = args.start_col,
      end_line = args.end_line,
      end_col = args.end_col,
    }
  end,
}
