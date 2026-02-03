-- Search for Neovim plugins on Dotfyle with snacks.picker UI
local M = {}

-- Cache for debouncing API calls
local cache = {
  last_query = nil,
  last_results = nil,
  pending_query = nil,
  timer = nil,
}

local DEBOUNCE_MS = 250 -- Wait 250ms after typing stops

-- Install a plugin by creating a lazy.nvim spec file
local function install_plugin(item)
  local plugins_dir = vim.fn.stdpath("config") .. "/lua/plugins"
  local filename = item.owner .. "-" .. item.repo .. ".lua"
  local filepath = plugins_dir .. "/" .. filename

  -- Check if already installed
  if vim.fn.filereadable(filepath) == 1 then
    vim.notify("Plugin already installed: " .. item.text, vim.log.levels.WARN)
    return false
  end

  -- Create spec content
  local spec = string.format([[-- Installed via Dotfyle search
return {
  "%s/%s",
}
]], item.owner, item.repo)

  -- Write the file
  local file = io.open(filepath, "w")
  if not file then
    vim.notify("Failed to create plugin file: " .. filepath, vim.log.levels.ERROR)
    return false
  end
  file:write(spec)
  file:close()

  vim.notify("Installed " .. item.text .. " - run :Lazy sync to activate", vim.log.levels.INFO)
  return true
end

-- Fetch plugins from Dotfyle using tRPC API (async version)
local function fetch_plugins_async(query, callback)
  query = query or ""

  -- Build tRPC API URL with search query
  local input = vim.json.encode({
    ["0"] = {
      query = query,
      sorting = "trending",
      categories = {},
      page = 1,
    }
  })
  local url = "https://dotfyle.com/trpc/searchPlugins,listPluginCategories?batch=1&input=" .. vim.uri_encode(input)

  vim.system({
    "curl", "-s", url,
    "-H", "content-type: application/json",
  }, { text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        callback(nil, "Failed to fetch from Dotfyle")
        return
      end

      local ok, response = pcall(vim.json.decode, result.stdout)
      if not ok or not response or not response[1] then
        callback(nil, "Failed to parse Dotfyle response")
        return
      end

      local data = response[1].result and response[1].result.data and response[1].result.data.data
      if not data then
        callback(nil, "No data in Dotfyle response")
        return
      end
      local plugins = {}
      for _, p in ipairs(data) do
        table.insert(plugins, {
          owner = p.owner,
          repo = p.name,
          text = p.owner .. "/" .. p.name,
          url = "https://github.com/" .. p.owner .. "/" .. p.name,
          stars = p.stars,
          description = p.shortDescription or p.description or "",
          category = p.category,
        })
      end
      callback(plugins)
    end)
  end)
end

-- Fetch plugins from Dotfyle using tRPC API (sync version for MCP)
local function fetch_plugins(query)
  query = query or ""

  -- Build tRPC API URL with search query
  local input = vim.json.encode({
    ["0"] = {
      query = query,
      sorting = "trending",
      categories = {},
      page = 1,
    }
  })
  local url = "https://dotfyle.com/trpc/searchPlugins,listPluginCategories?batch=1&input=" .. vim.uri_encode(input)

  local result = vim.system({
    "curl", "-s", url,
    "-H", "content-type: application/json",
  }, { text = true }):wait()

  if result.code ~= 0 then
    return nil, "Failed to fetch from Dotfyle"
  end

  local ok, response = pcall(vim.json.decode, result.stdout)
  if not ok or not response or not response[1] then
    return nil, "Failed to parse Dotfyle response"
  end

  local data = response[1].result and response[1].result.data and response[1].result.data.data
  if not data then
    return nil, "No data in Dotfyle response"
  end
  local plugins = {}
  for _, p in ipairs(data) do
    table.insert(plugins, {
      owner = p.owner,
      repo = p.name,
      text = p.owner .. "/" .. p.name,
      url = "https://github.com/" .. p.owner .. "/" .. p.name,
      stars = p.stars,
      description = p.shortDescription or p.description or "",
      category = p.category,
    })
  end
  return plugins
