return {
  name = "window",
  title = "Window Manager",
  description = "Manage Neovim windows",
  annotations = {
    readOnlyHint = false,
  },
  input_schema = {
    type = "object",
    properties = {
      action = {
        type = "string",
        enum = { "list", "focus", "split", "vsplit", "close", "only" },
        description = "list: all windows, focus: focus a window, split: horizontal split, vsplit: vertical split, close: close window, only: keep only current window",
      },
      winnr = {
        type = "number",
        description = "Window number. Optional - defaults to current window for focus/close actions.",
      },
      direction = {
        type = "string",
        enum = { "h", "j", "k", "l" },
        description = "Direction for focus action: h=left, j=down, k=up, l=right",
      },
    },
    required = { "action" },
  },

  run = function(args)
    if args.action == "list" then
      -- Return list of all windows with their properties
      local windows = vim.api.nvim_list_wins()
      local result = {}

      for _, w in ipairs(windows) do
        local bufnr = vim.api.nvim_win_get_buf(w)
        local width = vim.api.nvim_win_get_width(w)
        local height = vim.api.nvim_win_get_height(w)

        table.insert(result, {
          winnr = w,
          bufnr = bufnr,
          width = width,
          height = height,
        })
      end

      return { success = true, windows = result }

    elseif args.action == "focus" then
      -- Focus a specific window or navigate by direction
      if args.direction then
        -- Navigate using wincmd
        local valid_directions = { h = true, j = true, k = true, l = true }
        if not valid_directions[args.direction] then
          return { success = false, error = "Invalid direction. Use: h, j, k, or l" }
        end
        vim.cmd("wincmd " .. args.direction)
        return { success = true, direction = args.direction }
      elseif args.winnr then
        -- Focus specific window by number
        local winnr = args.winnr
        if not vim.api.nvim_win_is_valid(winnr) then
          return { success = false, error = "Invalid window number" }
        end
        vim.api.nvim_set_current_win(winnr)
        return { success = true, winnr = winnr }
      else
        return { success = false, error = "Must specify winnr or direction for focus action" }
      end

    elseif args.action == "split" then
      -- Create horizontal split
      vim.cmd("split")
      local new_winnr = vim.api.nvim_get_current_win()
      return { success = true, winnr = new_winnr }

    elseif args.action == "vsplit" then
      -- Create vertical split
      vim.cmd("vsplit")
      local new_winnr = vim.api.nvim_get_current_win()
      return { success = true, winnr = new_winnr }

    elseif args.action == "close" then
      -- Close a window
      local winnr = args.winnr or 0
      if winnr == 0 then
        winnr = vim.api.nvim_get_current_win()
      end

      if not vim.api.nvim_win_is_valid(winnr) then
        return { success = false, error = "Invalid window number" }
      end

      vim.api.nvim_win_close(winnr, false)
      return { success = true, winnr = winnr }

    elseif args.action == "only" then
      -- Keep only the current window
      vim.cmd("only")
      local current_winnr = vim.api.nvim_get_current_win()
      return { success = true, winnr = current_winnr }

    else
      return { success = false, error = "Unknown action: " .. tostring(args.action) }
    end
  end,
}
