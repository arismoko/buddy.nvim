return {
  name = "grep",
  title = "Project Search",
  description = "Project-wide search using vimgrep with quickfix list",
  annotations = {
    readOnlyHint = true,
  },
  input_schema = {
    type = "object",
    properties = {
      pattern = {
        type = "string",
        description = "Search pattern to grep for",
      },
      file_pattern = {
        type = "string",
        description = "File pattern to search in (default: **/* for all files)",
      },
      path = {
        type = "string",
        description = "Directory to search in (default: current working directory)",
      },
    },
    required = { "pattern" },
  },

  run = function(args)
    local pattern = args.pattern or ""
    local file_pattern = args.file_pattern or "**/*"
    local search_path = args.path

    -- Validate pattern (same as TS)
    if pattern == "" then
      return { success = false, error = "Grep pattern cannot be empty" }
    end

    -- If path provided, temporarily cd to it
    local old_cwd = nil
    if search_path and search_path ~= "" then
      old_cwd = vim.fn.getcwd()
      local ok = pcall(vim.cmd, "cd " .. vim.fn.fnameescape(search_path))
      if not ok then
        return { success = false, error = "Invalid path: " .. search_path }
      end
    end

    -- Escape forward slashes in pattern to prevent command injection
    local escaped_pattern = pattern:gsub("/", "\\/")

    -- Use vimgrep for internal searching (same as TS)
    local command = string.format("vimgrep /%s/ %s", escaped_pattern, file_pattern)

    local ok, err = pcall(function() vim.cmd(command) end)
    
    -- Restore original cwd if we changed it
    if old_cwd then
      pcall(vim.cmd, "cd " .. vim.fn.fnameescape(old_cwd))
    end
    
    if not ok then
      -- Check if it's a "no match" error
      if tostring(err):find("E480") then
        return {
          success = true,
          pattern = pattern,
          file_pattern = file_pattern,
          matches = {},
          total = 0,
          message = "No matches found for: " .. pattern,
        }
      end
      return { success = false, error = tostring(err) }
    end

    -- Get quickfix list (same as TS)
    local qflist = vim.fn.getqflist()

    if #qflist == 0 then
      return {
        success = true,
        pattern = pattern,
        file_pattern = file_pattern,
        matches = {},
        total = 0,
        message = "No matches found for: " .. pattern,
      }
    end

    -- Format results (same as TS - show first 10)
    local matches = {}
    for i, item in ipairs(qflist) do
      if i <= 10 then
        local filename = vim.fn.bufname(item.bufnr)
        table.insert(matches, {
          filename = filename,
          lnum = item.lnum,
          text = vim.trim(item.text or ""),
        })
      end
    end

    return {
      success = true,
      pattern = pattern,
      file_pattern = file_pattern,
      path = search_path,
      matches = matches,
      total = #qflist,
      showing = math.min(10, #qflist),
    }
  end,
}
