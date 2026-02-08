local T = MiniTest.new_set()

T["hooks"] = {
  pre_case = function()
    -- Fresh module state for each test
    package.loaded["buddy.transport.router"] = nil
    package.loaded["buddy.transport.http.parser"] = nil
    package.loaded["buddy.app.http_handlers"] = nil
  end,
}

-- Helper: create a mock http_server that captures send_response calls
local function make_mock_server()
  local mock = {
    responses = {},
  }
  function mock:send_response(client, status, headers, body)
    table.insert(self.responses, {
      status = status,
      headers = headers,
      body = body,
    })
  end
  return mock
end

-- Helper: create a mock request
local function make_request(method, path, auth_header)
  local headers = {}
  if auth_header then
    headers["authorization"] = auth_header
  end
  return {
    method = method,
    path = path,
    headers = headers,
  }
end

-- ── Auth enforcement ───────────────────────────────────────────────

T["auth"] = MiniTest.new_set()

T["auth"]["rejects request without token when auth is enabled"] = function()
  local router = require("buddy.transport.router")
  router.set_auth_token("secret-123")

  local mock = make_mock_server()
  router.handle(mock, {}, make_request("GET", "/sse"), "")

  MiniTest.expect.equality(#mock.responses, 1)
  MiniTest.expect.equality(mock.responses[1].status, 401)
end

T["auth"]["rejects request with wrong token"] = function()
  local router = require("buddy.transport.router")
  router.set_auth_token("correct")

  local mock = make_mock_server()
  router.handle(mock, {}, make_request("POST", "/message?sessionId=1", "Bearer wrong"), "")

  MiniTest.expect.equality(#mock.responses, 1)
  MiniTest.expect.equality(mock.responses[1].status, 401)
end

T["auth"]["allows request with correct token"] = function()
  local router = require("buddy.transport.router")
  router.set_auth_token("my-secret")

  local mock = make_mock_server()
  -- Use /health to get a deterministic 200 response
  router.handle(mock, {}, make_request("GET", "/health", "Bearer my-secret"), "")

  MiniTest.expect.equality(#mock.responses, 1)
  MiniTest.expect.equality(mock.responses[1].status, 200)
end

T["auth"]["skips auth check for /health endpoint"] = function()
  local router = require("buddy.transport.router")
  router.set_auth_token("secret")

  local mock = make_mock_server()
  -- No auth header, but /health should bypass auth
  router.handle(mock, {}, make_request("GET", "/health"), "")

  MiniTest.expect.equality(#mock.responses, 1)
  MiniTest.expect.equality(mock.responses[1].status, 200)
end

T["auth"]["allows all requests when auth is disabled (nil token)"] = function()
  local router = require("buddy.transport.router")
  router.set_auth_token(nil)

  local mock = make_mock_server()
  router.handle(mock, {}, make_request("GET", "/health"), "")

  MiniTest.expect.equality(#mock.responses, 1)
  MiniTest.expect.equality(mock.responses[1].status, 200)
end

T["auth"]["401 body contains JSON error"] = function()
  local router = require("buddy.transport.router")
  router.set_auth_token("token")

  local mock = make_mock_server()
  router.handle(mock, {}, make_request("GET", "/sse"), "")

  local decoded = vim.json.decode(mock.responses[1].body)
  MiniTest.expect.equality(decoded.error.code, -32001)
  MiniTest.expect.equality(type(decoded.error.message), "string")
end

-- ── Route dispatch ─────────────────────────────────────────────────

T["dispatch"] = MiniTest.new_set()

T["dispatch"]["GET /health dispatches to handle_health"] = function()
  local router = require("buddy.transport.router")
  router.set_auth_token(nil)

  local mock = make_mock_server()
  router.handle(mock, {}, make_request("GET", "/health"), "")

  MiniTest.expect.equality(#mock.responses, 1)
  MiniTest.expect.equality(mock.responses[1].status, 200)
  local decoded = vim.json.decode(mock.responses[1].body)
  MiniTest.expect.equality(decoded.status, "ok")
  MiniTest.expect.equality(type(decoded.timestamp), "number")
end

T["dispatch"]["unknown route dispatches to handle_not_found"] = function()
  local router = require("buddy.transport.router")
  router.set_auth_token(nil)

  local mock = make_mock_server()
  router.handle(mock, {}, make_request("GET", "/unknown"), "")

  MiniTest.expect.equality(#mock.responses, 1)
  MiniTest.expect.equality(mock.responses[1].status, 404)
  local decoded = vim.json.decode(mock.responses[1].body)
  MiniTest.expect.equality(decoded.error.code, 404)
  MiniTest.expect.equality(decoded.error.path, "/unknown")
end

T["dispatch"]["DELETE method with known path returns 404 (no route)"] = function()
  local router = require("buddy.transport.router")
  router.set_auth_token(nil)

  local mock = make_mock_server()
  router.handle(mock, {}, make_request("DELETE", "/health"), "")

  MiniTest.expect.equality(#mock.responses, 1)
  MiniTest.expect.equality(mock.responses[1].status, 404)
end

-- ── Query param integration ────────────────────────────────────────

T["query params"] = MiniTest.new_set()

T["query params"]["strips query string from path before dispatch"] = function()
  local router = require("buddy.transport.router")
  router.set_auth_token(nil)

  local mock = make_mock_server()
  -- /health?foo=bar should still match the /health route
  router.handle(mock, {}, make_request("GET", "/health?foo=bar"), "")

  MiniTest.expect.equality(#mock.responses, 1)
  MiniTest.expect.equality(mock.responses[1].status, 200)
end

T["query params"]["populates request.params from query string"] = function()
  local router = require("buddy.transport.router")
  router.set_auth_token(nil)

  -- Spy on http_handlers to capture the request that arrives
  local captured_request
  local real_handlers = require("buddy.app.http_handlers")
  local orig_health = real_handlers.handle_health
  real_handlers.handle_health = function(http_server, client, request)
    captured_request = request
    return orig_health(http_server, client, request)
  end

  local mock = make_mock_server()
  router.handle(mock, {}, make_request("GET", "/health?sessionId=abc&foo=bar"), "")

  -- Restore
  real_handlers.handle_health = orig_health

  MiniTest.expect.equality(captured_request.params.sessionId, "abc")
  MiniTest.expect.equality(captured_request.params.foo, "bar")
  -- Path should be stripped of query string
  MiniTest.expect.equality(captured_request.path, "/health")
end

-- ── _reset() ───────────────────────────────────────────────────────

T["_reset"] = MiniTest.new_set()

T["_reset"]["clears auth token"] = function()
  local router = require("buddy.transport.router")
  router.set_auth_token("some-token")
  MiniTest.expect.equality(router.get_auth_token(), "some-token")

  router._reset()
  MiniTest.expect.equality(router.get_auth_token(), nil)
end

-- ── No side effects ────────────────────────────────────────────────

T["isolation"] = MiniTest.new_set()

T["isolation"]["router module does NOT require service or lifecycle modules"] = function()
  -- Clear everything
  package.loaded["buddy.transport.router"] = nil
  package.loaded["buddy.services.tool_service"] = nil
  package.loaded["buddy.services.notifier"] = nil
  package.loaded["buddy.app.lifecycle"] = nil
  package.loaded["buddy.mcp.methods"] = nil

  -- Loading the router should NOT cause these modules to be loaded
  require("buddy.transport.router")

  MiniTest.expect.equality(package.loaded["buddy.services.tool_service"], nil)
  MiniTest.expect.equality(package.loaded["buddy.services.notifier"], nil)
  MiniTest.expect.equality(package.loaded["buddy.app.lifecycle"], nil)
  -- parser is the only dependency — that's expected
  MiniTest.expect.no_equality(package.loaded["buddy.transport.http.parser"], nil)
end

T["isolation"]["router does not wire services on handle()"] = function()
  local router = require("buddy.transport.router")
  router.set_auth_token(nil)

  -- Clear lifecycle before calling handle
  package.loaded["buddy.app.lifecycle"] = nil

  local mock = make_mock_server()
  router.handle(mock, {}, make_request("GET", "/health"), "")

  -- lifecycle should NOT have been loaded by the router
  MiniTest.expect.equality(package.loaded["buddy.app.lifecycle"], nil)
end

return T
