return {
  name = "edit",
  title = "Buffer Editor",
  description = "Edit buffer content (works on unsaved buffers, unlike file edit)",
  annotations = {
    destructiveHint = true,
  },
  input_schema = {
    type = "object",
    properties = {
      action = {
        type = "string",
        enum = { "insert", "replace", "delete", "replace_all", "replace_match" },
        description = "insert: insert lines at position, replace: replace line range, delete: delete line range, replace_all: replace entire buffer, replace_match: find and replace text (recommended)",
      },
      line = {
        type = "number",
        description = "Line number (1-indexed) for insert/replace/delete",
      },
      end_line = {
        type = "number",
        description = "End line for replace/delete range",
      },
      content = {
        type = "string",
        description = "Content to insert/replace (string or array of strings)",
      },
      oldString = {
        type = "string",
        description = "Text to find and replace (for replace_match action)",
      },
      newString = {
        type = "string",
        description = "Replacement text (for replace_match action)",
      },
      replaceAll = {
        type = "boolean",
        description = "Replace all occurrences (for replace_match, default: false)",
      },
    },
    required = { "action" },
  },

  run = function(args)
    local bufnr = 0

    -- Convert content to table if it's a string
    local lines = args.content
    if type(lines) == "string" then
      -- Unescape common escape sequences so callers can pass \n, \t, \r as escape sequences
      local unescaped = args.content:gsub("\\n", "\n"):gsub("\\t", "\t"):gsub("\\r", "\r")
      -- Split string by newline (preserving empty lines)
      lines = vim.split(unescaped, "\n", { plain = true })
    elseif not lines then
      lines = {}
    end

    if args.action == "insert" then
      local success, err = pcall(vim.api.nvim_buf_set_lines, bufnr, args.line - 1, args.line - 1, false, lines)
      if not success then
        return { success = false, error = "Failed to insert: " .. tostring(err) }
      end
      return { success = true, inserted = #lines }

    elseif args.action == "replace" then
      if not args.end_line then
        return { success = false, error = "end_line required for replace" }
      end
      local success, err = pcall(vim.api.nvim_buf_set_lines, bufnr, args.line - 1, args.end_line, false, lines)
      if not success then
        return { success = false, error = "Failed to replace: " .. tostring(err) }
      end
      return { success = true, replaced = args.end_line - args.line + 1, inserted = #lines }

    elseif args.action == "delete" then
      if not args.end_line then
        return { success = false, error = "end_line required for delete" }
      end
      local success, err = pcall(vim.api.nvim_buf_set_lines, bufnr, args.line - 1, args.end_line, false, {})
      if not success then
        return { success = false, error = "Failed to delete: " .. tostring(err) }
      end
      return { success = true, deleted = args.end_line - args.line + 1 }

    elseif args.action == "replace_all" then
      local success, err = pcall(vim.api.nvim_buf_set_lines, bufnr, 0, -1, false, lines)
      if not success then
        return { success = false, error = "Failed to replace all: " .. tostring(err) }
      end
      return { success = true, replaced_all = true, lines = #lines }

    elseif args.action == "replace_match" then
      -- Text-matching replacement (matches opencode edit tool semantics)
      if not args.oldString then
        return { success = false, error = "oldString (text to find) required for replace_match" }
      end
      if args.newString == nil then
        return { success = false, error = "newString (replacement text) required for replace_match" }
      end

      local buf_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local content = table.concat(buf_lines, "\n")

      -- Find the old text
      local start_pos, end_pos = content:find(args.oldString, 1, true) -- plain text search
      if not start_pos then
        return { success = false, error = "oldString not found in buffer" }
      end

      -- Check for multiple matches if not replaceAll
      local replace_all = args.replaceAll or false
      if not replace_all then
        local second_match = content:find(args.oldString, end_pos + 1, true)
        if second_match then
          return {
            success = false,
            error = "oldString found multiple times - provide more context to make it unique, or set replaceAll: true",
          }
        end
      end

      -- Perform replacement
      local new_content
      if not replace_all then
        new_content = content:sub(1, start_pos - 1) .. args.newString .. content:sub(end_pos + 1)
      else
        -- Replace all occurrences
        new_content = content:gsub(vim.pesc(args.oldString), args.newString:gsub("%%", "%%%%"))
      end

      -- Convert back to lines and set buffer
      local new_lines = {}
      for l in new_content:gmatch("([^\n]*)\n?") do
        table.insert(new_lines, l)
      end
      -- Remove trailing empty line if original didn't have one
      if #new_lines > 0 and new_lines[#new_lines] == "" and not content:match("\n$") then
        table.remove(new_lines)
      end

      local success, err = pcall(vim.api.nvim_buf_set_lines, bufnr, 0, -1, false, new_lines)
      if not success then
        return { success = false, error = "Failed to apply replacement: " .. tostring(err) }
      end

      return { success = true, action = "replace_match", replaced = replace_all and "all" or 1 }

    else
      return { success = false, error = "Unknown action: " .. tostring(args.action) }
    end
  end,
}
