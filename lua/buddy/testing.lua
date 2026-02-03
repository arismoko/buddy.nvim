--- Testing utilities for buddy tool authors.
--- Provides helpers to test tools without full Neovim setup.
---@tag buddy-testing
---@toc_entry Testing Utilities
local M = {}

local validate = require("buddy.tools.validate")
local errors = require("buddy.tools.errors")

---@class ToolTestContext
---@field tool table The tool being tested
---@field opts table Tool options
---@field results table[] Collected results from run calls

--- Build a JSON Schema from the new tool format
---@param tool table Tool with args and required fields
---@return table schema JSON Schema compatible format
local function build_schema(tool)
  return {
    type = "object",
    properties = tool.args or {},
    required = tool.required or {},
  }
end

--- Create a test context for a tool
--- Provides isolated testing without registering the tool
---@param tool table Tool definition (must have name, description, and run)
---@param opts table|nil Tool options to pass
---@return ToolTestContext
function M.create_context(tool, opts)
  assert(tool, "Tool is required")
  assert(tool.name, "Tool must have name")
  assert(tool.run, "Tool must have run function")

  return {
    tool = tool,
    opts = opts or {},
    results = {},
  }
end

--- Run a tool with given args and capture result
--- Validates input against schema before running
---@param ctx ToolTestContext
---@param args table Input arguments
---@return boolean success
---@return any result_or_error
function M.run(ctx, args)
  -- Validate against schema
  local schema = build_schema(ctx.tool)
  local valid, err = validate.validate(args, schema)
  if not valid then
    return false, errors.create(errors.codes.INVALID_INPUT, err)
  end

  -- Run the tool
  local ok, result = pcall(ctx.tool.run, args, ctx.opts)
  if ok then
    table.insert(ctx.results, result)
    return true, result
  else
    return false, result
  end
end

--- Assert that args pass schema validation
---@param tool table Tool with args and required fields
---@param args table Arguments to validate
---@return boolean
function M.assert_valid(tool, args)
  local schema = build_schema(tool)
  local valid, err = validate.validate(args, schema)
  if not valid then
    error("Expected args to be valid but got: " .. err)
  end
  return true
end

--- Assert that args fail schema validation
---@param tool table Tool with args and required fields
---@param args table Arguments to validate
---@param expected_pattern string|nil Optional pattern to match in error
---@return boolean
function M.assert_invalid(tool, args, expected_pattern)
  local schema = build_schema(tool)
  local valid, err = validate.validate(args, schema)
  if valid then
    error("Expected args to be invalid but validation passed")
  end
  if expected_pattern and not err:match(expected_pattern) then
    error("Expected error to match '" .. expected_pattern .. "' but got: " .. err)
  end
  return true
end

--- Assert that running a tool succeeds
---@param ctx ToolTestContext
---@param args table
---@return any result
function M.assert_succeeds(ctx, args)
  local ok, result = M.run(ctx, args)
  if not ok then
    local msg = errors.is_tool_error(result) and result.message or tostring(result)
    error("Expected tool to succeed but got error: " .. msg)
  end
  return result
end

--- Assert that running a tool fails
---@param ctx ToolTestContext
---@param args table
---@param expected_code string|nil Expected error code
---@return any error
function M.assert_fails(ctx, args, expected_code)
  local ok, result = M.run(ctx, args)
  if ok then
    error("Expected tool to fail but it succeeded")
  end
  if expected_code and errors.is_tool_error(result) then
    if result.code ~= expected_code then
      error("Expected error code " .. expected_code .. " but got " .. result.code)
    end
  end
  return result
end

--- Assert tool definition is complete
---@param tool table
---@return boolean
function M.assert_metadata_complete(tool)
  assert(tool.name, "Tool missing name")
  assert(type(tool.name) == "string", "name must be string")
  assert(tool.description, "Tool missing description")
  assert(type(tool.description) == "string", "description must be string")
  assert(tool.run, "Tool missing run function")
  assert(type(tool.run) == "function", "run must be a function")
  return true
end

--- Create a mock Neovim buffer for testing buffer-related tools
---@param lines string[] Initial buffer lines
---@return table mock_buffer
function M.mock_buffer(lines)
  return {
    lines = lines or {},
    get_lines = function(self)
      return self.lines
    end,
    set_lines = function(self, new_lines)
      self.lines = new_lines
    end,
  }
end

--- Create mock opts with common defaults
---@param overrides table|nil
---@return table
function M.mock_opts(overrides)
  local defaults = {
    debug = false,
  }
  return vim.tbl_extend("force", defaults, overrides or {})
end

return M
