-- Tests for services/client_requester.lua
local T = MiniTest.new_set()

T['hooks'] = {
  pre_case = function()
    package.loaded['buddy.services.client_requester'] = nil
  end,
}

local function get_requester()
  return require('buddy.services.client_requester')
end

T['ClientRequester'] = MiniTest.new_set()

T['ClientRequester']['new() requires send_fn'] = function()
  local ClientRequester = get_requester()
  MiniTest.expect.error(function()
    ClientRequester.new({})
  end)
  MiniTest.expect.error(function()
    ClientRequester.new(nil)
  end)
end

T['ClientRequester']['new() creates instance with send_fn'] = function()
  local ClientRequester = get_requester()
  local requester = ClientRequester.new({
    send_fn = function() return true end,
  })
  MiniTest.expect.equality(type(requester), 'table')
  MiniTest.expect.equality(type(requester.request_sync), 'function')
  MiniTest.expect.equality(type(requester.handle_response), 'function')
  MiniTest.expect.equality(type(requester.cleanup_session), 'function')
end

T['request/response'] = MiniTest.new_set()

T['request/response']['request_sync sends correct JSON-RPC and returns on response'] = function()
  local ClientRequester = get_requester()
  local sent_messages = {}

  local requester = ClientRequester.new({
    send_fn = function(session_id, msg)
      table.insert(sent_messages, { session_id = session_id, msg = msg })
      -- Simulate async response arriving
      vim.schedule(function()
        requester:handle_response({
          jsonrpc = '2.0',
          id = msg.id,
          result = { roots = { { uri = 'file:///test' } } },
        })
      end)
      return true
    end,
  })

  local result, err = requester:request_sync('session-1', 'roots/list', {}, 5000)

  -- Verify message was sent
  MiniTest.expect.equality(#sent_messages, 1)
  MiniTest.expect.equality(sent_messages[1].session_id, 'session-1')
  MiniTest.expect.equality(sent_messages[1].msg.jsonrpc, '2.0')
  MiniTest.expect.equality(sent_messages[1].msg.method, 'roots/list')
  MiniTest.expect.equality(type(sent_messages[1].msg.id), 'string')

  -- Verify result
  MiniTest.expect.equality(err, nil)
  MiniTest.expect.equality(result.roots[1].uri, 'file:///test')
end

T['request/response']['request_sync returns error on send failure'] = function()
  local ClientRequester = get_requester()

  local requester = ClientRequester.new({
    send_fn = function() return false end,
  })

  local result, err = requester:request_sync('session-1', 'roots/list', {}, 1000)

  MiniTest.expect.equality(result, nil)
  MiniTest.expect.equality(err, 'Failed to send request')
end

T['request/response']['request_sync returns error response from client'] = function()
  local ClientRequester = get_requester()

  local requester = ClientRequester.new({
    send_fn = function(_session_id, msg)
      vim.schedule(function()
        requester:handle_response({
          jsonrpc = '2.0',
          id = msg.id,
          error = { code = -32600, message = 'Invalid request' },
        })
      end)
      return true
    end,
  })

  local result, err = requester:request_sync('session-1', 'test/method', {}, 5000)

  MiniTest.expect.equality(result, nil)
  MiniTest.expect.equality(type(err), 'table')
  MiniTest.expect.equality(err.code, -32600)
  MiniTest.expect.equality(err.message, 'Invalid request')
end

T['request/response']['request_sync times out'] = function()
  local ClientRequester = get_requester()

  local requester = ClientRequester.new({
    send_fn = function() return true end, -- Never responds
  })

  local result, err = requester:request_sync('session-1', 'test/method', {}, 100)

  MiniTest.expect.equality(result, nil)
  MiniTest.expect.equality(err, 'Request timeout')
end

T['request/response']['request IDs are unique'] = function()
  local ClientRequester = get_requester()
  local ids = {}

  local requester = ClientRequester.new({
    send_fn = function(_session_id, msg)
      table.insert(ids, msg.id)
      -- Respond immediately
      vim.schedule(function()
        requester:handle_response({
          jsonrpc = '2.0',
          id = msg.id,
          result = {},
        })
      end)
      return true
    end,
  })

  requester:request_sync('s1', 'method1', {}, 1000)
  requester:request_sync('s1', 'method2', {}, 1000)

  MiniTest.expect.equality(#ids, 2)
  -- IDs should be different
  local different = ids[1] ~= ids[2]
  MiniTest.expect.equality(different, true)
end

T['is_response'] = MiniTest.new_set()

T['is_response']['returns true for pending request id'] = function()
  local ClientRequester = get_requester()

  local captured_id
  local requester = ClientRequester.new({
    send_fn = function(_session_id, msg)
      captured_id = msg.id
      return true
    end,
  })

  -- Start a request but don't respond (will timeout)
  vim.schedule(function()
    requester:request_sync('s1', 'test', {}, 200)
  end)
  -- Give schedule a chance to fire
  vim.wait(50, function() return captured_id ~= nil end, 5)

  if captured_id then
    local is_resp = requester:is_response({ id = captured_id })
    MiniTest.expect.equality(is_resp, true)

    local not_resp = requester:is_response({ id = 'nonexistent' })
    MiniTest.expect.equality(not_resp, false)
  end

  -- Cleanup: wait for timeout
  vim.wait(300, function() return false end, 10)
end

T['is_response']['returns false for unknown id'] = function()
  local ClientRequester = get_requester()

  local requester = ClientRequester.new({
    send_fn = function() return true end,
  })

  MiniTest.expect.equality(requester:is_response({ id = 'unknown_123' }), false)
  MiniTest.expect.equality(requester:is_response({}), false)
end

T['cleanup'] = MiniTest.new_set()

T['cleanup']['cleanup_session rejects all pending requests for session'] = function()
  local ClientRequester = get_requester()
  local errors = {}

  local requester = ClientRequester.new({
    send_fn = function(_session_id, msg)
      -- Start request but don't respond — we'll cleanup instead
      vim.schedule(function()
        -- After a short delay, cleanup the session
        requester:cleanup_session('session-to-clean')
      end)
      return true
    end,
  })

  local _result, err = requester:request_sync('session-to-clean', 'test/method', {}, 5000)

  -- Should get session closed error
  MiniTest.expect.equality(type(err), 'table')
  MiniTest.expect.equality(err.message, 'Session closed')
end

T['cleanup']['cleanup_session does not affect other sessions'] = function()
  local ClientRequester = get_requester()
  local send_count = 0

  local requester = ClientRequester.new({
    send_fn = function(session_id, msg)
      send_count = send_count + 1
      if session_id == 'session-ok' then
        vim.schedule(function()
          requester:handle_response({
            jsonrpc = '2.0',
            id = msg.id,
            result = { ok = true },
          })
        end)
      end
      return true
    end,
  })

  -- Clean up session-bad (no pending requests for it yet, but that's fine)
  requester:cleanup_session('session-bad')

  -- session-ok should still work
  local result, err = requester:request_sync('session-ok', 'test', {}, 5000)
  MiniTest.expect.equality(err, nil)
  MiniTest.expect.equality(result.ok, true)
end

return T
