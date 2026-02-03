return {
  name = "status",
  title = "Neovim Status",
  description = "Get comprehensive Neovim status including cursor position, mode, marks, and registers",
  annotations = {
    readOnlyHint = true,
  },
  output_schema = {
    type = "object",
    properties = {
      mode = { type = "string", description = "Current Vim mode" },
      file = { type = "string", description = "Current file path" },
      cursor = {
        type = "object",
        properties = {
          line = { type = "number" },
          col = { type = "number" },
        },
      },
      modified = { type = "boolean", description = "Buffer has unsaved changes" },
    },
  },
  input_schema = {
    type = "object",
    properties = {},
  },

  run = function(_args)
    -- Get basic info
    local mode = vim.api.nvim_get_mode().mode
    local cursor = vim.api.nvim_win_get_cursor(0)
    local bufnr = vim.api.nvim_get_current_buf()
    local filename = vim.api.nvim_buf_get_name(bufnr)
    local cwd = vim.fn.getcwd()

    -- Get current tab
    local current_tab = vim.fn.tabpagenr()

    -- Get window layout
    local layout = vim.fn.winlayout()

    -- Get marks (a-z) - only include set marks (same as TS)
    local marks = {}
    for i = string.byte("a"), string.byte("z") do
      local mark = string.char(i)
      local pos = vim.fn.getpos("'" .. mark)
      -- Only include marks that are actually set (not at position 0,0)
      if pos[2] > 0 and pos[3] > 0 then
        marks[mark] = { pos[2], pos[3] }
      end
    end

    -- Get registers (a-z, ", 0-9) - only include non-empty registers (same as TS)
    local registers = {}
    -- Named registers a-z
    for i = string.byte("a"), string.byte("z") do
      local reg = string.char(i)
      local content = vim.fn.getreg(reg)
      if content and content ~= "" then
        registers[reg] = content
      end
    end
    -- Unnamed register
    local unnamed = vim.fn.getreg('"')
    if unnamed and unnamed ~= "" then
      registers['"'] = unnamed
    end
    -- Numbered registers 0-9
    for i = 0, 9 do
      local content = vim.fn.getreg(tostring(i))
      if content and content ~= "" then
        registers[tostring(i)] = content
      end
    end

    -- Get visual selection info (same as TS)
    local visual_info = {
      hasActiveSelection = false,
    }

    local is_visual = mode:find("v") or mode:find("V") or mode == "\22" -- Ctrl-V
    if is_visual then
      visual_info.hasActiveSelection = true
      visual_info.visualModeType = vim.fn.visualmode()

      local start_pos = vim.fn.getpos("v")
      local end_pos = vim.fn.getpos(".")
      visual_info.startPos = { start_pos[2], start_pos[3] }
      visual_info.endPos = { end_pos[2], end_pos[3] }
    else
      -- Get last visual selection marks
      local last_start = vim.fn.getpos("'<")
      local last_end = vim.fn.getpos("'>")
      if last_start[2] > 0 then
        visual_info.lastVisualStart = { last_start[2], last_start[3] }
        visual_info.lastVisualEnd = { last_end[2], last_end[3] }
      end
    end

    -- Get LSP info (same as TS)
    local lsp_info = "No active LSP clients"
    local clients = vim.lsp.get_clients({ bufnr = bufnr })
    if #clients > 0 then
      local names = {}
      for _, client in ipairs(clients) do
        table.insert(names, client.name)
      end
      lsp_info = "Active LSP clients: " .. table.concat(names, ", ")
    end

    -- Get plugin info (same as TS)
    local plugins = {}
    if vim.fn.exists(":LspInfo") > 0 then
      table.insert(plugins, "LSP")
    end
    if vim.fn.exists(":Telescope") > 0 then
      table.insert(plugins, "Telescope")
    end
    if vim.g.loaded_nvim_treesitter then
      table.insert(plugins, "TreeSitter")
    end
    local plugin_info = #plugins > 0 and ("Detected plugins: " .. table.concat(plugins, ", "))
      or "No common plugins detected"

    return {
      success = true,
      cursorPosition = { cursor[1], cursor[2] },
      mode = mode,
      fileName = filename,
      windowLayout = layout,
      currentTab = current_tab,
      marks = marks,
      registers = registers,
      cwd = cwd,
      lspInfo = lsp_info,
      pluginInfo = plugin_info,
      visualInfo = visual_info,
    }
  end,
}
