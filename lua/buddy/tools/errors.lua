--- Structured error utilities for tools
local M = {}

-- Error categories
M.codes = {
  -- Validation errors (4xx range)
  INVALID_INPUT = "INVALID_INPUT",
  INVALID_PARAMS = "INVALID_PARAMS",
  MISSING_REQUIRED = "MISSING_REQUIRED",
  TYPE_ERROR = "TYPE_ERROR",
  
  -- Runtime errors (5xx range)
  EXECUTION_ERROR = "EXECUTION_ERROR",
  NOT_FOUND = "NOT_FOUND",
  PERMISSION_DENIED = "PERMISSION_DENIED",
  TIMEOUT = "TIMEOUT",
  EXTERNAL_ERROR = "EXTERNAL_ERROR",
  CANCELLED = "CANCELLED",
}

---@class ToolError
---@field code string Error code from M.codes
---@field message string Human-readable error message
---@field data table|nil Additional error context

--- Create a structured tool error
--- Tools should throw this to return structured error responses
---@param code string Error code from errors.codes
---@param message string Human-readable message
---@param data table|nil Additional context
---@return table error object
function M.create(code, message, data)
  return {
    _is_tool_error = true,
    code = code,
    message = message,
    data = data,  -- Optional structured context
  }
end

--- Throw a structured error (convenience function)
---@param code string
---@param message string
---@param data table|nil
function M.throw(code, message, data)
  error(M.create(code, message, data))
end

--- Check if a value is a structured tool error
---@param err any
---@return boolean
function M.is_tool_error(err)
  return type(err) == "table" and err._is_tool_error == true
end

--- Format error for MCP response content
---@param err any Error from pcall
---@return table MCP-compatible content with isError
function M.to_mcp_response(err)
  local response = {
    isError = true,
    content = {
      { type = "text", text = (type(err) == "table" and err.message) or tostring(err) },
    },
  }
  if type(err) == "table" and err.data then
    response.data = err.data
  end
  return response
end

function M.validation_error(message, data)
  return M.create(M.codes.INVALID_PARAMS, message, data)
end

function M.not_found(message, data)
  return M.create(M.codes.NOT_FOUND, message, data)
end

function M.execution_error(message, data)
  return M.create(M.codes.EXECUTION_ERROR, message, data)
end

return M
