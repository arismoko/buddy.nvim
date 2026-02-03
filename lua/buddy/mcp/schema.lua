local M = {}

function M.result(id, result)
  return {
    jsonrpc = "2.0",
    id = id,
    result = result
  }
end

-- Standard error codes: -32700 Parse, -32600 Invalid Request, -32601 Method not found, -32602 Invalid params, -32603 Internal
function M.error(id, code, message, data)
  local response = {
    jsonrpc = "2.0",
    id = id,
    error = {
      code = code,
      message = message
    }
  }

  if data ~= nil then
    response.error.data = data
  end

  return response
end

return M
