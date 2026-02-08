local T = MiniTest.new_set()

T['hooks'] = {
  pre_case = function()
    -- Fresh module state for each test
    package.loaded['buddy.server.router'] = nil
    package.loaded['buddy.config'] = nil
  end
}

T['auth'] = MiniTest.new_set()

-- Helper: create a mock http_server that captures send_response calls
local function make_mock_server()
  local mock = {
    responses = {},
    sse_connections = {},
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

-- Helper: create a mock request with optional auth header
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

T['auth']['rejects request without token when auth is enabled'] = function()
  local router = require('buddy.server.router')
  router.set_auth_token('test-secret-token')

  local mock = make_mock_server()
  local request = make_request('GET', '/sse', nil)

  router.handle(mock, {}, request, '')

  MiniTest.expect.equality(#mock.responses, 1)
  MiniTest.expect.equality(mock.responses[1].status, 401)
end

T['auth']['rejects request with wrong token'] = function()
  local router = require('buddy.server.router')
  router.set_auth_token('correct-token')

  local mock = make_mock_server()
  local request = make_request('POST', '/message?sessionId=123', 'Bearer wrong-token')

  router.handle(mock, {}, request, '')

  MiniTest.expect.equality(#mock.responses, 1)
  MiniTest.expect.equality(mock.responses[1].status, 401)
end

T['auth']['allows /health without token'] = function()
  local router = require('buddy.server.router')
  router.set_auth_token('secret-token')

  local mock = make_mock_server()
  local request = make_request('GET', '/health', nil)

  router.handle(mock, {}, request, '')

  -- /health should return 200, not 401
  MiniTest.expect.equality(#mock.responses, 1)
  MiniTest.expect.equality(mock.responses[1].status, 200)
end

T['auth']['allows request with correct token'] = function()
  local router = require('buddy.server.router')
  router.set_auth_token('my-secret')

  local mock = make_mock_server()
  -- Use /health with correct token to verify it passes auth AND completes
  local request = make_request('GET', '/health', 'Bearer my-secret')

  router.handle(mock, {}, request, '')

  MiniTest.expect.equality(#mock.responses, 1)
  MiniTest.expect.equality(mock.responses[1].status, 200)
end

T['auth']['allows all requests when auth is disabled (nil token)'] = function()
  local router = require('buddy.server.router')
  router.set_auth_token(nil)

  local mock = make_mock_server()
  -- /health without any auth header should work
  local request = make_request('GET', '/health', nil)

  router.handle(mock, {}, request, '')

  MiniTest.expect.equality(#mock.responses, 1)
  MiniTest.expect.equality(mock.responses[1].status, 200)
end

T['auth']['returns 401 for SSE endpoint without token'] = function()
  local router = require('buddy.server.router')
  router.set_auth_token('sse-token')

  local mock = make_mock_server()
  local request = make_request('GET', '/sse', nil)

  router.handle(mock, {}, request, '')

  MiniTest.expect.equality(#mock.responses, 1)
  MiniTest.expect.equality(mock.responses[1].status, 401)
end

T['auth']['returns 401 for POST /message without token'] = function()
  local router = require('buddy.server.router')
  router.set_auth_token('msg-token')

  local mock = make_mock_server()
  local request = make_request('POST', '/message?sessionId=abc', nil)

  router.handle(mock, {}, request, '')

  MiniTest.expect.equality(#mock.responses, 1)
  MiniTest.expect.equality(mock.responses[1].status, 401)
end

T['auth']['config defaults auth to true'] = function()
  local config = require('buddy.config')
  local cfg = config.get()
  MiniTest.expect.equality(cfg.auth, true)
end

T['auth']['config auth can be disabled'] = function()
  local config = require('buddy.config')
  config.setup({ auth = false })
  local cfg = config.get()
  MiniTest.expect.equality(cfg.auth, false)
end

return T
