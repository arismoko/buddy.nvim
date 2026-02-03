local M = {}

--- List all available resources (buffers)
---@return table[] List of resource descriptors
function M.list()
  local result = {}
  
  -- List loaded buffers with files
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      local name = vim.api.nvim_buf_get_name(bufnr)
      if name and name ~= "" then
        table.insert(result, {
          uri = "vim://buffer/" .. bufnr,
          name = vim.fn.fnamemodify(name, ":t"),
          description = name,
          mimeType = "text/plain",
        })
      end
    end
  end
  
  return result
end

--- List resource templates
---@return table[] List of resource templates
function M.list_templates()
  return {
    {
      uriTemplate = "vim://buffer/{bufnr}",
      name = "Buffer by number",
      description = "Access a Neovim buffer by its buffer number",
      mimeType = "text/plain",
    },
    {
      uriTemplate = "vim://file/{path}",
      name = "File by path",
      description = "Access a file by its filesystem path",
      mimeType = "text/plain",
    },
  }
end

--- Read a resource by URI
---@param uri string Resource URI (e.g., "vim://buffer/1")
---@return table[]|nil Content array or nil if not found
function M.read(uri)
  -- Parse vim://buffer/{bufnr}
  local bufnr_str = uri:match("^vim://buffer/(%d+)$")
  if bufnr_str then
    local bufnr = tonumber(bufnr_str) --[[@as integer]]
    if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      return {
        {
          uri = uri,
          mimeType = "text/plain",
          text = table.concat(lines, "\n"),
        },
      }
    end
  end

  -- Parse vim://file/{path}
  local path = uri:match("^vim://file/(.+)$")
  if path then
    local ok, lines = pcall(vim.fn.readfile, path)
    if ok then
      return {
        {
          uri = uri,
          mimeType = "text/plain",
          text = table.concat(lines, "\n"),
        },
      }
    end
  end
  
  return nil
end

return M
