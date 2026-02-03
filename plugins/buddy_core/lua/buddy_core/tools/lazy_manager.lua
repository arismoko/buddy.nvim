-- Lazy.nvim config file browser with Snacks.picker UI
local M = {}

-- Get all plugin config files
local function get_config_files()
  local plugins_dir = vim.fn.stdpath("config") .. "/lua/plugins"
  local files = vim.fn.glob(plugins_dir .. "/*.lua", false, true)
  local items = {}

  for _, file in ipairs(files) do
    local filename = vim.fn.fnamemodify(file, ":t")
    local name = filename:gsub("%.lua$", "")
    
    -- Skip theme files
    if not name:lower():find("theme") then
      table.insert(items, {
        text = name,
        name = name,
        file = file,
        filename = filename,
      })
    end
  end

  -- Sort by name
  table.sort(items, function(a, b)
    return a.name:lower() < b.name:lower()
  end)

  return items
end

-- Open the lazy manager picker
local function open_picker()
  local ok, Snacks = pcall(require, "snacks")
  if not ok or not Snacks.picker then
    vim.notify("Lazy Manager requires snacks.nvim with picker", vim.log.levels.WARN)
    return
  end

  local files = get_config_files()

  Snacks.picker.pick({
    source = "Plugin Configs",
    items = files,
    format = function(item)
      return {
        { " ", "Directory" },
        { item.name, "Function" },
        { ".lua", "Comment" },
      }
    end,
    preview = function(ctx)
      local item = ctx.item
      if item and item.file then
        ctx.item.file = item.file
        Snacks.picker.preview.file(ctx)
      end
    end,
    confirm = function(picker, item)
      picker:close()
      if item and item.file then
        vim.cmd("edit " .. vim.fn.fnameescape(item.file))
      end
    end,
    actions = {
      dotfyle = function(picker)
        picker:close()
        local dotfyle_ok, dotfyle = pcall(require, "buddy_core.tools.dotfyle")
        if dotfyle_ok and dotfyle.open_picker then
          dotfyle.open_picker()
          vim.schedule(function()
            vim.cmd("startinsert")
          end)
        else
          vim.notify("Dotfyle tool not available", vim.log.levels.WARN)
        end
      end,
      new_file = function(picker)
        picker:close()
        local plugins_dir = vim.fn.stdpath("config") .. "/lua/plugins"
        vim.ui.input({ prompt = "New plugin file: ", default = plugins_dir .. "/" }, function(input)
          if input and input ~= "" then
            vim.cmd("edit " .. vim.fn.fnameescape(input))
          end
        end)
      end,
      buddy_manager = function(picker)
        picker:close()
        local ok, bm = pcall(require, "buddy_core.tools.buddy_manager")
        if ok and bm.open_picker then
          bm.open_picker()
        end
      end,
    },
    win = {
      preview = {
        wo = { wrap = true },
      },
      input = {
        keys = {
          ["<C-a>"] = { "dotfyle", desc = "Dotfyle", mode = { "i", "n" } },
          ["<C-n>"] = { "new_file", desc = "New File", mode = { "i", "n" } },
          ["<C-b>"] = { "buddy_manager", desc = "Buddy Manager", mode = { "i", "n" } },
          ["?"] = { "toggle_help_input", desc = "Help" },
        },
        footer_keys = { "<C-a>", "<C-n>", "<C-b>", "?" },
      },
    },
  })
end

function M.list_configs(query)
  query = query or ""

  if query == "" then
    vim.schedule(open_picker)
    return "Opened Plugin Configs picker"
  end

  local files = get_config_files()
  local pattern = query:lower()
  local filtered = {}
  for _, f in ipairs(files) do
    if f.name:lower():find(pattern, 1, true) then
      table.insert(filtered, f)
    end
  end

  if #filtered == 0 then
    return "No config files found matching '" .. query .. "'"
  end

  local lines = { "Found " .. #filtered .. " config files:" }
  for _, f in ipairs(filtered) do
    table.insert(lines, "- " .. f.filename .. " (" .. f.file .. ")")
  end

  return table.concat(lines, "\n")
end

M.open_picker = open_picker

return M
