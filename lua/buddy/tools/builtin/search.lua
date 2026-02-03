return {
  name = "search",
  title = "Search & Replace",
  description = "Search and replace in current buffer",
  annotations = {
    destructiveHint = true,
  },
  input_schema = {
    type = "object",
    properties = {
      action = {
        type = "string",
        enum = { "find", "find_replace" },
        description = "find: search for pattern, find_replace: search and replace",
      },
      pattern = {
        type = "string",
        description = "Search pattern",
      },
      replacement = {
        type = "string",
        description = "Replacement text (for find_replace)",
      },
      ignore_case = {
        type = "boolean",
        description = "Case insensitive search",
      },
      whole_word = {
        type = "boolean",
        description = "Match whole words only",
      },
      global = {
        type = "boolean",
        description = "Replace all occurrences (for find_replace)",
      },
    },
    required = { "action", "pattern" },
  },

  run = function(args)
    local action = args.action
    local pattern = args.pattern or ""

    if pattern == "" then
      return { success = false, error = "Pattern cannot be empty" }
    end

    if action == "find" then
      -- Build search pattern (same as TS: \<pattern\> for wholeWord)
      local search_pattern = pattern
      if args.whole_word then
        search_pattern = "\\<" .. pattern .. "\\>"
      end

      -- Set case sensitivity (same as TS)
      local old_ignorecase = vim.o.ignorecase
      vim.o.ignorecase = args.ignore_case or false

      local count = 0
      local save_view = vim.fn.winsaveview()

      -- Set the search register and use searchcount
      -- This is more reliable than passing pattern directly
      vim.fn.setreg("/", search_pattern)
      local searchcount_result = vim.fn.searchcount({ maxcount = 1000 })
      count = searchcount_result.total or 0

      -- Restore position
      vim.fn.winrestview(save_view)

      vim.o.ignorecase = old_ignorecase

      if count == 0 then
        return { success = true, pattern = pattern, total = 0, message = "No matches found" }
      end

      return {
        success = true,
        pattern = pattern,
        total = count,
        incomplete = false,
      }

    elseif action == "find_replace" then
      if not args.replacement then
        return { success = false, error = "Replacement required for find_replace" }
      end

      -- Build flags (same as TS)
      local flags = ""
      if args.global then flags = flags .. "g" end
      if args.ignore_case then flags = flags .. "i" end

      -- Escape pattern and replacement (same as TS)
      local escaped_pattern = pattern:gsub("/", "\\/")
      local escaped_replacement = args.replacement:gsub("/", "\\/")

      local cmd = string.format("%%s/%s/%s/%s", escaped_pattern, escaped_replacement, flags)

      local ok, result = pcall(vim.fn.execute, cmd)

      if not ok then
        if tostring(result):find("Pattern not found") then
          return { success = true, pattern = pattern, message = "No matches found" }
        end
        return { success = false, error = tostring(result) }
      end

      return {
        success = true,
        pattern = pattern,
        replacement = args.replacement,
        message = result and vim.trim(result) or "Search and replace completed",
      }

    else
      return { success = false, error = "Unknown action: " .. tostring(action) }
    end
  end,
}