end
local function open_picker()
  local ok, Snacks = pcall(require, "snacks")
  if not ok or not Snacks.picker then
    vim.notify("Dotfyle search requires snacks.nvim with picker", vim.log.levels.WARN)
    return
  end

  -- Reset cache when opening picker
  cache.last_query = ""
  cache.last_results = {}
  -- Fetch initial trending results asynchronously (don't block UI)
  vim.system({
    "curl", "-s",
    "https://dotfyle.com/trpc/searchPlugins,listPluginCategories?batch=1&input=" .. vim.uri_encode(vim.json.encode({
      ["0"] = { query = "", sorting = "trending", categories = {}, page = 1 }
    })),
    "-H", "content-type: application/json",
  }, { text = true }, function(result)
    if result.code ~= 0 then return end
    local ok, response = pcall(vim.json.decode, result.stdout)
    if not ok or not response or not response[1] then return end
    local data = response[1].result and response[1].result.data and response[1].result.data.data
    if not data then return end
    local plugins = {}
    for _, p in ipairs(data) do
      table.insert(plugins, {
        owner = p.owner,
        repo = p.name,
        text = p.owner .. "/" .. p.name,
        url = "https://github.com/" .. p.owner .. "/" .. p.name,
        stars = p.stars,
        description = p.shortDescription or p.description or "",
        category = p.category,
      })
    end
    vim.schedule(function()
      cache.last_results = plugins
      cache.last_query = ""
    end)
  end)
  Snacks.picker.pick({
    live = true,
    finder = function(opts, ctx)
      local pattern = ctx.filter.search or ""

      -- Return cached results immediately if query matches
      if pattern == cache.last_query and cache.last_results then
        return cache.last_results
      end

      -- Cancel pending timer
      if cache.timer then
        cache.timer:stop()
        cache.timer:close()
        cache.timer = nil
      end

      -- Schedule debounced fetch
      cache.pending_query = pattern
      cache.timer = vim.uv.new_timer()
      cache.timer:start(DEBOUNCE_MS, 0, vim.schedule_wrap(function()
        cache.timer = nil
        if cache.pending_query ~= cache.last_query then
          local query_to_fetch = cache.pending_query
          fetch_plugins_async(query_to_fetch, function(plugins, err)
            if plugins and query_to_fetch == cache.pending_query then
              cache.last_query = query_to_fetch
              cache.last_results = plugins
              -- Refresh picker
              if ctx.picker and ctx.picker.find then
                ctx.picker:find({ refresh = true })
              end
            end
          end)
        end
      end))

      -- Return cached results while waiting
      return cache.last_results or {}
    end,
    format = function(item)
      return {
        { item.owner .. "/", "Comment" },
        { item.repo,         "Function" },
      }
    end,
    preview = function(ctx)
      local item = ctx.item
      local lines = {
        "# " .. item.text,
        "",
        item.description ~= "" and item.description or "(no description)",
        "",
        "⭐ " .. (item.stars or 0) .. " stars",
        "📁 " .. (item.category or "unknown"),
        "",
        "GitHub: " .. item.url,
        "Dotfyle: https://dotfyle.com/plugins/" .. item.owner .. "/" .. item.repo,
      }
      ctx.preview:set_lines(lines)
    end,
    confirm = function(picker, item)
      picker:close()
      if item then
        vim.ui.select({ "Install plugin", "Open GitHub" }, {
          prompt = item.text,
        }, function(choice)
          if choice == "Install plugin" then
            install_plugin(item)
          elseif choice == "Open GitHub" then
            vim.ui.open(item.url)
          end
        end)
      end
    end,
    win = {
      preview = {
        wo = { wrap = true },
      },
    },
  })
end

function M.search(query)
  query = query or ""

  -- If no query: open interactive picker
  if query == "" then
    vim.schedule(open_picker)
    return "Opened Dotfyle picker"
  end

  -- Fetch results
  local plugins, err = fetch_plugins(query)
  if not plugins then
    return "Error: " .. (err or "Unknown error")
  end

  if #plugins == 0 then
    return "No plugins found matching '" .. query .. "'"
  end

  local lines = { "Found " .. #plugins .. " plugins:" }
  for i, p in ipairs(plugins) do
    if i > 20 then
      table.insert(lines, "... and " .. (#plugins - 20) .. " more")
      break
    end
    table.insert(lines, "- " .. p.text .. " (" .. p.url .. ")")
  end

  return table.concat(lines, "\n")
end

M.open_picker = open_picker

return M
