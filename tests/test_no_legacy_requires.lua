--- Guard test: ensure no production code references deleted legacy modules.
--- Scans all lua/buddy/ files for stale require paths.
local T = MiniTest.new_set()

local legacy_patterns = {
  ["buddy.mcp.methods"]          = "deleted in Wave 5 (replaced by event bus + protocol registry)",
  ["buddy.mcp.client_requests"]  = "deleted in Wave 5 (replaced by buddy.app.client_requests)",
  ["buddy.server.router"]        = "deleted shim (use buddy.transport.router)",
  ["buddy.server.http"]          = "deleted shim (use buddy.transport.http.server)",
}

--- Collect all .lua files under lua/buddy/
local function get_source_files()
  local files = vim.fn.glob("lua/buddy/**/*.lua", false, true)
  -- Also grab top-level files in lua/buddy/
  local top = vim.fn.glob("lua/buddy/*.lua", false, true)
  for _, f in ipairs(top) do
    -- glob("**/*.lua") should include these, but be safe
    if not vim.tbl_contains(files, f) then
      table.insert(files, f)
    end
  end
  return files
end

for pattern, reason in pairs(legacy_patterns) do
  T["no require of " .. pattern] = function()
    local violations = {}
    for _, filepath in ipairs(get_source_files()) do
      local lines = vim.fn.readfile(filepath)
      for lnum, line in ipairs(lines) do
        -- Match both require("...") and require('...')
        if line:find(pattern, 1, true) then
          table.insert(violations, ("%s:%d: %s"):format(filepath, lnum, vim.trim(line)))
        end
      end
    end

    if #violations > 0 then
      error(
        ("Found %d reference(s) to deleted module '%s' (%s):\n  %s"):format(
          #violations,
          pattern,
          reason,
          table.concat(violations, "\n  ")
        )
      )
    end
  end
end

return T
