local M = {}
local methods = require("buddy.mcp.methods")
local schema = require("buddy.mcp.schema")

local function validate_request(request)
  if type(request) ~= "table" then
    return false, "Request must be a JSON object"
  end

  if request.jsonrpc ~= "2.0" then
    return false, "Missing or invalid jsonrpc version (must be '2.0')"
  end

  if not request.method then
    return false, "Missing 'method' field"
  end

  return true, nil
end

function M.handle_request(session_id, request)
  local valid, err = validate_request(request)
  if not valid then
    if request.id then
      return schema.error(request.id, -32600, "Invalid Request", err)
    end
    return nil
  end

  local is_notification = request.id == nil

  local method_handler = methods[request.method]

  if not method_handler then
    if is_notification then
      return nil
    end
    return schema.error(request.id, -32601, "Method not found", "Unknown method: " .. request.method)
  end

  local ok, result = pcall(method_handler, session_id, request.params or {}, request.id)

  if not ok then
    if is_notification then
      return nil
    end
    return schema.error(request.id, -32603, "Internal error", tostring(result))
  end

  if is_notification then
    return nil
  end

  return schema.result(request.id, result)
end

return M
