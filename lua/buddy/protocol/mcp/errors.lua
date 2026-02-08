--- MCP and JSON-RPC protocol error code constants and mapping helpers
---
--- Centralizes error codes defined by JSON-RPC 2.0 and the MCP specification.
--- Provides helpers for constructing well-formed error response objects.

local M = {}

-- ────────────────────────────────────────────────────────────────────────────
-- JSON-RPC 2.0 standard error codes
-- ────────────────────────────────────────────────────────────────────────────

---@enum JsonRpcErrorCode
M.PARSE_ERROR = -32700
M.INVALID_REQUEST = -32600
M.METHOD_NOT_FOUND = -32601
M.INVALID_PARAMS = -32602
M.INTERNAL_ERROR = -32603

-- JSON-RPC reserved server error range: -32000 to -32099
-- MCP uses this range for protocol-specific errors.

-- ────────────────────────────────────────────────────────────────────────────
-- MCP-specific error codes (within JSON-RPC server error range)
-- ────────────────────────────────────────────────────────────────────────────

M.REQUEST_CANCELLED = -32800
M.CONTENT_TOO_LARGE = -32801

-- ────────────────────────────────────────────────────────────────────────────
-- Human-readable messages for each code
-- ────────────────────────────────────────────────────────────────────────────

---@type table<number, string>
M.messages = {
  [M.PARSE_ERROR] = "Parse error",
  [M.INVALID_REQUEST] = "Invalid Request",
  [M.METHOD_NOT_FOUND] = "Method not found",
  [M.INVALID_PARAMS] = "Invalid params",
  [M.INTERNAL_ERROR] = "Internal error",
  [M.REQUEST_CANCELLED] = "Request cancelled",
  [M.CONTENT_TOO_LARGE] = "Content too large",
}

-- ────────────────────────────────────────────────────────────────────────────
-- Helpers
-- ────────────────────────────────────────────────────────────────────────────

--- Get the default message for an error code
---@param code number JSON-RPC/MCP error code
---@return string message
function M.message_for(code)
  return M.messages[code] or "Unknown error"
end

--- Build a JSON-RPC error response object
---
---@param id any Request id (number, string, or vim.NIL)
---@param code number Error code
---@param message string|nil Human-readable message (defaults to code's standard message)
---@param data any|nil Additional error data
---@return table response JSON-RPC error response: { jsonrpc, id, error = { code, message, data? } }
function M.response(id, code, message, data)
  local err_obj = {
    code = code,
    message = message or M.message_for(code),
  }
  if data ~= nil then
    err_obj.data = data
  end
  return {
    jsonrpc = "2.0",
    id = id,
    error = err_obj,
  }
end

--- Build just the error object (without the full response envelope)
---
---@param code number Error code
---@param message string|nil Human-readable message
---@param data any|nil Additional error data
---@return table error_object { code, message, data? }
function M.object(code, message, data)
  local err_obj = {
    code = code,
    message = message or M.message_for(code),
  }
  if data ~= nil then
    err_obj.data = data
  end
  return err_obj
end

return M
