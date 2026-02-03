return {
  name = "diagnostics",
  title = "LSP Diagnostics",
  description = "Get LSP diagnostics from Neovim",
  annotations = {
    readOnlyHint = true,
  },
  input_schema = {
    type = "object",
    properties = {
      bufnr = {
        type = "number",
        description = "Buffer number. Optional - omit for all buffers, 0 for current buffer.",
      },
      severity = {
        type = "string",
        enum = { "error", "warning", "info", "hint", "all" },
        description = "Filter by severity level. Defaults to 'all'.",
      },
      path = {
        type = "string",
        description = "Filter diagnostics to files matching this path pattern.",
      },
      scan_dir = {
        type = "string",
        description = "Directory to scan for files. Opens matching files to trigger LSP diagnostics.",
      },
      pattern = {
        type = "string",
        description = "Glob pattern for scan_dir (default: '**/*.lua').",
      },
    },
  },

  run = function(args)
    local severity_map = {
      error = vim.diagnostic.severity.ERROR,
      warning = vim.diagnostic.severity.WARN,
      info = vim.diagnostic.severity.INFO,
      hint = vim.diagnostic.severity.HINT,
    }

    local severity_names = {
      [vim.diagnostic.severity.ERROR] = "error",
      [vim.diagnostic.severity.WARN] = "warning",
      [vim.diagnostic.severity.INFO] = "info",
      [vim.diagnostic.severity.HINT] = "hint",
    }

    local scanned_bufs = {}
    local pending = {}

    if args.scan_dir then
      local pattern = args.pattern or "**/*.lua"
      local full_pattern = args.scan_dir .. "/" .. pattern
      local files = vim.fn.glob(full_pattern, false, true)

      -- Track when buffers receive diagnostics
      local diag_autocmd = vim.api.nvim_create_autocmd("DiagnosticChanged", {
        callback = function(ev)
          if pending[ev.buf] then
            pending[ev.buf] = true
          end
        end,
      })

      -- Load files properly to trigger LSP
      for _, file in ipairs(files) do
        local existing = vim.fn.bufnr(file)
        local bufnr
        if existing == -1 then
          bufnr = vim.fn.bufadd(file)
          vim.fn.bufload(bufnr)
          vim.bo[bufnr].bufhidden = "wipe"
          vim.bo[bufnr].swapfile = false
        else
          -- Reload existing buffer from disk
          bufnr = existing
          vim.api.nvim_buf_call(bufnr, function()
            vim.cmd("edit!")
          end)
        end
        local ft = vim.filetype.match({ filename = file })
        if ft then
          vim.bo[bufnr].filetype = ft
        end
        pending[bufnr] = false
        table.insert(scanned_bufs, bufnr)
      end

      -- Wait for diagnostics (event-driven with timeout)
      if #scanned_bufs > 0 then
        vim.wait(10000, function()
          for _, is_done in pairs(pending) do
            if not is_done then
              return false
            end
          end
          return true
        end, 50)
      end

      vim.api.nvim_del_autocmd(diag_autocmd)
    end

    -- Get diagnostics
    local bufnr = args.bufnr
    if bufnr == 0 then
      bufnr = vim.api.nvim_get_current_buf()
    end

    local opts = {}
    if args.severity and args.severity ~= "all" then
      opts.severity = severity_map[args.severity]
    end

    local raw_diags = vim.diagnostic.get(bufnr, opts)

    -- Format diagnostics grouped by file
    local by_file = {}
    for _, d in ipairs(raw_diags) do
      local buf_name = vim.api.nvim_buf_get_name(d.bufnr)
      if not args.path or buf_name:match(args.path) then
        by_file[buf_name] = by_file[buf_name] or {}
        table.insert(by_file[buf_name], {
          line = d.lnum + 1,
          col = d.col + 1,
          severity = severity_names[d.severity] or "unknown",
          message = d.message,
          source = d.source or "unknown",
          code = d.code,
        })
      end
    end

    -- Convert to sorted array
    local results = {}
    for file, diags in pairs(by_file) do
      table.sort(diags, function(a, b) return a.line < b.line end)
      table.insert(results, { file = file, diagnostics = diags, count = #diags })
    end
    table.sort(results, function(a, b) return a.file < b.file end)

    -- Summary counts
    local counts = { error = 0, warning = 0, info = 0, hint = 0 }
    for _, r in ipairs(results) do
      for _, d in ipairs(r.diagnostics) do
        counts[d.severity] = (counts[d.severity] or 0) + 1
      end
    end

    return {
      success = true,
      total = #raw_diags,
      counts = counts,
      files = results,
      scanned = #scanned_bufs > 0 and #scanned_bufs or nil,
    }
  end,
}
