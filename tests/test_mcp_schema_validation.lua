-- Test that MCP responses conform to JSON-RPC/MCP schema expectations
-- This catches issues like empty Lua tables becoming arrays instead of objects

local T = MiniTest.new_set()

-- Load builtin tools before testing
local registry = require("buddy.tools")
registry.load_builtins()

local methods = require("buddy.mcp.methods")

T["tools/list"] = MiniTest.new_set()

T["tools/list"]["returns tools array"] = function()
  local result = methods["tools/list"]("test", {})
  MiniTest.expect.equality(type(result.tools), "table")
  MiniTest.expect.equality(#result.tools > 0, true)
end

T["tools/list"]["each tool has required fields"] = function()
  local result = methods["tools/list"]("test", {})
  for i, tool in ipairs(result.tools) do
    MiniTest.expect.equality(type(tool.name), "string")
    MiniTest.expect.equality(type(tool.description), "string")
    MiniTest.expect.equality(type(tool.inputSchema), "table")
  end
end

T["tools/list"]["inputSchema.properties serializes as object not array"] = function()
  -- This is the bug we fixed: empty Lua tables serialize to [] not {}
  local result = methods["tools/list"]("test", {})
  for _, tool in ipairs(result.tools) do
    if tool.inputSchema.properties then
      local json = vim.json.encode(tool.inputSchema)
      -- Should contain "properties":{} or "properties":{"key":...}, never "properties":[]
      local has_array_properties = json:match('"properties":%[') ~= nil
      MiniTest.expect.equality(has_array_properties, false)
    end
  end
end

T["tools/list"]["required field serializes as array"] = function()
  -- Ensure required is always an array (even when empty)
  local result = methods["tools/list"]("test", {})
  for _, tool in ipairs(result.tools) do
    if tool.inputSchema.required then
      local json = vim.json.encode(tool.inputSchema)
      -- Should contain "required":[] or "required":["field",...], never "required":{}
      local has_object_required = json:match('"required":{') ~= nil
      MiniTest.expect.equality(has_object_required, false)
    end
  end
end

return T
