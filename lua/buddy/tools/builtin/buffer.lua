return {
  name = "buffer",
  title = "Buffer Manager",
  description = "Read and list Neovim buffers (includes unsaved changes, unlike file read)",
  annotations = {
    readOnlyHint = true,
  },
  input_schema = {
    type = "object",
    properties = {
      action = {
        type = "string",
        enum = { "list", "get_content", "get_info" },
        description = "list: all loaded buffers, get_content: buffer text, get_info: buffer metadata",
      },
      bufnr = {
        type = "number",
        description = "Buffer number. Optional - defaults to current buffer if omitted.",
      },
      offset = {
        type = "number",
        description = "Line number to start reading from (0-based). For get_content action.",
      },
      limit = {
        type = "number",
        description = "Number of lines to read (defaults to 2000). For get_content action.",
      },
    },
    required = { "action" },
  },

  run = function(args)
    local bufnr = args.bufnr or 0
    if bufnr == 0 then bufnr = vim.api.nvim_get_current_buf() end

    -- Constants matching opencode's read tool
    local DEFAULT_LIMIT = 2000
    local MAX_LINE_LENGTH = 2000

    if args.action == "list" then
      -- Return list of loaded buffers with name, modified, filetype
      local buffers = vim.api.nvim_list_bufs()
      local result = {}

      -- Get ignored filetypes from config
      local config = require("buddy.config").get()
      local ignored = config.buffer and config.buffer.ignored_filetypes or {}
      local ignored_set = {}
      for _, ft in ipairs(ignored) do
        ignored_set[ft] = true
      end

      for _, b in ipairs(buffers) do
        local name = vim.api.nvim_buf_get_name(b)
        local modified = vim.bo[b].modified
        local filetype = vim.bo[b].filetype
        local loaded = vim.api.nvim_buf_is_loaded(b)

        -- Only include loaded buffers with a filetype (or terminals), skip ignored filetypes
        local is_terminal = name:match("^term://") ~= nil
        if loaded and (is_terminal or filetype ~= "") and not ignored_set[filetype] then
          table.insert(result, {
            bufnr = b,
            name = name or "",
            modified = modified,
            filetype = filetype or "",
          })
        end
      end

      return { success = true, buffers = result }

    elseif args.action == "get_content" then
      -- Return buffer content with line numbers and diagnostics
      -- Matches opencode read tool formatting
      if not vim.api.nvim_buf_is_valid(bufnr) then
        return { success = false, error = "Invalid buffer number" }
      end

      local total_lines = vim.api.nvim_buf_line_count(bufnr)
      local offset = args.offset or 0
      local limit = args.limit or DEFAULT_LIMIT
      local end_line = math.min(offset + limit, total_lines)

      local lines = vim.api.nvim_buf_get_lines(bufnr, offset, end_line, false)

      -- Format with 5-digit padded line numbers (matching opencode read)
      local numbered_lines = {}
      for i, line in ipairs(lines) do
        local line_num = offset + i
        -- Truncate long lines
        if #line > MAX_LINE_LENGTH then
          line = line:sub(1, MAX_LINE_LENGTH) .. "..."
        end
        table.insert(numbered_lines, string.format("%05d| %s", line_num, line))
      end
      local content = table.concat(numbered_lines, "\n")

      -- Get diagnostics for this buffer
      local raw_diags = vim.diagnostic.get(bufnr)
      local severity_names = {
        [vim.diagnostic.severity.ERROR] = "error",
        [vim.diagnostic.severity.WARN] = "warning",
        [vim.diagnostic.severity.INFO] = "info",
        [vim.diagnostic.severity.HINT] = "hint",
      }
      local diagnostics = {}
      local counts = { error = 0, warning = 0, info = 0, hint = 0 }
      for _, d in ipairs(raw_diags) do
        local sev = severity_names[d.severity] or "unknown"
        counts[sev] = (counts[sev] or 0) + 1
        table.insert(diagnostics, {
          line = d.lnum + 1,
          col = d.col + 1,
          severity = sev,
          message = d.message,
          source = d.source or "unknown",
        })
      end
      table.sort(diagnostics, function(a, b) return a.line < b.line end)

      -- Get attached LSP clients
      local clients = vim.lsp.get_clients({ bufnr = bufnr })
      local lsp_clients = {}
      for _, client in ipairs(clients) do
        table.insert(lsp_clients, {
          name = client.name,
          id = client.id,
        })
      end

      return {
        success = true,
        bufnr = bufnr,
        name = vim.api.nvim_buf_get_name(bufnr),
        content = content,
        line_count = total_lines,
        offset = offset,
        limit = limit,
        showing = #lines,
        has_more = end_line < total_lines,
        lsp_clients = #lsp_clients > 0 and lsp_clients or nil,
        diagnostics = #diagnostics > 0 and diagnostics or nil,
        diagnostic_counts = (counts.error > 0 or counts.warning > 0) and counts or nil,
      }

    elseif args.action == "get_info" then
      -- Return buffer name, filetype, modified, line count
      if not vim.api.nvim_buf_is_valid(bufnr) then
        return { success = false, error = "Invalid buffer number" }
      end

      local name = vim.api.nvim_buf_get_name(bufnr)
      local modified = vim.bo[bufnr].modified
      local filetype = vim.bo[bufnr].filetype
      local lines = vim.api.nvim_buf_line_count(bufnr)

      return {
        success = true,
        bufnr = bufnr,
        name = name,
        filetype = filetype or "",
        modified = modified,
        line_count = lines,
      }

    else
      return { success = false, error = "Unknown action: " .. tostring(args.action) }
    end
  end,
}
