return {
  name = "tab",
  title = "Tab Manager",
  description = "Manage Neovim tabs",
  annotations = {
    readOnlyHint = false,
  },
  input_schema = {
    type = "object",
    properties = {
      action = {
        type = "string",
        enum = { "list", "new", "close", "next", "prev", "goto", "first", "last" },
        description = "list: all tabs, new: create new tab, close: close current tab, next/prev: navigate tabs, goto: jump to specific tab, first/last: jump to first/last tab",
      },
      tabnr = {
        type = "number",
        description = "Tab number for goto action.",
      },
      file = {
        type = "string",
        description = "File path for new tab. Optional.",
      },
    },
    required = { "action" },
  },

  run = function(args)
    if args.action == "list" then
      local tabs = vim.api.nvim_list_tabpages()
      local result = {}

      for _, tab in ipairs(tabs) do
        local windows = vim.api.nvim_tabpage_list_wins(tab)
        local buffers = {}

        for _, win in ipairs(windows) do
          local buf = vim.api.nvim_win_get_buf(win)
          local name = vim.api.nvim_buf_get_name(buf)
          table.insert(buffers, name or "")
        end

        table.insert(result, {
          tabnr = tab,
          buffers = buffers,
        })
      end

      return { success = true, tabs = result }

    elseif args.action == "new" then
      vim.cmd("tabnew " .. (args.file or ""))
      return { success = true }

    elseif args.action == "close" then
      vim.cmd("tabclose")
      return { success = true }

    elseif args.action == "next" then
      vim.cmd("tabnext")
      return { success = true }

    elseif args.action == "prev" then
      vim.cmd("tabprev")
      return { success = true }

    elseif args.action == "goto" then
      if not args.tabnr then
        return { success = false, error = "tabnr required for goto action" }
      end
      vim.cmd("tabn " .. args.tabnr)
      return { success = true, tabnr = args.tabnr }

    elseif args.action == "first" then
      vim.cmd("tabfirst")
      return { success = true }

    elseif args.action == "last" then
      vim.cmd("tablast")
      return { success = true }

    else
      return { success = false, error = "Unknown action: " .. tostring(args.action) }
    end
  end,
}
