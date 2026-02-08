-- Tests for services/client_requester.lua async (nio-based) behavior
local nio = require('nio')

local T = MiniTest.new_set()

T['hooks'] = {
  pre_case = function()
    package.loaded['buddy.services.client_requester'] = nil
  end,
}

local function get_requester()
  return require('buddy.services.client_requester')
end

T['async request()'] = MiniTest.new_set()

T['async request()']['resolves with result via nio.run'] = function()
  local ClientRequester = get_requester()
  local sent = {}

  local requester = ClientRequester.new({
    send_fn = function(session_id, msg)
      table.insert(sent, { session_id = session_id, msg = msg })
      -- Simulate async response from client
      vim.schedule(function()
        requester:handle_response({
          jsonrpc = '2.0',
          id = msg.id,
          result = { roots = { { uri = 'file:///async-test' } } },
        })
      end)
      return true
    end,
  })

  local result, err
  local done = false

  nio.run(function()
    result, err = requester:request('session-async', 'roots/list', {}, 5000)
  end, function()
    done = true
  end)

  vim.wait(2000, function() return done end, 10)

  MiniTest.expect.equality(done, true)
  MiniTest.expect.equality(err, nil)
  MiniTest.expect.equality(result.roots[1].uri, 'file:///async-test')
  MiniTest.expect.equality(#sent, 1)
  MiniTest.expect.equality(sent[1].session_id, 'session-async')
  MiniTest.expect.equality(sent[1].msg.method, 'roots/list')
end

T['async request()']['returns error on send failure'] = function()
  local ClientRequester = get_requester()

  local requester = ClientRequester.new({
    send_fn = function() return false end,
  })

  local result, err
  local done = false

  nio.run(function()
    result, err = requester:request('s1', 'test', {}, 1000)
  end, function()
    done = true
  end)

  vim.wait(2000, function() return done end, 10)

  MiniTest.expect.equality(done, true)
  MiniTest.expect.equality(result, nil)
  MiniTest.expect.equality(err, 'Failed to send request')
end

T['async request()']['returns error response from client'] = function()
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

  local result, err
  local done = false

  nio.run(function()
    result, err = requester:request('s1', 'test/method', {}, 5000)
  end, function()
    done = true
  end)

  vim.wait(2000, function() return done end, 10)

  MiniTest.expect.equality(done, true)
  MiniTest.expect.equality(result, nil)
  MiniTest.expect.equality(type(err), 'table')
  MiniTest.expect.equality(err.code, -32600)
  MiniTest.expect.equality(err.message, 'Invalid request')
end

T['async request()']['times out when no response'] = function()
  local ClientRequester = get_requester()

  local requester = ClientRequester.new({
    send_fn = function() return true end, -- Never responds
  })

  local result, err
  local done = false

  nio.run(function()
    result, err = requester:request('s1', 'test/method', {}, 200)
  end, function()
    done = true
  end)

  vim.wait(2000, function() return done end, 10)

  MiniTest.expect.equality(done, true)
  MiniTest.expect.equality(result, nil)
  MiniTest.expect.equality(err, 'Request timeout')
end

T['async request()']['cleans up pending after completion'] = function()
  local ClientRequester = get_requester()
  local captured_id

  local requester = ClientRequester.new({
    send_fn = function(_session_id, msg)
      captured_id = msg.id
      vim.schedule(function()
        requester:handle_response({
          jsonrpc = '2.0',
          id = msg.id,
          result = { ok = true },
        })
      end)
      return true
    end,
  })

  local done = false

  nio.run(function()
    requester:request('s1', 'test', {}, 5000)
  end, function()
    done = true
  end)

  vim.wait(2000, function() return done end, 10)

  -- After completion, pending entry should be cleaned up
  MiniTest.expect.equality(done, true)
  MiniTest.expect.equality(requester:is_response({ id = captured_id }), false)
end

T['async request()']['multiple concurrent requests resolve independently'] = function()
  local ClientRequester = get_requester()

  local requester = ClientRequester.new({
    send_fn = function(_session_id, msg)
      -- Respond after a small delay
      vim.defer_fn(function()
        requester:handle_response({
          jsonrpc = '2.0',
          id = msg.id,
          result = { method = msg.method },
        })
      end, 10)
      return true
    end,
  })

  local results = {}
  local count = 0

  nio.run(function()
    -- Launch two concurrent requests using nio.gather-like pattern
    local r1, r2
    nio.run(function()
      r1 = requester:request('s1', 'method_a', {}, 5000)
      results.a = r1
      count = count + 1
    end)
    nio.run(function()
      r2 = requester:request('s1', 'method_b', {}, 5000)
      results.b = r2
      count = count + 1
    end)
  end)

  vim.wait(3000, function() return count >= 2 end, 10)

  MiniTest.expect.equality(count, 2)
  MiniTest.expect.equality(results.a.method, 'method_a')
  MiniTest.expect.equality(results.b.method, 'method_b')
end

T['async cleanup_session'] = MiniTest.new_set()

T['async cleanup_session']['resolves pending futures with session closed error'] = function()
  local ClientRequester = get_requester()

  local requester = ClientRequester.new({
    send_fn = function(_session_id, msg)
      -- Schedule cleanup after request is sent
      vim.schedule(function()
        requester:cleanup_session('session-to-clean')
      end)
      return true
    end,
  })

  local result, err
  local done = false

  nio.run(function()
    result, err = requester:request('session-to-clean', 'test/method', {}, 5000)
  end, function()
    done = true
  end)

  vim.wait(2000, function() return done end, 10)

  MiniTest.expect.equality(done, true)
  MiniTest.expect.equality(result, nil)
  MiniTest.expect.equality(type(err), 'table')
  MiniTest.expect.equality(err.message, 'Session closed')
end

T['request_sync with nio'] = MiniTest.new_set()

T['request_sync with nio']['works from non-nio context'] = function()
  local ClientRequester = get_requester()

  local requester = ClientRequester.new({
    send_fn = function(_session_id, msg)
      vim.schedule(function()
        requester:handle_response({
          jsonrpc = '2.0',
          id = msg.id,
          result = { sync_ok = true },
        })
      end)
      return true
    end,
  })

  -- Call request_sync directly (not inside nio.run)
  local result, err = requester:request_sync('s1', 'test', {}, 5000)

  MiniTest.expect.equality(err, nil)
  MiniTest.expect.equality(result.sync_ok, true)
end

T['request_sync with nio']['timeout works from non-nio context'] = function()
  local ClientRequester = get_requester()

  local requester = ClientRequester.new({
    send_fn = function() return true end, -- Never responds
  })

  local result, err = requester:request_sync('s1', 'test', {}, 200)

  MiniTest.expect.equality(result, nil)
  MiniTest.expect.equality(err, 'Request timeout')
end

return T
