--- JSON-RPC 2.0 request validation and response frame builders
local M = {}

--- Validate a JSON-RPC 2.0 request envelope
---@param req table The request table to validate
---@return boolean valid
---@return string|nil error_message
function M.validate_request(req)
  if type(req) ~= "table" then
    return false, "Request must be a JSON object"
  end

  if req.jsonrpc ~= "2.0" then
    return false, "Missing or invalid jsonrpc version (must be '2.0')"
  end

  if not req.method then
    return false, "Missing 'method' field"
  end

  return true, nil
end

--- Build a JSON-RPC 2.0 success response
---@param id any The request id
---@param result any The result payload
---@return table
function M.result(id, result)
  return {
    jsonrpc = "2.0",
    id = id,
    result = result,
  }
end

--- Build a JSON-RPC 2.0 error response
--- Standard codes: -32700 Parse, -32600 Invalid Request, -32601 Method not found,
--- -32602 Invalid params, -32603 Internal
---@param id any The request id
---@param code number The error code
---@param message string The error message
---@param data any|nil Optional error data
---@return table
function M.error(id, code, message, data)
  local response = {
    jsonrpc = "2.0",
    id = id,
    error = {
      code = code,
      message = message,
    },
  }

  if data ~= nil then
    response.error.data = data
  end

  return response
end

return M
