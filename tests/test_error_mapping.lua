--- Tests for error code consistency across the MCP stack
local T = MiniTest.new_set()

-- ────────────────────────────────────────────────────────────────
-- Error constants module
-- ────────────────────────────────────────────────────────────────

T['errors module'] = MiniTest.new_set()

T['errors module']['has all JSON-RPC standard codes'] = function()
  local errors = require("buddy.protocol.mcp.errors")

  MiniTest.expect.equality(errors.PARSE_ERROR, -32700)
  MiniTest.expect.equality(errors.INVALID_REQUEST, -32600)
  MiniTest.expect.equality(errors.METHOD_NOT_FOUND, -32601)
  MiniTest.expect.equality(errors.INVALID_PARAMS, -32602)
  MiniTest.expect.equality(errors.INTERNAL_ERROR, -32603)
end

T['errors module']['has MCP-specific codes'] = function()
  local errors = require("buddy.protocol.mcp.errors")

  MiniTest.expect.equality(errors.REQUEST_CANCELLED, -32800)
  MiniTest.expect.equality(errors.CONTENT_TOO_LARGE, -32801)
end

T['errors module']['message_for returns correct messages'] = function()
  local errors = require("buddy.protocol.mcp.errors")

  MiniTest.expect.equality(errors.message_for(-32700), "Parse error")
  MiniTest.expect.equality(errors.message_for(-32600), "Invalid Request")
  MiniTest.expect.equality(errors.message_for(-32601), "Method not found")
  MiniTest.expect.equality(errors.message_for(-32603), "Internal error")
  MiniTest.expect.equality(errors.message_for(-32800), "Request cancelled")
  MiniTest.expect.equality(errors.message_for(99999), "Unknown error")
end

T['errors module']['response() builds well-formed error response'] = function()
  local errors = require("buddy.protocol.mcp.errors")

  local resp = errors.response(1, errors.INTERNAL_ERROR, "something broke", { detail = "oops" })
  MiniTest.expect.equality(resp.jsonrpc, "2.0")
  MiniTest.expect.equality(resp.id, 1)
  MiniTest.expect.equality(resp.error.code, -32603)
  MiniTest.expect.equality(resp.error.message, "something broke")
  MiniTest.expect.equality(resp.error.data.detail, "oops")
end

T['errors module']['response() uses default message when nil'] = function()
  local errors = require("buddy.protocol.mcp.errors")

  local resp = errors.response(2, errors.PARSE_ERROR)
  MiniTest.expect.equality(resp.error.message, "Parse error")
end

T['errors module']['object() builds error without envelope'] = function()
  local errors = require("buddy.protocol.mcp.errors")

  local obj = errors.object(errors.METHOD_NOT_FOUND, "no such method")
  MiniTest.expect.equality(obj.code, -32601)
  MiniTest.expect.equality(obj.message, "no such method")
  MiniTest.expect.equality(obj.data, nil)
end

-- ────────────────────────────────────────────────────────────────
-- Dispatcher uses error constants (not inline literals)
-- ────────────────────────────────────────────────────────────────

T['dispatcher errors'] = MiniTest.new_set()

T['dispatcher errors']['hooks'] = {
  pre_case = function()
    package.loaded['buddy.protocol.mcp.dispatcher'] = nil
    package.loaded['buddy.protocol.mcp.registry'] = nil
    package.loaded['buddy.protocol.jsonrpc'] = nil
    package.loaded['buddy.protocol.mcp.handlers.core'] = nil
    package.loaded['buddy.protocol.mcp.handlers.tools'] = nil
    package.loaded['buddy.protocol.mcp.handlers.resources'] = nil
    package.loaded['buddy.protocol.mcp.handlers.prompts'] = nil
    package.loaded['buddy.protocol.mcp.handlers.completion'] = nil
    package.loaded['buddy.protocol.mcp.handlers.notifications'] = nil
  end,
}

T['dispatcher errors']['invalid request uses INVALID_REQUEST code'] = function()
  local dispatcher = require("buddy.protocol.mcp.dispatcher")
  local errors = require("buddy.protocol.mcp.errors")

  -- Missing jsonrpc version
  local response = dispatcher.handle_request("sess", { id = 1, method = "test" })
  MiniTest.expect.equality(response.error.code, errors.INVALID_REQUEST)
end

T['dispatcher errors']['unknown method uses METHOD_NOT_FOUND code'] = function()
  local dispatcher = require("buddy.protocol.mcp.dispatcher")
  local errors = require("buddy.protocol.mcp.errors")

  local response = dispatcher.handle_request("sess", {
    jsonrpc = "2.0",
    id = 2,
    method = "nonexistent/method",
  })
  MiniTest.expect.equality(response.error.code, errors.METHOD_NOT_FOUND)
end

return T
